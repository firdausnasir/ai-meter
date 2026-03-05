import Foundation
import Combine
import AppKit

@MainActor
final class QuotaHistoryService: ObservableObject {
    @Published var history = QuotaHistory()

    private var flushTimer: AnyCancellable?
    private var isDirty = false
    private var terminationObserver: Any?

    private static let retentionInterval: TimeInterval = 7 * 86400 // 7 days
    private static let flushInterval: TimeInterval = 300 // 5 minutes

    private static var historyFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
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

    func recordDataPoint(session: Double, weekly: Double) {
        let point = QuotaDataPoint(session: session, weekly: weekly)
        history.dataPoints.append(point)
        isDirty = true
        startFlushTimerIfNeeded()
    }

    func downsampledPoints(for range: QuotaTimeRange) -> [QuotaDataPoint] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        let filtered = history.dataPoints.filter { $0.timestamp >= cutoff }
        guard filtered.count > range.targetPointCount else { return filtered }

        let bucketCount = range.targetPointCount
        let bucketDuration = range.interval / Double(bucketCount)

        var buckets = [[QuotaDataPoint]](repeating: [], count: bucketCount)
        for point in filtered {
            let offset = point.timestamp.timeIntervalSince(cutoff)
            var index = Int(offset / bucketDuration)
            if index < 0 { index = 0 }
            if index >= bucketCount { index = bucketCount - 1 }
            buckets[index].append(point)
        }

        return buckets.compactMap { bucket -> QuotaDataPoint? in
            guard !bucket.isEmpty else { return nil }
            let avgSession = bucket.map(\.session).reduce(0, +) / Double(bucket.count)
            let avgWeekly = bucket.map(\.weekly).reduce(0, +) / Double(bucket.count)
            let avgTime = bucket.map { $0.timestamp.timeIntervalSince1970 }.reduce(0, +) / Double(bucket.count)
            return QuotaDataPoint(
                timestamp: Date(timeIntervalSince1970: avgTime),
                session: avgSession,
                weekly: avgWeekly
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
            var loaded = try JSONDecoder.appDecoder.decode(QuotaHistory.self, from: data)
            loaded.dataPoints = pruned(loaded.dataPoints)
            history = loaded
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            history = QuotaHistory()
        }
    }

    private func startFlushTimerIfNeeded() {
        guard flushTimer == nil else { return }
        flushTimer = Timer.publish(every: Self.flushInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.flushToDisk() }
    }

    private func pruned(_ points: [QuotaDataPoint]) -> [QuotaDataPoint] {
        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        return points.filter { $0.timestamp >= cutoff }
    }
}
