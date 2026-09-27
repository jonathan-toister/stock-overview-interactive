import Foundation
import PortfolioCore

// Checks the app's data code against real data without opening the app.
//
//   swift run portfolio-check --file report.xml
//       Parse a saved Flex report and print what the app would show.
//   swift run portfolio-check --yahoo AAPL
//       Show what Yahoo returns for one symbol (public data only).
//   swift run portfolio-check
//       Download the report and print a connection check. Prints only counts,
//       never amounts, so account figures don't end up in logs.
//
// IBKR details are the ones saved by the app's setup guide.

let args = CommandLine.arguments.dropFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), args.index(after: i) < args.endIndex else { return nil }
    return args[args.index(after: i)]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

func money(_ v: Double) -> String { String(format: "%.2f", v) }

if let path = option("--file") {
    let stmt: FlexStatement
    do { stmt = try parseFlexFile(URL(fileURLWithPath: path)) } catch { fail(error.localizedDescription) }
    let data = accountData(from: stmt)
    print("Sections: \(stmt.sections.sorted().joined(separator: ", "))")
    print("Report date: \(data.reportDate ?? "-")")
    print("Cash: \(money(data.balances.cash)) \(data.balances.currency)")
    print("\nPositions (\(data.positions.count)):")
    for p in data.positions {
        print("  \(p.symbol)  qty \(p.quantity)  paid \(money(p.costBasis))  avg \(money(p.avgCost))  snapshot \(money(p.snapshotPrice)) \(p.currency)")
    }
    print("\nTrades (\(data.trades.count)):")
    for t in data.trades {
        print("  \(t.date)  \(t.side.rawValue)  \(t.quantity) × \(t.symbol) @ \(money(t.price)) = \(money(t.amount))")
    }
    print("\nDividends (\(data.dividends.count)):")
    for d in data.dividends {
        let r = d.reinvested.map { $0 ? "reinvested" : "kept as cash" } ?? "unknown"
        print("  \(d.date)  \(d.symbol)  paid \(money(d.amount))  tax \(money(d.taxWithheld))  net \(money(d.netAmount))  \(r)")
    }
    exit(0)
}

if let symbol = option("--yahoo") {
    guard let q = await YahooClient.shared.quote(symbol) else { fail("No price from Yahoo for \(symbol).") }
    print("Quote: \(q.name)  \(q.price) \(q.currency)  today \(q.changeTodayPercent.map { String(format: "%+.2f%%", $0) } ?? "-")")
    guard let c = await YahooClient.shared.companyInfo(symbol) else { fail("No company info from Yahoo for \(symbol).") }
    for (label, value) in Mirror(reflecting: c).children.map({ ($0.label ?? "", $0.value) }) where label != "topHoldings" {
        print("  \(label): \(value)")
    }
    print("  topHoldings: \(c.topHoldings.count)")
    exit(0)
}

guard let creds = CredentialStore.load() else {
    fail("No IBKR details found — connect your account in the app first.")
}
print("Requesting your report from IBKR (can take ~10-30 seconds)...")
let stmt: FlexStatement
do { stmt = try await fetchFlexStatement(token: creds.token, queryId: creds.queryId) } catch {
    fail(error.localizedDescription)
}
let data = accountData(from: stmt)

print("\n✓ Connected! Report received.")
print("  Period:         \(stmt.fromDate ?? "?") → \(stmt.toDate ?? "?")")
print("  Sections:       \(stmt.sections.sorted().joined(separator: ", "))")
print("  Open positions: \(data.positions.count)")
print("  Trades:         \(data.trades.count)")
print("  Dividends:      \(data.dividends.count)")
