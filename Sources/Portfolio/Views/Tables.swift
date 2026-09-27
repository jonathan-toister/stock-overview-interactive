import PortfolioCore
import SwiftUI

@MainActor
struct DividendsTable: View {
    @Environment(AppStore.self) private var store
    var dividends: [Dividend]
    var showStock = false

    var body: some View {
        if dividends.isEmpty {
            Text("No dividend payments in the last year.").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Date")
                    if showStock { Text("Stock") }
                    Text("Paid to you").gridColumnAlignment(.trailing)
                    Text("Tax taken").gridColumnAlignment(.trailing)
                    Text("You received").gridColumnAlignment(.trailing)
                    Text("Reinvested?")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()

                ForEach(Array(dividends.enumerated()), id: \.offset) { _, d in
                    GridRow {
                        Text(Fmt.shortDate(d.date)).foregroundStyle(.secondary)
                        if showStock {
                            Button(d.symbol) { store.selection = .stock(d.symbol) }
                                .buttonStyle(.link)
                                .fontWeight(.semibold)
                        }
                        Text(Fmt.money(d.amount, d.currency))
                        Text(d.taxWithheld > 0 ? Fmt.money(d.taxWithheld, d.currency) : "–")
                            .foregroundStyle(.secondary)
                        Text(Fmt.money(d.netAmount, d.currency)).fontWeight(.semibold)
                        Text(d.reinvested.map { $0 ? "Yes — bought more shares" : "No — kept as cash" } ?? "–")
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }

                Divider()
                GridRow {
                    Text("Total received (after tax)")
                        .gridCellColumns(showStock ? 4 : 3)
                    Text(totals).fontWeight(.bold).monospacedDigit()
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
        }
    }

    // Totals per currency (usually there's just one)
    private var totals: String {
        var sums: [String: Double] = [:]
        var order: [String] = []
        for d in dividends {
            if sums[d.currency] == nil { order.append(d.currency) }
            sums[d.currency, default: 0] += d.netAmount
        }
        return order.map { Fmt.money(sums[$0]!, $0) }.joined(separator: " + ")
    }
}

struct TradesTable: View {
    var trades: [Trade]
    @State private var showAll = false
    private let initialShown = 15

    var body: some View {
        if trades.isEmpty {
            Text("No buys or sells in the last year.").foregroundStyle(.secondary)
        } else {
            let shown = showAll ? trades : Array(trades.prefix(initialShown))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Date")
                    Text("What happened")
                    Text("Total").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()

                ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                    GridRow {
                        Text(Fmt.shortDate(t.date)).foregroundStyle(.secondary)
                        (Text(t.side == .buy ? "Bought " : "Sold ")
                            .foregroundColor(t.side == .buy ? .green : .red)
                            .fontWeight(.medium)
                         + Text("\(Fmt.number(t.quantity)) × ")
                         + Text(t.symbol).fontWeight(.semibold)
                         + Text(" at \(Fmt.money(t.price, t.currency))"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.money(t.amount, t.currency))
                    }
                    .monospacedDigit()
                }
            }
            if trades.count > initialShown {
                Button(showAll ? "Show fewer" : "Show all \(trades.count)") { showAll.toggle() }
                    .buttonStyle(.link)
                    .padding(.top, 4)
            }
        }
    }
}
