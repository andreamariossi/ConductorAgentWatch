import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.activities) { activity in
                    ActivityCard(activity: activity, now: now)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .onReceive(clock) { now = $0 }
    }
}

struct ActivityCard: View {
    let activity: AgentActivity
    let now: Date

    private var accent: Color {
        Color(hex: activity.agent.accentHex)
    }

    private var agentName: String {
        activity.agent.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            HStack {
                Text(agentName)
                    .font(.firaCode(14, weight: .bold))
                    .foregroundStyle(activity.agent.textGradient)
                
                Spacer()
                
                StatusBadge(state: activity.state, agent: activity.agent)
            }
            
            Divider().background(Color.neutral700.opacity(0.5))
            
            // Details Rows
            VStack(spacing: 8) {
                HStack(alignment: .center) {
                    Text("PROJECT:")
                        .font(.firaCode(10, weight: .bold))
                        .foregroundStyle(Color.neutral500)
                        .frame(width: 70, alignment: .leading)
                    
                    Text(activity.project)
                        .font(.firaCode(11, weight: .semibold))
                        .foregroundStyle(Color.neutral300)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if activity.state != .idle {
                        Text(timeAgoLabel(from: activity.lastUpdated, now: now))
                            .font(.firaCode(10))
                            .foregroundStyle(Color.neutral500)
                    }
                }
                
                HStack(alignment: .top) {
                    Text("TASK:")
                        .font(.firaCode(10, weight: .bold))
                        .foregroundStyle(Color.neutral500)
                        .frame(width: 70, alignment: .leading)
                    
                    Text(activity.currentTask)
                        .font(.firaCode(11, weight: .medium))
                        .foregroundStyle(Color.neutral300)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
            }
            
            // Code block for executing scripts
            if let script = activity.activeScript {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVE COMMAND:")
                        .font(.firaCode(10, weight: .bold))
                        .foregroundStyle(Color.neutral500)
                    
                    Text(script)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.neutral300)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.neutral900.opacity(0.85))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accent.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.top, 2)
            }
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

    private func timeAgoLabel(from date: Date, now: Date) -> String {
        let diff = now.timeIntervalSince(date)
        if diff < 0 {
            return "Just now"
        } else if diff < 5 {
            return "Just now"
        } else if diff < 60 {
            return "\(Int(diff))s ago"
        } else {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        }
    }
}

struct StatusBadge: View {
    let state: AgentActivityState
    let agent: AIAgent
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if state == .running || state == .interventionNeeded {
                    Circle()
                        .fill(stateColor)
                        .scaleEffect(pulse ? 1.6 : 1.0)
                        .opacity(pulse ? 0.0 : 0.6)
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                pulse = true
                            }
                        }
                }
                
                if state == .finished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(stateColor)
                } else {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 14, height: 14)
            
            Text(state.rawValue.uppercased())
                .font(.firaCode(9, weight: .bold))
                .foregroundStyle(stateColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(stateColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(stateColor.opacity(0.25), lineWidth: 1)
        )
    }
    
    private var stateColor: Color {
        switch state {
        case .running:
            return agent == .antigravity ? Color(hex: 0x3B82F6) : Color(hex: 0x10B981)
        case .interventionNeeded:
            return Color(hex: 0xEF4444)
        case .finished:
            return Color(hex: 0x10B981)
        case .idle:
            return Color.neutral500
        }
    }
}
