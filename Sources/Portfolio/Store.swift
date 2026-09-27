import Foundation
import Observation
import PortfolioCore

enum SidebarItem: Hashable {
    case account
    case stock(String)
}

/// What the small coloured pill in each sidebar row shows (clicking a pill
/// switches between them, like Apple's Stocks app).
enum PillMode: String, CaseIterable {
    case today, gainPercent, gainAmount

    var next: PillMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// All the state the windows show. Loads the saved report instantly, then
/// refreshes from IBKR in the background when it's more than 6 hours old.
@Observable @MainActor
final class AppStore {
    var account: AccountData?
    var positions: [EnrichedPosition] = []
    var summary: Summary?
    var isRefreshing = false
    /// A general problem (no internet, IBKR busy…), shown with "Try again"
    var errorMessage: String?
    /// A problem with the token or Query ID — the setup guide can fix it
    var connectionProblem: FlexError?
    /// (Made-up screen-check data never touches the real IBKR details.)
    var isConnected = DevHooks.fixture == nil && CredentialStore.load() != nil
    /// Set to open the setup guide as a sheet (for reconnecting)
    var setupRequest: SetupStep?
    var selection: SidebarItem? = .account

    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        await DevHooks.apply(to: self)
        await loadCachedThenRefresh()
    }

    private func loadCachedThenRefresh() async {
        guard isConnected else { return }
        if let cached = await Portfolio.shared.cachedData() {
            await show(cached)
            if AccountCache.isStale(cached) { await refresh() }
        } else {
            await refresh()
        }
    }

    func refresh() async {
        guard isConnected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let data = try await Portfolio.shared.refresh()
            errorMessage = nil
            connectionProblem = nil
            await show(data)
        } catch let error as FlexError where error.fix != nil {
            connectionProblem = error
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-read today's prices without asking IBKR for a new report.
    func refreshPrices() async {
        guard let account else { return }
        await show(account)
    }

    private func show(_ data: AccountData) async {
        let enriched = await enrichPositions(data.positions)
        account = data
        positions = enriched.sorted { $0.currentValue > $1.currentValue }
        summary = makeSummary(data, positions: enriched)
    }

    /// Called by the setup guide once its test download worked. The window
    /// switches to the dashboard only in finishSetup(), so the guide can show
    /// its last screen first.
    func connected(_ creds: Credentials, report: AccountData) async throws {
        try CredentialStore.save(creds)
        await Portfolio.shared.adopt(report)
        connectionProblem = nil
        errorMessage = nil
        await show(report)
    }

    func finishSetup() {
        isConnected = CredentialStore.load() != nil
        setupRequest = nil
    }

    func disconnect() async {
        CredentialStore.clear()
        await Portfolio.shared.reset()
        isConnected = false
        account = nil
        positions = []
        summary = nil
        connectionProblem = nil
        errorMessage = nil
        selection = .account
    }

    func position(_ symbol: String) -> EnrichedPosition? {
        positions.first { $0.symbol == symbol }
    }

    func trades(for symbol: String) -> [Trade] {
        account?.trades.filter { $0.symbol == symbol } ?? []
    }

    func dividends(for symbol: String) -> [Dividend] {
        account?.dividends.filter { $0.symbol == symbol } ?? []
    }
}
