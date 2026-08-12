# My Stocks — personal IBKR dashboard

A small web app that shows your Interactive Brokers account in plain language: what you own, what it's worth, how much you've gained or lost, dividends you received, and your trade history. It runs on your own computer; other devices on your home network can open it in a browser.

- **Read-only** — the app can only *download reports* from IBKR. It can never trade or move money.
- **Report page** (`/`) — the whole account at a glance.
- **Stock page** — click any stock for its chart, your trades, and its dividends.
- Account data comes from IBKR report snapshots (updated by IBKR a few times a day); current prices and charts come from Yahoo Finance to stay near-live.

## 1. Connect your IBKR account (one time, ~10 minutes)

The app never gets your IBKR password. Instead, IBKR lets you define a **report** (called a "Flex Query") and an **access token**; the app uses those two values to download your data.

### a. Create the report definition ("Flex Query")

1. Log in at [interactivebrokers.com](https://www.interactivebrokers.com) → **Performance & Reports → Flex Queries**.
2. Next to *Activity Flex Query*, click **+** (create new). Name it e.g. `stock-overview`.
3. In **Sections**, enable these four (inside each, tick **all fields** — extra fields are harmless):
   - **Open Positions**
   - **Trades**
   - **Cash Report**
   - **Cash Transactions**  ← this is where dividends and dividend tax appear
   - *(optional but recommended)* **Account Information** — lets the app know your account's base currency
4. In **Delivery Configuration**: Period = **Last 365 Calendar Days**, Format = **XML**, Date format = **yyyy-MM-dd**.
5. Save. Back in the list, note the **Query ID** number shown next to your new query.

### b. Turn on report downloads ("Flex Web Service") and get a token

This is on the **same page** where you created the Flex Query:

1. Go to **Performance & Reports → Flex Queries** (or Menu → Reporting → Flex Queries).
2. Find the **Flex Web Service Configuration** panel on that page (usually on the right side) and click its **gear icon**.
3. Click the toggle to **enable** the Flex Web Service — a **token** appears; copy it (a long number).
4. Optional: click **Generate A New Token** to set a longer expiry (up to a year). When it expires, generate a new one and update the config below.

> If you don't see the Flex Web Service Configuration panel at all, your account may be part of a managed/linked structure where only the main account holder can see the token — in that case contact your broker (or IBKR support) and ask them to enable "Flex Web Service" access for your user.

### c. Give both values to the app

```bash
cp server/.env.example server/.env
```

Edit `server/.env` and fill in:

```
FLEX_TOKEN=your-token-here
FLEX_QUERY_ID=your-query-id-here
```

This file stays on your machine and is ignored by git.

### d. Test the connection

```bash
npm run test-flex
```

You should see `✓ Connected!` with counts of your positions, trades, and cash rows. If something's off, the script tells you which report section is missing.

## 2. Run the app

First time only:

```bash
npm install
```

(Node.js 22+ is recommended; on Node 20 the price library prints a harmless version warning.)

**Everyday use** (one command, then open the printed address):

```bash
npm run build
npm start
```

Open [http://localhost:3000](http://localhost:3000). The startup log also prints an address like `http://192.168.x.x:3000` — open that from your phone or any other device on the same network.

**Development** (auto-reloads when you edit code):

```bash
npm run dev
```

Open [http://localhost:5173](http://localhost:5173) (the frontend proxies API calls to the server on port 3000).

## How it works

```
client/  React + Vite frontend — report page and per-stock pages
server/  Node.js (Express) backend
  src/flex.ts          downloads & parses the IBKR Flex report
  src/providers/       data-provider interface; flexProvider is the v1 source.
                       A future live provider (TWS / IB Gateway API) plugs in here.
  src/prices.ts        near-live prices, charts & company info from Yahoo Finance
  src/cache.ts         keeps the last report on disk; auto-refreshes after 6 hours
  src/routes.ts        the /api/* endpoints
```

Notes & limitations:

- The IBKR report covers the **last 365 days**, so trade and dividend history goes back at most a year.
- "Reinvested?" on dividends is a best-effort guess (a buy of the same stock shortly after the payment for roughly the same amount).
- Account totals assume a single base currency; mixed-currency accounts will show slightly off totals.
- If Yahoo doesn't recognize a symbol (common for non-US listings), the app falls back to the price from the last IBKR report and skips the chart.
