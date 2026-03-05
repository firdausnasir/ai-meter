import SwiftUI
import Charts

struct QuotaChartView: View {
    @ObservedObject var historyService: QuotaHistoryService
    @State private var selectedRange: QuotaTimeRange = .day1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trend")
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

            let points = historyService.downsampledPoints(for: selectedRange)

            if points.isEmpty {
                Text("No history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                chartView(points: points)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func chartView(points: [QuotaDataPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.session * 100)
                )
                .foregroundStyle(by: .value("Metric", "Session"))
                .interpolationMethod(.monotone)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.weekly * 100)
                )
                .foregroundStyle(by: .value("Metric", "Weekly"))
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.system(size: 9))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.1))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: xAxisFormat)
                    .font(.system(size: 9))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.1))
            }
        }
        .chartForegroundStyleScale([
            "Session": Color.blue,
            "Weekly": Color.orange
        ])
        .chartLegend(.visible)
        .chartLegend(position: .bottom, spacing: 4)
        .frame(height: 80)
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .hour1:
            return .dateTime.hour().minute()
        case .hour6, .day1:
            return .dateTime.hour()
        case .day7:
            return .dateTime.weekday(.abbreviated)
        }
    }
}
