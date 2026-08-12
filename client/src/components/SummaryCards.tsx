import type { Summary } from '../types';
import { money0, percent, timeAgo } from '../format';
import SumBlock from './SumBlock';

interface Props {
  summary: Summary;
  onRefresh: () => void;
  refreshing: boolean;
}

function longDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
}

export default function SummaryCards({ summary, onRefresh, refreshing }: Props) {
  const s = summary;
  const gainPct = s.totalPaid !== 0 ? (s.gainLoss / s.totalPaid) * 100 : null;
  const word = s.gainLoss >= 0 ? 'gain' : 'loss';
  const resultLabel = gainPct != null ? `${word} · ${percent(gainPct)}` : word;

  return (
    <section>
      <div className="mast">
        <h1>Your account</h1>
        <span className="date">
          {longDate(s.reportDate ?? s.lastUpdated)} · data from {timeAgo(s.lastUpdated)}{' '}
          <button className="link-btn" onClick={onRefresh} disabled={refreshing}>
            {refreshing ? 'updating… (~30s)' : 'update now'}
          </button>
        </span>
      </div>

      <SumBlock
        large
        worthNow={s.investedValue}
        youPaid={s.totalPaid}
        gainLoss={s.gainLoss}
        gainLossPercent={gainPct}
        currency={s.currency}
        worthNote="your stocks"
        resultLabel={resultLabel}
      />
      <p className="divline">
        plus <b>{money0(s.cash, s.currency)}</b> cash sitting in the account — everything together:{' '}
        <b>{money0(s.totalValue, s.currency)}</b>
      </p>
      <p className="divline">
        companies have paid you <b>{money0(s.dividendsThisYear, s.currency)}</b> in dividends this
        year, after tax
      </p>
    </section>
  );
}
