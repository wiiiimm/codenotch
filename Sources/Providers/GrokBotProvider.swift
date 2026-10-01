import AppKit
import Foundation

/// A separately switchable dial borrowing the same session as Cursor.
/// Its requests and failures are independent of Cursor's normal usage fetch.
actor GrokBotProvider: UsageProvider {
    nonisolated let id = "grok-bot"
    nonisolated let displayName = "Grok Bot"
    nonisolated let glyph = ProviderGlyph.grok
    static let endpoint = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!

    private let session: URLSession
    private let cookie: () throws -> String
    private let forgetCredential: () -> Void

    init(session: URLSession = .shared,
         cookie: @escaping () throws -> String = { try CursorCredentials.load().sessionCookie },
         forgetCredential: @escaping () -> Void = CursorCredentials.forgetCachedAgent) {
        self.session = session
        self.cookie = cookie
        self.forgetCredential = forgetCredential
    }

    nonisolated var signInRoute: SignInRoute {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CursorCredentials.bundleID) != nil
        return CursorCredentials.signInRoute(editorInstalled: installed)
    }

    nonisolated func account() -> ProviderAccount? { CursorCredentials.account() }
    nonisolated func forgetCachedCredential() { CursorCredentials.forgetCachedAgent() }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue(try cookie(), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            forgetCredential()
            throw UsageProviderError.needsAuth
        }
        if status == 429 { throw UsageProviderError.rateLimited(retryAfter: 60) }
        guard (200..<300).contains(status) else { throw UsageProviderError.badResponse(status: status) }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok,
                                windows: try GrokBotUsage.windows(from: data),
                                headlineID: "allowance")
    }
}
