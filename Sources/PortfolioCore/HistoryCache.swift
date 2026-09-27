import Foundation

// IBKR hands out at most 365 days per report, so trades and dividends older
// than the regular report are downloaded a year at a time and kept here
// (history.json, next to account.json). Past years never change, so each is
// downloaded once.

public struct AccountHistory: Codable, Sendable {
    /// Everything dated before `coversTo`
    public var trades: [Trade] = []
    public var dividends: [Dividend] = []
    /// The earliest day downloaded so far (yyyy-MM-dd)
    public var coversFrom: String
    /// The day after the last one kept here: where the regular report took over
    public var coversTo: String
    /// True once we've gone back past the account's first activity
    public var complete = false
    /// How many years in a row came back empty (two means we're done)
    public var emptyYears = 0
}

public enum HistoryCache {
    static var file: URL { AccountCache.directory.appendingPathComponent("history.json") }

    public static func load() -> AccountHistory? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(AccountHistory.self, from: data)
    }

    public static func save(_ history: AccountHistory) throws {
        try FileManager.default.createDirectory(at: AccountCache.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: file, options: .atomic)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}

private let dayFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// Moves a yyyy-MM-dd date by a number of days.
func shiftDay(_ day: String, by days: Int) -> String? {
    guard let d = dayFormat.date(from: day) else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(byAdding: .day, value: days, to: d).map(dayFormat.string)
}
