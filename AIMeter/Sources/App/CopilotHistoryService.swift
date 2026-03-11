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
        let point = CopilotHistoryDataPoint(from: data)
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

            func avgNilableInt(_ keyPath: KeyPath<CopilotHistoryDataPoint, Int?>) -> Int? {
                let nonNil = bucket.compactMap { $0[keyPath: keyPath] }
                guard !nonNil.isEmpty else { return nil }
                return Int((Double(nonNil.reduce(0, +)) / Double(nonNil.count)).rounded())
            }

            // Build a synthetic CopilotUsageData from bucket averages to reuse the initializer
            // We use a custom init directly instead to avoid reconstructing CopilotUsageData
            return CopilotHistoryDataPoint(
                timestamp: Date(timeIntervalSince1970: avgTime),
                chatUtilization: avgNilableInt(\.chatUtilization),
                chatRemaining: avgNilableInt(\.chatRemaining),
                completionsUtilization: avgNilableInt(\.completionsUtilization),
                completionsRemaining: avgNilableInt(\.completionsRemaining),
                premiumUtilization: avgNilableInt(\.premiumUtilization),
                premiumRemaining: avgNilableInt(\.premiumRemaining)
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
