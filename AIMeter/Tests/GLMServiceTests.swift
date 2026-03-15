import XCTest
@testable import AIMeter

/// Tests for GLMService static helpers.
/// Conditional tests skip gracefully when the machine has GLM credentials set.
final class GLMServiceTests: XCTestCase {
    // MARK: - resolvedAPIKey

    @MainActor
    func testResolvedAPIKeyReturnsNilWithNoCredentials() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["GLM_API_KEY"] != nil,
            "GLM_API_KEY env var is set — skipping credential-absence test"
        )
        let key = GLMService.resolveAPIKey()
        XCTAssertNil(key)
    }

    @MainActor
    func testResolvedAPIKeyReturnsValueWhenEnvVarSet() throws {
        let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"] ?? ""
        try XCTSkipIf(envKey.isEmpty, "GLM_API_KEY env var not set — skipping env-var presence test")
        let key = GLMService.resolveAPIKey()
        XCTAssertNotNil(key)
    }

    // MARK: - keyIsFromEnvironment

    @MainActor
    func testKeyIsFromEnvironmentFalseWithNoCredentials() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["GLM_API_KEY"] != nil,
            "GLM_API_KEY env var is set — skipping absence test"
        )
        XCTAssertFalse(GLMService.keyIsFromEnvironment)
    }

    @MainActor
    func testKeyIsFromEnvironmentTrueWhenOnlyEnvVarSet() throws {
        let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"] ?? ""
        try XCTSkipIf(envKey.isEmpty, "GLM_API_KEY env var not set — skipping env-var test")
        // Keychain takes priority over env var, so only meaningful when Keychain is empty
        try XCTSkipIf(
            APIKeyKeychainHelper.glm.readAPIKey() != nil,
            "Keychain key present — env-var flag would be false by design"
        )
        XCTAssertTrue(GLMService.keyIsFromEnvironment)
    }

    // MARK: - GLMUsageData model

    func testGLMUsageDataEmpty() {
        let empty = GLMUsageData.empty
        XCTAssertEqual(empty.tokensPercent, 0)
        XCTAssertEqual(empty.tier, "")
        XCTAssertEqual(empty.fetchedAt, .distantPast)
    }

    func testGLMUsageDataEquatable() {
        let a = GLMUsageData(tokensPercent: 42, tier: "pro", fetchedAt: .distantPast)
        let b = GLMUsageData(tokensPercent: 42, tier: "pro", fetchedAt: .distantPast)
        XCTAssertEqual(a, b)
    }

    func testGLMUsageDataNotEqualDifferentPercent() {
        let a = GLMUsageData(tokensPercent: 10, tier: "pro", fetchedAt: .distantPast)
        let b = GLMUsageData(tokensPercent: 90, tier: "pro", fetchedAt: .distantPast)
        XCTAssertNotEqual(a, b)
    }
}
