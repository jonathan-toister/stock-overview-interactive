import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AccountData } from './providers/types.js';

// The IBKR report is slow to generate and only updates a few times a day,
// so we keep the last download on disk and refresh it in the background
// when it gets old.

const CACHE_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'cache');
const CACHE_FILE = path.join(CACHE_DIR, 'account.json');

export const MAX_AGE_MS = 6 * 60 * 60_000; // refresh after 6 hours

export function loadAccountCache(): AccountData | null {
  try {
    return JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8')) as AccountData;
  } catch {
    return null;
  }
}

export function saveAccountCache(data: AccountData): void {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  fs.writeFileSync(CACHE_FILE, JSON.stringify(data, null, 2));
}

export function isStale(data: AccountData): boolean {
  return Date.now() - new Date(data.fetchedAt).getTime() > MAX_AGE_MS;
}
