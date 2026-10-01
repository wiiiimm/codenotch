import XCTest
@testable import Codenotch

final class GrokBotUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func parse(_ json: String) throws -> LimitWindow {
        try GrokBotUsage.windows(from: Data(json.utf8), now: now)[0]
    }

    func testIncludedAllowanceHasItsOwnWeek() throws {
        let w = try parse(#"{"includedLimitZero":false,"usagePercent":42,"currentPeriodStart":"2026-08-17T07:57:50.647Z","nextResetTimestampUtc":"2026-08-24T07:57:50.647Z"}"#)
        XCTAssertEqual(w.usedFraction, 0.42)
        XCTAssertEqual(w.duration, 7 * 86400)
        XCTAssertNotNil(w.resetsAt)
    }
    func testExhaustedTrialDoesNotPretendToReset() throws {
        let w = try parse(#"{"includedLimitZero":true,"hasAvailableUsage":false,"usagePercent":100,"sandTrialExpiresAt":"2099-01-01T00:00:00Z","nextResetTimestampUtc":"2099-01-01T00:00:00Z"}"#)
        XCTAssertEqual(w.usedFraction, 1)
        XCTAssertNil(w.resetsAt)
        XCTAssertNil(w.duration)
    }
    func testZeroAndOverageAreBothReadings() throws {
        XCTAssertEqual(try parse(#"{"hasNonZeroIncludedLimit":true,"usagePercent":0}"#).usedFraction, 0)
        XCTAssertEqual(try parse(#"{"includedLimitZero":false,"usagePercent":120}"#).usedFraction, 1.2)
    }
    func testCurrentFlagWinsOverLegacyFlag() {
        XCTAssertThrowsError(try parse(#"{"includedLimitZero":true,"hasNonZeroIncludedLimit":true,"usagePercent":42}"#)) { error in
            guard case UsageProviderError.nothingMetered = error else { return XCTFail("\(error)") }
        }
    }
    func testExpiredTrialHasNoAllowance() {
        XCTAssertThrowsError(try parse(#"{"usagePercent":42,"sandTrialExpiresAt":"2020-01-01T00:00:00Z"}"#))
    }
    func testRejectsInvalidPercentages() {
        for value in ["null", "true", "-1", "\"42\""] {
            XCTAssertThrowsError(try parse("{\"includedLimitZero\":false,\"usagePercent\":\(value)}"))
        }
    }
    func testPaidAllowanceWinsOverTrialAndMissingClocksStayAbsent() throws {
        let w = try parse(#"{"includedLimitZero":false,"usagePercent":42,"sandTrialExpiresAt":"2099-01-01T00:00:00Z"}"#)
        XCTAssertEqual(w.label, "Included usage")
        XCTAssertNil(w.duration)
        XCTAssertNil(w.resetsAt)
    }
}
