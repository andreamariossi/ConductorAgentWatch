import SwiftUI

/// Preferences tab, warm-themed. Writes through to ~/.conductoragentwatch/settings.json
/// (shared with the legacy app; unknown keys are preserved).
struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var customLimitText = ""
    @State private var launchAtLogin = false
    @State private var launchAtLoginFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                planSection
                menuBarSection
                widgetSection
                startupSection
                refreshSection
                aboutSection
            }
            .padding(.bottom, 8)
        }
        .tint(store.selectedAgent.primaryColor)
        .onAppear {
            customLimitText = store.settings.customTokenLimit.map(String.init) ?? ""
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "\(store.selectedAgent.rawValue) Plan")
            Picker("Plan", selection: planBinding) {
                ForEach(AppSettings.Plan.allCases) { plan in
                    Text(plan.displayName).font(.firaCode(11)).tag(plan)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.firaCode(11))

            if store.settings.plan == .custom {
                HStack {
                    TextField("Custom token limit", text: $customLimitText)
                        .textFieldStyle(.roundedBorder)
                        .font(.firaCode(11))
                        .frame(width: 160)
                    Button("Apply") { applyCustomLimit() }
                        .font(.firaCode(11))
                }
            }

            Text(planExplanation)
                .font(.firaCode(10))
                .foregroundStyle(Color.neutral400)
        }
        .warmCard()
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Menu Bar")
            Picker("Display", selection: displayModeBinding) {
                Text("Percentage").tag(AppSettings.MenuBarDisplayMode.percentage)
                Text("Cost").tag(AppSettings.MenuBarDisplayMode.cost)
                Text("Alternate").tag(AppSettings.MenuBarDisplayMode.alternate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.settings.menuBarDisplayMode != .percentage {
                Picker("Cost source", selection: costSourceBinding) {
                    Text("Today's cost").tag(AppSettings.CostSource.today)
                    Text("Session window").tag(AppSettings.CostSource.sessionWindow)
                }
                .font(.firaCode(11))
            }
        }
        .warmCard()
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Startup")
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at login")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral100)
            }
            .toggleStyle(.switch)
            .tint(store.selectedAgent.primaryColor)

            Text(launchAtLoginFailed
                ? "Couldn't update the login item. Move Conductor AgentWatch to /Applications and try again."
                : "Start Conductor AgentWatch automatically when you log in.")
                .font(.firaCode(10))
                .foregroundStyle(launchAtLoginFailed ? Color.warnFrom : Color.neutral400)
        }
        .warmCard()
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Refresh")
            Picker("Fallback interval", selection: refreshIntervalBinding) {
                Text("30 seconds").tag(30)
                Text("60 seconds").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
            }
            .font(.firaCode(11))
            Text(refreshExplanation)
                .font(.firaCode(10))
                .foregroundStyle(Color.neutral400)
        }
        .warmCard()
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "About")
            Text("Settings file: \(store.settingsFilePath)")
                .font(.firaCode(10))
                .foregroundStyle(Color.neutral400)
                .textSelection(.enabled)
            Text(aboutExplanation)
                .font(.firaCode(10))
                .foregroundStyle(Color.neutral500)
        }
        .warmCard()
    }

    private var widgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Desktop Widget")
            Toggle(isOn: showWidgetBinding) {
                Text("Show widget on desktop")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral100)
            }
            .toggleStyle(.switch)
            .tint(store.selectedAgent.primaryColor)
            
            Divider().background(Color.neutral700.opacity(0.3))
            
            HStack {
                Text("Widget Size")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral100)
                Spacer()
                Picker("Size", selection: widgetScaleBinding) {
                    ForEach(AppSettings.WidgetScale.allCases) { scale in
                        Text(scale.displayName).tag(scale)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.firaCode(11))
            }
        }
        .warmCard()
    }

    // MARK: - Bindings

    private var widgetScaleBinding: Binding<AppSettings.WidgetScale> {
        Binding(
            get: { store.settings.widgetScale },
            set: { newValue in
                var s = store.settings
                s.widgetScale = newValue
                store.updateSettings(s)
            }
        )
    }

    private var showWidgetBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showDesktopWidget },
            set: { newValue in
                var s = store.settings
                s.showDesktopWidget = newValue
                store.updateSettings(s)
                
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.updateWidgetVisibility()
                }
            }
        )
    }

    private var planBinding: Binding<AppSettings.Plan> {
        Binding(
            get: { store.settings.plan },
            set: { newValue in
                var s = store.settings
                s.plan = newValue
                store.updateSettings(s)
            }
        )
    }

    private var displayModeBinding: Binding<AppSettings.MenuBarDisplayMode> {
        Binding(
            get: { store.settings.menuBarDisplayMode },
            set: { newValue in
                var s = store.settings
                s.menuBarDisplayMode = newValue
                store.updateSettings(s)
            }
        )
    }

    private var costSourceBinding: Binding<AppSettings.CostSource> {
        Binding(
            get: { store.settings.menuBarCostSource },
            set: { newValue in
                var s = store.settings
                s.menuBarCostSource = newValue
                store.updateSettings(s)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                let ok = LaunchAtLogin.setEnabled(newValue)
                launchAtLoginFailed = !ok
                // Reflect the OS's actual state if the change was rejected.
                launchAtLogin = ok ? newValue : LaunchAtLogin.isEnabled
            }
        )
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { store.settings.refreshIntervalSeconds },
            set: { newValue in
                var s = store.settings
                s.refreshIntervalSeconds = newValue
                store.updateSettings(s)
            }
        )
    }

    private func applyCustomLimit() {
        guard let value = Int(customLimitText.trimmingCharacters(in: .whitespaces)), value > 0 else {
            customLimitText = store.settings.customTokenLimit.map(String.init) ?? ""
            return
        }
        var s = store.settings
        s.customTokenLimit = value
        store.updateSettings(s)
    }

    private var planExplanation: String {
        switch store.selectedAgent {
        case .claude:
            return "Used only for the local fallback estimate when the live limits endpoint is unavailable. Effective limit: \(Format.tokens(store.localTokenLimit)) tokens per 5h block."
        case .codex:
            return "Used only for the local fallback estimate when live Codex limits are unavailable. Effective limit: \(Format.tokens(store.localTokenLimit)) tokens per 5h block."
        case .antigravity:
            return "Effective limit: \(Format.tokens(store.localTokenLimit)) tokens per 5h block."
        }
    }

    private var refreshExplanation: String {
        switch store.selectedAgent {
        case .claude:
            return "File changes under ~/.claude/projects refresh automatically (FSEvents). This interval is just the safety-net poll."
        case .codex:
            return "File changes under ~/.codex/sessions refresh automatically (FSEvents). This interval is just the safety-net poll."
        case .antigravity:
            return "File changes under ~/.gemini/antigravity/brain refresh automatically (FSEvents). This interval is just the safety-net poll."
        }
    }

    private var aboutExplanation: String {
        switch store.selectedAgent {
        case .claude:
            return "Limit gauges use Claude Code's unofficial OAuth usage endpoint; when unreachable, Conductor AgentWatch falls back to local estimates from your transcripts."
        case .codex:
            return "Limit gauges use Codex's local telemetry and billing estimations parsed from session rollouts."
        case .antigravity:
            return "Limit gauges estimate usage from your local planning transcripts."
        }
    }
}
