import { useCallback, useEffect, useState } from 'react';
import { api } from '../api';
import type { Dividend, Position, Summary, Trade } from '../types';
import SummaryCards from '../components/SummaryCards';
import PositionCards from '../components/PositionCards';
import TradesList from '../components/TradesList';
import DividendsTable from '../components/DividendsTable';

export default function ReportPage() {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [positions, setPositions] = useState<Position[] | null>(null);
  const [trades, setTrades] = useState<Trade[] | null>(null);
  const [dividends, setDividends] = useState<Dividend[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [s, p, t, d] = await Promise.all([
        api.summary(),
        api.positions(),
        api.trades(),
        api.dividends(),
      ]);
      setSummary(s);
      setPositions(p);
      setTrades(t);
      setDividends(d);
    } catch (err) {
      setError((err as Error).message);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const refresh = async () => {
    setRefreshing(true);
    try {
      await api.refresh();
      await load();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setRefreshing(false);
    }
  };

  if (error) {
    const needsSetup = error.includes('FLEX_TOKEN');
    return (
      <div className="card error-card">
        <h2>{needsSetup ? 'Almost there — connect your IBKR account' : 'Something went wrong'}</h2>
        <p>{error}</p>
        {needsSetup && (
          <p>
            Open the <code>README.md</code> in the project folder — it has a step-by-step guide for
            connecting your Interactive Brokers account (about 10 minutes, one time only).
          </p>
        )}
        <button onClick={load}>Try again</button>
      </div>
    );
  }

  if (!summary || !positions || !trades || !dividends) {
    return <div className="loading">Loading your account…</div>;
  }

  return (
    <>
      <SummaryCards summary={summary} onRefresh={refresh} refreshing={refreshing} />

      <section>
        <h2>Your stocks</h2>
        <PositionCards positions={positions} dividends={dividends} />
      </section>

      <section>
        <h2>Dividends</h2>
        <p className="section-sub">Money companies paid you for holding their stock.</p>
        <DividendsTable dividends={dividends} showStock />
      </section>

      <section>
        <h2>Your buys &amp; sells</h2>
        <TradesList trades={trades} />
      </section>
    </>
  );
}
