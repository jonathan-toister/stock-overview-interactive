import Foundation

// Near-live prices and company info come from Yahoo Finance (free, no API
// key). There's no Swift library for it, so this calls the same web endpoints
// the yahoo-finance2 JavaScript package uses. IBKR
// symbols are used as-is; if Yahoo doesn't recognise one we return nil and
// the app falls back to the price from the IBKR report.

public struct Quote: Sendable, Hashable {
    public var price: Double
    public var currency: String
    public var name: String
    public var changeToday: Double?
    /// Percent, e.g. 1.2 = up 1.2% today
    public var changeTodayPercent: Double?
}

public struct FundHolding: Sendable, Hashable {
    public var symbol: String?
    public var name: String
    /// Share of the fund's money in this one stock (0.07 = 7% of the fund)
    public var percent: Double
}

/// The numbers behind the "key numbers" panel on a stock page. Deliberately a
/// short list. Everything is optional: Yahoo has different data for an
/// ordinary company than for a fund, and some companies are missing pieces.
/// Fractions (0.03 = 3%) are noted.
public struct CompanyInfo: Sendable, Hashable {
    public enum Kind: Sendable { case company, fund }

    public var name: String
    /// A fund/ETF holds a basket of other companies; a company is a single business
    public var kind: Kind
    public var sector: String?
    public var industry: String?
    public var website: String?

    // --- Size and price ---
    /// What the whole company is worth on the market
    public var marketCap: Double?
    /// Lowest and highest the share price has been over the past year
    public var yearLow: Double?
    public var yearHigh: Double?
    /// How much the price moved over the past year, and the same for the
    /// whole US market, so the two can be compared (fractions)
    public var yearChange: Double?
    public var marketYearChange: Double?
    /// How much this tends to move when the market moves 1% (1.0 = the same)
    public var beta: Double?

    // --- What you get paid ---
    /// Yearly dividend as a fraction of the price (0.02 = pays ~2% a year)
    public var dividendYield: Double?
    /// Yearly dividend in money, per share
    public var dividendPerShare: Double?
    public var nextDividendDate: Date?

    // --- How the business is doing (companies only) ---
    /// Price divided by a year's earnings per share — what you pay for $1 of profit
    public var priceToEarnings: Double?
    /// A year's profit per share, in money
    public var earningsPerShare: Double?
    /// Share of sales left over as profit (0.25 = $25 profit per $100 of sales)
    public var profitMargin: Double?
    /// Total sales over the past year, and how that compares to the year before
    public var revenue: Double?
    public var revenueGrowth: Double?

    // --- Funds only ---
    /// Yearly fee as a fraction of what you hold (0.0003 = 0.03% a year)
    public var expenseRatio: Double?
    public var returnYearToDate: Double?
    /// Average yearly return over the past three / five years (fractions)
    public var returnThreeYear: Double?
    public var returnFiveYear: Double?
    public var topHoldings: [FundHolding]
}

public actor YahooClient {
    public static let shared = YahooClient()

    private struct Entry { var value: Any; var expires: Date }
    private var memo: [String: Entry] = [:]
    private var crumb: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static let host = "https://query2.finance.yahoo.com"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // MARK: Memo

    private func cached<T>(_ key: String) -> T? {
        guard let hit = memo[key], hit.expires > Date() else { return nil }
        return hit.value as? T
    }

    private func store(_ key: String, _ value: Any, ttl: TimeInterval) {
        memo[key] = Entry(value: value, expires: Date().addingTimeInterval(ttl))
    }

    // MARK: HTTP

    private func get(_ url: URL) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Yahoo wants a cookie plus a matching "crumb" token on most endpoints.
    private func getCrumb(renew: Bool = false) async -> String? {
        if let crumb, !renew { return crumb }
        crumb = nil
        _ = try? await get(URL(string: "https://fc.yahoo.com")!) // sets the cookie (the page itself 404s)
        guard let (data, status) = try? await get(URL(string: "\(Self.host)/v1/test/getcrumb")!),
              status == 200,
              let text = String(data: data, encoding: .utf8), !text.isEmpty, !text.contains("<") else {
            return nil
        }
        crumb = text
        return text
    }

    /// GET a JSON endpoint that needs the crumb; retries once with a new crumb.
    private func getJSON(path: String, query: [URLQueryItem]) async -> [String: Any]? {
        for attempt in 0..<2 {
            guard let crumb = await getCrumb(renew: attempt > 0) else { return nil }
            var comps = URLComponents(string: Self.host + path)!
            comps.queryItems = query + [URLQueryItem(name: "crumb", value: crumb)]
            guard let url = comps.url, let (data, status) = try? await get(url) else { return nil }
            if status == 401 || status == 403 { continue }
            guard status == 200 else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return nil
    }

    // MARK: Quotes

    /// Today's prices for several symbols in one request (5-minute memo).
    public func quotes(for symbols: [String]) async -> [String: Quote] {
        var result: [String: Quote] = [:]
        var missing: [String] = []
        for s in symbols {
            if let q: Quote = cached("quote:\(s)") { result[s] = q } else { missing.append(s) }
        }
        guard !missing.isEmpty else { return result }

        if let json = await getJSON(path: "/v7/finance/quote",
                                    query: [URLQueryItem(name: "symbols", value: missing.joined(separator: ","))]),
           let rows = (json["quoteResponse"] as? [String: Any])?["result"] as? [[String: Any]] {
            for row in rows {
                guard let symbol = row["symbol"] as? String, let price = number(row["regularMarketPrice"]) else { continue }
                let q = Quote(
                    price: price,
                    currency: row["currency"] as? String ?? "USD",
                    name: row["longName"] as? String ?? row["shortName"] as? String ?? symbol,
                    changeToday: number(row["regularMarketChange"]),
                    changeTodayPercent: number(row["regularMarketChangePercent"])
                )
                store("quote:\(symbol)", q, ttl: 5 * 60)
                result[symbol] = q
            }
        }

        // Anything the quote endpoint didn't answer: try the chart endpoint,
        // which works without the cookie
        for s in missing where result[s] == nil {
            if let q = await chartQuote(s) {
                store("quote:\(s)", q, ttl: 5 * 60)
                result[s] = q
            }
        }
        return result
    }

    public func quote(_ symbol: String) async -> Quote? {
        await quotes(for: [symbol])[symbol]
    }

    private func chartQuote(_ symbol: String) async -> Quote? {
        var comps = URLComponents(string: "\(Self.host)/v8/finance/chart/\(symbol)")!
        comps.queryItems = [URLQueryItem(name: "range", value: "5d"), URLQueryItem(name: "interval", value: "1d")]
        guard let url = comps.url, let (data, status) = try? await get(url), status == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let meta = (((json["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first)?["meta"] as? [String: Any],
              let price = number(meta["regularMarketPrice"]) else { return nil }
        let prev = number(meta["previousClose"]) ?? number(meta["chartPreviousClose"])
        let change = prev.map { price - $0 }
        return Quote(
            price: price,
            currency: meta["currency"] as? String ?? "USD",
            name: meta["longName"] as? String ?? meta["shortName"] as? String ?? symbol,
            changeToday: change,
            changeTodayPercent: prev.flatMap { $0 != 0 ? (price - $0) / $0 * 100 : nil }
        )
    }

    // MARK: Company info

    /// The key numbers for a stock or fund (24-hour memo).
    public func companyInfo(_ symbol: String) async -> CompanyInfo? {
        if let hit: CompanyInfo = cached("info:\(symbol)") { return hit }
        guard let r = await quoteSummary(symbol, modules: [
            "assetProfile", "summaryDetail", "price", "defaultKeyStatistics", "financialData", "calendarEvents",
        ]) else { return nil }

        let profile = r["assetProfile"] as? [String: Any]
        let detail = r["summaryDetail"] as? [String: Any]
        let price = r["price"] as? [String: Any]
        let stats = r["defaultKeyStatistics"] as? [String: Any]
        let fin = r["financialData"] as? [String: Any]
        let quoteType = price?["quoteType"] as? String
        let isFund = quoteType == "ETF" || quoteType == "MUTUALFUND"

        // Yahoo rejects the whole request if a module doesn't apply, so
        // fund-only modules are fetched separately and are allowed to fail
        let fund = isFund ? await quoteSummary(symbol, modules: ["fundProfile", "topHoldings"]) : nil
        let fees = (fund?["fundProfile"] as? [String: Any])?["feesExpensesInvestment"] as? [String: Any]
        let holdings = ((fund?["topHoldings"] as? [String: Any])?["holdings"] as? [[String: Any]]) ?? []

        let info = CompanyInfo(
            name: price?["longName"] as? String ?? price?["shortName"] as? String ?? symbol,
            kind: isFund ? .fund : .company,
            sector: profile?["sector"] as? String,
            industry: profile?["industry"] as? String,
            website: profile?["website"] as? String,

            marketCap: number(price?["marketCap"]) ?? number(detail?["marketCap"]),
            yearLow: number(detail?["fiftyTwoWeekLow"]),
            yearHigh: number(detail?["fiftyTwoWeekHigh"]),
            yearChange: number(stats?["52WeekChange"]),
            marketYearChange: number(stats?["SandP52WeekChange"]),
            beta: number(detail?["beta"]) ?? number(stats?["beta"]),

            dividendYield: number(detail?["dividendYield"]) ?? number(detail?["yield"]),
            dividendPerShare: number(detail?["dividendRate"]),
            nextDividendDate: number((r["calendarEvents"] as? [String: Any])?["dividendDate"])
                .map { Date(timeIntervalSince1970: $0) },

            priceToEarnings: number(detail?["trailingPE"]),
            earningsPerShare: number(stats?["trailingEps"]),
            profitMargin: number(fin?["profitMargins"]) ?? number(stats?["profitMargins"]),
            revenue: number(fin?["totalRevenue"]),
            revenueGrowth: number(fin?["revenueGrowth"]),

            expenseRatio: number(fees?["annualReportExpenseRatio"]),
            returnYearToDate: number(stats?["ytdReturn"]),
            returnThreeYear: number(stats?["threeYearAverageReturn"]),
            returnFiveYear: number(stats?["fiveYearAverageReturn"]),
            topHoldings: holdings.compactMap { h in
                guard let pct = number(h["holdingPercent"]) else { return nil }
                let sym = h["symbol"] as? String
                return FundHolding(symbol: sym, name: h["holdingName"] as? String ?? sym ?? "", percent: pct)
            }
        )
        store("info:\(symbol)", info, ttl: 24 * 60 * 60)
        return info
    }

    private func quoteSummary(_ symbol: String, modules: [String]) async -> [String: Any]? {
        guard let json = await getJSON(
            path: "/v10/finance/quoteSummary/\(symbol)",
            query: [URLQueryItem(name: "modules", value: modules.joined(separator: ","))]
        ) else { return nil }
        return ((json["quoteSummary"] as? [String: Any])?["result"] as? [[String: Any]])?.first
    }
}

/// Yahoo sends numbers either plain or as {"raw": 1.23, "fmt": "1.23"}.
private func number(_ v: Any?) -> Double? {
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    if let d = v as? [String: Any], let raw = d["raw"] as? NSNumber { return raw.doubleValue }
    return nil
}
