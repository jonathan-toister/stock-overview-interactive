// Quick connectivity check: downloads your Flex report and prints what's in it.
// Run with: npm run test-flex   (after filling in server/.env)
import 'dotenv/config';
import { fetchFlexStatement } from '../src/flex.js';

const token = process.env.FLEX_TOKEN;
const queryId = process.env.FLEX_QUERY_ID;

if (!token || !queryId) {
  console.error('Missing FLEX_TOKEN or FLEX_QUERY_ID — copy server/.env.example to server/.env and fill them in.');
  process.exit(1);
}

console.log('Requesting your report from IBKR (can take ~10-30 seconds)...');
try {
  const stmt = await fetchFlexStatement(token, queryId);
  console.log('\n✓ Connected! Report received.');
  console.log(`  Account:        ${stmt.accountId ?? '(not included)'}`);
  console.log(`  Period:         ${stmt.fromDate} → ${stmt.toDate}`);
  console.log(`  Open positions: ${stmt.OpenPositions?.OpenPosition?.length ?? 0}`);
  console.log(`  Trades:         ${stmt.Trades?.Trade?.length ?? 0}`);
  console.log(`  Cash rows:      ${stmt.CashTransactions?.CashTransaction?.length ?? 0}`);
  if (!stmt.OpenPositions) {
    console.warn('\n⚠ The report has no "Open Positions" section — edit your Flex Query on the IBKR site and enable it.');
  }
  if (!stmt.CashTransactions) {
    console.warn('⚠ The report has no "Cash Transactions" section — dividends will be empty. Enable it in your Flex Query.');
  }
} catch (err) {
  console.error(`\n✗ Failed: ${(err as Error).message}`);
  process.exit(1);
}
