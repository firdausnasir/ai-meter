# Implementation Plan: Copilot History Chart

## Overview

Add quota snapshot history tracking and a multi-series trend chart to the Copilot tab, mirroring the existing `QuotaHistoryService` / `QuotaChartView` pattern for Claude.

---

## Build Command (run after each task to verify no regressions)

```
xcodebuild -project /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter.xcodeproj -scheme AIMeter -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```

Expected output on success:
```
** BUILD SUCCEEDED **
```

---

## Tasks

### Task 1: Create CopilotHistory.swift — data models

**File:** `/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/Shared/CopilotHistory.swift`

**Steps:**

1. Create the file with the following content:

```swift
import Foundation

struct CopilotHistoryDataPoint: Codable, Identifiable {
    var id: UUID
    let timestamp: Date
    let chatUtilization: Int?
    let chatRemaining: Int?
    let completionsUtilization: Int?
    let completionsRemaining: Int?
    let premiumUtilization: Int?
    let premiumRemaining: Int?

    init(
        timestamp: Date = Date(),
        chatUtilization: Int? = nil, chatRemaining: Int? = nil,
        completionsUtilization: Int? = nil, completionsRemaining: Int? = nil,
        premiumUtilization: Int? = nil, premiumRemaining: Int? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.chatUtilization = chatUtilization
        self.chatRemaining = chatRemaining
        self.completionsUtilization = completionsUtilization
        self.completionsRemaining = completionsRemaining
        self.premiumUtilization = premiumUtilization
        self.premiumRemaining = premiumRemaining
    }
}

struct CopilotHistory: Codable {
    var dataPoints: [CopilotHistoryDataPoint] = []
}

enum CopilotChartMetric: String, CaseIterable, Identifiable {
    case utilization = "Usage %"
    case remaining = "Remaining"

    var id: String { rawValue }
}
```

2. Add `CopilotHistory.swift` to the Xcode project under the `Shared` group (same group as `QuotaHistory.swift`). This is required for the file to compile — it must appear in the `.xcodeproj` target membership. Open the project in Xcode and drag the file into the `Shared` group, or use `File > Add Files to "AIMeter"` targeting the `AIMeter` target.

3. Run build — expect: `** BUILD SUCCEEDED **`

4. Commit: `feat: add CopilotHistory data models (CopilotHistoryDataPoint, CopilotHistory, CopilotChartMetric)`

---

### Task 2: Create CopilotHistoryService.swift

**File:** `/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/CopilotHistoryService.swift`

**Steps:**

1. Create the file with the following content (mirrors `QuotaHistoryService` exactly, adapted for `CopilotHistoryDataPoint` with nullable Int fields):

```swift
import Foundation
import Combine
import AppKit

@MainActor
final class CopilotHistoryService: ObservableObject {
    @Published var history = CopilotHistory()

    private var flushTimer: AnyCancellable?
    private var isDirty = false
    private var terminationObserver: Any?

    private static let retentionInterval: TimeInterval = 7 * 86400 // 7 days
    private static let flushInterval: TimeInterval = 300 // 5 minutes

    private static var historyFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("copilot-history.json")
    }

    init() {
        loadHistory()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.flushToDisk() }
        }
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func recordSnapshot(_ data: CopilotUsageData) {
        let point = CopilotHistoryDataPoint(
            chatUtilization: data.chat.unlimited ? nil : data.chat.utilization,
            chatRemaining: data.chat.unlimited ? nil : data.chat.remaining,
            completionsUtilization: data.completions.unlimited ? nil : data.completions.utilization,
            completionsRemaining: data.completions.unlimited ? nil : data.completions.remaining,
            premiumUtilization: data.premiumInteractions.unlimited ? nil : data.premiumInteractions.utilization,
            premiumRemaining: data.premiumInteractions.unlimited ? nil : data.premiumInteractions.remaining
        )
        history.dataPoints.append(point)
        isDirty = true
        startFlushTimerIfNeeded()
    }

    func downsampledPoints(for range: QuotaTimeRange) -> [CopilotHistoryDataPoint] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        let filtered = history.dataPoints.filter { $0.timestamp >= cutoff }
        guard filtered.count > range.targetPointCount else { return filtered }

        let bucketCount = range.targetPointCount
        let bucketDuration = range.interval / Double(bucketCount)

        var buckets = [[CopilotHistoryDataPoint]](repeating: [], count: bucketCount)
        for point in filtered {
            let offset = point.timestamp.timeIntervalSince(cutoff)
            var index = Int(offset / bucketDuration)
            if index < 0 { index = 0 }
            if index >= bucketCount { index = bucketCount - 1 }
            buckets[index].append(point)
        }

        return buckets.compactMap { bucket -> CopilotHistoryDataPoint? in
            guard !bucket.isEmpty else { return nil }
            let avgTime = bucket.map { $0.timestamp.timeIntervalSince1970 }.reduce(0, +) / Double(bucket.count)

            func avgNullableInt(_ keyPath: KeyPath<CopilotHistoryDataPoint, Int?>) -> Int? {
                let values = bucket.compactMap { $0[keyPath: keyPath] }
                guard !values.isEmpty else { return nil }
                return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
            }

            return CopilotHistoryDataPoint(
                timestamp: Date(timeIntervalSince1970: avgTime),
                chatUtilization: avgNullableInt(\.chatUtilization),
                chatRemaining: avgNullableInt(\.chatRemaining),
                completionsUtilization: avgNullableInt(\.completionsUtilization),
                completionsRemaining: avgNullableInt(\.completionsRemaining),
                premiumUtilization: avgNullableInt(\.premiumUtilization),
                premiumRemaining: avgNullableInt(\.premiumRemaining)
            )
        }
    }

    func flushToDisk() {
        guard isDirty else { return }
        history.dataPoints = pruned(history.dataPoints)
        guard let data = try? JSONEncoder.appEncoder.encode(history) else { return }
        try? data.write(to: Self.historyFileURL, options: .atomic)
        isDirty = false
        flushTimer?.cancel()
        flushTimer = nil
    }

    private func loadHistory() {
        let url = Self.historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            var loaded = try JSONDecoder.appDecoder.decode(CopilotHistory.self, from: data)
            loaded.dataPoints = pruned(loaded.dataPoints)
            history = loaded
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            history = CopilotHistory()
        }
    }

    private func startFlushTimerIfNeeded() {
        guard flushTimer == nil else { return }
        flushTimer = Timer.publish(every: Self.flushInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.flushToDisk() }
    }

    private func pruned(_ points: [CopilotHistoryDataPoint]) -> [CopilotHistoryDataPoint] {
        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        return points.filter { $0.timestamp >= cutoff }
    }
}
```

2. Add `CopilotHistoryService.swift` to the Xcode project under the `App` group (same group as `QuotaHistoryService.swift`), targeting the `AIMeter` target.

3. Run build — expect: `** BUILD SUCCEEDED **`

4. Commit: `feat: add CopilotHistoryService (snapshot recording, downsampling, 7-day persistence)`

---

### Task 3: Create CopilotChartView.swift

**File:** `/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/CopilotChartView.swift`

**Steps:**

1. Create the file with the following content:

```swift
import SwiftUI
import Charts

struct CopilotChartView: View {
    @ObservedObject var historyService: CopilotHistoryService
    @State private var selectedRange: QuotaTimeRange = .day1
    @State private var selectedMetric: CopilotChartMetric = .utilization

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

            Picker("", selection: $selectedMetric) {
                ForEach(CopilotChartMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
    private func chartView(points: [CopilotHistoryDataPoint]) -> some View {
        let showChat = points.contains { $0.chatUtilization != nil || $0.chatRemaining != nil }
        let showCompletions = points.contains { $0.completionsUtilization != nil || $0.completionsRemaining != nil }
        let showPremium = points.contains { $0.premiumUtilization != nil || $0.premiumRemaining != nil }

        Chart {
            if showChat {
                ForEach(points) { point in
                    if let value = metricValue(point, series: .chat) {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(selectedMetric.rawValue, value)
                        )
                        .foregroundStyle(by: .value("Metric", "Chat"))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            if showCompletions {
                ForEach(points) { point in
                    if let value = metricValue(point, series: .completions) {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(selectedMetric.rawValue, value)
                        )
                        .foregroundStyle(by: .value("Metric", "Completions"))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            if showPremium {
                ForEach(points) { point in
                    if let value = metricValue(point, series: .premium) {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(selectedMetric.rawValue, value)
                        )
                        .foregroundStyle(by: .value("Metric", "Premium"))
                        .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .modifier(ChartYAxisModifier(metric: selectedMetric))
        .chartYAxis {
            if selectedMetric == .utilization {
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
            } else {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9))
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                }
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
            "Chat": Color.blue,
            "Completions": Color.green,
            "Premium": Color.purple
        ])
        .chartLegend(.visible)
        .chartLegend(position: .bottom, spacing: 4)
        .frame(height: 80)
    }

    private enum Series { case chat, completions, premium }

    private func metricValue(_ point: CopilotHistoryDataPoint, series: Series) -> Double? {
        switch (selectedMetric, series) {
        case (.utilization, .chat): return point.chatUtilization.map(Double.init)
        case (.utilization, .completions): return point.completionsUtilization.map(Double.init)
        case (.utilization, .premium): return point.premiumUtilization.map(Double.init)
        case (.remaining, .chat): return point.chatRemaining.map(Double.init)
        case (.remaining, .completions): return point.completionsRemaining.map(Double.init)
        case (.remaining, .premium): return point.premiumRemaining.map(Double.init)
        }
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

// Separate modifier to apply chartYScale conditionally — Swift Charts requires
// the domain to be the same type as the data, so we only fix 0...100 for utilization.
private struct ChartYAxisModifier: ViewModifier {
    let metric: CopilotChartMetric

    func body(content: Content) -> some View {
        if metric == .utilization {
            content.chartYScale(domain: 0...100)
        } else {
            content
        }
    }
}
```

2. Add `CopilotChartView.swift` to the Xcode project under the `App` group (same group as `QuotaChartView.swift`), targeting the `AIMeter` target.

3. Run build — expect: `** BUILD SUCCEEDED **`

4. Commit: `feat: add CopilotChartView (multi-series line chart with metric toggle and time range picker)`

---

### Task 4: Modify CopilotService — inject CopilotHistoryService, call recordSnapshot

**File:** `/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/CopilotService.swift`

**Steps:**

1. Add a `private weak var copilotHistoryService: CopilotHistoryService?` property after the existing `private var refreshInterval` line.

2. Change the `start` signature from:
   ```swift
   func start(interval: TimeInterval = 60) {
   ```
   to:
   ```swift
   func start(interval: TimeInterval = 60, copilotHistoryService: CopilotHistoryService? = nil) {
   ```

3. As the first line of the new `start` body, add:
   ```swift
   self.copilotHistoryService = copilotHistoryService
   ```

4. In `fetch()`, after `SharedDefaults.saveCopilot(data)` and before `WidgetCenter.shared.reloadAllTimelines()`, add:
   ```swift
   copilotHistoryService?.recordSnapshot(data)
   ```

   The relevant block after the change:
   ```swift
   self.copilotData = data
   self.isStale = false
   self.error = nil
   SharedDefaults.saveCopilot(data)
   copilotHistoryService?.recordSnapshot(data)
   WidgetCenter.shared.reloadAllTimelines()
   ```

5. Run build — expect: `** BUILD SUCCEEDED **`

6. Commit: `feat: wire CopilotHistoryService into CopilotService.fetch()`

---

### Task 5: Modify AIMeterApp — instantiate CopilotHistoryService and pass through

**File:** `/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/AIMeterApp.swift`

**Steps:**

1. Add after the `@StateObject private var historyService = QuotaHistoryService()` line:
   ```swift
   @StateObject private var copilotHistoryService = CopilotHistoryService()
   ```

2. In the `.task { ... }` block, change:
   ```swift
   copilotService.start(interval: refreshInterval)
   ```
   to:
   ```swift
   copilotService.start(interval: refreshInterval, copilotHistoryService: copilotHistoryService)
   ```

3. In the `.onChange(of: refreshInterval)` handler, change:
   ```swift
   copilotService.stop()
   copilotService.start(interval: newValue)
   ```
   to:
   ```swift
   copilotService.stop()
   copilotService.start(interval: newValue, copilotHistoryService: copilotHistoryService)
   ```

4. Pass `copilotHistoryService` into `PopoverView`. Change the `PopoverView(...)` initializer call (line 46) to add `copilotHistoryService: copilotHistoryService` as a parameter. (The `PopoverView` initializer will be updated in the next task — do that task first if building incrementally, or do both in one build cycle.)

5. Run build after both Task 5 and Task 6 are applied — expect: `** BUILD SUCCEEDED **`

6. Commit: `feat: instantiate CopilotHistoryService in AIMeterApp and wire to CopilotService and PopoverView`

---

### Task 6: Modify PopoverView and CopilotTabView — add CopilotChartView

**File:** `/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/PopoverView.swift`

**Steps:**

1. In `PopoverView`, add after `@ObservedObject var copilotService: CopilotService`:
   ```swift
   @ObservedObject var copilotHistoryService: CopilotHistoryService
   ```

2. Update the call site in `PopoverView.body` where `CopilotTabView` is constructed (line 52). Change:
   ```swift
   CopilotTabView(copilotService: copilotService, timeZone: configuredTimeZone)
   ```
   to:
   ```swift
   CopilotTabView(copilotService: copilotService, copilotHistoryService: copilotHistoryService, timeZone: configuredTimeZone)
   ```

3. In `CopilotTabView`, add after `@ObservedObject var copilotService: CopilotService`:
   ```swift
   @ObservedObject var copilotHistoryService: CopilotHistoryService
   ```

4. In `CopilotTabView.body`, inside the `VStack(alignment: .leading, spacing: 6)` block, add `CopilotChartView` after the reset text and before the first `copilotQuotaRow`. The block becomes:

   ```swift
   VStack(alignment: .leading, spacing: 6) {
       if let resetText = ResetTimeFormatter.format(copilot.resetDate, style: .dayTime, timeZone: timeZone) {
           Text("Reset \(resetText)")
               .font(.system(size: 11))
               .foregroundColor(.secondary)
               .padding(.bottom, 2)
       }
       CopilotChartView(historyService: copilotHistoryService)
       copilotQuotaRow(title: "Chat", quota: copilot.chat)
       copilotQuotaRow(title: "Completions", quota: copilot.completions)
       copilotQuotaRow(title: "Premium", quota: copilot.premiumInteractions)
   }
   ```

5. Run build — expect: `** BUILD SUCCEEDED **`

6. Commit: `feat: add CopilotChartView to CopilotTabView between reset text and quota rows`

---

## Phase Assessment

This is a single-phase plan (6 tasks). The changes span 3 concerns (models + service + UI) but are not independently shippable in phases — each task directly depends on the previous. Total tasks: 6.

No phase split required.
