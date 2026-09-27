import Foundation

// Turns IBKR's Flex report XML into the app's data shapes.

/// One row of the report: IBKR puts every field in an XML attribute.
public typealias FlexRow = [String: String]

/// The parts of a Flex report the app uses.
public struct FlexStatement: Sendable {
    public var accountId: String?
    public var fromDate: String?
    public var toDate: String?
    /// Which report sections were included (e.g. "OpenPositions", "Trades")
    public var sections: Set<String> = []
    public var openPositions: [FlexRow] = []
    public var trades: [FlexRow] = []
    public var cashTransactions: [FlexRow] = []
    public var cashReport: [FlexRow] = []
    public var accountInformation: FlexRow?
}

/// What IBKR sent back: either a finished report, or a status message
/// (reference code, "still generating", or an error).
enum FlexResponse {
    case statement(FlexStatement?)
    case status([String: String])
}

// MARK: - XML reading

private final class FlexXMLReader: NSObject, XMLParserDelegate {
    static let sectionNames: Set<String> = [
        "OpenPositions", "Trades", "CashTransactions", "CashReport", "AccountInformation",
    ]

    var isQueryResponse = false
    var statement: FlexStatement?
    var statementDone = false
    var inStatement = false
    var status: [String: String] = [:]
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "FlexQueryResponse":
            isQueryResponse = true
        case "FlexStatement" where !statementDone:
            // Only the first statement is used (one account per report)
            inStatement = true
            statement = FlexStatement(
                accountId: attributes["accountId"],
                fromDate: attributes["fromDate"],
                toDate: attributes["toDate"]
            )
        default:
            guard inStatement else { return }
            if Self.sectionNames.contains(name) { statement?.sections.insert(name) }
            switch name {
            case "OpenPosition": statement?.openPositions.append(attributes)
            case "Trade": statement?.trades.append(attributes)
            case "CashTransaction": statement?.cashTransactions.append(attributes)
            case "CashReportCurrency": statement?.cashReport.append(attributes)
            case "AccountInformation": statement?.accountInformation = attributes
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if name == "FlexStatement" && inStatement {
            inStatement = false
            statementDone = true
        } else if !isQueryResponse {
            // Status replies are simple <Tag>value</Tag> children
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { status[name] = value }
        }
        text = ""
    }
}

func parseFlexXML(_ data: Data) throws -> FlexResponse {
    let reader = FlexXMLReader()
    let parser = XMLParser(data: data)
    parser.delegate = reader
    guard parser.parse() else {
        throw FlexError(message: "IBKR sent back something the app couldn't read. Try again in a minute.")
    }
    return reader.isQueryResponse ? .statement(reader.statement) : .status(reader.status)
}

/// Reads a saved Flex report file (used by portfolio-check to test the parser).
public func parseFlexFile(_ url: URL) throws -> FlexStatement {
    guard case .statement(let stmt?) = try parseFlexXML(try Data(contentsOf: url)) else {
        throw FlexError(message: "That file isn't an IBKR Flex report.")
    }
    return stmt
}

// MARK: - Converting rows to app data

private func num(_ v: String?) -> Double {
    guard let v, let n = Double(v.trimmingCharacters(in: .whitespaces)), n.isFinite else { return 0 }
    return n
}

/// Dates can come as "yyyy-MM-dd", "yyyyMMdd", or with a ";HHmmss" time part,
/// depending on the date format chosen in the Flex Query settings.
public func flexDate(_ v: String?) -> String {
    let d = String((v ?? "").split(separator: ";", omittingEmptySubsequences: false).first ?? "")
    if d.count == 8, d.allSatisfy(\.isNumber) {
        let c = Array(d)
        return "\(String(c[0..<4]))-\(String(c[4..<6]))-\(String(c[6..<8]))"
    }
    return d
}

private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// nil when either date can't be read — then nothing counts as "close by".
private func daysBetween(_ a: String, _ b: String) -> Double? {
    guard let da = dayFormatter.date(from: a), let db = dayFormatter.date(from: b) else { return nil }
    return abs(da.timeIntervalSince(db)) / 86_400
}

/// Some report setups include both summary and per-lot/detail rows for the
/// same data; keep only one level to avoid counting things twice.
private func oneLevel(_ rows: [FlexRow], _ level: String) -> [FlexRow] {
    let matching = rows.filter { ($0["levelOfDetail"] ?? "") == level }
    return matching.isEmpty ? rows.filter { ($0["levelOfDetail"] ?? "").isEmpty } : matching
}

private func parsePositions(_ stmt: FlexStatement) -> [Position] {
    oneLevel(stmt.openPositions, "SUMMARY")
        .filter { num($0["position"]) != 0 }
        .map { r in
            Position(
                symbol: r["symbol"] ?? "",
                description: r["description"] ?? r["symbol"] ?? "",
                quantity: num(r["position"]),
                costBasis: num(r["costBasisMoney"]),
                avgCost: num(r["costBasisPrice"]),
                snapshotPrice: num(r["markPrice"]),
                snapshotValue: num(r["positionValue"]),
                currency: r["currency"] ?? "USD"
            )
        }
}

private func parseTrades(_ stmt: FlexStatement) -> [Trade] {
    oneLevel(stmt.trades, "EXECUTION")
        .filter { !($0["symbol"] ?? "").isEmpty }
        .map { r in
            Trade(
                date: flexDate(r["tradeDate"] ?? r["dateTime"]),
                symbol: r["symbol"] ?? "",
                description: r["description"] ?? r["symbol"] ?? "",
                side: (r["buySell"] ?? "").uppercased() == "SELL" ? .sell : .buy,
                quantity: abs(num(r["quantity"])),
                price: num(r["tradePrice"]),
                amount: abs(num(r["tradeMoney"])),
                currency: r["currency"] ?? "USD"
            )
        }
        .sorted { $0.date > $1.date }
}

private func parseDividends(_ stmt: FlexStatement, trades: [Trade]) -> [Dividend] {
    let rows = oneLevel(stmt.cashTransactions, "DETAIL")
    let type = { (r: FlexRow) in r["type"] ?? "" }

    let payments = rows.filter { ["Dividends", "Payment In Lieu Of Dividends"].contains(type($0)) }
    let taxes = rows.filter { type($0) == "Withholding Tax" }

    return payments
        .map { r in
            let date = flexDate(r["dateTime"] ?? r["reportDate"])
            let symbol = r["symbol"] ?? ""
            let amount = num(r["amount"])

            // Tax rows are negative amounts reported alongside the payment
            let taxWithheld = taxes
                .filter { t in
                    (t["symbol"] ?? "") == symbol
                        && (daysBetween(flexDate(t["dateTime"] ?? t["reportDate"]), date).map { $0 <= 3 } ?? false)
                }
                .reduce(0) { $0 + abs(num($1["amount"])) }

            let netAmount = amount - taxWithheld

            // Best-effort: IBKR reports dividend reinvestment as a normal buy
            // soon after the payment, for roughly the paid amount.
            let reinvested: Bool? = trades.isEmpty
                ? nil
                : trades.contains { t in
                    t.side == .buy
                        && t.symbol == symbol
                        && (daysBetween(t.date, date).map { $0 <= 7 } ?? false)
                        && abs(t.amount - netAmount) <= max(1, netAmount * 0.3)
                }

            return Dividend(
                date: date,
                symbol: symbol,
                description: r["description"] ?? symbol,
                amount: amount,
                taxWithheld: taxWithheld,
                netAmount: netAmount,
                currency: r["currency"] ?? "USD",
                reinvested: reinvested
            )
        }
        .sorted { $0.date > $1.date }
}

private func parseBalances(_ stmt: FlexStatement) -> Balances {
    let rows = stmt.cashReport
    let row = rows.first { $0["currency"] == "BASE_SUMMARY" } ?? rows.first
    let baseCurrency = stmt.accountInformation?["currency"]
        ?? rows.compactMap { $0["currency"] }.first { $0 != "BASE_SUMMARY" }
        ?? "USD"
    return Balances(
        cash: num(row?["endingCash"] ?? row?["endingSettledCash"]),
        currency: baseCurrency
    )
}

public func accountData(from stmt: FlexStatement, fetchedAt: Date = Date()) -> AccountData {
    let trades = parseTrades(stmt)
    return AccountData(
        positions: parsePositions(stmt),
        trades: trades,
        dividends: parseDividends(stmt, trades: trades),
        balances: parseBalances(stmt),
        fetchedAt: ISO8601DateFormatter.withFractions.string(from: fetchedAt),
        reportDate: stmt.toDate.map(flexDate)
    )
}
