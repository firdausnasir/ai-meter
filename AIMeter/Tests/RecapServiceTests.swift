import XCTest
@testable import AIMeter

final class RecapServiceTests: XCTestCase {
    // MARK: - Helpers

    @MainActor
    private func makeService() -> RecapService {
        let quotaService = QuotaHistoryService()
        quotaService.history.dataPoints = []
        let copilotService = CopilotHistoryService()
        copilotService.history.dataPoints = []
        return RecapService(quotaHistoryService: quotaService, copilotHistoryService: copilotService)
    }

    private func firstOfMonth(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    // MARK: - Empty history → nil stats

    @MainActor
    func testGenerateRecapEmptyHistoryReturnsNilStats() {
        let service = makeService()
        let month = firstOfMonth(year: 2026, month: 2)

        let recap = service.generateRecap(for: month)

        XCTAssertNil(recap.claude)
        XCTAssertNil(recap.copilot)
    }

    @MainActor
    func testGenerateRecapEmptyHistoryReturnsCorrectMonth() {
        let service = makeService()
        let month = firstOfMonth(year: 2026, month: 2)

        let recap = service.generateRecap(for: month)

        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: recap.month), 2026)
        XCTAssertEqual(cal.component(.month, from: recap.month), 2)
    }

    // MARK: - Sample Claude data → correct aggregation

    @MainActor
    func testGenerateRecapClaudeAverageAndPeak() {
        let quotaService = QuotaHistoryService()
        let feb10 = firstOfMonth(year: 2026, month: 2).addingTimeInterval(9 * 86400)
        let feb15 = firstOfMonth(year: 2026, month: 2).addingTimeInterval(14 * 86400)
        quotaService.history.dataPoints = [
            QuotaDataPoint(timestamp: feb10, session: 0.4, weekly: 0.3),
            QuotaDataPoint(timestamp: feb15, session: 0.8, weekly: 0.6)
        ]
        let copilotService = CopilotHistoryService()
        copilotService.history.dataPoints = []
        let service = RecapService(quotaHistoryService: quotaService, copilotHistoryService: copilotService)

        let recap = service.generateRecap(for: firstOfMonth(year: 2026, month: 2))

        let claude = try! XCTUnwrap(recap.claude)
        XCTAssertEqual(claude.avgSessionUtilization, 0.6, accuracy: 0.001)
        XCTAssertEqual(claude.avgWeeklyUtilization, 0.45, accuracy: 0.001)
        XCTAssertEqual(claude.peakSessionUtilization, 0.8, accuracy: 0.001)
        XCTAssertEqual(claude.peakWeeklyUtilization, 0.6, accuracy: 0.001)
        XCTAssertEqual(claude.dataPointCount, 2)
        XCTAssertEqual(claude.peakDate, feb15)
    }

    @MainActor
    func testGenerateRecapExcludesPointsOutsideMonth() {
        let quotaService = QuotaHistoryService()
        let jan31 = firstOfMonth(year: 2026, month: 2).addingTimeInterval(-1)   // last second of January
        let feb01 = firstOfMonth(year: 2026, month: 2).addingTimeInterval(3600)  // 1 hour into February
        let mar01 = firstOfMonth(year: 2026, month: 3)                           // first of March (excluded)
        quotaService.history.dataPoints = [
            QuotaDataPoint(timestamp: jan31, session: 0.9, weekly: 0.9),
            QuotaDataPoint(timestamp: feb01, session: 0.5, weekly: 0.5),
            QuotaDataPoint(timestamp: mar01, session: 0.7, weekly: 0.7)
        ]
        let copilotService = CopilotHistoryService()
        copilotService.history.dataPoints = []
        let service = RecapService(quotaHistoryService: quotaService, copilotHistoryService: copilotService)

        let recap = service.generateRecap(for: firstOfMonth(year: 2026, month: 2))

        let claude = try! XCTUnwrap(recap.claude)
        XCTAssertEqual(claude.dataPointCount, 1)
        XCTAssertEqual(claude.avgSessionUtilization, 0.5, accuracy: 0.001)
    }

    // MARK: - Save + load roundtrip

    @MainActor
    func testSaveAndLoadRoundtrip() throws {
        let service = makeService()
        let month = firstOfMonth(year: 2026, month: 1)
        let recap = MonthlyRecapData(
            month: month,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            claude: ClaudeRecapStats(
                avgSessionUtilization: 0.42,
                avgWeeklyUtilization: 0.35,
                peakSessionUtilization: 0.9,
                peakWeeklyUtilization: 0.7,
                peakDate: month.addingTimeInterval(86400),
                dataPointCount: 10,
                planName: "Pro"
            ),
            copilot: nil
        )

        service.saveRecap(recap)
        let loaded = service.loadSavedRecaps()

        XCTAssertEqual(loaded.count, 1)
        let r = try XCTUnwrap(loaded.first)
        XCTAssertEqual(r.claude?.avgSessionUtilization ?? 0, 0.42, accuracy: 0.001)
        XCTAssertEqual(r.claude?.dataPointCount, 10)
        XCTAssertEqual(r.claude?.planName, "Pro")
        XCTAssertNil(r.copilot)

        // Cleanup — remove the written file to avoid affecting other tests
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let filename = formatter.string(from: month) + ".json"
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter/recaps/\(filename)")
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Codable roundtrip for MonthlyRecapData

    func testMonthlyRecapDataCodableRoundtrip() throws {
        let month = Date(timeIntervalSince1970: 1_740_787_200) // 2026-03-01
        let original = MonthlyRecapData(
            month: month,
            generatedAt: Date(timeIntervalSince1970: 1_740_800_000),
            claude: nil,
            copilot: nil
        )
        let data = try JSONEncoder.appEncoder.encode(original)
        let decoded = try JSONDecoder.appDecoder.decode(MonthlyRecapData.self, from: data)

        XCTAssertEqual(decoded.month.timeIntervalSince1970, original.month.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(decoded.claude)
        XCTAssertNil(decoded.copilot)
    }
}
