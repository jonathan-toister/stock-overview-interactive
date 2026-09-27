import PortfolioCore
import SwiftUI

@MainActor
struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("pillMode") private var pillMode: PillMode = .today

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            if let s = store.summary {
                NavigationLink(value: SidebarItem.account) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("My account").font(.headline)
                        HStack {
                            Text(Fmt.money0(s.totalValue, s.currency))
                                .font(.title3.weight(.semibold).monospacedDigit())
                            Spacer()
                            if let pct = s.gainLossPercent {
                                Text(Fmt.percent(pct))
                                    .font(.callout.weight(.medium).monospacedDigit())
                                    .foregroundStyle(Color.gain(pct))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section("Your stocks") {
                if store.positions.isEmpty && store.summary != nil {
                    Text("No stocks in the account right now.").foregroundStyle(.secondary)
                }
                ForEach(store.positions) { p in
                    NavigationLink(value: SidebarItem.stock(p.symbol)) {
                        PositionRow(position: p, mode: pillMode) { pillMode = pillMode.next }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// One stock in the sidebar, laid out like Apple's Stocks app.
struct PositionRow: View {
    var position: EnrichedPosition
    var mode: PillMode
    var onTapPill: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.symbol).font(.headline)
                Text(position.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money0(position.currentValue, position.currency))
                    .font(.callout.weight(.medium).monospacedDigit())
                pill
            }
        }
        .padding(.vertical, 4)
    }

    private var pillValue: (text: String, value: Double?) {
        switch mode {
        case .today:
            return (position.changeTodayPercent.map { Fmt.percent($0, digits: 2) } ?? "–", position.changeTodayPercent)
        case .gainPercent:
            return (position.gainLossPercent.map { Fmt.percent($0) } ?? "–", position.gainLossPercent)
        case .gainAmount:
            return (Fmt.signedMoney0(position.gainLoss, position.currency), position.gainLoss)
        }
    }

    private var pill: some View {
        let (text, value) = pillValue
        return Button(action: onTapPill) {
            Text(text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 64, alignment: .trailing)
                .background(Color.gain(value).opacity(value == nil || value == 0 ? 0.5 : 1),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(mode == .today ? "Change today — click to show your total gain or loss"
              : "Your gain or loss — click to switch")
    }
}
