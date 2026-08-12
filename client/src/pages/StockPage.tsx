import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../api';
import type { StockDetail } from '../types';
import { gainClass, money, percent } from '../format';
import SumBlock from '../components/SumBlock';
import KeyIndicators from '../components/KeyIndicators';
import TradesList from '../components/TradesList';
import DividendsTable from '../components/DividendsTable';

export default function StockPage() {
  const { symbol = '' } = useParams();
  const [detail, setDetail] = useState<StockDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setDetail(null);
    setError(null);
    api
      .stock(symbol)
      .then(setDetail)
      .catch((err) => setError((err as Error).message));
  }, [symbol]);

  if (error) {
    return (
      <div className="error-card">
        <h2>Couldn't load {symbol}</h2>
        <p>{error}</p>
        <Link to="/">← Back to your account</Link>
      </div>
    );
  }

  if (!detail) {
    return <div className="loading">Loading {symbol}…</div>;
  }

  const { position: pos, quote, company } = detail;
  const currency = pos?.currency ?? quote?.currency ?? 'USD';
  const name = company?.name ?? quote?.name ?? pos?.name ?? symbol;

  const divTotal = detail.dividends.reduce((sum, d) => sum + d.netAmount, 0);
  // When the stock is down, say how much of the loss its dividends give back
  let lossNote = '';
  if (pos && pos.gainLoss < 0 && divTotal > 0) {
    const coverage = divTotal / -pos.gainLoss;
    lossNote =
      coverage >= 1
        ? ' — more than the loss above'
        : ` — covers ${Math.round(coverage * 100)}% of the loss above`;
  }

  return (
    <>
      <Link to="/" className="back-link">
        ← Back to your account
      </Link>

      <div className="stock-header">
        <div>
          <h1>
            {name}
            <span className="ticker">{symbol}</span>
          </h1>
          {company?.sector && (
            <p className="stock-sector">
              {company.sector}
              {company.industry ? ` · ${company.industry}` : ''}
            </p>
          )}
        </div>
        {quote && (
          <div className="stock-price">
            <span className="price-amt">{money(quote.price, quote.currency)}</span>
            <span className="price-sub">
              price now
              {quote.changeTodayPercent != null && (
                <>
                  {' · '}
                  <span className={gainClass(quote.changeTodayPercent)}>
                    {percent(quote.changeTodayPercent)} today
                  </span>
                </>
              )}
            </span>
          </div>
        )}
      </div>

      {pos ? (
        <section>
          <SumBlock
            large
            worthNow={pos.currentValue}
            youPaid={pos.costBasis}
            gainLoss={pos.gainLoss}
            gainLossPercent={pos.gainLossPercent}
            currency={currency}
            worthNote={`${pos.quantity} ${pos.quantity === 1 ? 'share' : 'shares'} · ${money(pos.currentPrice, currency)} each${pos.priceIsLive ? '' : ' (last report)'}`}
            paidNote={`${money(pos.avgCost, currency)} each`}
          />
          {divTotal > 0 && (
            <p className="divline">
              plus <b>{money(divTotal, currency)}</b> paid to you in dividends this past year
              {lossNote}
            </p>
          )}
        </section>
      ) : (
        <p className="muted">You don't currently own this stock.</p>
      )}

      {company && (
        <section>
          <h2>Key numbers</h2>
          <p className="section-sub">The few measures worth knowing, and what each one means.</p>
          <KeyIndicators
            company={company}
            currency={currency}
            price={quote?.price ?? pos?.currentPrice ?? null}
          />
        </section>
      )}

      <section>
        <h2>Dividends this stock paid you</h2>
        <DividendsTable dividends={detail.dividends} />
      </section>

      <section>
        <h2>Your buys &amp; sells of {symbol}</h2>
        <TradesList trades={detail.trades} />
      </section>
    </>
  );
}
