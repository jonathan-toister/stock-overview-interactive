import PortfolioCore
import SwiftUI

@MainActor
struct AccountView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let s = store.summary, let account = store.account {
            Page {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My account").font(.headline).foregroundStyle(.secondary)
                    Text(Fmt.money0(s.totalValue, s.currency))
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                    Text("everything together — your stocks plus cash"
                         + (s.reportDate.map { " · IBKR report from \(Fmt.shortDate($0))" } ?? ""))
                        .foregroundStyle(.secondary)
                }

                Card(title: "Overview") {
                    ValueRow(label: "Your stocks are worth now", value: Fmt.money0(s.investedValue, s.currency))
                    Divider()
                    ValueRow(label: "What you paid for them", value: Fmt.money0(s.totalPaid, s.currency))
                    Divider()
                    ValueRow(
                        label: s.gainLoss >= 0 ? "Gain" : "Loss",
                        value: Fmt.signedMoney0(s.gainLoss, s.currency)
                            + (s.gainLossPercent.map { "  (\(Fmt.percent($0)))" } ?? ""),
                        note: "worth now minus what you paid",
                        color: .gain(s.gainLoss),
                        bold: true
                    )
                    Divider()
                    ValueRow(label: "Cash in the account", value: Fmt.money0(s.cash, s.currency))
                    Divider()
                    ValueRow(
                        label: "Dividends this year",
                        value: Fmt.money0(s.dividendsThisYear, s.currency),
                        note: "what companies paid you this year, after tax"
                    )
                }

                Card(title: "Dividends", subtitle: "Money companies paid you for holding their stock.") {
                    DividendsTable(dividends: account.dividends, showStock: true)
                }

                Card(title: "Your buys & sells") {
                    TradesTable(trades: account.trades)
                }
            }
        }
    }
}
