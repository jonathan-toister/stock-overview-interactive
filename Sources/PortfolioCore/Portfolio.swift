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

    /// The last regular report as downloaded (the most recent 365 days)
    private var memoryCache: AccountData?
    private var inFlight: Task<AccountData, Error>?
    /// Trades and dividends from before the regular report (nil until the first backfill)
    private var history: AccountHistory?
    private var historyLoaded = false
    private var backfilling = false

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
        store(data)
        return withHistory(data)
    }

    /// The saved report straight away (nil if there isn't one yet).
    public func cachedData() -> AccountData? {
        if memoryCache == nil { memoryCache = AccountCache.load() }
        return memoryCache.map(withHistory)
    }

    /// Use a report that was already downloaded (by the setup guide's test).
    public func adopt(_ data: AccountData) {
        store(data)
    }

    /// Forget everything downloaded (used when disconnecting).
    public func reset() {
        memoryCache = nil
        history = nil
        historyLoaded = true
        AccountCache.clear()
        HistoryCache.clear()
    }

    /// Throw away the older years so the next backfill downloads them again.
    public func forgetHistory() {
        history = nil
        historyLoaded = true
        HistoryCache.clear()
    }

    /// Whether older years still need downloading.
    public func needsBackfill() -> Bool {
        guard fixture == nil, cachedData() != nil else { return false }
        return loadHistory().map { !$0.complete } ?? true
    }

    private func loadHistory() -> AccountHistory? {
        if !historyLoaded {
            history = HistoryCache.load()
            historyLoaded = true
        }
        return history
    }

    private func store(_ data: AccountData) {
        carryOver(from: memoryCache ?? AccountCache.load(), to: data)
        memoryCache = data
        try? AccountCache.save(data)
    }

    /// The regular report always covers the last 365 days, so each new one
    /// starts a little later than the one before. Move the days that just fell
    /// out of it into the history, so nothing goes missing in between.
    private func carryOver(from old: AccountData?, to new: AccountData) {
        guard var h = loadHistory(), let newStart = new.periodStart, h.coversTo < newStart else { return }
        if let old {
            let moving = { (date: String) in date >= h.coversTo && date < newStart }
            // Newest first, like the rest of the lists
            h.trades = old.trades.filter { moving($0.date) } + h.trades
            h.dividends = old.dividends.filter { moving($0.date) } + h.dividends
        }
        h.coversTo = newStart
        history = h
        try? HistoryCache.save(h)
    }

    /// The regular report with the older years added on.
    private func withHistory(_ recent: AccountData) -> AccountData {
        guard let h = loadHistory() else { return recent }
        let cutoff = recent.periodStart ?? h.coversTo
        var merged = recent
        merged.trades += h.trades.filter { $0.date < cutoff }
        merged.dividends += h.dividends.filter { $0.date < cutoff }
        return merged
    }

    /// Download the years before the regular report, one year at a time
    /// (IBKR's limit), going back until there's nothing left. Saves after each
    /// year, so if it stops half way the next run carries on from there.
    /// `progress` gets the year being downloaded. Returns the full data.
    public func backfillHistory(progress: @Sendable (Int) async -> Void = { _ in }) async throws -> AccountData? {
        guard fixture == nil, !backfilling, let creds = credentials() else { return nil }
        backfilling = true
        defer { backfilling = false }
        // Reports saved by earlier versions don't record where they start
        if cachedData()?.periodStart == nil { _ = try await refresh() }
        guard let start = cachedData()?.periodStart else { return nil }
        if history == nil {
            history = AccountHistory(coversFrom: start, coversTo: start)
            try? HistoryCache.save(history!)
        }
        let oldest = shiftDay(start, by: -25 * 365) ?? "1990-01-01"

        while let h = history, !h.complete {
            guard let to = shiftDay(h.coversFrom, by: -1), let from = shiftDay(to, by: -364) else { break }
            await progress(Int(from.prefix(4)) ?? 0)
            // IBKR allows about 10 report requests a minute
            try await Task.sleep(for: .seconds(6))

            let stmt: FlexStatement
            do {
                stmt = try await fetchFlexStatement(token: creds.token, queryId: creds.queryId, from: from, to: to)
            } catch let error as FlexError where error.code == "1003" || (error.fix == nil && h.emptyYears > 0) {
                // 1003 "Statement is not available": IBKR has nothing for
                // those dates, i.e. they're from before the account existed.
                // (After an empty year, any refusal is taken to mean the same.)
                markComplete()
                break
            }
            guard flexDate(stmt.toDate) == to else {
                throw FlexError(message: "IBKR sent the usual report instead of the older dates that were asked for, so older history can't be downloaded this way.")
            }
            let year = accountData(from: stmt)

            // Re-read: a regular update may have changed the history while we waited
            guard var current = history else { break }
            current.trades += year.trades
            current.dividends += year.dividends
            let empty = year.trades.isEmpty && year.dividends.isEmpty
            current.emptyYears = empty ? current.emptyYears + 1 : 0
            current.coversFrom = from
            // IBKR starts the report later than asked when the account opened part way through
            let startedLate = stmt.fromDate.map(flexDate).map { $0 > from } ?? false
            current.complete = current.emptyYears >= 2 || startedLate || from <= oldest
            history = current
            try? HistoryCache.save(current)
        }
        return cachedData()
    }

    private func markComplete() {
        guard var h = history else { return }
        h.complete = true
        history = h
        try? HistoryCache.save(h)
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
