# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal, read-only native Mac app (Swift/SwiftUI, no server) for the user's Interactive Brokers (IBKR) account. Account data comes from IBKR Flex Query report snapshots; near-live prices and company info come from Yahoo Finance. (There used to be a React + Express web version; it was removed in September 2026 and lives on only in git history.)

## Commands

A Swift package at the repo root. Only the Command Line Tools are installed (no Xcode), Swift 5.10 / macOS 14 SDK.

- `scripts/build-app.sh` — release build wrapped into `build/Portfolio.app`, ad-hoc signed with a fixed designated requirement (`identifier "local.portfolio.ibkr"`) so macOS treats every build as the same app (plain ad-hoc identifies it by one build's hash); `--install` moves (not copies) it to /Applications, since a second copy shows up as a duplicate app
- `swift build` — debug build
- `swift scripts/make-icon.swift` — redraws `Resources/AppIcon.icns` (the icon is drawn in code; `Resources/Info.plist` is the bundle's plist, copied in by `build-app.sh`)
- `swift run portfolio-check --file Fixtures/sample-flex.xml` — prints what the parser makes of the made-up report; `--yahoo SYM` shows Yahoo data; no flag does a real IBKR download with the saved credentials and prints counts only (never amounts)
- Screens can be checked without a real account: `PORTFOLIO_FIXTURE=<xml> PORTFOLIO_SELECT=AAPL PORTFOLIO_SETUP=<step> PORTFOLIO_SNAPSHOT=<dir> .build/debug/Portfolio` writes a PNG of the window (see `Sources/Portfolio/DevHooks.swift`). The terminal has no screen-recording permission, so `screencapture` doesn't work.

There is no test suite.

The IBKR token and Query ID live in `~/Library/Application Support/Portfolio/credentials.sealed`, and the cached report in `account.json` next to it. Both are personal account data — never commit or print their contents.

## Architecture

Data flow: IBKR Flex Web Service → `FlexClient` (download) → `FlexParser` (XML → app types) → `Portfolio` (memory + disk cache) → `enrichPositions` (Yahoo quotes) → `AppStore` → SwiftUI views.

- `Sources/PortfolioCore/FlexClient.swift` — two-step Flex download (SendRequest → poll GetStatement with backoff; error code 1019 means "still generating"), plus IBKR error codes → plain messages and which setup step fixes them.
- `Sources/PortfolioCore/FlexParser.swift` — converts Flex XML into app types. Handles IBKR quirks: multiple date formats, summary vs. detail row levels (`oneLevel`), matching withholding-tax rows to dividend payments by symbol + date proximity, best-effort reinvestment detection (a BUY of the same symbol within 7 days for ~the net amount).
- `Sources/PortfolioCore/Models.swift` — the app's data shapes (`Position`, `Trade`, `Dividend`, `AccountData`); also the layout of the cached `account.json`.
- `Sources/PortfolioCore/Portfolio.swift` + `AccountCache.swift` — the Flex report is slow and only updates a few times a day, so the last download is kept on disk and in memory. Stale data (>6h) is shown immediately while a background refresh runs; `inFlight` dedupes concurrent refreshes. `makeSummary` computes the account totals. A future live TWS/IB Gateway data source would replace the download in `Portfolio.refresh()`.
- `Sources/PortfolioCore/HistoryCache.swift` — IBKR caps a report at 365 days, so `Portfolio.backfillHistory()` downloads the years before the regular report one at a time (`fd`/`td` on SendRequest), stopping after two empty years, and keeps them in `history.json`. Each regular refresh moves the days that just left the 365-day window into the history (`carryOver`), and `withHistory` joins the two by date, so nothing is duplicated or lost.
- `Sources/PortfolioCore/YahooClient.swift` — calls Yahoo's endpoints directly (cookie + crumb handshake) with per-key TTL memoization (quotes 5 min, company info 24 h). Returns `nil` on any failure; callers fall back to the IBKR snapshot price (`priceIsLive: false`).
- `Sources/PortfolioCore/Credentials.swift` — `CredentialStore` keeps the token and Query ID in `credentials.sealed`, encrypted with a key held by the Secure Enclave (CryptoKit, no entitlements needed): no Keychain, no password prompts, and the file is useless on another Mac. Read once per launch. Earlier versions used the Keychain; the user asked that the app never read or write it again, so don't reintroduce it (for credentials or anything else).
- `Sources/Portfolio/` — SwiftUI app. `Store.swift` holds state; `Views/SetupGuide.swift` is the step-by-step IBKR onboarding, written for someone who has never heard of a Flex Query (credentials are saved only after a test download passes, and missing report sections are flagged there).

## Conventions

- Look: Apple Stocks style, chosen by the user (sidebar of positions with coloured change pills, system font, native controls, automatic dark mode). **No charts or graphs anywhere.** The user explicitly rejected them; don't add charts or sparklines.
- All user-facing sentences (explanations, error messages, README, setup guide) use plain language, not finance jargon: e.g. "what you paid" / "gain or loss", never "cost basis" / "P&L" / "realized/unrealized". Code comments explain financial fields in plain terms too (see `Models.swift`).
- **Exception, and the one place jargon belongs:** each measure in the key-numbers panel (`Sources/Portfolio/Views/KeyNumbersView.swift`) is labelled with its *standard* name ("P/E ratio", "Beta", "Expense ratio") with the plain explanation in the line beneath. Invented plain labels ("How jumpy it is") were tried and rejected: a real name is something the user can look up and will meet on IBKR, and the sentence underneath is what carries the meaning. So: real name as the label, plain English everywhere else.
- The key-numbers panel is deliberately short: 8 measures for a company, 6 for a fund. The app exists so the user never has to open Yahoo Finance, which they find overwhelming; a new measure has to displace an existing one rather than be added alongside it.
- Money amounts are in each position's own currency; account totals assume a single base currency.
