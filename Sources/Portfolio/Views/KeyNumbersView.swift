import PortfolioCore
import SwiftUI

// A short panel of the standard measures behind a ticker. Each one is labelled
// with its real name (the name you'd meet on IBKR or anywhere else) and a line
// underneath says in plain words what the number actually means.
//
// The list is deliberately short: eight for a company, six for a fund. A new
// measure has to displace an old one rather than be added on.

private struct Stat: Identifiable {
    var label: String
    var value: String
    var note: String?
    var color: Color = .primary
    var id: String { label }
}

private func companyStats(_ c: CompanyInfo, _ cur: String) -> [Stat] {
    var stats: [Stat] = []

    if let y = c.dividendYield, y > 0 {
        // Yahoo's dividend date can be the last payment rather than the next
        // one, so say which it is instead of promising a date that has passed
        let paymentDate = c.nextDividendDate.map {
            "\($0 > Date() ? "next" : "last") payment \(Fmt.shortDate($0))"
        }
        stats.append(Stat(
            label: "Dividend yield",
            value: Fmt.rate(y),
            note: ["the slice of the price paid back to you each year",
                   c.dividendPerShare.map { "\(Fmt.money($0, cur)) a share" },
                   paymentDate].compactMap { $0 }.joined(separator: " — ")
        ))
    }

    if let pe = c.priceToEarnings, pe > 0 {
        stats.append(Stat(
            label: "P/E ratio",
            value: String(format: "%.1f", pe),
            // The "years to earn the price back" framing is the one beginners grasp
            note: "how pricey the shares are: you pay \(Fmt.money(pe, cur)) for every \(Fmt.money0(1, cur)) it earns in a year, so at that rate it takes about \(Int(pe.rounded())) years of profit to earn the price back"
        ))
    }

    if let yc = c.yearChange {
        stats.append(Stat(
            label: "One-year return",
            value: Fmt.signedRate(yc),
            note: c.marketYearChange.map {
                "how the share price moved over twelve months — the whole US market moved \(Fmt.signedRate($0))"
            } ?? "how the share price moved over twelve months",
            color: .gain(yc)
        ))
    }

    if let cap = c.marketCap {
        stats.append(Stat(
            label: "Market cap",
            value: Fmt.compactMoney(cap, cur),
            note: "what the whole company is worth — every share added together"
        ))
    }

    if let beta = c.beta {
        // The market itself is always 1.0, so the gap from 1 is the readable part
        let gap = Int((abs(beta - 1) * 100).rounded())
        let feel = beta > 1.15
            ? "this moves about \(gap)% more than the market — a bumpier ride"
            : beta < 0.85
                ? "this moves about \(gap)% less than the market — a smoother ride"
                : "this moves about as much as the market does"
        stats.append(Stat(label: "Beta", value: String(format: "%.2f×", beta), note: "how much the price swings: \(feel)"))
    }

    if let m = c.profitMargin {
        stats.append(Stat(
            label: "Profit margin",
            value: Fmt.rate(m),
            note: "out of every \(Fmt.money0(100, cur)) of sales, about \(Fmt.money(m * 100, cur)) is profit"
        ))
    }

    if let rev = c.revenue {
        stats.append(Stat(
            label: "Revenue",
            value: Fmt.compactMoney(rev, cur),
            note: c.revenueGrowth.map {
                "everything it sold in the past year — \($0 >= 0 ? "up" : "down") \(Fmt.rate(abs($0))) on the year before"
            } ?? "everything it sold in the past year"
        ))
    }

    return stats
}

private func fundStats(_ c: CompanyInfo, _ cur: String) -> [Stat] {
    var stats: [Stat] = []

    if let e = c.expenseRatio {
        stats.append(Stat(
            label: "Expense ratio",
            value: Fmt.rate(e, digits: 2),
            note: "its yearly fee — \(Fmt.money(e * 10_000, cur)) a year for every \(Fmt.money0(10_000, cur)) you hold"
        ))
    }
    if let y = c.dividendYield, y > 0 {
        stats.append(Stat(label: "Dividend yield", value: Fmt.rate(y), note: "the slice of the price paid back to you each year"))
    }
    if let r = c.returnYearToDate {
        stats.append(Stat(label: "Return this year", value: Fmt.signedRate(r), note: "change since 1 January", color: .gain(r)))
    }
    if let r = c.returnThreeYear {
        stats.append(Stat(label: "3-year return", value: Fmt.signedRate(r), note: "the average for each of the past three years", color: .gain(r)))
    }
    if let r = c.returnFiveYear {
        stats.append(Stat(label: "5-year return", value: Fmt.signedRate(r), note: "the average for each of the past five years", color: .gain(r)))
    }
    return stats
}

struct KeyNumbersView: View {
    var company: CompanyInfo
    var currency: String
    /// Today's price, so the year's range can say where the price sits in it
    var price: Double?

    var body: some View {
        let isFund = company.kind == .fund
        let stats = isFund ? fundStats(company, currency) : companyStats(company, currency)
        let holdings = isFund ? Array(company.topHoldings.prefix(8)) : []

        VStack(alignment: .leading, spacing: 16) {
            if stats.isEmpty && range == nil && holdings.isEmpty {
                Text("Yahoo Finance has no key numbers for this one.").foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 20, alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(stats) { s in
                    StatCell(label: s.label, value: s.value, note: s.note, color: s.color)
                }
            }

            if let (low, high, where_) = range {
                StatCell(
                    label: "52-week range",
                    value: "\(Fmt.money(low, currency)) – \(Fmt.money(high, currency))",
                    note: "the lowest and highest the price has been in the past year"
                        + (where_.map { " — today's \(Fmt.money(price!, currency)) sits \(Int($0.rounded()))% of the way up" } ?? "")
                )
            }

            if !holdings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top holdings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("the biggest companies the fund owns, and how much of it each one is")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(holdings, id: \.self) { h in
                        HStack {
                            Text(h.name)
                            Spacer()
                            Text(Fmt.rate(h.percent)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }

            if let site = company.website, let url = URL(string: site) {
                Link(site.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression),
                     destination: url)
                    .font(.callout)
            }
        }
    }

    /// Low, high, and where today's price sits between them (0–100%).
    /// A range means little for a fund tracking the whole market, so it's
    /// shown for companies only.
    private var range: (Double, Double, Double?)? {
        guard company.kind == .company, let low = company.yearLow, let high = company.yearHigh, high > low else {
            return nil
        }
        let pos = price.map { max(0, min(100, ($0 - low) / (high - low) * 100)) }
        return (low, high, pos)
    }
}

private struct StatCell: View {
    var label: String
    var value: String
    var note: String?
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
