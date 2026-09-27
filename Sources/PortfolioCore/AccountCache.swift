import Foundation

// The IBKR report is slow to generate and only updates a few times a day, so
// the last download is kept on disk and refreshed in the background when it
// gets old.

public enum AccountCache {
    /// ~/Library/Application Support/Portfolio
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portfolio", isDirectory: true)
    }

    static var file: URL { directory.appendingPathComponent("account.json") }

    /// Refresh after 6 hours
    public static let maxAge: TimeInterval = 6 * 60 * 60

    public static func load() -> AccountData? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(AccountData.self, from: data)
    }

    public static func save(_ account: AccountData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(account).write(to: file, options: .atomic)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: file)
    }

    public static func isStale(_ account: AccountData) -> Bool {
        Date().timeIntervalSince(account.fetchedDate) > maxAge
    }
}
