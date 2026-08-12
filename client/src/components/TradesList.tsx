import { useState } from 'react';
import type { Trade } from '../types';
import { money, shortDate } from '../format';

const INITIAL_SHOWN = 15;

export default function TradesList({ trades }: { trades: Trade[] }) {
  const [showAll, setShowAll] = useState(false);

  if (trades.length === 0) {
    return <p className="muted">No buys or sells in the last year.</p>;
  }

  const shown = showAll ? trades : trades.slice(0, INITIAL_SHOWN);

  return (
    <div className="card table-card">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>What happened</th>
            <th className="num">Total</th>
          </tr>
        </thead>
        <tbody>
          {shown.map((t, i) => (
            <tr key={`${t.date}-${t.symbol}-${i}`}>
              <td className="muted">{shortDate(t.date)}</td>
              <td>
                <span className={t.side === 'BUY' ? 'trade-side gain' : 'trade-side loss'}>
                  {t.side === 'BUY' ? 'Bought' : 'Sold'}
                </span>{' '}
                {t.quantity} × <strong>{t.symbol}</strong> at {money(t.price, t.currency)}
              </td>
              <td className="num">{money(t.amount, t.currency)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {trades.length > INITIAL_SHOWN && (
        <button className="link-btn table-footer-btn" onClick={() => setShowAll(!showAll)}>
          {showAll ? 'Show fewer' : `Show all ${trades.length}`}
        </button>
      )}
    </div>
  );
}
