import SwiftUI
import Charts

/// Generic single-series history chart for providers that record one value over time.
struct UsageHistoryChartView: View {
    let title: String
    let dataPoints: [(date: Date, value: Double, label: String)]
    /// Formats the y-axis value for tooltips and the summary row (e.g. "45%" or "¥1.23")
    let valueFormatter: (Double) -> String
    let accentColor: Color

    @State private var selectedRange: QuotaTimeRange = .hour6
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Picker("", selection: $selectedRange) {
                    ForEach(QuotaTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            let filtered = filteredPoints
            if filtered.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    message: "No history yet",
                    hint: "Trends will appear as data is collected"
                )
            } else {
                chartBody(points: filtered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(AppRadius.card)
    }

    // MARK: - Filtered points for the selected range

    private var filteredPoints: [(date: Date, value: Double, label: String)] {
        let cutoff = Date().addingTimeInterval(-selectedRange.interval)
        return dataPoints.filter { $0.date >= cutoff }
    }

    // MARK: - Chart

    private func chartBody(points: [(date: Date, value: Double, label: String)]) -> some View {
        let values = points.map(\.value)
        let minVal = values.min() ?? 0
        let maxVal = max(values.max() ?? 1, minVal + 1)
        // Add a small padding above the max so the line isn't clipped
        let domainMax = maxVal + (maxVal - minVal) * 0.1

        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                LineMark(
                    x: .value("Time", pt.date),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Time", pt.date),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.25), accentColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }

            if let hoverDate {
                RuleMark(x: .value("Hover", hoverDate))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center) {
                        if let nearest = nearestPoint(to: hoverDate, in: points) {
                            VStack(spacing: 1) {
                                Text(nearest.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                Text(valueFormatter(nearest.value))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(accentColor)
                            }
                            .padding(4)
                            .background(Color.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                        }
                    }
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...domainMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(valueFormatter(v))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.1))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 80)
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverDate = proxy.value(atX: location.x, as: Date.self)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
    }

    private func nearestPoint(
        to date: Date,
        in points: [(date: Date, value: Double, label: String)]
    ) -> (date: Date, value: Double, label: String)? {
        points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
}
