import { XMLParser } from 'fast-xml-parser';

// IBKR Flex Web Service: two-step download.
// 1) SendRequest with token + query id -> reference code
// 2) GetStatement with token + reference code -> statement XML
//    (IBKR generates the report on demand; retry while it's not ready)

const BASE = 'https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService';

// Elements that must always parse as arrays even when there's a single row
const ARRAY_ELEMENTS = new Set([
  'FlexStatement',
  'OpenPosition',
  'Trade',
  'CashTransaction',
  'CashReportCurrency',
]);

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '',
  isArray: (name) => ARRAY_ELEMENTS.has(name),
});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fetchXml(url: string): Promise<any> {
  const res = await fetch(url, { headers: { 'User-Agent': 'stock-overview-interactive' } });
  if (!res.ok) {
    throw new Error(`IBKR Flex service returned HTTP ${res.status}`);
  }
  return parser.parse(await res.text());
}

export interface FlexStatement {
  accountId?: string;
  fromDate?: string;
  toDate?: string;
  OpenPositions?: { OpenPosition?: any[] };
  Trades?: { Trade?: any[] };
  CashTransactions?: { CashTransaction?: any[] };
  CashReport?: { CashReportCurrency?: any[] };
  AccountInformation?: any;
}

export async function fetchFlexStatement(token: string, queryId: string): Promise<FlexStatement> {
  const send = await fetchXml(`${BASE}/SendRequest?t=${token}&q=${queryId}&v=3`);
  const sendResp = send.FlexStatementResponse;
  if (!sendResp || sendResp.Status !== 'Success') {
    const msg = sendResp?.ErrorMessage ?? 'unknown error from IBKR';
    throw new Error(`IBKR rejected the report request: ${msg}`);
  }

  const refCode = sendResp.ReferenceCode;
  const statementUrl = sendResp.Url || `${BASE}/GetStatement`;

  // Poll until the report is generated (usually a few seconds)
  let delay = 2000;
  for (let attempt = 0; attempt < 8; attempt++) {
    await sleep(delay);
    const result = await fetchXml(`${statementUrl}?t=${token}&q=${refCode}&v=3`);
    if (result.FlexQueryResponse) {
      const statements = result.FlexQueryResponse.FlexStatements?.FlexStatement;
      if (!statements?.length) {
        throw new Error('IBKR returned an empty report');
      }
      return statements[0] as FlexStatement;
    }
    const status = result.FlexStatementResponse;
    // 1019 = statement generation in progress
    if (status && String(status.ErrorCode) !== '1019') {
      throw new Error(`IBKR could not produce the report: ${status.ErrorMessage ?? 'unknown error'}`);
    }
    delay = Math.min(delay * 1.5, 15000);
  }
  throw new Error('Timed out waiting for IBKR to generate the report');
}
