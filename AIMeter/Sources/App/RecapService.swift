import Foundation
import os

@MainActor
final class RecapService: ObservableObject {
    @Published private(set) var savedRecaps: [MonthlyRecapData] = []

    private let quotaHistoryService: QuotaHistoryService
    private let copilotHistoryService: CopilotHistoryService
    private let logger = Logger(subsystem: "com.khairul.aimeter", category: "RecapService")

    private static var recapsDir: URL {
        AppConstants.Paths.configDir.appendingPathComponent("recaps", isDirectory: true)
    }

    init(quotaHistoryService: QuotaHistoryService, copilotHistoryService: CopilotHistoryService) {
        self.quotaHistoryService = quotaHistoryService
        self.copilotHistoryService = copilotHistoryService
    }

    // MARK: - Aggregation

    func generateRecap(for month: Date) -> MonthlyRecapData {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let monthStart = calendar.date(from: components),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return MonthlyRecapData(month: month, generatedAt: Date(), claude: nil, copilot: nil)
        }

        let claudeStats = buildClaudeStats(from: monthStart, to: monthEnd)
        let copilotStats = buildCopilotStats(from: monthStart, to: monthEnd)

        return MonthlyRecapData(
            month: monthStart,
            generatedAt: Date(),
            claude: claudeStats,
            copilot: copilotStats
        )
    }

    private func buildClaudeStats(from start: Date, to end: Date) -> ClaudeRecapStats? {
        let points = quotaHistoryService.history.dataPoints.filter {
            $0.timestamp >= start && $0.timestamp < end
        }
        guard !points.isEmpty else { return nil }

        let avgSession = points.map(\.session).reduce(0, +) / Double(points.count)
        let avgWeekly = points.map(\.weekly).reduce(0, +) / Double(points.count)
        let peakPoint = points.max(by: { $0.session < $1.session })!

        return ClaudeRecapStats(
            avgSessionUtilization: avgSession,
            avgWeeklyUtilization: avgWeekly,
            peakSessionUtilization: peakPoint.session,
            peakWeeklyUtilization: peakPoint.weekly,
            peakDate: peakPoint.timestamp,
            dataPointCount: points.count,
            planName: nil   // planName not stored in history; populated by caller if needed
        )
    }

    private func buildCopilotStats(from start: Date, to end: Date) -> CopilotRecapStats? {
        let points = copilotHistoryService.history.dataPoints.filter {
            $0.timestamp >= start && $0.timestamp < end
        }
        guard !points.isEmpty else { return nil }

        func avg(_ keyPath: KeyPath<CopilotHistoryDataPoint, Int?>) -> Double {
            let nonNil = points.compactMap { $0[keyPath: keyPath] }
            guard !nonNil.isEmpty else { return 0 }
            return Double(nonNil.reduce(0, +)) / Double(nonNil.count)
        }

        func peak(_ keyPath: KeyPath<CopilotHistoryDataPoint, Int?>) -> Double {
            Double(points.compactMap { $0[keyPath: keyPath] }.max() ?? 0)
        }

        let peakPoint = points.max(by: {
            let lhs = max($0.chatUtilization ?? 0, $0.completionsUtilization ?? 0, $0.premiumUtilization ?? 0)
            let rhs = max($1.chatUtilization ?? 0, $1.completionsUtilization ?? 0, $1.premiumUtilization ?? 0)
            return lhs < rhs
        })!

        return CopilotRecapStats(
            avgChatUtilization: avg(\.chatUtilization),
            avgCompletionsUtilization: avg(\.completionsUtilization),
            avgPremiumUtilization: avg(\.premiumUtilization),
            peakChatUtilization: peak(\.chatUtilization),
            peakCompletionsUtilization: peak(\.completionsUtilization),
            peakPremiumUtilization: peak(\.premiumUtilization),
            peakDate: peakPoint.timestamp,
            dataPointCount: points.count,
            plan: nil   // plan not stored in history; populated by caller if needed
        )
    }

    // MARK: - Persistence

    func saveRecap(_ recap: MonthlyRecapData) {
        let dir = Self.recapsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = recapFileURL(for: recap.month)
        guard let data = try? JSONEncoder.appEncoder.encode(recap) else { return }
        do {
            try data.write(to: url, options: .atomic)
            if let idx = savedRecaps.firstIndex(where: { Calendar.current.isDate($0.month, equalTo: recap.month, toGranularity: .month) }) {
                savedRecaps[idx] = recap
            } else {
                savedRecaps.append(recap)
                savedRecaps.sort { $0.month < $1.month }
            }
        } catch {
            logger.error("Failed to save recap: \(error.localizedDescription)")
        }
    }

    func loadSavedRecaps() -> [MonthlyRecapData] {
        let dir = Self.recapsDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let recaps = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MonthlyRecapData? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.appDecoder.decode(MonthlyRecapData.self, from: data)
            }
            .sorted { $0.month < $1.month }
        savedRecaps = recaps
        return recaps
    }

    // MARK: - Launch trigger

    /// Checks if last month's recap is missing and generates it. Called on app launch.
    func checkAndGenerateRecap(notificationManager: NotificationManager? = nil) {
        let calendar = Calendar.current
        let now = Date()
        guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return }
        let lastMonthComponents = calendar.dateComponents([.year, .month], from: lastMonthDate)
        guard let lastMonthStart = calendar.date(from: lastMonthComponents) else { return }

        let recapURL = recapFileURL(for: lastMonthStart)
        guard !FileManager.default.fileExists(atPath: recapURL.path) else { return }

        let recap = generateRecap(for: lastMonthStart)
        saveRecap(recap)
        notificationManager?.fireRecapNotification(for: lastMonthStart)
        logger.info("Generated recap for \(lastMonthStart)")
    }

    // MARK: - Helpers

    private func recapFileURL(for month: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let filename = formatter.string(from: month) + ".json"
        return Self.recapsDir.appendingPathComponent(filename)
    }
}
