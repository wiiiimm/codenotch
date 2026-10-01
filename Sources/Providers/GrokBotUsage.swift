import Foundation

/// Cursor calls Grok Bot "Sand" internally. This is its own allowance, not
/// Cursor's monthly Auto bucket and not the Grok CLI's billing endpoint.
enum GrokBotUsage {
    private struct Status: Decodable {
        let includedLimitZero: Bool?
        let hasNonZeroIncludedLimit: Bool?
        let usagePercent: Double?
        let currentPeriodStart: String?
        let nextResetTimestampUtc: String?
        let sandTrialExpiresAt: String?
    }

    static func windows(from data: Data, now: Date = Date()) throws -> [LimitWindow] {
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else {
            throw UsageProviderError.badResponse(status: 0)
        }
        // The newer explicit zero flag takes precedence over the older field.
        let included = status.includedLimitZero.map { !$0 } ?? status.hasNonZeroIncludedLimit
        let trial = included != true && date(status.sandTrialExpiresAt).map { $0 > now } == true
        guard included == true || trial else {
            throw UsageProviderError.nothingMetered(L10n.t("No Grok Bot allowance or active trial on this Cursor account"))
        }
        guard let percent = status.usagePercent, percent.isFinite, percent >= 0 else {
            throw UsageProviderError.badResponse(status: 0)
        }
        // Trial expiry ends access; it does not replenish a recurring quota.
        let reset = trial ? nil : date(status.nextResetTimestampUtc)
        let duration = date(status.currentPeriodStart).flatMap { start in
            reset.flatMap { end -> TimeInterval? in
                let span = end.timeIntervalSince(start)
                return span > 0 ? span : nil
            }
        }
        return [LimitWindow(id: "allowance", label: trial ? L10n.t("Trial usage") : L10n.t("Included usage"),
                            usedFraction: percent / 100, resetsAt: reset, duration: duration)]
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
