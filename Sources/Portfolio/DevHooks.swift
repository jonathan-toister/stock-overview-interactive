import AppKit
import PortfolioCore
import SwiftUI

// Developer-only switches, read from environment variables, for checking the
// screens with made-up data instead of a real account. None of them are set
// when the app is opened normally.
//
//   PORTFOLIO_FIXTURE=path.xml   use this saved Flex report instead of IBKR
//   PORTFOLIO_SETUP=3            open the setup guide at this step (0–6)
//   PORTFOLIO_SELECT=AAPL        open this stock's page
//   PORTFOLIO_SNAPSHOT=dir       save pictures of the window into dir, then quit
enum DevHooks {
    static let env = ProcessInfo.processInfo.environment

    static var fixture: URL? { env["PORTFOLIO_FIXTURE"].map { URL(fileURLWithPath: $0) } }
    static var setupStep: SetupStep? { env["PORTFOLIO_SETUP"].flatMap(Int.init).flatMap(SetupStep.init) }
    static var select: String? { env["PORTFOLIO_SELECT"] }

    @MainActor
    static func apply(to store: AppStore) async {
        if let fixture {
            let data = (try? parseFlexFile(fixture)).map { accountData(from: $0) }
            await Portfolio.shared.setCredentialsSource { Credentials(token: "fixture", queryId: "0") }
            await Portfolio.shared.useFixture(data)
            store.isConnected = setupStep == nil
        }
        if let symbol = select { store.selection = .stock(symbol) }
    }

    @MainActor
    static func snapshotIfAsked() {
        guard let dir = env["PORTFOLIO_SNAPSHOT"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = env["PORTFOLIO_SNAPSHOT_NAME"] ?? "snapshot"
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            exit(0)
        }
    }
}
