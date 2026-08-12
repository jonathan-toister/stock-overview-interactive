import { fetchFlexStatement, type FlexStatement } from '../flex.js';
import type { AccountData, AccountDataProvider, Dividend, Position, Trade } from './types.js';

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

// Dates can come as "yyyy-MM-dd", "yyyyMMdd", or with a ";HHmmss" time part,
// depending on the date format chosen in the Flex Query settings.
const toDate = (v: unknown): string => {
  const d = String(v ?? '').split(';')[0];
  return /^\d{8}$/.test(d) ? `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6)}` : d;
};

// Some report configurations include both summary and per-lot/detail rows for
// the same data; keep only one level to avoid double counting.
const oneLevel = (rows: any[], level: string): any[] => {
  const matching = rows.filter((r) => String(r.levelOfDetail ?? '') === level);
  return matching.length > 0 ? matching : rows.filter((r) => !r.levelOfDetail);
};

const daysBetween = (a: string, b: string): number =>
  Math.abs(new Date(a).getTime() - new Date(b).getTime()) / 86_400_000;

function parsePositions(stmt: FlexStatement): Position[] {
  const rows = oneLevel(stmt.OpenPositions?.OpenPosition ?? [], 'SUMMARY');
  return rows
    .filter((r) => num(r.position) !== 0)
    .map((r) => ({
      symbol: String(r.symbol),
      description: String(r.description ?? r.symbol),
      quantity: num(r.position),
      costBasis: num(r.costBasisMoney),
      avgCost: num(r.costBasisPrice),
      snapshotPrice: num(r.markPrice),
      snapshotValue: num(r.positionValue),
      currency: String(r.currency ?? 'USD'),
    }));
}

function parseTrades(stmt: FlexStatement): Trade[] {
  const rows = oneLevel(stmt.Trades?.Trade ?? [], 'EXECUTION');
  return rows
    .filter((r) => r.symbol)
    .map((r) => ({
      date: toDate(r.tradeDate ?? r.dateTime),
      symbol: String(r.symbol),
      description: String(r.description ?? r.symbol),
      side: (String(r.buySell).toUpperCase() === 'SELL' ? 'SELL' : 'BUY') as Trade['side'],
      quantity: Math.abs(num(r.quantity)),
      price: num(r.tradePrice),
      amount: Math.abs(num(r.tradeMoney)),
      currency: String(r.currency ?? 'USD'),
    }))
    .sort((a, b) => b.date.localeCompare(a.date));
}

function parseDividends(stmt: FlexStatement, trades: Trade[]): Dividend[] {
  const rows = oneLevel(stmt.CashTransactions?.CashTransaction ?? [], 'DETAIL');
  const type = (r: any) => String(r.type ?? '');

  const payments = rows.filter((r) =>
    ['Dividends', 'Payment In Lieu Of Dividends'].includes(type(r))
  );
  const taxes = rows.filter((r) => type(r) === 'Withholding Tax');

  return payments
    .map((r) => {
      const date = toDate(r.dateTime ?? r.reportDate);
      const symbol = String(r.symbol ?? '');
      const amount = num(r.amount);

      // Tax rows are negative amounts reported alongside the payment
      const taxWithheld = taxes
        .filter((t) => String(t.symbol ?? '') === symbol && daysBetween(toDate(t.dateTime ?? t.reportDate), date) <= 3)
        .reduce((sum, t) => sum + Math.abs(num(t.amount)), 0);

      const netAmount = amount - taxWithheld;

      // Best-effort: IBKR reports dividend reinvestment as a normal buy soon
      // after the payment, for roughly the paid amount.
      const reinvested =
        trades.length === 0
          ? null
          : trades.some(
              (t) =>
                t.side === 'BUY' &&
                t.symbol === symbol &&
                daysBetween(t.date, date) <= 7 &&
                Math.abs(t.amount - netAmount) <= Math.max(1, netAmount * 0.3)
            );

      return {
        date,
        symbol,
        description: String(r.description ?? symbol),
        amount,
        taxWithheld,
        netAmount,
        currency: String(r.currency ?? 'USD'),
        reinvested,
      };
    })
    .sort((a, b) => b.date.localeCompare(a.date));
}

function parseBalances(stmt: FlexStatement): AccountData['balances'] {
  const rows = stmt.CashReport?.CashReportCurrency ?? [];
  const base = rows.find((r) => String(r.currency) === 'BASE_SUMMARY');
  const row = base ?? rows[0];
  const baseCurrency =
    stmt.AccountInformation?.currency ??
    rows.map((r) => String(r.currency)).find((c) => c !== 'BASE_SUMMARY') ??
    'USD';
  return {
    cash: num(row?.endingCash ?? row?.endingSettledCash),
    currency: String(baseCurrency),
  };
}

export function createFlexProvider(token: string, queryId: string): AccountDataProvider {
  return {
    async getAccountData(): Promise<AccountData> {
      const stmt = await fetchFlexStatement(token, queryId);
      const trades = parseTrades(stmt);
      return {
        positions: parsePositions(stmt),
        trades,
        dividends: parseDividends(stmt, trades),
        balances: parseBalances(stmt),
        fetchedAt: new Date().toISOString(),
        reportDate: stmt.toDate ? toDate(stmt.toDate) : null,
      };
    },
  };
}
