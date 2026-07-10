import Foundation

/// `ConductorAgentWatch --diagnose`: headless functional check. Runs the JSONL scan, block
/// computation and weekly aggregation synchronously, probes the limits endpoint,
/// prints a summary and exits. Used to verify the data pipeline without
/// launching the UI.
enum Diagnose {
    static func run() {
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            let roots = UsageDataSource.discoverRoots()
            print("Conductor AgentWatch diagnose")
            print("=========================")
            print("Data roots: \(roots.isEmpty ? "(none found)" : roots.map(\.path).joined(separator: ", "))")

            let source = UsageDataSource()
            let snapshot = await source.scan()
            let stats = snapshot.stats

            print("Files seen: \(stats.filesSeen) (parsed this pass: \(stats.filesParsed))")
            print(String(format: "Scan duration: %.2fs", stats.scanDuration))
            print("Raw usage lines: \(stats.rawUsageLines)")
            print("Duplicates skipped: \(stats.duplicatesSkipped)")
            print("Entries after dedup: \(snapshot.totalEntries)")
            print("Session blocks: \(snapshot.blocks.count)")

            if let block = snapshot.activeBlock {
                print(String(
                    format: "Active block: %@ tokens, $%.2f, started %@, ends %@, models: %@",
                    Format.tokens(block.totalTokens), block.costUSD,
                    ISO8601.plain.string(from: block.startTime),
                    ISO8601.plain.string(from: block.endTime),
                    block.models.map(Format.shortModelName).joined(separator: ", ")
                ))
            } else {
                print("Active block: none")
            }

            print(String(format: "Today: %@ tokens, $%.2f", Format.tokens(snapshot.todayTokens), snapshot.todayCost))

            print("")
            print("Codex scan:")
            print("===========")
            let codexScanner = CodexScanner()
            let codexResult = await codexScanner.scan()
            let codexSnap = codexResult.snapshot
            print("Session blocks: \(codexSnap.blocks.count)")
            if let block = codexSnap.activeBlock {
                print(String(
                    format: "Active block: %@ tokens, $%.2f, started %@, ends %@, models: %@",
                    Format.tokens(block.totalTokens), block.costUSD,
                    ISO8601.plain.string(from: block.startTime),
                    ISO8601.plain.string(from: block.endTime),
                    block.models.map(Format.shortModelName).joined(separator: ", ")
                ))
            } else {
                print("Active block: none")
            }
            print(String(format: "Today: %@ tokens, $%.2f", Format.tokens(codexSnap.todayTokens), codexSnap.todayCost))

            print("")
            print("Antigravity scan:")
            print("=================")
            let antigravityScanner = AntigravityScanner()
            let agiSnap = await antigravityScanner.scan()
            print("Session blocks: \(agiSnap.blocks.count)")
            if let block = agiSnap.activeBlock {
                print(String(
                    format: "Active block: %@ tokens, $%.2f, started %@, ends %@, models: %@",
                    Format.tokens(block.totalTokens), block.costUSD,
                    ISO8601.plain.string(from: block.startTime),
                    ISO8601.plain.string(from: block.endTime),
                    block.models.map(Format.shortModelName).joined(separator: ", ")
                ))
            } else {
                print("Active block: none")
            }
            print(String(format: "Today: %@ tokens, $%.2f", Format.tokens(agiSnap.todayTokens), agiSnap.todayCost))

            print("")
            print("Limits endpoint:")
            let provider = OAuthLimitsProvider()
            do {
                let limits = try await provider.fetch()
                for window in limits.windows {
                    let reset = window.resetsAt.map {
                        "resets in \(Format.duration($0.timeIntervalSinceNow))"
                    } ?? "no reset time"
                    print(String(format: "  %@ [%@]: %.1f%%, %@",
                                 window.label, window.key, window.utilization, reset))
                }
            } catch {
                print("  unavailable: \(error)")
                print("  (gauges would fall back to local estimation)")
            }

            semaphore.signal()
        }

        semaphore.wait()
    }
}
