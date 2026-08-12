import { Link } from 'react-router-dom';
import type { Dividend, Position } from '../types';
import { gainClass, money, percent } from '../format';
import SumBlock from './SumBlock';

interface Props {
  positions: Position[];
  dividends: Dividend[];
}

export default function PositionCards({ positions, dividends }: Props) {
  if (positions.length === 0) {
    return <p className="muted">No stocks in the account right now.</p>;
  }

  const sorted = [...positions].sort((a, b) => b.currentValue - a.currentValue);

  const divTotals = new Map<string, number>();
  for (const d of dividends) {
    divTotals.set(d.symbol, (divTotals.get(d.symbol) ?? 0) + d.netAmount);
  }

  return (
    <div className="cards">
      {sorted.map((p) => {
        const divTotal = divTotals.get(p.symbol) ?? 0;
        return (
          <Link key={p.symbol} to={`/stock/${encodeURIComponent(p.symbol)}`} className="pos-card">
            <div className="head">
              <span className="co">{p.name || p.symbol}</span>
              <span className="meta">
                {p.symbol} · {p.quantity} {p.quantity === 1 ? 'share' : 'shares'}
                {p.changeTodayPercent != null && (
                  <span className={`small ${gainClass(p.changeTodayPercent)}`}>
                    {percent(p.changeTodayPercent)} today
                  </span>
                )}
              </span>
            </div>
            <SumBlock
              worthNow={p.currentValue}
              youPaid={p.costBasis}
              gainLoss={p.gainLoss}
              gainLossPercent={p.gainLossPercent}
              currency={p.currency}
              worthNote={`${money(p.currentPrice, p.currency)} each${p.priceIsLive ? '' : ' (last report)'}`}
              paidNote={`${money(p.avgCost, p.currency)} each`}
            />
            {divTotal > 0 && (
              <p className="divline">
                dividends, past year <b>{money(divTotal, p.currency)}</b>
              </p>
            )}
          </Link>
        );
      })}
    </div>
  );
}
