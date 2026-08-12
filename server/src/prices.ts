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

export interface FundHolding {
  symbol: string | null;
  name: string;
  // Share of the fund's money in this one stock (0.07 = 7% of the fund)
  percent: number;
}

// The numbers behind the "key numbers" panel on a stock page. Deliberately a
// short list — the dashboard exists to replace Yahoo Finance, not reproduce it,
// so anything here has to earn its place. Everything is optional: Yahoo has
// different data for an ordinary company than for a fund, and some companies are
// missing pieces. Fractions (0.03 = 3%) are noted.
export interface CompanyInfo {
  name: string;
  // A fund/ETF holds a basket of other companies; a company is a single business
  kind: 'company' | 'fund';
  sector: string | null;
  industry: string | null;
  website: string | null;

  // --- Size and price ---
  // What the whole company is worth on the market
  marketCap: number | null;
  // Lowest and highest the share price has been over the past year
  yearLow: number | null;
  yearHigh: number | null;
  // How much the price moved over the past year, and the same for the whole
  // US market, so the two can be compared (fractions)
  yearChange: number | null;
  marketYearChange: number | null;
  // How much this tends to move when the market moves 1% (1.0 = the same)
  beta: number | null;

  // --- What you get paid ---
  // Yearly dividend as a fraction of the price (0.02 = pays ~2% a year)
  dividendYield: number | null;
  // Yearly dividend in money, per share
  dividendPerShare: number | null;
  nextDividendDate: string | null;

  // --- How the business is doing (companies only) ---
  // Price divided by a year's earnings per share — what you pay for $1 of profit
  priceToEarnings: number | null;
  // A year's profit per share, in money
  earningsPerShare: number | null;
  // Share of sales left over as profit (0.25 = $25 profit per $100 of sales)
  profitMargin: number | null;
  // Total sales over the past year, and how that compares to the year before
  revenue: number | null;
  revenueGrowth: number | null;

  // --- Funds only ---
  // Yearly fee as a fraction of what you hold (0.0003 = 0.03% a year)
  expenseRatio: number | null;
  returnYearToDate: number | null;
  // Average yearly return over the past three / five years (fractions)
  returnThreeYear: number | null;
  returnFiveYear: number | null;
  topHoldings: FundHolding[];
}

// Yahoo rejects the whole request if a module doesn't apply, so fund-only
// modules are fetched separately and are allowed to fail.
async function fundModules(symbol: string) {
  try {
    return await yahooFinance.quoteSummary(symbol, { modules: ['fundProfile', 'topHoldings'] });
  } catch {
    return null;
  }
}

const isoDate = (d: Date | string | null | undefined): string | null =>
  d ? new Date(d).toISOString().slice(0, 10) : null;

export async function getCompanyInfo(symbol: string): Promise<CompanyInfo | null> {
  return cached(`info:${symbol}`, 24 * 60 * 60_000, async () => {
    const r = await yahooFinance.quoteSummary(symbol, {
      modules: [
        'assetProfile',
        'summaryDetail',
        'price',
        'defaultKeyStatistics',
        'financialData',
        'calendarEvents',
      ],
    });
    const profile = r.assetProfile;
    const detail = r.summaryDetail;
    const stats = r.defaultKeyStatistics;
    const fin = r.financialData;
    const isFund = r.price?.quoteType === 'ETF' || r.price?.quoteType === 'MUTUALFUND';

    const fund = isFund ? await fundModules(symbol) : null;

    return {
      name: r.price?.longName ?? r.price?.shortName ?? symbol,
      kind: isFund ? 'fund' : 'company',
      sector: profile?.sector ?? null,
      industry: profile?.industry ?? null,
      website: profile?.website ?? null,

      marketCap: r.price?.marketCap ?? detail?.marketCap ?? null,
      yearLow: detail?.fiftyTwoWeekLow ?? null,
      yearHigh: detail?.fiftyTwoWeekHigh ?? null,
      yearChange: stats?.['52WeekChange'] ?? null,
      marketYearChange: stats?.SandP52WeekChange ?? null,
      beta: detail?.beta ?? stats?.beta ?? null,

      dividendYield: detail?.dividendYield ?? detail?.yield ?? null,
      dividendPerShare: detail?.dividendRate ?? null,
      nextDividendDate: isoDate(r.calendarEvents?.dividendDate),

      priceToEarnings: detail?.trailingPE ?? null,
      earningsPerShare: stats?.trailingEps ?? null,
      profitMargin: fin?.profitMargins ?? stats?.profitMargins ?? null,
      revenue: fin?.totalRevenue ?? null,
      revenueGrowth: fin?.revenueGrowth ?? null,

      expenseRatio: fund?.fundProfile?.feesExpensesInvestment?.annualReportExpenseRatio ?? null,
      returnYearToDate: stats?.ytdReturn ?? null,
      returnThreeYear: stats?.threeYearAverageReturn ?? null,
      returnFiveYear: stats?.fiveYearAverageReturn ?? null,
      topHoldings: (fund?.topHoldings?.holdings ?? [])
        .filter((h) => h.holdingPercent != null)
        .map((h) => ({
          symbol: h.symbol ?? null,
          name: h.holdingName ?? h.symbol ?? '',
          percent: h.holdingPercent as number,
        })),
    };
  });
}
