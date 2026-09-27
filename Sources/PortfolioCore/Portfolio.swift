import Foundation

// Keeps the account data (memory + disk), refreshes it from IBKR, and fills
// in today's prices.

public enum PortfolioError: LocalizedError, Sendable {
    case notConnected

    public var errorDescription: String? {
        "Not connected to IBKR yet."
    }
}

public actor Portfolio {
    public static let shared = Portfolio()

    private var memoryCache: AccountData?
    private var inFlight: Task<AccountData, Error>?

    /// Where the IBKR token and Query ID come from (the details saved on this Mac by default).
    public var credentials: @Sendable () -> Credentials? = { CredentialStore.load() }

    public func setCredentialsSource(_ source: @escaping @Sendable () -> Credentials?) {
        credentials = source
    }

    private var fixture: AccountData?

    /// For checking the screens with made-up data: "downloads" return this.
    public func useFixture(_ data: AccountData?) {
        fixture = data
        memoryCache = data
    }

    /// Download a fresh report now. Concurrent calls share one download.
    public func refresh() async throws -> AccountData {
        if let fixture { return fixture }
        if let inFlight { return try await inFlight.value }
        guard let creds = credentials() else { throw PortfolioError.notConnected }
        let task = Task { () throws -> AccountData in
            let stmt = try await fetchFlexStatement(token: creds.token, queryId: creds.queryId)
            return accountData(from: stmt)
        }
        inFlight = task
        defer { inFlight = nil }
        let data = try await task.value
        memoryCache = data
        try? AccountCache.save(data)
        return data
    }

    /// The saved report straight away (nil if there isn't one yet).
    public func cachedData() -> AccountData? {
        if memoryCache == nil { memoryCache = AccountCache.load() }
        return memoryCache
    }

    /// Use a report that was already downloaded (by the setup guide's test).
    public func adopt(_ data: AccountData) {
        memoryCache = data
        try? AccountCache.save(data)
    }

    /// Forget everything downloaded (used when disconnecting).
    public func reset() {
        memoryCache = nil
        AccountCache.clear()
    }
}

/// Fill in today's price for each position (Yahoo), falling back to the IBKR
/// report's price when Yahoo doesn't know the symbol or can't be reached.
public func enrichPositions(_ positions: [Position]) async -> [EnrichedPosition] {
    let quotes = await YahooClient.shared.quotes(for: positions.map(\.symbol))
    return positions.map { pos in
        let quote = quotes[pos.symbol]
        let currentPrice = quote?.price ?? pos.snapshotPrice
        let currentValue = currentPrice * pos.quantity
        let gainLoss = currentValue - pos.costBasis
        return EnrichedPosition(
            position: pos,
            name: quote?.name ?? pos.description,
            currentPrice: currentPrice,
            currentValue: currentValue,
            gainLoss: gainLoss,
            gainLossPercent: pos.costBasis != 0 ? gainLoss / pos.costBasis * 100 : nil,
            changeTodayPercent: quote?.changeTodayPercent,
            priceIsLive: quote != nil
        )
    }
}

/// Account-wide totals shown at the top of the account page.
public func makeSummary(_ data: AccountData, positions: [EnrichedPosition], now: Date = Date()) -> Summary {
    let investedValue = positions.reduce(0) { $0 + $1.currentValue }
    let totalPaid = positions.reduce(0) { $0 + $1.position.costBasis }
    let thisYear = String(Calendar(identifier: .gregorian).component(.year, from: now))
    let dividendsThisYear = data.dividends
        .filter { $0.date.hasPrefix(thisYear) }
        .reduce(0) { $0 + $1.netAmount }
    return Summary(
        totalValue: investedValue + data.balances.cash,
        investedValue: investedValue,
        totalPaid: totalPaid,
        gainLoss: investedValue - totalPaid,
        cash: data.balances.cash,
        currency: data.balances.currency,
        dividendsThisYear: dividendsThisYear,
        positionCount: positions.count,
        lastUpdated: data.fetchedDate,
        reportDate: data.reportDate
    )
}
