import Charts
import SwiftUI

/// Unified Historical charts — daily, weekly, model, and project breakdowns
/// with interactive timeframe, chart type, and metric selection.
struct AnalyticsView: View {
    @EnvironmentObject private var store: UsageStore

    @State private var selectedDays: Int = 7
    @State private var chartType: ChartType = .area
    @State private var selectedMetric: MetricType = .tokens

    enum ChartType {
        case area, line, bar
    }

    enum MetricType {
        case tokens, cost
    }

    private var chartData: [DailyUsage] {
        guard let snap = store.snapshot else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedDays, to: Date()) ?? Date()
        return snap.daily.filter { $0.date >= cutoff }.sorted(by: { $0.date < $1.date })
    }

    private var chartColor: Color {
        selectedMetric == .tokens ? Color.safeFrom : store.selectedAgent.primaryColor
    }

    var body: some View {
        if let snap = store.snapshot, snap.totalEntries > 0 {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    controlsSection
                    analyticsChart

                    modelBreakdown(snap)
                    projectBreakdown(snap)
                    weeklySummary(snap)
                    
                    if snap.hasUnpricedModels {
                        Text("Some models unpriced: \(snap.unknownModels.map(Format.shortModelName).joined(separator: ", "))")
                            .font(.firaCode(10))
                            .foregroundStyle(Color.neutral500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 8)
            }
        } else {
            EmptyStateView()
        }
    }

    // MARK: - Header & Controls

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage Analytics")
                    .font(.firaCode(20, weight: .bold))
                    .foregroundStyle(store.selectedAgent.textGradient)
                Text("Deep insights into your \(store.selectedAgent.rawValue) API consumption patterns")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral400)
            }
            Spacer()
            
            // Live data status indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.safeFrom)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.safeFrom.opacity(0.8), radius: 3)
                Text("Live Data")
                    .font(.firaCode(10, weight: .semibold))
                    .foregroundStyle(Color.neutral300)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.neutral800.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.neutral700.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Time Range Selection
                customSegmentedControl(
                    options: [7, 30],
                    label: { "\($0) Days" },
                    selected: $selectedDays,
                    activeColor: Color(hex: 0x3B82F6),
                    icon: { _ in "calendar" }
                )
                
                // Chart Type Selection
                customSegmentedControl(
                    options: [.area, .line, .bar],
                    label: { option in
                        switch option {
                        case .area: return "Area"
                        case .line: return "Line"
                        case .bar: return "Bar"
                        }
                    },
                    selected: $chartType,
                    activeColor: Color(hex: 0xA855F7),
                    icon: { option in
                        switch option {
                        case .area: return "waveform.path.ecg"
                        case .line: return "trending.up"
                        case .bar: return "chart.bar"
                        }
                    }
                )
            }
            
            // Metric Selection
            customSegmentedControl(
                options: [.tokens, .cost],
                label: { option in
                    switch option {
                    case .tokens: return "Tokens"
                    case .cost: return "Cost"
                    }
                },
                selected: $selectedMetric,
                activeColor: Color(hex: 0x22C55E),
                icon: { option in
                    switch option {
                    case .tokens: return "trending.up"
                    case .cost: return "dollarsign"
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func customSegmentedControl<T: Hashable>(
        options: [T],
        label: @escaping (T) -> String,
        selected: Binding<T>,
        activeColor: Color,
        icon: @escaping (T) -> String?
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    selected.wrappedValue = option
                } label: {
                    HStack(spacing: 6) {
                        if let iconName = icon(option) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(label(option))
                            .font(.firaCode(12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selected.wrappedValue == option ? activeColor : Color.clear)
                    .foregroundStyle(selected.wrappedValue == option ? Color.white : Color.neutral400)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(hex: 0x11161B))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.neutral800, lineWidth: 1)
        )
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    private var analyticsChart: some View {
        chartCard(title: "\(selectedMetric == .tokens ? "Daily Tokens" : "Daily Cost") — last \(selectedDays) days") {
            Chart(chartData) { day in
                let xVal = dayLabel(day.date)
                let yVal = selectedMetric == .tokens ? Double(day.tokens.total) : day.cost
                
                switch chartType {
                case .bar:
                    BarMark(
                        x: .value("Day", xVal),
                        y: .value(selectedMetric == .tokens ? "Tokens" : "Cost", yVal)
                    )
                    .foregroundStyle(chartColor)
                case .line:
                    LineMark(
                        x: .value("Day", xVal),
                        y: .value(selectedMetric == .tokens ? "Tokens" : "Cost", yVal)
                    )
                    .foregroundStyle(chartColor)
                case .area:
                    AreaMark(
                        x: .value("Day", xVal),
                        y: .value(selectedMetric == .tokens ? "Tokens" : "Cost", yVal)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [chartColor.opacity(0.4), chartColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    LineMark(
                        x: .value("Day", xVal),
                        y: .value(selectedMetric == .tokens ? "Tokens" : "Cost", yVal)
                    )
                    .foregroundStyle(chartColor)
                }
            }
            .chartYAxis {
                if selectedMetric == .tokens {
                    axisMarks { Format.tokens($0) }
                } else {
                    axisMarksDouble { Format.cost($0) }
                }
            }
            .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.neutral800) } }
            .frame(height: 140)
        }
    }

    // MARK: - Breakdowns

    private func modelBreakdown(_ snap: UsageSnapshot) -> some View {
        let models = snap.modelBreakdown.prefix(6).map { $0 }
        let accent = store.selectedAgent.primaryColor
        return chartCard(title: "Cost by Model — last 30 days") {
            Chart(models) { model in
                BarMark(x: .value("Cost", model.cost),
                        y: .value("Model", Format.shortModelName(model.model)))
                    .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                                    startPoint: .leading, endPoint: .trailing))
            }
            .chartXAxis { axisMarksDouble { Format.cost($0) } }
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) {
                    AxisValueLabel()
                        .font(.firaCode(9))
                        .foregroundStyle(Color.neutral400)
                }
            }
            .frame(height: CGFloat(max(1, min(models.count, 6))) * 30 + 30)
        }
    }

    private func projectBreakdown(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Projects This Month")
            if snap.projectsThisMonth.isEmpty {
                Text("No project usage data recorded")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(snap.projectsThisMonth.prefix(8)) { project in
                    HStack {
                        Text(project.name).font(.firaCode(11)).foregroundStyle(Color.neutral100).lineLimit(1)
                        Spacer()
                        Text(Format.tokens(project.totalTokens))
                            .font(.firaCode(10)).foregroundStyle(Color.neutral400)
                        Text(Format.cost(project.cost))
                            .font(.firaCode(11, weight: .medium)).foregroundStyle(Color.neutral100)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .warmCard()
    }

    private func weeklySummary(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Weekly Totals (Mon–Sun)")
            if snap.weekly.isEmpty {
                Text("No weekly totals recorded")
                    .font(.firaCode(11))
                    .foregroundStyle(Color.neutral500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(snap.weekly.suffix(4).reversed()) { week in
                    HStack {
                        Text(week.weekStart.formatted(date: .abbreviated, time: .omitted))
                            .font(.firaCode(11)).foregroundStyle(Color.neutral100)
                        Spacer()
                        Text(Format.tokens(week.tokens.total))
                            .font(.firaCode(10)).foregroundStyle(Color.neutral400)
                        Text(Format.cost(week.cost))
                            .font(.firaCode(11, weight: .medium)).foregroundStyle(Color.neutral100)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .warmCard()
    }

    // MARK: - Helpers

    private func chartCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            content()
        }
        .warmCard()
    }

    private func axisMarks(_ format: @escaping (Int) -> String) -> some AxisContent {
        AxisMarks { value in
            AxisGridLine().foregroundStyle(Color.neutral800)
            AxisValueLabel {
                if let v = value.as(Int.self) {
                    Text(format(v)).font(.firaCode(9)).foregroundStyle(Color.neutral400)
                }
            }
        }
    }

    private func axisMarksDouble(_ format: @escaping (Double) -> String) -> some AxisContent {
        AxisMarks { value in
            AxisGridLine().foregroundStyle(Color.neutral800)
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(format(v)).font(.firaCode(9)).foregroundStyle(Color.neutral400)
                }
            }
        }
    }
}
