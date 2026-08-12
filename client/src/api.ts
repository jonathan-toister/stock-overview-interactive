import type { Dividend, Position, StockDetail, Summary, Trade } from './types';

async function getJSON<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(body?.error ?? `Request failed (${res.status})`);
  }
  return body as T;
}

export const api = {
  summary: () => getJSON<Summary>('/api/summary'),
  positions: () => getJSON<Position[]>('/api/positions'),
  trades: (symbol?: string) =>
    getJSON<Trade[]>(`/api/trades${symbol ? `?symbol=${encodeURIComponent(symbol)}` : ''}`),
  dividends: (symbol?: string) =>
    getJSON<Dividend[]>(`/api/dividends${symbol ? `?symbol=${encodeURIComponent(symbol)}` : ''}`),
  stock: (symbol: string) => getJSON<StockDetail>(`/api/stock/${encodeURIComponent(symbol)}`),
  refresh: () => getJSON<{ ok: boolean }>('/api/refresh', { method: 'POST' }),
};
