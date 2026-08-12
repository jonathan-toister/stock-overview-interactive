import { Router } from 'express';
import { createFlexProvider } from './providers/flexProvider.js';
import type { AccountData, Position } from './providers/types.js';
import { isStale, loadAccountCache, saveAccountCache } from './cache.js';
import { getCompanyInfo, getHistory, getQuote } from './prices.js';

function getProvider() {
  const token = process.env.FLEX_TOKEN;
  const queryId = process.env.FLEX_QUERY_ID;
  if (!token || !queryId) return null;
  return createFlexProvider(token, queryId);
}

let memoryCache: AccountData | null = null;
let inFlight: Promise<AccountData> | null = null;

function refresh(): Promise<AccountData> {
  if (inFlight) return inFlight;
  const provider = getProvider();
  if (!provider) {
    return Promise.reject(
      new Error('Not connected to IBKR yet — fill in FLEX_TOKEN and FLEX_QUERY_ID in server/.env (see README)')
    );
  }
  inFlight = provider
    .getAccountData()
    .then((data) => {
      memoryCache = data;
      saveAccountCache(data);
      return data;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

async function getData(force = false): Promise<AccountData> {
  if (force) return refresh();
  memoryCache ??= loadAccountCache();
  if (!memoryCache) return refresh();
  if (isStale(memoryCache)) {
    // Serve the old snapshot immediately, update in the background
    refresh().catch((err) => console.error('Background refresh failed:', err.message));
  }
  return memoryCache;
}

interface EnrichedPosition extends Position {
  name: string;
  currentPrice: number;
  currentValue: number;
  gainLoss: number;
  gainLossPercent: number | null;
  changeTodayPercent: number | null;
  priceIsLive: boolean;
}

async function enrichPositions(positions: Position[]): Promise<EnrichedPosition[]> {
  return Promise.all(
    positions.map(async (pos) => {
      const quote = await getQuote(pos.symbol);
      const currentPrice = quote?.price ?? pos.snapshotPrice;
      const currentValue = currentPrice * pos.quantity;
      const gainLoss = currentValue - pos.costBasis;
      return {
        ...pos,
        name: quote?.name ?? pos.description,
        currentPrice,
        currentValue,
        gainLoss,
        gainLossPercent: pos.costBasis !== 0 ? (gainLoss / pos.costBasis) * 100 : null,
        changeTodayPercent: quote?.changeTodayPercent ?? null,
        priceIsLive: quote != null,
      };
    })
  );
}

export const api = Router();

// Wrap async handlers so thrown errors become JSON responses
const wrap =
  (fn: (req: any, res: any) => Promise<void>) =>
  (req: any, res: any) =>
    fn(req, res).catch((err: Error) => {
      const needsSetup = err.message.includes('FLEX_TOKEN');
      res.status(needsSetup ? 503 : 502).json({ error: err.message });
    });

api.get(
  '/summary',
  wrap(async (_req, res) => {
    const data = await getData();
    const positions = await enrichPositions(data.positions);
    const investedValue = positions.reduce((s, p) => s + p.currentValue, 0);
    const totalPaid = positions.reduce((s, p) => s + p.costBasis, 0);
    const thisYear = new Date().getFullYear();
    const dividendsThisYear = data.dividends
      .filter((d) => d.date.startsWith(String(thisYear)))
      .reduce((s, d) => s + d.netAmount, 0);
    res.json({
      totalValue: investedValue + data.balances.cash,
      investedValue,
      totalPaid,
      gainLoss: investedValue - totalPaid,
      cash: data.balances.cash,
      currency: data.balances.currency,
      dividendsThisYear,
      positionCount: positions.length,
      lastUpdated: data.fetchedAt,
      reportDate: data.reportDate,
    });
  })
);

api.get(
  '/positions',
  wrap(async (_req, res) => {
    const data = await getData();
    res.json(await enrichPositions(data.positions));
  })
);

api.get(
  '/trades',
  wrap(async (req, res) => {
    const data = await getData();
    const symbol = req.query.symbol as string | undefined;
    res.json(symbol ? data.trades.filter((t) => t.symbol === symbol) : data.trades);
  })
);

api.get(
  '/dividends',
  wrap(async (req, res) => {
    const data = await getData();
    const symbol = req.query.symbol as string | undefined;
    res.json(symbol ? data.dividends.filter((d) => d.symbol === symbol) : data.dividends);
  })
);

api.get(
  '/stock/:symbol',
  wrap(async (req, res) => {
    const symbol = req.params.symbol as string;
    const data = await getData();
    const position = data.positions.find((p) => p.symbol === symbol) ?? null;
    const [enriched, info, quote] = await Promise.all([
      position ? enrichPositions([position]) : Promise.resolve([]),
      getCompanyInfo(symbol),
      getQuote(symbol),
    ]);
    res.json({
      symbol,
      position: enriched[0] ?? null,
      trades: data.trades.filter((t) => t.symbol === symbol),
      dividends: data.dividends.filter((d) => d.symbol === symbol),
      company: info,
      quote,
    });
  })
);

api.get(
  '/history/:symbol',
  wrap(async (req, res) => {
    const days = Math.min(Number(req.query.days) || 365, 3650);
    const history = await getHistory(req.params.symbol as string, days);
    res.json(history ?? []);
  })
);

api.post(
  '/refresh',
  wrap(async (_req, res) => {
    const data = await getData(true);
    res.json({ ok: true, lastUpdated: data.fetchedAt });
  })
);
