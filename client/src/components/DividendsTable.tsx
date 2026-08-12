import { Link } from 'react-router-dom';
import type { Dividend } from '../types';
import { money, shortDate } from '../format';

interface Props {
  dividends: Dividend[];
  showStock?: boolean;
}

export default function DividendsTable({ dividends, showStock = false }: Props) {
  if (dividends.length === 0) {
    return <p className="muted">No dividend payments in the last year.</p>;
  }

  // Totals per currency (usually there's just one)
  const totals = new Map<string, number>();
  for (const d of dividends) {
    totals.set(d.currency, (totals.get(d.currency) ?? 0) + d.netAmount);
  }

  return (
    <div className="card table-card">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            {showStock && <th>Stock</th>}
            <th className="num">Paid to you</th>
            <th className="num">Tax taken</th>
            <th className="num">You received</th>
            <th>Reinvested?</th>
          </tr>
        </thead>
        <tbody>
          {dividends.map((d, i) => (
            <tr key={`${d.date}-${d.symbol}-${i}`}>
              <td className="muted">{shortDate(d.date)}</td>
              {showStock && (
                <td>
                  <Link to={`/stock/${encodeURIComponent(d.symbol)}`} className="symbol-link">
                    <strong>{d.symbol}</strong>
                  </Link>
                </td>
              )}
              <td className="num">{money(d.amount, d.currency)}</td>
              <td className="num muted">
                {d.taxWithheld > 0 ? money(d.taxWithheld, d.currency) : '–'}
              </td>
              <td className="num">
                <strong>{money(d.netAmount, d.currency)}</strong>
              </td>
              <td>
                {d.reinvested == null ? '–' : d.reinvested ? 'Yes — bought more shares' : 'No — kept as cash'}
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td colSpan={showStock ? 4 : 3}>Total received (after tax)</td>
            <td className="num">
              <strong>
                {[...totals.entries()].map(([cur, sum]) => money(sum, cur)).join(' + ')}
              </strong>
            </td>
            <td />
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
