import SwiftUI

/// Unified Dashboard tab: shows dynamic usage metrics and visual gauges
/// for the selected AI agent.
struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Group {
            if store.snapshot == nil {
                loading
            } else if let snap = store.snapshot, snap.totalEntries == 0 && !store.limitsState.isLive {
                EmptyStateView()
            } else {
                dashboardContent
            }
        }
    }

    // MARK: - Loading

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Scanning \(store.selectedAgent.rawValue) usage data…")
                .font(.firaCode(12))
                .foregroundStyle(Color.neutral400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                fiveHourStrip
                limitHeadroomCard
                statGrid
                modelUsageCard
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage Dashboard")
                    .font(.firaCode(20, weight: .bold))
                    .foregroundStyle(store.selectedAgent.textGradient)
                Text("Real-time monitoring of your \(store.selectedAgent.rawValue) API usage")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral400)
            }

            let uResult = store.fiveHourUtilization() ?? (value: 0.0, isLive: false)
            ProgressRing(
                percentage: uResult.value,
                ringGradient: uResult.isLive ? UsageStatus(percentage: uResult.value).gradient : store.selectedAgent.ringGradient,
                centerLabel: uResult.isLive ? "LIMIT USED" : "SESSION USED",
                bigText: "",
                subtitle: store.sessionTimeLeft.map { "⏱ \($0) left" } ?? "no active session",
                diameter: 180
            )
            .frame(maxWidth: .infinity)
            .help("Session Ring:\n• How it's calculated: This reads your local log files (~/.claude/projects/) to count the exact number of tokens you consumed in your active session and compares it to your nominal plan limit (e.g., 10M tokens).\n• What it represents: Your actual physical consumption of your nominal token budget.")

            keyMetricsRow

            if case .estimated(let reason) = store.limitsState {
                Text("Live limits unavailable: \(reason)")
                    .font(.firaCode(10))
                    .foregroundStyle(store.selectedAgent.primaryColor)
            }
        }
        .warmCard(padding: 20)
    }

    private var keyMetricsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            metric(
                value: Format.tokens(store.activeBlockTokens),
                label: "Tokens Used",
                sub: "current 5h block"
            )
            metric(
                value: Format.cost(store.snapshot?.todayCost ?? 0),
                label: "Cost Today",
                sub: "\(Format.tokens(store.snapshot?.todayTokens ?? 0)) tokens"
            )
            if store.limitsState.isLive, let fiveHour = store.limits?.fiveHour {
                let left = max(0, 100 - fiveHour.utilization)
                metric(value: "\(Int(left.rounded()))%", label: "5h Limit Left", sub: "live")
            } else {
                metric(
                    value: store.sessionTimeLeft ?? "—",
                    label: "Session Left",
                    sub: store.sessionTimeLeft == nil ? "no active session" : "until reset"
                )
            }
        }
    }

    private func metric(value: String, label: String, sub: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.firaCode(20, weight: .bold))
                .foregroundStyle(Color.neutral100)
            Text(label)
                .font(.firaCode(11))
                .foregroundStyle(Color.neutral400)
            Text(sub)
                .font(.firaCode(10))
                .foregroundStyle(Color.neutral500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 5-hour strip

    private var fiveHourStrip: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                GradientIconTile(systemName: "clock", colors: GradientIconTile.fiveHour)
                VStack(alignment: .leading, spacing: 2) {
                    Text("5-Hour Block")
                        .font(.firaCode(13, weight: .bold))
                        .foregroundStyle(Color.neutral100)
                    Text(store.sessionTimeLeft.map { "Resets in \($0)" } ?? "No active session")
                        .font(.firaCode(10))
                        .foregroundStyle(Color.neutral400)
                }
            }
            Spacer()
            if let block = store.snapshot?.activeBlock {
                HStack(alignment: .top, spacing: 18) {
                    StatFigure(value: Format.tokens(block.totalTokens), label: "Tokens")
                    StatFigure(
                        value: block.burnRate.map { "\(Format.tokens(Int($0.tokensPerMinute)))/min" } ?? "--",
                        label: "Burn Rate"
                    )
                    StatFigure(
                        value: block.projection(now: Date()).map { Format.cost($0.projectedCost) } ?? "--",
                        label: "Projected Cost"
                    )
                }
            }
        }
        .warmCard()
    }

    // MARK: - Limit Headroom

    private var limitHeadroomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Limit Headroom")
                    .font(.firaCode(13, weight: .bold))
                    .foregroundStyle(Color.neutral100)
                Spacer()
                ThemedPill(
                    text: store.limitsState.isLive ? "live" : "estimated",
                    color: store.limitsState.isLive ? .safeFrom : store.selectedAgent.primaryColor
                )
            }
            .help("Limit Headroom Ring:\n• How it's calculated: This queries Anthropic's servers in real-time to see what they report as your rate limit status.\n• What it represents: The server's decision to allow or block your requests.")

            HStack(alignment: .top, spacing: 8) {
                if store.limitsState.isLive, let limits = store.limits {
                    if let fiveHour = limits.fiveHour {
                        UtilizationRing(label: fiveHour.label, utilization: fiveHour.utilization,
                                        resetsAt: fiveHour.resetsAt, isLive: true)
                        .help("Limit Headroom:\n• How it's calculated: This queries Anthropic's servers in real-time to see what they report as your rate limit status.\n• What it represents: The server's decision to allow or block your requests.")
                    }
                    if let sevenDay = limits.sevenDay {
                        UtilizationRing(label: sevenDay.label, utilization: sevenDay.utilization,
                                        resetsAt: sevenDay.resetsAt, isLive: true)
                        .help("Weekly limits: This queries Anthropic's servers in real-time for your accumulated 7-day rate limit usage.")
                    }
                    if let modelWeekly = limits.modelSpecificWeekly {
                        UtilizationRing(label: modelWeekly.label, utilization: modelWeekly.utilization,
                                        resetsAt: modelWeekly.resetsAt, isLive: true)
                    }
                } else if let estimated = store.estimatedFiveHourWindow {
                    UtilizationRing(label: estimated.label, utilization: estimated.utilization,
                                    resetsAt: estimated.resetsAt, isLive: false)
                    .help("Estimated Session: Estimated from your local active block token count vs plan limit.")
                    VStack(spacing: 6) {
                        Text(store.selectedAgent == .antigravity ? "No live limit window for Antigravity" : "Weekly limits need the live endpoint")
                            .font(.firaCode(10))
                            .foregroundStyle(Color.neutral400)
                            .multilineTextAlignment(.center)
                        Text(store.selectedAgent == .antigravity ? "Estimating from conversation history" : "Estimate uses plan limit: \(Format.tokens(store.localTokenLimit)) tokens")
                            .font(.firaCode(10))
                            .foregroundStyle(Color.neutral500)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                }
            }

            if let prediction = store.sessionPrediction {
                let warns = prediction.contains("hit") || prediction.contains("reached")
                HStack(spacing: 8) {
                    Image(systemName: warns ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(warns ? Color.warnFrom : Color.safeFrom)
                    Text(prediction)
                        .font(.firaCode(11))
                        .foregroundStyle(Color.neutral300)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.neutral800.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .warmCard()
    }

    // MARK: - 2x2 stat grid

    private var statGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        return LazyVGrid(columns: columns, spacing: 16) {
            currentPlanCard
            burnRateCard
            todayCard
            thisWeekCard
        }
    }

    private var planProgress: (label: String, value: String, fraction: Double, gradient: LinearGradient) {
        if let uResult = store.fiveHourUtilization() {
            let label = uResult.isLive ? "5h limit used" : "Session token usage"
            return (label, "\(Int(uResult.value.rounded()))%", uResult.value / 100.0, UsageStatus(percentage: uResult.value).gradient)
        }
        return ("No active session", "0%", 0.0, store.selectedAgent.ringGradient)
    }

    private var currentPlanCard: some View {
        let progress = planProgress
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                tile: GradientIconTile(systemName: "checkmark.shield",
                                       colors: GradientIconTile.today),
                title: store.selectedAgent == .claude ? store.planDisplayName : "Standard", subtitle: "Current Plan"
            )
            VStack(spacing: 8) {
                StatRow(label: progress.label, value: progress.value)
                ThemedProgressBar(value: progress.fraction, tint: progress.gradient, height: 8)
            }
        }
        .warmCard()
    }

    private var burnRateCard: some View {
        let rate = store.burnRatePerHour
        let badge: (String, Color) = rate > 1000
            ? ("High Usage", .critFrom)
            : rate > 500 ? ("Moderate Usage", .warnFrom) : ("Normal Usage", .safeFrom)
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                tile: GradientIconTile(systemName: "flame", colors: GradientIconTile.burnRate),
                title: Format.tokens(rate), subtitle: "Tokens/Hour"
            )
            VStack(spacing: 8) {
                StatRow(label: "Depletion",
                        value: store.sessionTimeLeft.map { "\($0) left" } ?? "No session")
                Text(badge.0)
                    .font(.firaCode(10, weight: .semibold))
                    .foregroundStyle(badge.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(badge.1.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .warmCard()
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                tile: GradientIconTile(systemName: "chart.line.uptrend.xyaxis",
                                       colors: GradientIconTile.today),
                title: "Today", subtitle: "Usage Summary"
            )
            VStack(spacing: 8) {
                StatRow(label: "Tokens", value: Format.tokens(store.snapshot?.todayTokens ?? 0))
                StatRow(label: "Cost", value: Format.cost(store.snapshot?.todayCost ?? 0))
                StatRow(label: "Models", value: "\(store.todayModelCount)")
            }
        }
        .warmCard()
    }

    private var thisWeekCard: some View {
        let totals = store.weekTotals
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                tile: GradientIconTile(systemName: "calendar", colors: GradientIconTile.week),
                title: "This Week", subtitle: "7-Day Summary"
            )
            VStack(spacing: 8) {
                StatRow(label: "Total Cost", value: Format.cost(totals.cost))
                StatRow(label: "Total Tokens", value: Format.tokens(totals.tokens))
                StatRow(label: "Avg Daily", value: Format.cost(totals.cost / 7))
            }
        }
        .warmCard()
    }

    private func cardHeader(tile: GradientIconTile, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.firaCode(15, weight: .bold))
                    .foregroundStyle(Color.neutral100)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral400)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Model usage

    private var modelUsageCard: some View {
        let models = store.dashboardModelUsage
        let total = max(1, models.reduce(0) { $0 + $1.tokens.total })
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Usage")
                    .font(.firaCode(13, weight: .bold))
                    .foregroundStyle(Color.neutral100)
                Text("Distribution by model (30 days)")
                    .font(.firaCode(10))
                    .foregroundStyle(Color.neutral400)
            }
            if models.isEmpty {
                Text("No model usage data available")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    modelRow(model, total: total, index: index)
                }
            }
        }
        .warmCard()
    }

    private func modelRow(_ model: ModelUsage, total: Int, index: Int) -> some View {
        let pct = Double(model.tokens.total) / Double(total) * 100
        let dotColors: [Color] = [Color(hex: 0xA855F7), Color(hex: 0x3B82F6), Color(hex: 0x22C55E)]
        let dot = dotColors[min(index, dotColors.count - 1)]
        return HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 10, height: 10)
            VStack(spacing: 4) {
                HStack {
                    Text(Format.shortModelName(model.model))
                        .font(.firaCode(11, weight: .medium))
                        .foregroundStyle(Color.neutral100)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Format.tokens(model.tokens.total)) (\(String(format: "%.1f", pct))%)")
                        .font(.firaCode(10))
                        .foregroundStyle(Color.neutral400)
                }
                ThemedProgressBar(
                    value: pct / 100,
                    tint: LinearGradient(colors: [dot, dot.opacity(0.6)],
                                         startPoint: .leading, endPoint: .trailing),
                    height: 5
                )
            }
        }
    }
}
