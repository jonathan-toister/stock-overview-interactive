import AppKit
import PortfolioCore
import SwiftUI

/// Portfolio → Settings… (⌘,)
@MainActor
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section("IBKR connection") {
                if store.isConnected {
                    LabeledContent("Status") {
                        Label(store.connectionProblem == nil ? "Connected" : "Needs attention",
                              systemImage: store.connectionProblem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(store.connectionProblem == nil ? .green : .orange)
                    }
                    LabeledContent("Query ID", value: CredentialStore.load()?.queryId ?? "–")
                    if let date = store.account?.fetchedDate {
                        LabeledContent("Last report", value: Fmt.timeAgo(date))
                    }
                    HStack {
                        Button("Reconnect IBKR…") { store.setupRequest = .welcome }
                        Spacer()
                        if confirmDisconnect {
                            Text("Remove your IBKR details and saved data?").foregroundStyle(.secondary)
                            Button("Cancel") { confirmDisconnect = false }
                            Button("Disconnect", role: .destructive) {
                                confirmDisconnect = false
                                Task { await store.disconnect() }
                            }
                        } else {
                            Button("Disconnect…") { confirmDisconnect = true }
                        }
                    }
                } else {
                    Text("Not connected. The setup guide is in the main window.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Your data") {
                Text("The token and Query ID are saved in a file on this Mac, locked with a key held by your Mac's security chip, so the file can't be opened on any other computer. The last downloaded report is saved on this Mac so the app opens instantly; it refreshes from IBKR when it's more than 6 hours old.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show saved data in Finder") {
                    try? FileManager.default.createDirectory(at: AccountCache.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AccountCache.directory)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
