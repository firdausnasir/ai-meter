import XCTest
@testable import AIMeter

final class HTTPPollingServiceTests: XCTestCase {
    // MARK: - HTTPPollingError equatability

    func testNoKeyEqualsNoKey() {
        XCTAssertEqual(HTTPPollingError.noKey, HTTPPollingError.noKey)
    }

    func testFetchFailedEqualsFetchFailed() {
        XCTAssertEqual(HTTPPollingError.fetchFailed, HTTPPollingError.fetchFailed)
    }

    func testRateLimitedEqualsSameRetryAfter() {
        XCTAssertEqual(
            HTTPPollingError.rateLimited(retryAfter: 60),
            HTTPPollingError.rateLimited(retryAfter: 60)
        )
    }

    func testRateLimitedNotEqualsDifferentRetryAfter() {
        XCTAssertNotEqual(
            HTTPPollingError.rateLimited(retryAfter: 30),
            HTTPPollingError.rateLimited(retryAfter: 60)
        )
    }

    func testNoKeyNotEqualsFetchFailed() {
        XCTAssertNotEqual(HTTPPollingError.noKey, HTTPPollingError.fetchFailed)
    }

    func testNoKeyNotEqualsRateLimited() {
        XCTAssertNotEqual(HTTPPollingError.noKey, HTTPPollingError.rateLimited(retryAfter: 60))
    }

    func testFetchFailedNotEqualsRateLimited() {
        XCTAssertNotEqual(HTTPPollingError.fetchFailed, HTTPPollingError.rateLimited(retryAfter: 60))
    }

    // MARK: - Canonical retry-after values

    func testRateLimitedZeroRetryAfter() {
        XCTAssertEqual(
            HTTPPollingError.rateLimited(retryAfter: 0),
            HTTPPollingError.rateLimited(retryAfter: 0)
        )
    }

    func testRateLimitedFractionalRetryAfter() {
        XCTAssertEqual(
            HTTPPollingError.rateLimited(retryAfter: 1.5),
            HTTPPollingError.rateLimited(retryAfter: 1.5)
        )
    }
}
