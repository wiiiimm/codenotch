import XCTest
@testable import Codenotch

final class GrokBotProviderTests: XCTestCase {
    private func provider(cookie: @escaping () throws -> String = { "test-session" },
                          forget: @escaping () -> Void = {}) -> GrokBotProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrokBotEndpoint.self]
        return GrokBotProvider(session: URLSession(configuration: config), cookie: cookie,
                               forgetCredential: forget)
    }

    func testFetchUsesCursorSessionAndReturnsSeparateDial() async throws {
        GrokBotEndpoint.reset(status: 200)
        let snapshot = try await provider().fetchSnapshot()
        XCTAssertEqual(snapshot.id, "grok-bot")
        XCTAssertEqual(snapshot.displayName, "Grok Bot")
        XCTAssertEqual(snapshot.headlineID, "allowance")
        XCTAssertEqual(snapshot.usedFraction, 0.42)
        let request = try XCTUnwrap(GrokBotEndpoint.request)
        XCTAssertEqual(request.url?.absoluteString, "https://cursor.com/api/dashboard/get-sand-usage-status")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "test-session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRejectedSessionInvalidatesCredential() async {
        GrokBotEndpoint.reset(status: 401)
        let forgotten = expectation(description: "Credential invalidated")
        do {
            _ = try await provider(forget: { forgotten.fulfill() }).fetchSnapshot()
            XCTFail("Expected authentication failure")
        } catch {
            guard case UsageProviderError.needsAuth = error else { return XCTFail("\(error)") }
        }
        await fulfillment(of: [forgotten], timeout: 1)
    }

    func testMissingSessionMakesNoRequest() async {
        GrokBotEndpoint.reset(status: 200)
        do {
            _ = try await provider(cookie: { throw UsageProviderError.needsAuth }).fetchSnapshot()
            XCTFail("Expected authentication failure")
        } catch {
            guard case UsageProviderError.needsAuth = error else { return XCTFail("\(error)") }
        }
        XCTAssertNil(GrokBotEndpoint.request)
    }

    func testRateLimitHasRetryStatus() async {
        GrokBotEndpoint.reset(status: 429)
        do {
            _ = try await provider().fetchSnapshot()
            XCTFail("Expected throttling")
        } catch {
            guard case UsageProviderError.rateLimited = error else { return XCTFail("\(error)") }
        }
    }
}

private final class GrokBotEndpoint: URLProtocol {
    private static let lock = NSLock()
    private static var status = 200
    private static var recorded: URLRequest?
    static var request: URLRequest? { lock.withLock { recorded } }
    static func reset(status: Int) { lock.withLock { Self.status = status; recorded = nil } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = Self.lock.withLock { Self.recorded = request; return Self.status }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"includedLimitZero":false,"usagePercent":42}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
