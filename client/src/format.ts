export function money(value: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    maximumFractionDigits: 2,
  }).format(value);
}

export function signedMoney(value: number, currency = 'USD'): string {
  return `${value > 0 ? '+' : ''}${money(value, currency)}`;
}

// Whole-dollar amounts for the big "worth now / you paid / gain" sums,
// where cents would just be noise
export function money0(value: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    maximumFractionDigits: 0,
  }).format(value);
}

export function signedMoney0(value: number, currency = 'USD'): string {
  return `${value > 0 ? '+' : ''}${money0(value, currency)}`;
}

export function percent(value: number, digits = 1): string {
  return `${value > 0 ? '+' : ''}${value.toFixed(digits)}%`;
}

export function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

export function timeAgo(iso: string): string {
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? '' : 's'} ago`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? '' : 's'} ago`;
}

export function compactNumber(value: number): string {
  return new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 }).format(
    value
  );
}

// Big amounts shortened to something readable: $2.9T, $466.8B
export function compactMoney(value: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(value);
}

// Turns a fraction into a plain percentage: 0.0345 → "3.5%"
export function rate(fraction: number, digits = 1): string {
  return `${(fraction * 100).toFixed(digits)}%`;
}

// Same, but with a + or − so it reads as a move: 0.307 → "+30.7%"
export function signedRate(fraction: number, digits = 1): string {
  return percent(fraction * 100, digits);
}

// CSS class for coloring gains green and losses red
export const gainClass = (v: number): string => (v > 0 ? 'gain' : v < 0 ? 'loss' : '');
