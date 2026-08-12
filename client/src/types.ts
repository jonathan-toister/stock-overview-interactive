// Shapes returned by the server API (see server/src/providers/types.ts and
// server/src/routes.ts — keep in sync when either changes).

export interface Summary {
  totalValue: number;
  investedValue: number;
  totalPaid: number;
  gainLoss: number;
  cash: number;
  currency: string;
  dividendsThisYear: number;
  positionCount: number;
  lastUpdated: string;
  reportDate: string | null;
}

export interface Position {
  symbol: string;
  description: string;
  name: string;
  quantity: number;
  costBasis: number;
  avgCost: number;
  currency: string;
  currentPrice: number;
  currentValue: number;
  gainLoss: number;
  gainLossPercent: number | null;
  changeTodayPercent: number | null;
  priceIsLive: boolean;
}

export interface Trade {
  date: string;
  symbol: string;
  description: string;
  side: 'BUY' | 'SELL';
  quantity: number;
  price: number;
  amount: number;
  currency: string;
}

export interface Dividend {
  date: string;
  symbol: string;
  description: string;
  amount: number;
  taxWithheld: number;
  netAmount: number;
  currency: string;
  reinvested: boolean | null;
}

export interface Quote {
  price: number;
  currency: string;
  name: string;
  changeToday: number | null;
  changeTodayPercent: number | null;
}

export interface CompanyInfo {
  name: string;
  sector: string | null;
  industry: string | null;
  website: string | null;
  marketCap: number | null;
  dividendYield: number | null;
  summary: string | null;
}

export interface StockDetail {
  symbol: string;
  position: Position | null;
  trades: Trade[];
  dividends: Dividend[];
  company: CompanyInfo | null;
  quote: Quote | null;
}

export interface HistoryPoint {
  date: string;
  close: number;
}
