import PortfolioCore
import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.isConnected {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 380)
                } detail: {
                    detail
                }
                .toolbar { toolbar }
                .sheet(item: $store.setupRequest) { step in
                    SetupGuide(startAt: step, isSheet: true)
                        .frame(width: 640, height: 600)
                }
            } else {
                // First launch: the setup guide fills the window
                SetupGuide(startAt: DevHooks.setupStep ?? .welcome, isSheet: false)
            }
        }
        .task { await store.start() }
    }

    // The page's scroll view has to be the detail column's own content, not
    // tucked under the banner in a VStack: otherwise macOS loses track of the
    // space under the toolbar and the top of the page ends up hidden after
    // scrolling. The banner rides on top as a safe-area inset instead.
    private var detail: some View {
        page.safeAreaInset(edge: .top, spacing: 0) { banner }
    }

    @ViewBuilder
    private var banner: some View {
        if let problem = store.connectionProblem {
            Banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Your IBKR connection needs attention",
                message: problem.message,
                buttonTitle: "Fix"
            ) { store.setupRequest = problem.fix == .queryId ? .queryId : .token }
        } else if let message = store.errorMessage {
            Banner(
                icon: "wifi.exclamationmark",
                tint: .secondary,
                title: store.account == nil ? "Couldn't load your account" : "Couldn't update",
                message: message + (store.account == nil ? "" : " Showing the last saved report."),
                buttonTitle: "Try again"
            ) { Task { await store.refresh() } }
        } else if let message = store.historyError {
            Banner(
                icon: "clock.arrow.circlepath",
                tint: .secondary,
                title: "Couldn't get your older history",
                message: message + " Showing the years that did arrive.",
                buttonTitle: "Try again"
            ) { Task { await store.loadHistory() } }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch store.selection {
        case .stock(let symbol):
            StockView(symbol: symbol)
                .id(symbol)
        default:
            if store.summary != nil {
                AccountView()
            } else if store.errorMessage == nil && store.connectionProblem == nil {
                ProgressView("Loading your account… the first download from IBKR takes about 30 seconds.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                    Text("Updating… (~30s)").foregroundStyle(.secondary)
                } else if let year = store.historyYear {
                    ProgressView().controlSize(.small)
                    Text("Getting older history: \(String(year))…").foregroundStyle(.secondary)
                        .help("IBKR sends one year at a time. This only happens once.")
                } else if let date = store.account?.fetchedDate {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Text("Updated \(Fmt.timeAgo(date, now: ctx.date))").foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                }
                .help("Download a fresh report from IBKR (⌘R)")
                .disabled(store.isRefreshing)
            }
        }
    }
}

extension SetupStep: Identifiable {
    var id: Self { self }
}

/// A strip across the top of the window for problems that need a click.
struct Banner: View {
    var icon: String
    var tint: Color
    var title: String
    var message: String
    var buttonTitle: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .controlSize(.large)
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
