import AppKit
import PortfolioCore
import SwiftUI

// The step-by-step guide for connecting an IBKR account. Written for someone
// who has never heard of a "Flex Query": one small job per screen, IBKR's own
// button names in bold so they can be matched on screen, and a real test
// download at the end. Nothing is saved until that test works.

enum SetupStep: Int, CaseIterable, Comparable {
    case welcome, login, createReport, queryId, token, test, done

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Steps 1–5 get a "Step n of 5" counter; welcome and done don't.
    var number: Int? { (1...5).contains(rawValue) ? rawValue : nil }
}

private let ibkrLogin = URL(string: "https://www.interactivebrokers.com/sso/Login")!

private func openIBKR() { NSWorkspace.shared.open(ibkrLogin) }

private func pasteboardText() -> String {
    NSPasteboard.general.string(forType: .string) ?? ""
}

/// Removes spaces, line breaks and stray punctuation people pick up when copying.
private func cleaned(_ s: String) -> String {
    s.filter { $0.isLetter || $0.isNumber }
}

@MainActor
struct SetupGuide: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var startAt: SetupStep
    /// true when reconnecting from inside the app (can be cancelled)
    var isSheet: Bool

    @State private var step: SetupStep = .welcome
    @State private var queryId = CredentialStore.load()?.queryId ?? ""
    @State private var token = ""
    @State private var reportChecks: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .onAppear { step = startAt }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            if let n = step.number {
                Text("Step \(n) of 5").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                ProgressView(value: Double(n), total: 5).frame(width: 160)
            } else {
                Text("Connect your IBKR account").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if isSheet {
                Button("Cancel") { store.setupRequest = nil; dismiss() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var footer: some View {
        if step != .test && step != .done {
            HStack {
                if step > .welcome {
                    Button("Back") { go(-1) }.controlSize(.large)
                }
                Spacer()
                if let hint = blockedHint {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
                Button(step == .welcome ? "Let's start" : step == .token ? "Test the connection" : "Continue") { go(1) }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(blockedHint != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    /// Why Continue is greyed out (nil = it isn't)
    private var blockedHint: String? {
        switch step {
        case .createReport where !ReportChecklist.required.isSubset(of: reportChecks):
            return "Tick each box as you do it"
        case .queryId where QueryIdField.problem(queryId) != nil: return " "
        case .token where TokenField.problem(token) != nil: return " "
        default: return nil
        }
    }

    private func go(_ delta: Int) {
        if let next = SetupStep(rawValue: step.rawValue + delta) { step = next }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .login: login
        case .createReport: ReportChecklist(checked: $reportChecks)
        case .queryId: QueryIdField(queryId: $queryId)
        case .token: TokenField(token: $token)
        case .test:
            ConnectionTest(credentials: Credentials(token: cleaned(token), queryId: cleaned(queryId))) { fix in
                step = fix
            } onSuccess: { creds, report in
                try await store.connected(creds, report: report)
                step = .done
            }
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "briefcase.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Let's connect your Interactive Brokers account").font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 10) {
                Label("See what you own, what it's worth, and how much you've gained or lost.", systemImage: "list.bullet.rectangle")
                Label("**Read-only.** This app can only download reports. It can never buy, sell or move money.", systemImage: "lock.shield")
                Label("It **never sees your IBKR password.** You'll give it two numbers that only unlock the report.", systemImage: "key")
                Label("Takes about **10 minutes**, one time only. We'll go one small step at a time.", systemImage: "clock")
            }
            .font(.body)
            Text("You'll switch between this window and the IBKR website in your browser. Keep both open side by side if you can.")
                .foregroundStyle(.secondary)
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Log in to IBKR").font(.largeTitle.weight(.bold))
            Text("Click the button to open the Interactive Brokers website in your browser, and log in the way you normally do.")
            Button {
                openIBKR()
            } label: {
                Label("Open the IBKR website", systemImage: "safari")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Text("Logged in? Come back to this window and click **Continue**.")
                .foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            Text("You're connected").font(.largeTitle.weight(.bold))
            Text("The app downloads a fresh report from IBKR by itself every few hours. Prices update every few minutes while the app is open.")
            Text("Your IBKR details are saved on this Mac, locked by its security chip. If the connection ever stops working, the app will tell you and bring you straight back to the right step.")
                .foregroundStyle(.secondary)
            Button("Open my dashboard") {
                store.finishSetup()
                if isSheet { dismiss() }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Step 2: create the report

private struct ReportChecklist: View {
    @Binding var checked: Set<Int>

    struct Item {
        var text: LocalizedStringKey
        var help: String?
        var optional = false
        var copy: String?
    }

    static let items: [Item] = [
        Item(text: "In the menu at the top, open **Performance & Reports**, then click **Flex Queries**.",
             help: "On some screens the menu is behind the ☰ icon, top left. It may also be called **Reporting**."),
        Item(text: "Find **Activity Flex Query** and click the **+** button next to it.",
             help: "There are two lists — pick the one called Activity, not Trade Confirmation."),
        Item(text: "In **Query Name**, type `stock-overview`.",
             help: "Any name works — this one just makes it easy to spot later.", copy: "stock-overview"),
        Item(text: "Under **Sections**, click **Open Positions**. In the window that opens, tick **Select All**, then click **Save**.",
             help: "This is the list of stocks you own."),
        Item(text: "Do the same for **Trades**: click it, tick **Select All**, **Save**.",
             help: "Your buys and sells."),
        Item(text: "Do the same for **Cash Report**.",
             help: "How much cash is in the account."),
        Item(text: "Do the same for **Cash Transactions**.",
             help: "This is where your dividends and dividend tax appear."),
        Item(text: "Recommended: do the same for **Account Information**.",
             help: "Lets the app know which currency your account uses.", optional: true),
        Item(text: "Under **Delivery Configuration**, set **Format** to **XML** and **Period** to **Last 365 Calendar Days**."),
        Item(text: "Under **General Configuration**, set **Date Format** to **yyyy-MM-dd**.",
             help: "If you can't find it, leave it — the app understands IBKR's usual date formats."),
        Item(text: "Click **Continue** at the bottom, then **Create** (or **Save**) on the next page."),
    ]

    static var required: Set<Int> {
        Set(items.indices.filter { !items[$0].optional })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create the report").font(.largeTitle.weight(.bold))
            Text("IBKR calls this a **Flex Query**: a report that lists what's in your account. You set it up once, then the app downloads it whenever it needs to. Tick each box as you do it.")
            Button { openIBKR() } label: { Label("Open the IBKR website", systemImage: "safari") }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { checked.contains(i) },
                            set: { on in if on { checked.insert(i) } else { checked.remove(i) } }
                        )) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text)
                                .strikethrough(checked.contains(i), color: .secondary)
                                .foregroundStyle(checked.contains(i) ? .secondary : .primary)
                            if let help = item.help {
                                Text(LocalizedStringKey(help)).font(.caption).foregroundStyle(.secondary)
                            }
                            if let copy = item.copy {
                                CopyButton(text: copy)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct CopyButton: View {
    var text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        } label: {
            Label(copied ? "Copied" : "Copy “\(text)”", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .controlSize(.small)
    }
}

// MARK: - Step 3: Query ID

private struct QueryIdField: View {
    @Binding var queryId: String

    static func problem(_ s: String) -> String? {
        let c = cleaned(s)
        if c.isEmpty { return "" }
        if !c.allSatisfy(\.isNumber) { return "The Query ID is only numbers — it looks like something else was pasted." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copy the Query ID").font(.largeTitle.weight(.bold))
            Text("Back on the **Flex Queries** page, find the report you just made (**stock-overview**) in the **Activity Flex Query** list.")
            Text("Next to its name is a number — that's the **Query ID**. Select it, copy it (**⌘C**), and paste it here.")
            Text("Can't see a number? Click the **ⓘ** (info) icon next to your report; the Query ID is shown at the top.")
                .font(.callout).foregroundStyle(.secondary)
            PasteField(title: "Query ID", placeholder: "e.g. 123456", text: $queryId, problem: Self.problem(queryId))
        }
    }
}

// MARK: - Step 4: token

private struct TokenField: View {
    @Binding var token: String
    @State private var showNoPanel = false

    static func problem(_ s: String) -> String? {
        let c = cleaned(s)
        if c.isEmpty { return "" }
        if c.count < 10 { return "That's shorter than a token usually is. Check that you copied the whole thing." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Turn on downloads and copy the token").font(.largeTitle.weight(.bold))
            Text("The token is like a key that only opens your report. It can't be used to trade or log in.")
            VStack(alignment: .leading, spacing: 10) {
                Text("1. On the same **Flex Queries** page, find the box called **Flex Web Service Configuration** (usually on the right).")
                Text("2. Click the **gear icon** ⚙︎ in that box.")
                Text("3. Switch it **on** (tick **Flex Web Service Status**) and click **Save**.")
                Text("4. A **Current Token** appears — a long number. Copy it and paste it below.")
            }
            Label("Tip: if IBKR lets you choose when the token expires, pick the longest option (up to a year). When it runs out, the app will walk you through making a new one.",
                  systemImage: "lightbulb")
                .font(.callout).foregroundStyle(.secondary)
            PasteField(title: "Token", placeholder: "a long number", text: $token, problem: Self.problem(token))

            DisclosureGroup("I don't see a Flex Web Service Configuration box", isExpanded: $showNoPanel) {
                Text("Some accounts are managed by an adviser or linked to a main account, and only the main account holder can see this box. Ask your broker (or IBKR support) to switch on **Flex Web Service** access for your user, then come back to this step.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

/// A text field with a big Paste button and a plain-language warning.
private struct PasteField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            HStack {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospacedDigit())
                Button {
                    text = cleaned(pasteboardText())
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .controlSize(.large)
            }
            if let problem, !problem.isEmpty {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            } else if problem == nil {
                Label("Looks right", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.green)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Step 5: test

private struct ConnectionTest: View {
    var credentials: Credentials
    var goTo: (SetupStep) -> Void
    var onSuccess: (Credentials, AccountData) async throws -> Void

    private enum Phase {
        case running
        case failed(FlexError)
        case checked(FlexStatement)
    }

    @State private var phase: Phase = .running
    @State private var attempt = 0

    private struct SectionCheck {
        var key: String
        var name: String
        var why: String
        var optional = false
    }

    private static let sections: [SectionCheck] = [
        SectionCheck(key: "OpenPositions", name: "Open Positions", why: "the stocks you own"),
        SectionCheck(key: "Trades", name: "Trades", why: "your buys and sells"),
        SectionCheck(key: "CashReport", name: "Cash Report", why: "the cash in your account"),
        SectionCheck(key: "CashTransactions", name: "Cash Transactions", why: "your dividends"),
        SectionCheck(key: "AccountInformation", name: "Account Information", why: "your account's currency", optional: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Testing the connection").font(.largeTitle.weight(.bold))
            switch phase {
            case .running:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Asking IBKR for your report… this usually takes 10–30 seconds.")
                }
            case .failed(let error):
                failed(error)
            case .checked(let stmt):
                results(stmt)
            }
        }
        .task(id: attempt) { await run() }
    }

    private func run() async {
        phase = .running
        do {
            phase = .checked(try await fetchFlexStatement(token: credentials.token, queryId: credentials.queryId))
        } catch let e as FlexError {
            phase = .failed(e)
        } catch {
            phase = .failed(FlexError(message: error.localizedDescription))
        }
    }

    private func failed(_ error: FlexError) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("It didn't work yet", systemImage: "xmark.octagon.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(.red)
            Text(error.message)
            HStack {
                switch error.fix {
                case .token:
                    Button("Go back to the token step") { goTo(.token) }.buttonStyle(.borderedProminent)
                case .queryId:
                    Button("Go back to the Query ID step") { goTo(.queryId) }.buttonStyle(.borderedProminent)
                case nil:
                    EmptyView()
                }
                Button("Try again") { attempt += 1 }
                Button("Open the IBKR website") { openIBKR() }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func results(_ stmt: FlexStatement) -> some View {
        let missing = Self.sections.filter { !$0.optional && !stmt.sections.contains($0.key) }
        let data = accountData(from: stmt)
        let counts = [
            "OpenPositions": "\(data.positions.count) found",
            "Trades": "\(data.trades.count) found",
            "CashTransactions": "\(data.dividends.count) dividend payments",
        ]

        VStack(alignment: .leading, spacing: 14) {
            Label("Connected to IBKR", systemImage: "checkmark.circle.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.sections, id: \.key) { s in
                    let ok = stmt.sections.contains(s.key)
                    HStack(alignment: .top) {
                        Image(systemName: ok ? "checkmark.circle.fill" : s.optional ? "minus.circle" : "xmark.circle.fill")
                            .foregroundStyle(ok ? .green : s.optional ? .secondary : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey("**\(s.name)** — \(s.why)" + (ok ? counts[s.key].map { " · \($0)" } ?? "" : "")))
                            if !ok {
                                Text(LocalizedStringKey(s.optional
                                     ? "Optional. Without it the app assumes US dollars."
                                     : "Missing. On IBKR, edit your **stock-overview** report, click **\(s.name)** under Sections, tick **Select All**, and save."))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

            if let short = shortPeriodWarning(stmt) {
                Label { Text(LocalizedStringKey(short)) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(.orange)
            }

            if missing.isEmpty {
                Button("Finish") {
                    Task {
                        do { try await onSuccess(credentials, data) } catch {
                            phase = .failed(FlexError(message: error.localizedDescription))
                        }
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Fix the \(missing.count == 1 ? "item" : "items") marked ✗ on the IBKR website, then check again. (IBKR sometimes takes a minute to use the changed report.)")
                HStack {
                    Button("Open the IBKR website") { openIBKR() }
                    Button("Check again") { attempt += 1 }.buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
        }
    }

    /// The report should cover about a year; warn if it's much shorter.
    private func shortPeriodWarning(_ stmt: FlexStatement) -> String? {
        guard let from = Fmt.day(flexDate(stmt.fromDate)), let to = Fmt.day(flexDate(stmt.toDate)) else { return nil }
        let days = to.timeIntervalSince(from) / 86_400
        guard days < 300 else { return nil }
        return "Your report only covers \(Int(days.rounded()) + 1) days, so older trades and dividends won't show. To fix it, edit the report on IBKR and set **Period** to **Last 365 Calendar Days**."
    }

}
