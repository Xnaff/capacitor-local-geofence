import Foundation

/// Platform-free rules, kept apart so they run in plain unit tests.
enum GeofenceLogic {
    static let maxEvents = 500

    /// Replaces `{time}` with the short local time of `timestamp` (milliseconds since epoch).
    static func fillTemplate(_ template: String, timestamp: Double, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard template.contains("{time}") else { return template }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return template.replacingOccurrences(of: "{time}", with: formatter.string(from: Date(timeIntervalSince1970: timestamp / 1000)))
    }

    /// Only a change of transition is a new event; repeated deliveries are dropped.
    static func isNewTransition(last: String?, transition: String) -> Bool {
        return last != transition
    }

    /// Keeps the newest `max` items of an oldest-first list.
    static func keepNewest<T>(_ items: [T], max: Int = maxEvents) -> [T] {
        return items.count <= max ? items : Array(items.suffix(max))
    }
}
