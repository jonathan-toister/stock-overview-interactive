import PortfolioCore
import SwiftUI

@MainActor
struct StockView: View {
    @Environment(AppStore.self) private var store
    var symbol: String

    @State private var quote: Quote?
    @State private var company: CompanyInfo?
    @State private var loaded = false

    var body: some View {
        let pos = store.position(symbol)
        let dividends = store.dividends(for: symbol)
        let currency = pos?.currency ?? quote?.currency ?? "USD"
        let name = company?.name ?? quote?.name ?? pos?.name ?? symbol

        Page {
            header(name: name)

            if let pos {
                yourShares(pos, dividends: dividends)
            } else {
                Text("You don't currently own this stock.").foregroundStyle(.secondary)
            }

            if let company {
                Card(title: "Key numbers", subtitle: "The few measures worth knowing, and what each one means.") {
                    KeyNumbersView(company: company, currency: currency,
                                   price: quote?.price ?? pos?.currentPrice)
                }
            } else if !loaded {
                ProgressView("Loading key numbers…").frame(maxWidth: .infinity)
            }

            Card(title: "Dividends this stock paid you") {
                DividendsTable(dividends: dividends)
            }

            Card(title: "Your buys & sells of \(symbol)") {
                TradesTable(trades: store.trades(for: symbol))
            }
        }
        .navigationTitle(symbol)
        .task {
            async let q = YahooClient.shared.quote(symbol)
            async let c = YahooClient.shared.companyInfo(symbol)
            (quote, company) = await (q, c)
            loaded = true
        }
    }

    private func header(name: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.largeTitle.weight(.bold))
                Text(([symbol] + [company?.sector, company?.industry].compactMap { $0 }).joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.money(quote.price, quote.currency))
                        .font(.system(size: 28, weight: .semibold).monospacedDigit())
                    if let pct = quote.changeTodayPercent {
                        Text("\(quote.changeToday.map { Fmt.signedMoney($0, quote.currency) } ?? "") (\(Fmt.percent(pct, digits: 2))) today")
                            .font(.callout.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.gain(pct))
                    } else {
                        Text("price now").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func yourShares(_ pos: EnrichedPosition, dividends: [Dividend]) -> some View {
        let c = pos.currency
        let divTotal = dividends.reduce(0) { $0 + $1.netAmount }
        // When the stock is down, say how much of the loss its dividends give back
        var lossNote: String?
        if pos.gainLoss < 0 && divTotal > 0 {
            let coverage = divTotal / -pos.gainLoss
            lossNote = coverage >= 1
                ? "more than makes up for the loss above"
                : "covers \(Int((coverage * 100).rounded()))% of the loss above"
        }

        return Card(title: "Your shares") {
            ValueRow(
                label: "Worth now",
                value: Fmt.money(pos.currentValue, c),
                note: "\(Fmt.shares(pos.position.quantity)) × \(Fmt.money(pos.currentPrice, c)) each"
                    + (pos.priceIsLive ? "" : " (price from the last IBKR report)")
            )
            Divider()
            ValueRow(
                label: "What you paid",
                value: Fmt.money(pos.position.costBasis, c),
                note: "\(Fmt.money(pos.position.avgCost, c)) a share on average"
            )
            Divider()
            ValueRow(
                label: pos.gainLoss >= 0 ? "Gain" : "Loss",
                value: Fmt.signedMoney(pos.gainLoss, c)
                    + (pos.gainLossPercent.map { "  (\(Fmt.percent($0)))" } ?? ""),
                note: "worth now minus what you paid",
                color: .gain(pos.gainLoss),
                bold: true
            )
            if divTotal > 0 {
                Divider()
                ValueRow(
                    label: "Dividends paid to you",
                    value: Fmt.money(divTotal, c),
                    note: "this past year, after tax" + (lossNote.map { " — \($0)" } ?? "")
                )
            }
        }
    }
}
