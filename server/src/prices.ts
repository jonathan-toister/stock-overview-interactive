import YahooFinance from 'yahoo-finance2';

// Near-live prices, historical charts and company info come from Yahoo
// Finance (free, no API key). IBKR symbols are used as-is; if Yahoo doesn't
// recognize one we return null and the UI falls back to the IBKR snapshot.

const yahooFinance = new YahooFinance({ suppressNotices: ['yahooSurvey'] });

interface CacheEntry<T> {
  value: T;
  expires: number;
}

const memo = new Map<string, CacheEntry<any>>();

async function cached<T>(key: string, ttlMs: number, fn: () => Promise<T>): Promise<T | null> {
  const hit = memo.get(key);
  if (hit && hit.expires > Date.now()) return hit.value as T;
  try {
    const value = await fn();
    memo.set(key, { value, expires: Date.now() + ttlMs });
    return value;
  } catch {
    return null;
  }
}

export interface Quote {
  price: number;
  currency: string;
  name: string;
  changeToday: number | null;
  changeTodayPercent: number | null;
}

export async function getQuote(symbol: string): Promise<Quote | null> {
  return cached(`quote:${symbol}`, 5 * 60_000, async () => {
    const q = await yahooFinance.quote(symbol);
    if (q?.regularMarketPrice == null) throw new Error('no price');
    return {
      price: q.regularMarketPrice,
      currency: q.currency ?? 'USD',
      name: q.longName ?? q.shortName ?? symbol,
      changeToday: q.regularMarketChange ?? null,
      changeTodayPercent: q.regularMarketChangePercent ?? null,
    };
  });
}

export interface HistoryPoint {
  date: string; // yyyy-MM-dd
  close: number;
}

export async function getHistory(symbol: string, rangeDays: number): Promise<HistoryPoint[] | null> {
  return cached(`history:${symbol}:${rangeDays}`, 60 * 60_000, async () => {
    const period1 = new Date(Date.now() - rangeDays * 86_400_000);
    const result = await yahooFinance.chart(symbol, { period1, interval: '1d' });
    return (result.quotes ?? [])
      .filter((p) => p.close != null)
      .map((p) => ({
        date: new Date(p.date).toISOString().slice(0, 10),
        close: p.close as number,
      }));
  });
}

export interface CompanyInfo {
  name: string;
  sector: string | null;
  industry: string | null;
  website: string | null;
  marketCap: number | null;
  // Yearly dividend as a fraction of the price (0.02 = pays ~2% of the
  // stock price per year in dividends)
  dividendYield: number | null;
  summary: string | null;
}

export async function getCompanyInfo(symbol: string): Promise<CompanyInfo | null> {
  return cached(`info:${symbol}`, 24 * 60 * 60_000, async () => {
    const r = await yahooFinance.quoteSummary(symbol, {
      modules: ['assetProfile', 'summaryDetail', 'price'],
    });
    return {
      name: r.price?.longName ?? r.price?.shortName ?? symbol,
      sector: r.assetProfile?.sector ?? null,
      industry: r.assetProfile?.industry ?? null,
      website: r.assetProfile?.website ?? null,
      marketCap: r.price?.marketCap ?? null,
      dividendYield: r.summaryDetail?.dividendYield ?? null,
      summary: r.assetProfile?.longBusinessSummary ?? null,
    };
  });
}
