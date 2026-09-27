import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when started with `swift run` (outside an .app bundle), so the
        // window comes to the front and the app shows in the Dock
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DevHooks.snapshotIfAsked()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PortfolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()

    var body: some Scene {
        Window("Portfolio", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Account") {
                Button("Update from IBKR") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(!store.isConnected || store.isRefreshing)
                Button("Update prices only") { Task { await store.refreshPrices() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.account == nil)
                Button("Download older history again") { Task { await store.reloadHistory() } }
                    .disabled(!store.isConnected || store.historyYear != nil)
                Divider()
                Button("Reconnect IBKR…") { store.setupRequest = .welcome }
                    .disabled(!store.isConnected)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
