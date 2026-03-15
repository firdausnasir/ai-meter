import XCTest
@testable import AIMeter

final class QuotaHistoryServiceTests: XCTestCase {
    // MARK: - recordDataPoint

    @MainActor
    func testRecordDataPointIncrementsCount() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        service.recordDataPoint(session: 0.5, weekly: 0.3)

        XCTAssertEqual(service.history.dataPoints.count, 1)
    }

    @MainActor
    func testRecordDataPointMarksDirty() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        service.recordDataPoint(session: 0.5, weekly: 0.3)

        XCTAssertTrue(service.isDirty)
    }

    @MainActor
    func testRecordDataPointStoresCorrectValues() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        service.recordDataPoint(session: 0.75, weekly: 0.25)

        let point = service.history.dataPoints.last!
        XCTAssertEqual(point.session, 0.75, accuracy: 0.001)
        XCTAssertEqual(point.weekly, 0.25, accuracy: 0.001)
    }

    @MainActor
    func testRecordMultipleDataPoints() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        service.recordDataPoint(session: 0.1, weekly: 0.1)
        service.recordDataPoint(session: 0.2, weekly: 0.2)
        service.recordDataPoint(session: 0.3, weekly: 0.3)

        XCTAssertEqual(service.history.dataPoints.count, 3)
    }

    // MARK: - downsampledPoints

    @MainActor
    func testDownsampledPointsEmptyWhenNoData() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        let points = service.downsampledPoints(for: .hour1)
        XCTAssertTrue(points.isEmpty)
    }

    @MainActor
    func testDownsampledPointsReturnAllWhenBelowTarget() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        service.recordDataPoint(session: 0.5, weekly: 0.3)
        service.recordDataPoint(session: 0.6, weekly: 0.4)

        // 2 points << 60 target — should be returned as-is
        let points = service.downsampledPoints(for: .hour1)
        XCTAssertEqual(points.count, 2)
    }

    @MainActor
    func testDownsampledPointsExcludesOldData() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        // Insert a point far in the past (outside any time range)
        let ancient = QuotaDataPoint(
            timestamp: Date().addingTimeInterval(-8 * 86400),
            session: 0.9,
            weekly: 0.9
        )
        service.history.dataPoints = [ancient]

        let points = service.downsampledPoints(for: .day7)
        XCTAssertTrue(points.isEmpty)
    }

    @MainActor
    func testDownsampledPointsIncludesRecentData() {
        let service = QuotaHistoryService()
        service.history.dataPoints = []

        // Insert a point from 30 minutes ago — within the 1h window
        let recent = QuotaDataPoint(
            timestamp: Date().addingTimeInterval(-1800),
            session: 0.4,
            weekly: 0.2
        )
        service.history.dataPoints = [recent]

        let points = service.downsampledPoints(for: .hour1)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].session, 0.4, accuracy: 0.001)
    }

    // MARK: - QuotaDataPoint model

    func testDataPointTimestampDefaultsToNow() {
        let before = Date()
        let point = QuotaDataPoint(session: 0.5, weekly: 0.5)
        let after = Date()
        XCTAssertGreaterThanOrEqual(point.timestamp, before)
        XCTAssertLessThanOrEqual(point.timestamp, after)
    }

    func testDataPointHasUniqueIDs() {
        let a = QuotaDataPoint(session: 0.5, weekly: 0.5)
        let b = QuotaDataPoint(session: 0.5, weekly: 0.5)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testDataPointCodableRoundTrip() throws {
        let original = QuotaDataPoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            session: 0.42,
            weekly: 0.77
        )
        let data = try JSONEncoder.appEncoder.encode(original)
        let decoded = try JSONDecoder.appDecoder.decode(QuotaDataPoint.self, from: data)

        XCTAssertEqual(decoded.session, original.session, accuracy: 0.0001)
        XCTAssertEqual(decoded.weekly, original.weekly, accuracy: 0.0001)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       original.timestamp.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - QuotaTimeRange

    func testQuotaTimeRangeIntervals() {
        XCTAssertEqual(QuotaTimeRange.hour1.interval, 3600)
        XCTAssertEqual(QuotaTimeRange.hour6.interval, 6 * 3600)
        XCTAssertEqual(QuotaTimeRange.day1.interval, 86400)
        XCTAssertEqual(QuotaTimeRange.day7.interval, 7 * 86400)
    }

    func testQuotaTimeRangeTargetPointCounts() {
        XCTAssertEqual(QuotaTimeRange.hour1.targetPointCount, 60)
        XCTAssertEqual(QuotaTimeRange.hour6.targetPointCount, 120)
        XCTAssertEqual(QuotaTimeRange.day1.targetPointCount, 144)
        XCTAssertEqual(QuotaTimeRange.day7.targetPointCount, 168)
    }

    func testQuotaTimeRangeIDs() {
        XCTAssertEqual(QuotaTimeRange.hour1.id, "1h")
        XCTAssertEqual(QuotaTimeRange.hour6.id, "6h")
        XCTAssertEqual(QuotaTimeRange.day1.id, "1d")
        XCTAssertEqual(QuotaTimeRange.day7.id, "7d")
    }
}
