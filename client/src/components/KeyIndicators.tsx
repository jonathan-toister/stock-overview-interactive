import type { CompanyInfo } from '../types';
import { compactMoney, gainClass, money, money0, rate, shortDate, signedRate } from '../format';

// A short panel of the standard measures behind a ticker. Each one is labelled
// with its real name — the name you'd meet on IBKR or anywhere else — and a line
// underneath says in plain words what the number actually means.
//
// The list is deliberately short: eight for a company, six for a fund. This
// dashboard exists so there's no need to open Yahoo Finance, not to reproduce
// it, so a new measure has to displace an old one rather than be added on.

interface Stat {
  label: string;
  value: string;
  note?: string;
  className?: string;
}

function companyStats(c: CompanyInfo, currency: string): Stat[] {
  const stats: Stat[] = [];

  if (c.dividendYield != null && c.dividendYield > 0) {
    // Yahoo's dividend date can be the last payment rather than the next one,
    // so say which it is instead of promising a date that has already passed
    const paymentDate = c.nextDividendDate
      ? `${new Date(c.nextDividendDate) > new Date() ? 'next' : 'last'} payment ${shortDate(c.nextDividendDate)}`
      : null;
    stats.push({
      label: 'Dividend yield',
      value: rate(c.dividendYield),
      note: [
        'the slice of the price paid back to you each year',
        c.dividendPerShare != null ? `${money(c.dividendPerShare, currency)} a share` : null,
        paymentDate,
      ]
        .filter(Boolean)
        .join(' — '),
    });
  }

  if (c.priceToEarnings != null && c.priceToEarnings > 0) {
    stats.push({
      label: 'P/E ratio',
      value: c.priceToEarnings.toFixed(1),
      // The "years to earn the price back" framing is the one beginners grasp
      note: `how pricey the shares are: you pay ${money(c.priceToEarnings, currency)} for every ${money0(1, currency)} it earns in a year, so at that rate it takes about ${Math.round(c.priceToEarnings)} years of profit to earn the price back`,
    });
  }

  if (c.yearChange != null) {
    stats.push({
      label: 'One-year return',
      value: signedRate(c.yearChange),
      className: gainClass(c.yearChange),
      note:
        c.marketYearChange != null
          ? `how the share price moved over twelve months — the whole US market moved ${signedRate(c.marketYearChange)}`
          : 'how the share price moved over twelve months',
    });
  }

  if (c.marketCap != null) {
    stats.push({
      label: 'Market cap',
      value: compactMoney(c.marketCap, currency),
      note: 'what the whole company is worth — every share added together',
    });
  }

  if (c.beta != null) {
    // The market itself is always 1.0, so the gap from 1 is the readable part
    const gap = Math.round(Math.abs(c.beta - 1) * 100);
    const feel =
      c.beta > 1.15
        ? `this moves about ${gap}% more than the market — a bumpier ride`
        : c.beta < 0.85
          ? `this moves about ${gap}% less than the market — a smoother ride`
          : 'this moves about as much as the market does';
    stats.push({
      label: 'Beta',
      value: `${c.beta.toFixed(2)}×`,
      note: `how much the price swings: ${feel}`,
    });
  }

  if (c.profitMargin != null) {
    stats.push({
      label: 'Profit margin',
      value: rate(c.profitMargin),
      note: `out of every ${money0(100, currency)} of sales, about ${money(c.profitMargin * 100, currency)} is profit`,
    });
  }

  if (c.revenue != null) {
    stats.push({
      label: 'Revenue',
      value: compactMoney(c.revenue, currency),
      note:
        c.revenueGrowth != null
          ? `everything it sold in the past year — ${c.revenueGrowth >= 0 ? 'up' : 'down'} ${rate(Math.abs(c.revenueGrowth))} on the year before`
          : 'everything it sold in the past year',
    });
  }

  return stats;
}

function fundStats(c: CompanyInfo, currency: string): Stat[] {
  const stats: Stat[] = [];

  if (c.expenseRatio != null) {
    stats.push({
      label: 'Expense ratio',
      value: rate(c.expenseRatio, 2),
      note: `its yearly fee — ${money(c.expenseRatio * 10_000, currency)} a year for every ${money0(10_000, currency)} you hold`,
    });
  }

  if (c.dividendYield != null && c.dividendYield > 0) {
    stats.push({
      label: 'Dividend yield',
      value: rate(c.dividendYield),
      note: 'the slice of the price paid back to you each year',
    });
  }

  if (c.returnYearToDate != null) {
    stats.push({
      label: 'Return this year',
      value: signedRate(c.returnYearToDate),
      className: gainClass(c.returnYearToDate),
      note: 'change since 1 January',
    });
  }

  if (c.returnThreeYear != null) {
    stats.push({
      label: '3-year return',
      value: signedRate(c.returnThreeYear),
      className: gainClass(c.returnThreeYear),
      note: 'the average for each of the past three years',
    });
  }

  if (c.returnFiveYear != null) {
    stats.push({
      label: '5-year return',
      value: signedRate(c.returnFiveYear),
      className: gainClass(c.returnFiveYear),
      note: 'the average for each of the past five years',
    });
  }

  return stats;
}

interface Props {
  company: CompanyInfo;
  currency: string;
  // Today's price, so the year's range can say where the price sits in it
  price: number | null;
}

export default function KeyIndicators({ company, currency, price }: Props) {
  const isFund = company.kind === 'fund';
  const stats = isFund ? fundStats(company, currency) : companyStats(company, currency);

  // A range means little for a fund tracking the whole market, so it's shown
  // for companies only
  const hasRange =
    !isFund &&
    company.yearLow != null &&
    company.yearHigh != null &&
    company.yearHigh > company.yearLow;
  // Where today's price sits between the year's low and high, 0–100%
  const positionInRange =
    hasRange && price != null
      ? Math.max(
          0,
          Math.min(100, ((price - company.yearLow!) / (company.yearHigh! - company.yearLow!)) * 100)
        )
      : null;

  const holdings = isFund ? company.topHoldings.slice(0, 8) : [];

  if (!stats.length && !hasRange && !holdings.length) return null;

  return (
    <div className="company-card">
      {stats.length > 0 && (
        <div className="stats">
          {stats.map((s) => (
            <div className="stat" key={s.label}>
              <div className="stat-lbl">{s.label}</div>
              <div className={`stat-val ${s.className ?? ''}`}>{s.value}</div>
              {s.note && <div className="stat-note">{s.note}</div>}
            </div>
          ))}
        </div>
      )}

      {hasRange && (
        <div className="stat stat-wide">
          <div className="stat-lbl">52-week range</div>
          <div className="stat-val">
            {money(company.yearLow!, currency)} – {money(company.yearHigh!, currency)}
          </div>
          <div className="stat-note">
            the lowest and highest the price has been in the past year
            {positionInRange != null &&
              ` — today's ${money(price!, currency)} sits ${Math.round(positionInRange)}% of the way up`}
          </div>
        </div>
      )}

      {holdings.length > 0 && (
        <div className="stat stat-wide">
          <div className="stat-lbl">Top holdings</div>
          <div className="stat-note">
            the biggest companies the fund owns, and how much of it each one is
          </div>
          <ul className="holdings">
            {holdings.map((h) => (
              <li key={h.symbol ?? h.name}>
                <span className="holding-name">{h.name}</span>
                <span className="holding-pct">{rate(h.percent)}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {company.website && (
        <p className="company-foot">
          <a href={company.website} target="_blank" rel="noreferrer">
            {company.website.replace(/^https?:\/\//, '')}
          </a>
        </p>
      )}
    </div>
  );
}
