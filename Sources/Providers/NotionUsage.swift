import Foundation
import CoreFoundation

/// Notion's web allowance is separate from paid Custom Agent credits.
/// The returned limits are denominators, not necessarily percentages.
enum NotionUsage {
    static func windows(fromJSON json: String, now: Date = Date()) throws -> [LimitWindow] {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UsageProviderError.badResponse(status: 0) }
        switch envelope["error"] as? String {
        case "workspace_missing":
            throw UsageProviderError.apiError(L10n.t("The selected Notion workspace is unavailable. Check its workspace ID in Settings."))
        case "ambiguous_account":
            throw UsageProviderError.apiError(L10n.t("Sign in to a single Notion account to read its AI usage."))
        case "no_workspaces":
            throw UsageProviderError.nothingMetered(L10n.t("No Notion workspace is available for this account."))
        case .some:
            throw UsageProviderError.badResponse(status: 0)
        case .none: break
        }
        guard let root = envelope["usage"] as? [String: Any] else {
            throw UsageProviderError.badResponse(status: 0)
        }
        if root["status"] as? String == "not_applicable" {
            throw UsageProviderError.nothingMetered(L10n.t("Notion AI allowances are available on Business and Enterprise workspaces."))
        }
        let group = envelope["workspaceName"] as? String
        let preview = root["enforcement"] as? String == "preview"
        var windows: [LimitWindow] = []
        for (key, id, label) in [("window", "rolling", L10n.t("Rolling")),
                                  ("billingPeriodWindow", "month", L10n.t("Monthly"))] {
            guard let raw = root[key], !(raw is NSNull) else { continue }
            guard let window = raw as? [String: Any],
                  let used = number(window["used"]), used >= 0,
                  let limit = number(window["limit"]), limit > 0,
                  (used / limit).isFinite else {
                throw UsageProviderError.badResponse(status: 0)
            }
            var reset: Date?
            var duration: TimeInterval?
            if id == "rolling" {
                if let seconds = number(root["resetsInSeconds"]), seconds >= 0,
                   seconds < Date.distantFuture.timeIntervalSince(now) {
                    reset = now.addingTimeInterval(seconds)
                }
                duration = span(window["window"] as? String)
            } else if let end = number(window["periodEndMs"]), end > 0,
                      end / 1000 < Date.distantFuture.timeIntervalSince1970 {
                reset = Date(timeIntervalSince1970: end / 1000)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                if let reset, let start = calendar.date(byAdding: .month, value: -1, to: reset) {
                    duration = reset.timeIntervalSince(start)
                }
            }
            windows.append(LimitWindow(id: id, group: group, label: preview ? "\(label) (\(L10n.t("Preview")))" : label,
                                       usedFraction: used / limit,
                                       resetsAt: reset, duration: duration))
        }
        guard !windows.isEmpty else { throw UsageProviderError.badResponse(status: 0) }
        return windows
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    private static func span(_ text: String?) -> TimeInterval? {
        guard let text, let unit = text.last,
              let multiplier: Double = ["m": 60, "h": 3600, "d": 86400, "w": 604800][String(unit)],
              !text.dropLast().isEmpty, text.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }),
              let count = Double(text.dropLast()), count > 0 else { return nil }
        let seconds = count * multiplier
        return seconds.isFinite && seconds < Date.distantFuture.timeIntervalSince1970 ? seconds : nil
    }
}
