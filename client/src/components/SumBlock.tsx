import { gainClass, money0, percent, signedMoney0 } from '../format';

// The design's signature: a gain or loss set like hand-written arithmetic —
// worth now, minus what you paid, result under a drawn sum-rule.
interface Props {
  worthNow: number;
  youPaid: number;
  gainLoss: number;
  gainLossPercent: number | null;
  currency: string;
  worthNote?: string;
  paidNote?: string;
  resultLabel?: string;
  large?: boolean;
}

export default function SumBlock({
  worthNow,
  youPaid,
  gainLoss,
  gainLossPercent,
  currency,
  worthNote,
  paidNote,
  resultLabel,
  large = false,
}: Props) {
  const cls = gainClass(gainLoss);
  const label =
    resultLabel ?? (gainLossPercent != null ? percent(gainLossPercent) : gainLoss < 0 ? 'loss' : 'gain');

  return (
    <table className={large ? 'sum sum-lg' : 'sum'}>
      <tbody>
        <tr>
          <td className="op" />
          <td className="amt">{money0(worthNow, currency)}</td>
          <td className="lbl">worth now{worthNote ? ` · ${worthNote}` : ''}</td>
        </tr>
        <tr>
          <td className="op">−</td>
          <td className="amt">{money0(youPaid, currency)}</td>
          <td className="lbl">you paid{paidNote ? ` · ${paidNote}` : ''}</td>
        </tr>
        <tr className="res">
          <td className="op">=</td>
          <td className={`amt ${cls}`}>{signedMoney0(gainLoss, currency)}</td>
          <td className={`lbl ${cls}`}>{label}</td>
        </tr>
      </tbody>
    </table>
  );
}
