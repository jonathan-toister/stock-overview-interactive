// Shared data shapes. All money amounts are in the position's own currency
// unless stated otherwise. Plain-language notes are included for each field.

export interface Position {
  symbol: string;
  description: string;
  quantity: number;
  // Total amount paid for the shares currently held
  costBasis: number;
  // Average price paid per share
  avgCost: number;
  // Price and value as of the last IBKR report snapshot
  snapshotPrice: number;
  snapshotValue: number;
  currency: string;
}

export interface Trade {
  date: string; // yyyy-MM-dd
  symbol: string;
  description: string;
  side: 'BUY' | 'SELL';
  quantity: number;
  price: number;
  // Total money the trade moved (positive number)
  amount: number;
  currency: string;
}

export interface Dividend {
  date: string; // yyyy-MM-dd
  symbol: string;
  description: string;
  // Amount the company paid you, before tax
  amount: number;
  // Tax automatically withheld from the payment (0 if none reported)
  taxWithheld: number;
  // What actually landed in your account
  netAmount: number;
  currency: string;
  // Whether the money was used to buy more shares (best-effort detection).
  // null = could not determine.
  reinvested: boolean | null;
}

export interface Balances {
  // Cash in the account, in the account's base currency
  cash: number;
  currency: string;
}

export interface AccountData {
  positions: Position[];
  trades: Trade[];
  dividends: Dividend[];
  balances: Balances;
  // When we downloaded the report (ISO timestamp)
  fetchedAt: string;
  // The date the report data is "as of"
  reportDate: string | null;
}

// v1 is backed by IBKR Flex Queries (snapshot reports). A future live
// implementation (TWS / IB Gateway API) only needs to implement this
// interface — routes and UI stay unchanged.
export interface AccountDataProvider {
  getAccountData(): Promise<AccountData>;
}
