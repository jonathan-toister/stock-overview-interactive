# Portfolio — personal IBKR app for the Mac

A small Mac app that shows your Interactive Brokers account in plain language: what you own, what it's worth, how much you've gained or lost, dividends you received, and your trade history.

- **Read-only.** The app can only *download reports* from IBKR. It can never trade or move money, and it never sees your IBKR password.
- **Account page:** the whole account at a glance.
- **Stock pages:** click any stock in the sidebar for your shares, a short list of key numbers (each with a plain explanation), your trades and its dividends.
- Account data comes from IBKR reports (IBKR updates them a few times a day). Today's prices come from Yahoo Finance, so values stay close to live.

## Install

You need the Xcode Command Line Tools (install them with `xcode-select --install`). Then, from this folder:

```bash
scripts/build-app.sh --install     # builds Portfolio.app and moves it into /Applications
```

(Without `--install` it only builds `build/Portfolio.app`.)

**First launch:** because the app isn't from the App Store, macOS may say it can't check it. Right-click **Portfolio** in Applications → **Open** → **Open**. You only need to do this once.

## Connect your IBKR account (one time, ~10 minutes)

The app walks you through this step by step. In short: on the IBKR website you create a **report** (IBKR calls it a "Flex Query") and turn on an **access token**, then paste the report's Query ID and the token into the app. The app does a test download before saving anything, and if the token ever expires it tells you and takes you back to the right step.

If you don't see IBKR's **Flex Web Service Configuration** panel at all, your account may be part of a managed or linked structure where only the main account holder can see the token. In that case ask your broker (or IBKR support) to turn on "Flex Web Service" access for your user.

**Where things are kept:** everything is in `~/Library/Application Support/Portfolio/`: the last downloaded report, and the token and Query ID in a file locked with a key held by your Mac's security chip (so it can't be opened on any other computer). **Portfolio → Settings…** can show that folder or disconnect the account.

## For development

```bash
swift build                                                  # debug build
swift run portfolio-check --file Fixtures/sample-flex.xml    # what the app makes of a made-up report
swift run portfolio-check --yahoo AAPL                       # what Yahoo returns for one stock
swift run portfolio-check                                    # test download from IBKR (prints counts, never amounts)
```

```
Sources/PortfolioCore/     downloads and reads the IBKR report, fetches Yahoo prices,
                           keeps the last report on disk (refreshed after 6 hours)
Sources/Portfolio/         the app's windows and the IBKR setup guide
Sources/portfolio-check/   the command-line checks above
Fixtures/sample-flex.xml   a made-up IBKR report for trying things without an account
scripts/                   app bundle build script and icon generator
```

## Notes & limitations

- The IBKR report covers the **last 365 days**, so trade and dividend history goes back at most a year.
- "Reinvested?" on dividends is a best guess: a buy of the same stock shortly after the payment, for roughly the same amount.
- Account totals assume all your money is in one currency. Accounts that hold several currencies will show slightly wrong totals.
- If Yahoo doesn't recognise a symbol (common for stocks listed outside the US), the app uses the price from the last IBKR report instead.
