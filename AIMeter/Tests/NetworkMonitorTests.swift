import XCTest
@testable import AIMeter

final class NetworkMonitorTests: XCTestCase {
    @MainActor
    func testSharedInstanceExists() {
        let monitor = NetworkMonitor.shared
        XCTAssertNotNil(monitor)
    }

    @MainActor
    func testSharedInstanceIsSingleton() {
        let a = NetworkMonitor.shared
        let b = NetworkMonitor.shared
        XCTAssertTrue(a === b)
    }

    @MainActor
    func testInitiallyConnectedOnTestMachine() {
        // On a CI / developer machine we expect network to be available
        let monitor = NetworkMonitor.shared
        XCTAssertTrue(monitor.isConnected)
    }
}
