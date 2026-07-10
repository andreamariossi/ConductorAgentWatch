import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case overview   = "Overview"
    case dashboard  = "Dashboard"
    case live       = "Live"
    case activity   = "Activity"
    case analytics  = "Analytics"
    case settings   = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview:   return "square.grid.2x2"
        case .dashboard:  return "gauge.with.dots.needle.67percent"
        case .live:       return "waveform.path.ecg"
        case .activity:   return "bolt.horizontal.fill"
        case .analytics:  return "chart.xyaxis.line"
        case .settings:   return "gearshape"
        }
    }
}

/// Widget root: warm background + header + global agent bar + tab bar + content.
struct RootView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var selectedTab: AppTab = .overview
    @State private var hoverQuit = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 10) {
                header
                agentPicker
                tabBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(14)
        }
        .frame(minWidth: 400, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .preferredColorScheme(.dark)
        .onReceive(clock) { now = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            AppIconImage(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Conductor AgentWatch")
                    .font(.firaCode(16, weight: .bold))
                    .foregroundStyle(store.selectedAgent.textGradient)
                Text("Track API usage")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral400)
            }
            Spacer()

            // Time chip
            Text(timeString)
                .font(.firaCode(11, weight: .medium))
                .foregroundStyle(Color.neutral300)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Refresh
            iconButton(system: "arrow.clockwise", spinning: store.isRefreshing) {
                store.manualRefresh()
            }
            .help("Refresh usage data and limits")

            // Close Widget Window (X)
            Button {
                if let window = NSApp.windows.first(where: { $0 is WidgetWindow }) {
                    window.orderOut(nil)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hoverQuit ? Color.critFrom : Color.neutral400)
                    .frame(width: 28, height: 28)
                    .background(
                        (hoverQuit ? Color.critFrom.opacity(0.12) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hoverQuit = $0 }
            .help("Hide Widget")
        }
    }

    // MARK: - Global Agent Picker

    /// This bar is shown on every tab so the user can switch agent context at any time.
    private var agentPicker: some View {
        HStack(spacing: 6) {
            ForEach(AIAgent.allCases) { agent in
                agentTab(agent)
            }
        }
        .padding(4)
        .background(Color.neutral900.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.neutral800, lineWidth: 1))
    }

    private func agentTab(_ agent: AIAgent) -> some View {
        let active = store.selectedAgent == agent
        let accent = Color(hex: agent.accentHex)
        return Button { store.selectedAgent = agent } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(active ? accent : Color.neutral600)
                    .frame(width: 6, height: 6)
                Text(agent.rawValue)
                    .font(.firaCode(11, weight: active ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(active ? .white : Color.neutral400)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.9), accent.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .shadow(color: accent.opacity(0.5), radius: 6, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                let active = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .medium))
                        Text(tab.rawValue)
                            .font(.firaCode(11, weight: active ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(active ? Color.white : Color.neutral400)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(store.selectedAgent.activeGradient)
                                .shadow(color: store.selectedAgent.primaryColor.opacity(0.4), radius: 6, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.neutral900.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.neutral800, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .overview:   OverviewView()
                              .id("overview-\(store.selectedAgent.id)")
        case .dashboard:  DashboardView()
                              .id("dashboard-\(store.selectedAgent.id)")
        case .live:       LiveView()
                              .id("live-\(store.selectedAgent.id)")
        case .activity:   ActivityView()
                              .id("activity-\(store.selectedAgent.id)")
        case .analytics:  AnalyticsView()
                              .id("analytics-\(store.selectedAgent.id)")
        case .settings:   SettingsView()
                              .id("settings-\(store.selectedAgent.id)")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func iconButton(system: String, spinning: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if spinning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: system)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.neutral300)
                }
            }
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }
}
