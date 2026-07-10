import SwiftUI

/// Overview tab — three compact terminal-style cards, one per agent.
struct OverviewView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AgentCompactCard(agent: .claude)
                AgentCompactCard(agent: .codex)
                AgentCompactCard(agent: .antigravity)
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Compact agent card

/// A dark terminal-style card matching the reference design:
/// [AgentName]  ● LIVE X.Xk tok/min
/// Session   Xh Xm  XX%  [━━━━━━━━░░░]
/// Weekly    Xh Xm  XX%  [━━━━░░░░░░]
/// X ← Read+Y · Z tok  $A.BB/turn · N  $C.DD
struct AgentCompactCard: View {
    let agent: AIAgent
    @EnvironmentObject private var store: UsageStore

    // MARK: - Computed data

    private var agentSnap: AgentSnapshot {
        switch agent {
        case .claude:      return store.claudeSummary
        case .codex:       return store.codexSummary
        case .antigravity: return store.antigravitySummary
        }
    }

    private var agentSnapshot: UsageSnapshot? {
        switch agent {
        case .claude:      return store.claudeSnapshot
        case .codex:       return store.codexSnapshot
        case .antigravity: return store.antigravitySnapshot
        }
    }

    // Session progress (0…1) and label
    private var sessionFraction: Double {
        // 1. If live limits are available, prioritize server-truth utilization
        switch agent {
        case .claude:
            if store.claudeLimitsState.isLive, let window = store.claudeLimits?.fiveHour {
                return min(1.0, max(0.0, window.utilization / 100.0))
            }
        case .codex:
            if let window = store.codexLimits?.fiveHour {
                return min(1.0, max(0.0, window.utilization / 100.0))
            }
        case .antigravity:
            break
        }

        // 2. Fall back to local token count vs nominal plan limit
        guard let s = agentSnapshot, let block = s.activeBlock else { return 0 }
        let limit = store.settings.tokenLimit(observedMaxBlockTokens: s.maxBlockTokens)
        return min(1.0, Double(block.totalTokens) / Double(max(limit, 1)))
    }

    private var sessionTimeLabel: String {
        // Use live resetsAt if available
        switch agent {
        case .claude:
            if store.claudeLimitsState.isLive, let window = store.claudeLimits?.fiveHour, let resetsAt = window.resetsAt {
                let remaining = resetsAt.timeIntervalSinceNow
                if remaining > 0 { return "resets at \(Format.time(resetsAt))" }
            }
        case .codex:
            if let window = store.codexLimits?.fiveHour, let resetsAt = window.resetsAt {
                let remaining = resetsAt.timeIntervalSinceNow
                if remaining > 0 { return "resets at \(Format.time(resetsAt))" }
            }
        case .antigravity:
            break
        }

        guard let s = agentSnapshot else { return "—" }
        if let block = s.activeBlock {
            let remaining = block.endTime.timeIntervalSinceNow
            if remaining > 0 { return "ends at \(Format.time(block.endTime))" }
            return "resetting…"
        }
        return "\(s.blocks.count) sessions"
    }

    private var sessionPct: Int {
        Int((sessionFraction * 100).rounded())
    }

    // Weekly progress (0…1) and label
    private var weeklyFraction: Double {
        guard let s = agentSnapshot else { return 0 }
        let limit = store.settings.tokenLimit(observedMaxBlockTokens: s.maxBlockTokens)
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = s.daily.filter { $0.date >= cutoff }
        let weeklyTokens = recent.reduce(0) { $0 + $1.tokens.total }
        return min(1.0, Double(weeklyTokens) / Double(max(limit, 1) * 7))
    }

    private var weeklyLabel: String {
        guard let s = agentSnapshot else { return "—" }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = s.daily.filter { $0.date >= cutoff }
        let weeklyCost = recent.reduce(0) { $0 + $1.cost }
        return Format.cost(weeklyCost)
    }

    private var weeklyPct: Int {
        Int((weeklyFraction * 100).rounded())
    }

    // Burn rate (tok/min)
    private var burnRateLabel: String {
        guard let s = agentSnapshot, let block = s.activeBlock, let rate = block.burnRate else { return "—" }
        let tpm = rate.tokensPerMinute
        return tpm > 0 ? "\(Format.tokens(Int(tpm)))" : "—"
    }

    private var isLive: Bool {
        agentSnapshot?.activeBlock != nil
    }

    // Bottom stats
    private var inputLabel: String  { Format.tokens(agentSnap.inputTokens) }
    private var outputLabel: String { Format.tokens(agentSnap.outputTokens) }
    private var costLabel: String   { Format.cost(agentSnap.costUSD) }

    private var costPerTurn: String {
        guard let s = agentSnapshot, let block = s.activeBlock, block.entryCount > 0 else { return "—" }
        return Format.cost(block.costUSD / Double(block.entryCount))
    }

    private var turnCount: Int {
        agentSnapshot?.blocks.reduce(0) { $0 + $1.entryCount } ?? 0
    }

    // MARK: - Accent colour

    private var accent: Color { Color(hex: agent.accentHex) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerRow
            Divider().background(Color.neutral700.opacity(0.5))
            progressRow(label: "Session",
                        timeLabel: sessionTimeLabel,
                        pct: sessionPct,
                        fraction: sessionFraction,
                        barColor: agent.sessionColor)
            .help(agent == .antigravity
                  ? "Session: Estimated from your local Antigravity conversation history."
                  : "Session: This shows your 5-hour rate limit utilization. It represents the server's rate limit status (server-truth when live, otherwise estimated from your local active block vs plan limit).")
            progressRow(label: "Weekly",
                        timeLabel: weeklyLabel,
                        pct: weeklyPct,
                        fraction: weeklyFraction,
                        barColor: agent.weeklyColor)
            .help("Weekly: This shows your accumulated token usage and estimated cost over the last 7 days.")
            Divider().background(Color.neutral700.opacity(0.5))
            statsRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0x0D1117).opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: accent.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // Agent name pill (black background, bold colored text)
            Text(agentDisplayName)
                .font(.firaCode(16, weight: .bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(accent.opacity(0.35), lineWidth: 1)
                )

            Spacer()

            // LIVE badge + burn rate
            HStack(spacing: 5) {
                Circle()
                    .fill(isLive ? Color.safeFrom : Color.neutral600)
                    .frame(width: 7, height: 7)
                    .shadow(color: isLive ? Color.safeFrom.opacity(0.8) : .clear, radius: 3)
                Text(isLive ? "LIVE" : "IDLE")
                    .font(.firaCode(10, weight: .semibold))
                    .foregroundStyle(isLive ? Color.safeFrom : Color.neutral500)
                if burnRateLabel != "—" {
                    Text("·")
                        .foregroundStyle(Color.neutral600)
                    Text("\(burnRateLabel) tok/min")
                        .font(.firaCode(10))
                        .foregroundStyle(Color.neutral300)
                }
            }
        }
    }

    private var agentDisplayName: String {
        switch agent {
        case .claude:      return "CLAUDE"
        case .codex:       return "CODEX"
        case .antigravity: return "ANTIGRAVITY"
        }
    }

    // MARK: - Progress row

    private func progressRow(
        label: String, timeLabel: String,
        pct: Int, fraction: Double,
        barColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.firaCode(12, weight: .semibold))
                    .foregroundStyle(Color.neutral100)
                Spacer()
                Text(timeLabel)
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral400)
                Text("\(pct)%")
                    .font(.firaCode(12, weight: .bold))
                    .foregroundStyle(Color.neutral100)
                    .frame(width: 36, alignment: .trailing)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.neutral800.opacity(0.7))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [barColor, barColor.opacity(0.65)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            // Input / output tokens
            statChip(
                icon: "↓",
                value: inputLabel,
                iconColor: Color(hex: 0x6FA8DC)
            )
            Text("·").font(.firaCode(11)).foregroundStyle(Color.neutral600).padding(.horizontal, 4)
            statChip(
                icon: "↑",
                value: outputLabel,
                iconColor: Color(hex: 0xA855F7)
            )

            Text("·").font(.firaCode(11)).foregroundStyle(Color.neutral600).padding(.horizontal, 4)

            // Cost per turn
            Text("$\(costLabel)")
                .font(.firaCode(11, weight: .medium))
                .foregroundStyle(Color(hex: 0xF8A55A))

            if costPerTurn != "—" {
                Text("·").font(.firaCode(11)).foregroundStyle(Color.neutral600).padding(.horizontal, 4)
                Text("\(costPerTurn)/turn")
                    .font(.firaCode(10))
                    .foregroundStyle(Color.neutral500)
            }

            Spacer()

            // Turn / session count
            Text("\(turnCount)")
                .font(.firaCode(11, weight: .semibold))
                .foregroundStyle(Color.neutral300)
            Text("turns")
                .font(.firaCode(10))
                .foregroundStyle(Color.neutral600)
                .padding(.leading, 3)
        }
    }

    private func statChip(icon: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: 3) {
            Text(icon)
                .font(.firaCode(10, weight: .bold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.firaCode(11))
                .foregroundStyle(Color.neutral300)
        }
    }
}
