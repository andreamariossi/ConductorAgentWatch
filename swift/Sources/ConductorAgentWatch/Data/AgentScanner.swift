import Foundation

// MARK: - Shared per-agent result

struct CodexScanResult {
    let snapshot: UsageSnapshot
    let limits: LimitsSnapshot?
}

/// Lightweight summary produced by scanning a single AI agent's logs.
struct AgentSnapshot {
    let agent: AIAgent
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let sessionCount: Int
    let lastActivity: Date?

    static func empty(_ agent: AIAgent) -> AgentSnapshot {
        AgentSnapshot(agent: agent, inputTokens: 0, outputTokens: 0,
                      costUSD: 0, sessionCount: 0, lastActivity: nil)
    }

    var totalTokens: Int { inputTokens + outputTokens }
}

/// The three agents we track.
enum AIAgent: String, CaseIterable, Identifiable {
    case claude       = "Claude"
    case codex        = "Codex"
    case antigravity  = "Antigravity"

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .claude:      return "CL"
        case .codex:       return "CX"
        case .antigravity: return "AG"
        }
    }

    var accentHex: UInt32 {
        switch self {
        case .claude:      return 0xCC785C  // warm orange (matches app theme)
        case .codex:       return 0x22C55E  // green
        case .antigravity: return 0x3B82F6  // blue
        }
    }
}

// MARK: - Codex Scanner

actor CodexScanner {

    private struct FileState {
        var identity: NSObject?
        var mtime: TimeInterval
        var size: UInt64
        var entries: [UsageEntry]
        var rateLimits: LimitsSnapshot?
        var lastActivity: Date?
    }

    private var cache: [String: FileState] = [:]
    /// Cached during scan() so scanActivity() avoids a second full enumeration.
    private var latestFilePath: URL?
    private var latestFileMtime: Date?

    func scan() -> CodexScanResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".codex/sessions")

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return CodexScanResult(snapshot: .empty, limits: nil)
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey,
                                       .isRegularFileKey, .fileResourceIdentifierKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                              options: [.skipsHiddenFiles]) else {
            return CodexScanResult(snapshot: .empty, limits: nil)
        }

        var livePaths = Set<String>()
        var scanLatestURL: URL?
        var scanLatestMtime: Date?

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-") else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }

            let path = url.path
            livePaths.insert(path)

            let size = UInt64(values.fileSize ?? 0)
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let identity = values.fileResourceIdentifier as? NSObject

            // Track the most-recently-modified file for scanActivity().
            if let mtimeDate = values.contentModificationDate {
                if scanLatestMtime == nil || mtimeDate > scanLatestMtime! {
                    scanLatestMtime = mtimeDate
                    scanLatestURL = url
                }
            }

            if let state = cache[path], state.size == size, state.mtime == mtime,
               identitiesEqual(state.identity, identity) {
                continue
            }

            let (fileEntries, fileLimits, lastSeen) = parseCodexFile(url: url)
            cache[path] = FileState(identity: identity, mtime: mtime, size: size,
                                    entries: fileEntries, rateLimits: fileLimits, lastActivity: lastSeen)
        }

        // Persist latest file info for scanActivity().
        self.latestFilePath = scanLatestURL
        self.latestFileMtime = scanLatestMtime

        // Drop deleted files
        for path in cache.keys where !livePaths.contains(path) { cache.removeValue(forKey: path) }

        var allEntries: [UsageEntry] = []
        var latestRateLimits: LimitsSnapshot? = nil

        for state in cache.values {
            allEntries.append(contentsOf: state.entries)
            if let rl = state.rateLimits {
                if latestRateLimits == nil || rl.fetchedAt > latestRateLimits!.fetchedAt {
                    latestRateLimits = rl
                }
            }
        }

        allEntries.sort { $0.timestamp < $1.timestamp }

        let stats = ScanStats(
            filesSeen: cache.count,
            filesParsed: cache.count,
            rawUsageLines: allEntries.count,
            duplicatesSkipped: 0,
            scanDuration: 0
        )

        let snapshot = Aggregator.buildSnapshot(entries: allEntries, stats: stats, now: Date())
        return CodexScanResult(snapshot: snapshot, limits: latestRateLimits)
    }

    // MARK: - File parsing

    private func parseCodexFile(url: URL) -> (entries: [UsageEntry], rateLimits: LimitsSnapshot?, lastSeen: Date?) {
        guard let data = try? Data(contentsOf: url) else { return ([], nil, nil) }
        let decoder = JSONDecoder()

        struct CodexLine: Decodable {
            let type: String?
            let timestamp: String?
            let payload: Payload?
            
            struct Payload: Decodable {
                let model: String?
                let cwd: String?
                let type: String?
                let info: Info?
                let rate_limits: RateLimits?
                
                struct Info: Decodable {
                    struct TokenUsage: Decodable {
                        let input_tokens: Int?
                        let output_tokens: Int?
                    }
                    let total_token_usage: TokenUsage?
                }
                
                struct RateLimits: Decodable {
                    struct LimitWindowData: Decodable {
                        let used_percent: Double?
                        let window_minutes: Int?
                        let resets_at: Double?
                    }
                    let primary: LimitWindowData?
                    let secondary: LimitWindowData?
                }
            }
        }

        var entries: [UsageEntry] = []
        var lastInput = 0
        var lastOutput = 0
        var currentModel = "gpt-4o"
        var currentCwd = "unknown"
        var lastRateLimits: LimitsSnapshot? = nil
        var lastSeen: Date? = nil

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = data.count
            var lineStart = 0, i = 0
            while i < count {
                if base[i] == 0x0A {
                    if i > lineStart {
                        let lineData = data.subdata(in: lineStart..<i)
                        if let lineObj = try? decoder.decode(CodexLine.self, from: lineData) {
                            let tsString = lineObj.timestamp ?? ""
                            let timestamp = ISO8601.parse(tsString) ?? Date()
                            lastSeen = timestamp
                            
                            if lineObj.type == "turn_context", let p = lineObj.payload {
                                currentModel = p.model ?? currentModel
                                currentCwd = p.cwd ?? currentCwd
                            } else if lineObj.type == "event_msg", let p = lineObj.payload, p.type == "token_count" {
                                if let tu = p.info?.total_token_usage {
                                    let inp = tu.input_tokens ?? lastInput
                                    let out = tu.output_tokens ?? lastOutput
                                    let incIn = inp - lastInput
                                    let incOut = out - lastOutput
                                    
                                    if incIn > 0 || incOut > 0 {
                                        let project = URL(fileURLWithPath: currentCwd).lastPathComponent
                                        let (cost, priced) = PricingTable.cost(
                                            model: currentModel, input: incIn, output: incOut,
                                            cacheCreation: 0, cacheRead: 0
                                        )
                                        let entry = UsageEntry(
                                            timestamp: timestamp,
                                            model: currentModel,
                                            inputTokens: incIn,
                                            outputTokens: incOut,
                                            cacheCreationTokens: 0,
                                            cacheReadTokens: 0,
                                            costUSD: cost,
                                            projectName: project,
                                            priced: priced
                                        )
                                        entries.append(entry)
                                        lastInput = inp
                                        lastOutput = out
                                    }
                                }
                                
                                if let rl = p.rate_limits {
                                    var windows: [LimitWindow] = []
                                    if let pri = rl.primary {
                                        let resets = pri.resets_at.map { Date(timeIntervalSince1970: $0) }
                                        windows.append(LimitWindow(
                                            key: "five_hour",
                                            label: "5-hour session",
                                            utilization: (pri.used_percent ?? 0) * 100.0,
                                            resetsAt: resets
                                        ))
                                    }
                                    if let sec = rl.secondary {
                                        let resets = sec.resets_at.map { Date(timeIntervalSince1970: $0) }
                                        windows.append(LimitWindow(
                                            key: "seven_day",
                                            label: "7-day limit",
                                            utilization: (sec.used_percent ?? 0) * 100.0,
                                            resetsAt: resets
                                        ))
                                    }
                                    if !windows.isEmpty {
                                        lastRateLimits = LimitsSnapshot(windows: windows, fetchedAt: timestamp)
                                    }
                                }
                            }
                        }
                    }
                    lineStart = i + 1
                }
                i += 1
            }
        }
        return (entries, lastRateLimits, lastSeen)
    }

    private func identitiesEqual(_ a: NSObject?, _ b: NSObject?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.isEqual(b)
        default: return false
        }
    }

    func scanActivity(now: Date = Date()) -> AgentActivity {
        // Reuse the latest file discovered during scan() — avoids a second
        // full recursive directory enumeration.
        let latestFile = self.latestFilePath
        let latestMtime = self.latestFileMtime
        
        guard let url = latestFile, let mtime = latestMtime else {
            return AgentActivity(agent: .codex, state: .idle, project: "—", currentTask: "—", activeScript: nil, lastUpdated: now)
        }
        
        if now.timeIntervalSince(mtime) > 60 {
            return AgentActivity(agent: .codex, state: .idle, project: "—", currentTask: "—", activeScript: nil, lastUpdated: mtime)
        }
        
        let lines = UsageDataSource.readLastLines(url: url)
        var project = "unknown"
        var task = "General Task"
        var activeScript: String? = nil
        var state: AgentActivityState = .idle
        
        struct CodexActivityEvent: Decodable {
            let type: String?
            let payload: Payload?
            
            struct Payload: Decodable {
                let cwd: String?
                let type: String?
                let role: String?
                let content: [ContentItem]?
                
                struct ContentItem: Decodable {
                    let type: String?
                    let text: String?
                    let tool_calls: [ToolCall]?
                    
                    struct ToolCall: Decodable {
                        let type: String?
                        let function: Func?
                        
                        struct Func: Decodable {
                            let name: String?
                            let arguments: String?
                        }
                    }
                }
            }
        }
        
        let decoder = JSONDecoder()
        var hasToolUse = false
        var toolUseName = ""
        var toolUseDetails = ""
        
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? decoder.decode(CodexActivityEvent.self, from: data) else { continue }
            
            if obj.type == "turn_context", let cwd = obj.payload?.cwd {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            if obj.type == "response_item", let payload = obj.payload {
                if payload.role == "user", let content = payload.content {
                    for item in content {
                        if item.type == "input_text", let text = item.text, task == "General Task" {
                            task = text
                        }
                    }
                }
                if payload.role == "assistant", let content = payload.content, !hasToolUse {
                    for item in content {
                        if let calls = item.tool_calls {
                            for call in calls {
                                if let name = call.function?.name {
                                    hasToolUse = true
                                    toolUseName = name
                                    toolUseDetails = call.function?.arguments ?? ""
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if hasToolUse {
            let detailStr = toolUseDetails.count > 40 ? String(toolUseDetails.prefix(37)) + "..." : toolUseDetails
            activeScript = "Executing: \(toolUseName) (\(detailStr))"
            if now.timeIntervalSince(mtime) < 4 {
                state = .running
            } else {
                state = .interventionNeeded
            }
        } else {
            state = .finished
        }
        
        return AgentActivity(agent: .codex, state: state, project: project, currentTask: task, activeScript: activeScript, lastUpdated: mtime)
    }
}

// MARK: - Antigravity Scanner

actor AntigravityScanner {

    private struct ConvState {
        var mtime: TimeInterval
        var entries: [UsageEntry]
        var lastActivity: Date?
    }

    private var cache: [String: ConvState] = [:]
    /// Cached during scan() so scanActivity() avoids a second full enumeration.
    private var latestTranscriptURL: URL?
    private var latestTranscriptMtime: Date?

    func scan() -> UsageSnapshot {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let brainRoot = home.appendingPathComponent(".gemini/antigravity/brain")

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: brainRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return .empty
        }

        var liveConvs = Set<String>()
        var scanLatestURL: URL?
        var scanLatestMtime: Date?

        guard let convDirs = try? fm.contentsOfDirectory(at: brainRoot,
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else {
            return .empty
        }

        for convDir in convDirs {
            guard (try? convDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let transcriptURL = convDir
                .appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard fm.fileExists(atPath: transcriptURL.path) else { continue }

            let convID = convDir.lastPathComponent
            liveConvs.insert(convID)

            guard let attrs = try? fm.attributesOfItem(atPath: transcriptURL.path),
                  let mtime = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int, size > 0 else { continue }

            let mtimeInterval = mtime.timeIntervalSince1970

            // Track the most-recently-modified transcript for scanActivity().
            if scanLatestMtime == nil || mtime > scanLatestMtime! {
                scanLatestMtime = mtime
                scanLatestURL = transcriptURL
            }

            if let cached = cache[convID], cached.mtime == mtimeInterval { continue }

            let (fileEntries, lastSeen) = parseAntigravityFile(url: transcriptURL, convID: convID)
            cache[convID] = ConvState(mtime: mtimeInterval,
                                      entries: fileEntries,
                                      lastActivity: lastSeen)
        }

        // Persist latest file info for scanActivity().
        self.latestTranscriptURL = scanLatestURL
        self.latestTranscriptMtime = scanLatestMtime

        // Drop deleted conversations
        for id in cache.keys where !liveConvs.contains(id) { cache.removeValue(forKey: id) }

        var allEntries: [UsageEntry] = []
        for state in cache.values {
            allEntries.append(contentsOf: state.entries)
        }

        allEntries.sort { $0.timestamp < $1.timestamp }

        let stats = ScanStats(
            filesSeen: cache.count,
            filesParsed: cache.count,
            rawUsageLines: allEntries.count,
            duplicatesSkipped: 0,
            scanDuration: 0
        )

        return Aggregator.buildSnapshot(entries: allEntries, stats: stats, now: Date())
    }

    private func parseAntigravityFile(url: URL, convID: String) -> (entries: [UsageEntry], lastSeen: Date?) {
        guard let data = try? Data(contentsOf: url) else { return ([], nil) }
        let decoder = JSONDecoder()

        struct TranscriptLine: Decodable {
            let type: String?
            let created_at: String?
            let content: String?
        }

        var entries: [UsageEntry] = []
        var currentModel = "gemini-3.5-flash"
        var lastSeen: Date? = nil

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = data.count
            var lineStart = 0, i = 0
            while i < count {
                if base[i] == 0x0A {
                    if i > lineStart {
                        let lineData = data.subdata(in: lineStart..<i)
                        if let lineObj = try? decoder.decode(TranscriptLine.self, from: lineData) {
                            let tsString = lineObj.created_at ?? ""
                            let timestamp = ISO8601.parse(tsString) ?? Date()
                            lastSeen = timestamp
                            
                            if let content = lineObj.content, content.contains("<USER_SETTINGS_CHANGE>") {
                                let pattern = "Model Selection`?\\s+from\\s+(.*?)\\s+to\\s+`?(.*?)[`.\\n]"
                                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                                    let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
                                    if let match = regex.firstMatch(in: content, options: [], range: nsRange),
                                       match.numberOfRanges >= 3,
                                       let toRange = Range(match.range(at: 2), in: content) {
                                        let modelStr = String(content[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                        if modelStr != "None" && !modelStr.isEmpty {
                                            currentModel = normalizeModelName(modelStr)
                                        }
                                    }
                                }
                            }
                            
                            if lineObj.type == "PLANNER_RESPONSE" {
                                let (cost, priced) = PricingTable.cost(
                                    model: currentModel, input: 2000, output: 500,
                                    cacheCreation: 0, cacheRead: 0
                                )
                                let entry = UsageEntry(
                                    timestamp: timestamp,
                                    model: currentModel,
                                    inputTokens: 2000,
                                    outputTokens: 500,
                                    cacheCreationTokens: 0,
                                    cacheReadTokens: 0,
                                    costUSD: cost,
                                    projectName: "Usage Monitor",
                                    priced: priced
                                )
                                entries.append(entry)
                            }
                        }
                    }
                    lineStart = i + 1
                }
                i += 1
            }
        }
        return (entries, lastSeen)
    }

    private func normalizeModelName(_ raw: String) -> String {
        let normalized = raw.lowercased()
        if normalized.contains("opus 4.6") { return "claude-opus-4-6" }
        if normalized.contains("opus 4.5") { return "claude-opus-4-5" }
        if normalized.contains("sonnet 4.6") { return "claude-sonnet-4-6" }
        if normalized.contains("sonnet 4.5") { return "claude-sonnet-4-5" }
        if normalized.contains("gemini 3.5 flash") || normalized.contains("flash") { return "gemini-3.5-flash" }
        if normalized.contains("gemini 2.5 pro") || normalized.contains("pro") { return "gemini-2.5-pro" }
        if normalized.contains("opus") { return "claude-3-opus" }
        if normalized.contains("sonnet") { return "claude-3-5-sonnet" }
        return "gemini-3.5-flash"
    }

    func scanActivity(now: Date = Date()) -> AgentActivity {
        // Reuse the latest transcript discovered during scan() — avoids a
        // second full directory enumeration.
        let latestFile = self.latestTranscriptURL
        let latestMtime = self.latestTranscriptMtime
        
        guard let url = latestFile, let mtime = latestMtime else {
            return AgentActivity(agent: .antigravity, state: .idle, project: "—", currentTask: "—", activeScript: nil, lastUpdated: now)
        }
        
        if now.timeIntervalSince(mtime) > 60 {
            return AgentActivity(agent: .antigravity, state: .idle, project: "—", currentTask: "—", activeScript: nil, lastUpdated: mtime)
        }
        
        let lines = UsageDataSource.readLastLines(url: url)
        let project = "Usage Monitor"
        var task = "General Task"
        var activeScript: String? = nil
        var state: AgentActivityState = .idle
        
        struct AntigravityLine: Decodable {
            let type: String?
            let content: String?
            let tool_calls: [ToolCall]?
            
            struct ToolCall: Decodable {
                let name: String?
                let args: Args?
                
                struct Args: Decodable {
                    let CommandLine: String?
                    let TargetFile: String?
                    let AbsolutePath: String?
                }
            }
        }
        
        let decoder = JSONDecoder()
        var hasToolUse = false
        var toolUseName = ""
        var toolUseDetails = ""
        
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? decoder.decode(AntigravityLine.self, from: data) else { continue }
            
            if obj.type == "USER_INPUT", let content = obj.content, task == "General Task" {
                task = content
            }
            if obj.type == "PLANNER_RESPONSE" {
                if let calls = obj.tool_calls {
                    hasToolUse = true
                    for call in calls {
                        if let name = call.name {
                            toolUseName = name
                            toolUseDetails = call.args?.CommandLine ?? call.args?.TargetFile ?? call.args?.AbsolutePath ?? ""
                        }
                    }
                }
            } else if obj.type == "SYSTEM" || obj.type == "USER" {
                hasToolUse = false
            }
        }
        
        if hasToolUse {
            let detailStr = toolUseDetails.count > 40 ? String(toolUseDetails.prefix(37)) + "..." : toolUseDetails
            activeScript = "Executing: \(toolUseName) (\(detailStr))"
            if now.timeIntervalSince(mtime) < 4 {
                state = .running
            } else {
                state = .interventionNeeded
            }
        } else {
            state = .finished
        }
        
        return AgentActivity(agent: .antigravity, state: state, project: project, currentTask: task, activeScript: activeScript, lastUpdated: mtime)
    }
}
