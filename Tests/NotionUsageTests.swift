import XCTest
@testable import Codenotch

final class NotionUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func parse(_ usage: String) throws -> [LimitWindow] {
        try NotionUsage.windows(fromJSON: "{\"workspaceName\":\"Example\",\"usage\":\(usage)}", now: now)
    }

    func testTwoAllowancesUseReturnedLimitsAndTheirOwnClocks() throws {
        let windows = try parse(#"{"status":"within_limit","window":{"window":"6h","used":42.5,"limit":50},"resetsInSeconds":12600,"billingPeriodWindow":{"used":18,"limit":200,"periodEndMs":1788000000000}}"#)
        XCTAssertEqual(windows.map(\.id), ["rolling", "month"])
        XCTAssertEqual(windows[0].group, "Example")
        XCTAssertEqual(windows[0].usedFraction, 0.85)
        XCTAssertEqual(windows[0].duration, 21600)
        XCTAssertEqual(windows[0].resetsAt, now.addingTimeInterval(12600))
        XCTAssertEqual(windows[1].usedFraction, 0.09)
        XCTAssertEqual(windows[1].resetsAt, Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertEqual(windows[1].duration, 31 * 86400)
    }

    func testPreservesOverageAndPreview() throws {
        let w = try parse(#"{"enforcement":"preview","window":{"used":120,"limit":100}}"#)[0]
        XCTAssertEqual(w.usedFraction, 1.2)
        XCTAssertTrue(w.label.contains("Preview"))
        XCTAssertNil(w.resetsAt)
        XCTAssertNil(w.duration)
    }

    func testMissingRollingWindowKeepsMonthlyReading() throws {
        let w = try parse(#"{"billingPeriodWindow":{"used":0,"limit":100}}"#)
        XCTAssertEqual(w.map(\.id), ["month"])
        XCTAssertNil(w[0].duration)
        XCTAssertNil(w[0].resetsAt)
    }

    func testRejectsMalformedOrEmptyReadings() {
        for json in ["{}", #"{"window":{"used":true,"limit":100}}"#,
                     #"{"window":{"used":3,"limit":0}}"#,
                     #"{"window":{"used":-1,"limit":100}}"#,
                     #"{"window":{"used":"3","limit":100}}"#,
                     #"{"window":[]}"#] {
            XCTAssertThrowsError(try parse(json), json)
        }
    }

    func testNotApplicableIsNotAnEmptyGauge() {
        XCTAssertThrowsError(try parse(#"{"status":"not_applicable"}"#)) { error in
            guard case UsageProviderError.nothingMetered = error else {
                return XCTFail("Expected no allowance, got \(error)")
            }
        }
    }

    func testMissingWorkspaceIsAnActionableError() {
        XCTAssertThrowsError(try NotionUsage.windows(fromJSON: #"{"error":"workspace_missing"}"#)) { error in
            guard case UsageProviderError.apiError = error else { return XCTFail("\(error)") }
        }
    }

    func testUnusableClocksAreNotInvented() throws {
        let w = try parse(#"{"window":{"used":2,"limit":100,"window":"tomorrow"},"resetsInSeconds":-1,"billingPeriodWindow":{"used":3,"limit":100,"periodEndMs":1e20}}"#)
        for window in w {
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(window.duration)
        }
    }

    @MainActor
    func testSiteDeclaresRolesAndOwnSessionHosts() {
        let site = Sites.notion()
        XCTAssertEqual(site.headlineID, "rolling")
        XCTAssertEqual(site.weeklyID, "month")
        XCTAssertEqual(site.origin.host, "app.notion.com")
        XCTAssertEqual(WebSessionProvider.websiteDataHosts(for: site), ["app.notion.com", "notion.com", "notion.so"])
        XCTAssertNotNil(site.authProbeScript)
    }
}
