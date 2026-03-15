import XCTest
@testable import AIMeter

final class UsageColorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset thresholds to defaults so tests are deterministic
        UserDefaults.standard.removeObject(forKey: "colorThresholdElevated")
        UserDefaults.standard.removeObject(forKey: "colorThresholdHigh")
        UserDefaults.standard.removeObject(forKey: "colorThresholdCritical")
    }

    // MARK: - levelDescription with default thresholds (50/80/95)

    func testLevelDescriptionNormalAtZero() {
        XCTAssertEqual(UsageColor.levelDescription(0), "Normal")
    }

    func testLevelDescriptionNormalBelowElevated() {
        XCTAssertEqual(UsageColor.levelDescription(49), "Normal")
    }

    func testLevelDescriptionElevatedAtThreshold() {
        XCTAssertEqual(UsageColor.levelDescription(50), "Elevated")
    }

    func testLevelDescriptionElevatedBelowHigh() {
        XCTAssertEqual(UsageColor.levelDescription(79), "Elevated")
    }

    func testLevelDescriptionHighAtThreshold() {
        XCTAssertEqual(UsageColor.levelDescription(80), "High")
    }

    func testLevelDescriptionHighBelowCritical() {
        XCTAssertEqual(UsageColor.levelDescription(94), "High")
    }

    func testLevelDescriptionCriticalAtThreshold() {
        XCTAssertEqual(UsageColor.levelDescription(95), "Critical")
    }

    func testLevelDescriptionCriticalAtMax() {
        XCTAssertEqual(UsageColor.levelDescription(100), "Critical")
    }

    // MARK: - Boundary / edge values

    func testLevelDescriptionNegativeValue() {
        XCTAssertEqual(UsageColor.levelDescription(-1), "Normal")
    }

    func testLevelDescriptionAboveMax() {
        XCTAssertEqual(UsageColor.levelDescription(200), "Critical")
    }

    // MARK: - forUtilization mirrors levelDescription categories

    func testForUtilizationNormalIsGreen() {
        XCTAssertEqual(UsageColor.forUtilization(0), .green)
        XCTAssertEqual(UsageColor.forUtilization(49), .green)
    }

    func testForUtilizationElevatedIsYellow() {
        XCTAssertEqual(UsageColor.forUtilization(50), .yellow)
        XCTAssertEqual(UsageColor.forUtilization(79), .yellow)
    }

    func testForUtilizationHighIsOrange() {
        XCTAssertEqual(UsageColor.forUtilization(80), .orange)
        XCTAssertEqual(UsageColor.forUtilization(94), .orange)
    }

    func testForUtilizationCriticalIsRed() {
        XCTAssertEqual(UsageColor.forUtilization(95), .red)
        XCTAssertEqual(UsageColor.forUtilization(100), .red)
    }

    // MARK: - Custom thresholds respected

    func testCustomThresholdsChangeLevelDescription() {
        // Set thresholds to 30/60/90
        UserDefaults.standard.set(30, forKey: "colorThresholdElevated")
        UserDefaults.standard.set(60, forKey: "colorThresholdHigh")
        UserDefaults.standard.set(90, forKey: "colorThresholdCritical")
        defer {
            UserDefaults.standard.removeObject(forKey: "colorThresholdElevated")
            UserDefaults.standard.removeObject(forKey: "colorThresholdHigh")
            UserDefaults.standard.removeObject(forKey: "colorThresholdCritical")
        }

        XCTAssertEqual(UsageColor.levelDescription(29), "Normal")
        XCTAssertEqual(UsageColor.levelDescription(30), "Elevated")
        XCTAssertEqual(UsageColor.levelDescription(59), "Elevated")
        XCTAssertEqual(UsageColor.levelDescription(60), "High")
        XCTAssertEqual(UsageColor.levelDescription(89), "High")
        XCTAssertEqual(UsageColor.levelDescription(90), "Critical")
    }
}
