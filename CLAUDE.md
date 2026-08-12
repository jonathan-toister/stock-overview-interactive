# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal, read-only dashboard for the user's Interactive Brokers (IBKR) account: React frontend + Express backend, run locally and viewed from any device on the home network. Account data comes from IBKR Flex Query report snapshots; near-live prices/charts/company info come from Yahoo Finance.

## Commands

npm workspaces monorepo (`server/`, `client/`). Run from the repo root:

- `npm run dev` — server (tsx watch, port 3000) + client (Vite, port 5173) concurrently; Vite proxies `/api` to 3000
- `npm run build` — `tsc` for server, `tsc -b && vite build` for client
- `npm start` — production: `node server/dist/index.js`, which also serves `client/dist` so one port (3000) serves everything
- `npm run test-flex` — verifies IBKR connectivity and that the Flex Query has the required sections (`server/scripts/test-flex.ts`)
- `npm run lint -w client` — oxlint (client only)

There is no test suite.

The server needs `server/.env` with `FLEX_TOKEN` and `FLEX_QUERY_ID` (copy from `server/.env.example`); without them, `/api/*` returns 503 with a setup message. `.env` and `server/cache/` contain personal account data — never commit or print their contents.

## Architecture

Data flow: IBKR Flex Web Service → `flex.ts` (download/parse XML) → `flexProvider.ts` (normalize to app types) → disk + memory cache → `routes.ts` (enrich with Yahoo quotes) → React client.

- `server/src/flex.ts` — two-step Flex download (SendRequest → poll GetStatement with backoff; error code 1019 means "still generating"). Returns raw parsed XML.
- `server/src/providers/types.ts` — the app's data shapes (`Position`, `Trade`, `Dividend`, `AccountData`) and the `AccountDataProvider` interface. **This interface is the seam for a future live TWS/IB Gateway provider** — new data sources implement `getAccountData()`; routes and UI stay unchanged.
- `server/src/providers/flexProvider.ts` — converts raw Flex XML into app types. Handles IBKR quirks: multiple date formats, summary vs. detail row levels (`oneLevel`), matching withholding-tax rows to dividend payments by symbol + date proximity, best-effort reinvestment detection (a BUY of the same symbol within 7 days for ~the net amount).
- `server/src/cache.ts` + `routes.ts` — the Flex report is slow and only updates a few times a day, so the last download is kept in `server/cache/account.json` and in memory. Stale data (>6h) is served immediately while a background refresh runs; `POST /api/refresh` forces one. `inFlight` dedupes concurrent refreshes.
- `server/src/prices.ts` — Yahoo Finance wrapper with per-key TTL memoization (quotes 5 min, history 1 h, company info 24 h). All functions return `null` on any failure; callers fall back to the IBKR snapshot price (`priceIsLive: false`).
- `client/src/` — two pages (`ReportPage` at `/`, `StockPage` at `/stock/:symbol`) via react-router; `api.ts` fetches, `types.ts` mirrors the server's enriched response shapes.

The server is ESM (`"type": "module"`): relative imports use `.js` extensions even in `.ts` files.

## Conventions

- Visual language ("set like arithmetic", user-approved after several design rounds): warm paper ground, serif numerals (system Charter/Iowan stack, no webfonts), and every gain/loss rendered as a subtraction — worth now − you paid = gain, result under a drawn double sum-rule — via `client/src/components/SumBlock.tsx`. **No charts or graphs anywhere** — the user explicitly rejected them; don't reintroduce recharts or sparklines.
- All user-facing text (UI labels, error messages, README) uses plain language, not finance jargon — e.g. "what you paid" / "gain or loss", never "cost basis" / "P&L" / "realized/unrealized". Code comments explain financial fields in plain terms too (see `providers/types.ts`).
- Money amounts are in each position's own currency; account totals assume a single base currency.
- Route handlers are wrapped so thrown errors become JSON (`wrap` in `routes.ts`): 503 for missing IBKR setup, 502 for upstream failures.
