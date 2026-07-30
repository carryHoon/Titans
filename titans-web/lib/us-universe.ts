// ─── US 유니버스 & 발행주수/환율 메타 (단일 소스) ─────────────────────────────
// market-cap 라우트(표시·랭킹)와 us-stats 스냅샷 레이어(stats 갱신)가 공유한다.
// 티커 리스트를 한 곳에서만 관리해, 종목 추가 시 두 경로가 어긋나지 않도록 한다.
//
// NASDAQ·NYSE 유니버스는 정적 큐레이션 리스트다. 실시간 스크리너 없이도 상위 20개가 항상
// 포함되도록 여유 있게 구성하고, 실시간 시총(Twelve Data /statistics + /quote 스케일링)으로
// 재정렬해 상위 20개를 뽑는다.

export interface CompanyMeta {
  ticker: string
  name:   string
  color:  string
}

// ─── 가격 기반 시총 계산 (stats 없이 발행주수 × 가격으로 직접 계산) ───────────────
// 대상: ADR(USD가격) 종목. /statistics가 부정확하거나 미지원인 종목.
// 합병·분할 없는 한 발행주수는 거의 변하지 않음. (최근 갱신: 2026-07)

// ADR: 발행주수(M) × ADR가격(USD) / 1,000,000 = 시총(T USD)
export const ADR_SHARE_RATIO: Record<string, number> = {
  TSM:  5,  // TSMC: 1 ADR = 5 대만 보통주
  HSBC: 5,  // HSBC: 1 ADR = 5 런던 보통주
}
export const ADR_SHARE_OUTSTANDING_M: Record<string, number> = {
  TSM:  5165,  // 보통주 25825M ÷ ADR비율 5 = 5165M ADR
  HSBC: 3437,  // 보통주 17183M ÷ ADR비율 5 = 3437M ADR
}

// SAR 종목 (Tadawul): /statistics가 market_capitalization을 SAR로 반환 → USD 변환 필요.
// SAR/USD 법정 고정환율(3.75)로 나누면 정확한 USD 시총.
// EOD 가격 기반 라이브 스케일링(stats × close/prev_close)은 일반 종목과 동일.
export const SAR_PER_USD = 3.75  // 사우디 리얄 법정 고정환율 (1946년~)
export const SAR_STATS_TICKERS = new Set(['2222:TADAWUL'])

// ─── 유니버스 ──────────────────────────────────────────────────────────────────

export const COMPANIES: CompanyMeta[] = [
  // Top 10 (US)
  { ticker: 'NVDA',           name: 'NVIDIA',        color: '#78BB17' },
  { ticker: 'AAPL',           name: 'Apple',         color: '#8E8E93' },
  { ticker: 'MSFT',           name: 'Microsoft',     color: '#0078D4' },
  { ticker: 'GOOGL',          name: 'Alphabet',      color: '#EA4335' },
  { ticker: 'AMZN',           name: 'Amazon',        color: '#FF9900' },
  { ticker: 'META',           name: 'Meta',          color: '#4267B2' },
  { ticker: 'TSLA',           name: 'Tesla',         color: '#CC1C1C' },
  { ticker: 'BRK.B',          name: 'Berkshire',     color: '#8B5E20' },
  { ticker: 'AVGO',           name: 'Broadcom',      color: '#CC0000' },
  { ticker: 'JPM',            name: 'JPMorgan',      color: '#005EB8' },
  // 글로벌 (ADR + Tadawul EOD)
  { ticker: 'TSM',            name: 'TSMC',          color: '#0073CE' },
  { ticker: '2222:TADAWUL',   name: 'Saudi Aramco',  color: '#007A3D' },
  // 11–20위권 (US)
  { ticker: 'LLY',            name: 'Eli Lilly',     color: '#8B5CF6' },
  { ticker: 'WMT',            name: 'Walmart',       color: '#007DC6' },
  { ticker: 'V',              name: 'Visa',          color: '#1A1F71' },
  { ticker: 'ORCL',           name: 'Oracle',        color: '#F80000' },
  { ticker: 'XOM',            name: 'ExxonMobil',    color: '#1A1A1A' },
  { ticker: 'MA',             name: 'Mastercard',    color: '#EB001B' },
  { ticker: 'COST',           name: 'Costco',        color: '#005DAA' },
  { ticker: 'NFLX',           name: 'Netflix',       color: '#E50914' },
  { ticker: 'UNH',            name: 'UnitedHealth',  color: '#002677' },
  { ticker: 'PLTR',           name: 'Palantir',      color: '#101828' },
  { ticker: 'SPCX',           name: 'SpaceX',        color: '#005288' },
  { ticker: 'AMD',            name: 'AMD',           color: '#ED1C24' },
  { ticker: 'MU',             name: 'Micron',        color: '#00AEEF' },
]

// NASDAQ 유니버스 (큐레이션, top-100 상위집합 ~112종목).
// 백본 = NASDAQ-100 지수 구성종목(나스닥 최대 비금융 100개) + 지수 밖 대형주 버퍼(금융·중국 ADR 등).
// 순서는 무관 — market-cap 라우트가 라이브 시총으로 재정렬해 top-100을 뽑는다. "완전성(누락 없음)"만 목표.
// ⚠️ Walmart(WMT) 등 NASDAQ 공식 상장 종목은 NYSE가 아닌 여기에 둔다.
// ⚠️ 외국 국적이라도 NASDAQ 정식 상장이면 포함(ASML·ARM·PDD·MELI 등) — 나스닥 공식 순위와 일치.
export const NASDAQ_COMPANIES: CompanyMeta[] = [
  // ── Top 메가캡 (기존 큐레이션) ──
  { ticker: 'NVDA',  name: 'NVIDIA',             color: '#78BB17' },
  { ticker: 'AAPL',  name: 'Apple',              color: '#8E8E93' },
  { ticker: 'MSFT',  name: 'Microsoft',          color: '#0078D4' },
  { ticker: 'GOOGL', name: 'Alphabet',           color: '#EA4335' },
  { ticker: 'AMZN',  name: 'Amazon',             color: '#FF9900' },
  { ticker: 'META',  name: 'Meta',               color: '#4267B2' },
  { ticker: 'AVGO',  name: 'Broadcom',           color: '#CC0000' },
  { ticker: 'TSLA',  name: 'Tesla',              color: '#CC1C1C' },
  { ticker: 'SPCX',  name: 'SpaceX',             color: '#005288' },
  { ticker: 'MU',    name: 'Micron',             color: '#00AEEF' },
  { ticker: 'WMT',   name: 'Walmart',            color: '#007DC6' },
  { ticker: 'AMD',   name: 'AMD',                color: '#ED1C24' },
  { ticker: 'INTC',  name: 'Intel',              color: '#0068B5' },
  { ticker: 'ASML',  name: 'ASML',               color: '#0B5394' },
  { ticker: 'CSCO',  name: 'Cisco',              color: '#1BA0D7' },
  { ticker: 'AMAT',  name: 'Applied Materials',  color: '#1A6DB4' },
  { ticker: 'COST',  name: 'Costco',             color: '#005DAA' },
  { ticker: 'LRCX',  name: 'Lam Research',       color: '#6EBE44' },
  { ticker: 'ARM',   name: 'Arm Holdings',       color: '#1BA8DF' },
  { ticker: 'PLTR',  name: 'Palantir',           color: '#101828' },
  { ticker: 'NFLX',  name: 'Netflix',            color: '#E50914' },
  { ticker: 'KLAC',  name: 'KLA',                color: '#0033A0' },
  { ticker: 'PANW',  name: 'Palo Alto Networks', color: '#FA582D' },
  { ticker: 'TXN',   name: 'Texas Instruments',  color: '#CC0000' },
  { ticker: 'LIN',   name: 'Linde',              color: '#005591' },
  { ticker: 'TMUS',  name: 'T-Mobile',           color: '#E20074' },
  { ticker: 'AMGN',  name: 'Amgen',              color: '#0063C3' },
  { ticker: 'ADBE',  name: 'Adobe',              color: '#FA0F00' },
  { ticker: 'INTU',  name: 'Intuit',             color: '#365EBF' },
  { ticker: 'QCOM',  name: 'Qualcomm',           color: '#3253DC' },
  { ticker: 'ISRG',  name: 'Intuitive Surgical', color: '#486B92' },
  // ── NASDAQ-100 나머지 구성종목 ──
  { ticker: 'PEP',   name: 'PepsiCo',            color: '#004B93' },
  { ticker: 'CMCSA', name: 'Comcast',            color: '#000000' },
  { ticker: 'HON',   name: 'Honeywell',          color: '#E8112D' },
  { ticker: 'ADP',   name: 'ADP',                color: '#E01A2B' },
  { ticker: 'GILD',  name: 'Gilead Sciences',    color: '#C8102E' },
  { ticker: 'VRTX',  name: 'Vertex Pharma',      color: '#00263A' },
  { ticker: 'SBUX',  name: 'Starbucks',          color: '#00704A' },
  { ticker: 'BKNG',  name: 'Booking Holdings',   color: '#003580' },
  { ticker: 'MELI',  name: 'MercadoLibre',       color: '#FFE600' },
  { ticker: 'PDD',   name: 'PDD Holdings',       color: '#E4002B' },
  { ticker: 'ADI',   name: 'Analog Devices',     color: '#1B3A6B' },
  { ticker: 'MDLZ',  name: 'Mondelez',           color: '#6E267B' },
  { ticker: 'REGN',  name: 'Regeneron',          color: '#003C71' },
  { ticker: 'APP',   name: 'AppLovin',           color: '#0A0A0A' },
  { ticker: 'MRVL',  name: 'Marvell',            color: '#0072CE' },
  { ticker: 'CEG',   name: 'Constellation En.',  color: '#00A9E0' },
  { ticker: 'CRWD',  name: 'CrowdStrike',        color: '#E01F27' },
  { ticker: 'SNPS',  name: 'Synopsys',           color: '#3B49AC' },
  { ticker: 'CDNS',  name: 'Cadence',            color: '#00AEC7' },
  { ticker: 'MSTR',  name: 'Strategy',           color: '#E4002B' },
  { ticker: 'NXPI',  name: 'NXP Semiconductors', color: '#00AEEF' },
  { ticker: 'FTNT',  name: 'Fortinet',           color: '#EE3124' },
  { ticker: 'ORLY',  name: "O'Reilly Auto",      color: '#00693C' },
  { ticker: 'ADSK',  name: 'Autodesk',           color: '#0696D7' },
  { ticker: 'CSX',   name: 'CSX',                color: '#003278' },
  { ticker: 'ABNB',  name: 'Airbnb',             color: '#FF5A5F' },
  { ticker: 'MAR',   name: 'Marriott',           color: '#A70023' },
  { ticker: 'MCHP',  name: 'Microchip',          color: '#EE3124' },
  { ticker: 'CTAS',  name: 'Cintas',             color: '#0033A0' },
  { ticker: 'DASH',  name: 'DoorDash',           color: '#FF3008' },
  { ticker: 'PAYX',  name: 'Paychex',            color: '#0067B1' },
  { ticker: 'PYPL',  name: 'PayPal',             color: '#003087' },
  { ticker: 'AEP',   name: 'American Elec. Pwr', color: '#E31837' },
  { ticker: 'ROP',   name: 'Roper Tech.',        color: '#003DA5' },
  { ticker: 'FAST',  name: 'Fastenal',           color: '#002D62' },
  { ticker: 'KDP',   name: 'Keurig Dr Pepper',   color: '#C8102E' },
  { ticker: 'DDOG',  name: 'Datadog',            color: '#632CA6' },
  { ticker: 'ODFL',  name: 'Old Dominion',       color: '#C8102E' },
  { ticker: 'EA',    name: 'Electronic Arts',    color: '#000000' },
  { ticker: 'BKR',   name: 'Baker Hughes',       color: '#00AEEF' },
  { ticker: 'CPRT',  name: 'Copart',             color: '#003DA5' },
  { ticker: 'EXC',   name: 'Exelon',             color: '#6E267B' },
  { ticker: 'GEHC',  name: 'GE HealthCare',      color: '#7D3F98' },
  { ticker: 'KHC',   name: 'Kraft Heinz',        color: '#4B2E83' },
  { ticker: 'TTWO',  name: 'Take-Two',           color: '#E4002B' },
  { ticker: 'CRWV',  name: 'CoreWeave',          color: '#FF6A00' },
  { ticker: 'XEL',   name: 'Xcel Energy',        color: '#0072CE' },
  { ticker: 'MNST',  name: 'Monster Beverage',   color: '#7AB800' },
  { ticker: 'IDXX',  name: 'Idexx Labs',         color: '#003A5D' },
  { ticker: 'WDAY',  name: 'Workday',            color: '#0875E1' },
  { ticker: 'FANG',  name: 'Diamondback En.',    color: '#00553A' },
  { ticker: 'TRI',   name: 'Thomson Reuters',    color: '#FA6400' },
  { ticker: 'DXCM',  name: 'Dexcom',             color: '#00A3E0' },
  { ticker: 'MPWR',  name: 'Monolithic Power',   color: '#0072CE' },
  { ticker: 'ROST',  name: 'Ross Stores',        color: '#003057' },
  { ticker: 'CCEP',  name: 'Coca-Cola EP',       color: '#F40000' },
  { ticker: 'TER',   name: 'Teradyne',           color: '#6CC24A' },
  { ticker: 'WBD',   name: 'Warner Bros. Disc.', color: '#0057FF' },
  { ticker: 'PCAR',  name: 'Paccar',             color: '#003478' },
  { ticker: 'FER',   name: 'Ferrovial',          color: '#0033A1' },
  { ticker: 'SHOP',  name: 'Shopify',            color: '#95BF47' },
  { ticker: 'WDC',   name: 'Western Digital',    color: '#0033A0' },
  { ticker: 'STX',   name: 'Seagate',            color: '#6EBE44' },
  { ticker: 'SNDK',  name: 'Sandisk',            color: '#E4002B' },
  { ticker: 'LITE',  name: 'Lumentum',           color: '#00539B' },
  { ticker: 'ALAB',  name: 'Astera Labs',        color: '#6C2EB9' },
  { ticker: 'NBIS',  name: 'Nebius Group',       color: '#0A0A0A' },
  { ticker: 'RKLB',  name: 'Rocket Lab',         color: '#0A0A0A' },
  { ticker: 'AXON',  name: 'Axon Enterprise',    color: '#0A0A0A' },
  { ticker: 'ALNY',  name: 'Alnylam Pharma',     color: '#00263A' },
  // ── 지수 밖 대형주 버퍼 (완전성 확보용: 금융·중국 ADR·성장주) ──
  { ticker: 'COIN',  name: 'Coinbase',           color: '#0052FF' },
  { ticker: 'HOOD',  name: 'Robinhood',          color: '#00C805' },
  { ticker: 'TEAM',  name: 'Atlassian',          color: '#2684FF' },
  { ticker: 'ZS',    name: 'Zscaler',            color: '#0075BE' },
  { ticker: 'TTD',   name: 'The Trade Desk',     color: '#2E7D32' },
  { ticker: 'CTSH',  name: 'Cognizant',          color: '#1E4471' },
  { ticker: 'IBKR',  name: 'Interactive Brokers',color: '#D3232A' },
  { ticker: 'NDAQ',  name: 'Nasdaq Inc.',        color: '#0092C5' },
  { ticker: 'BIDU',  name: 'Baidu',              color: '#2319DC' },
  { ticker: 'JD',    name: 'JD.com',             color: '#E1251B' },
  { ticker: 'NTES',  name: 'NetEase',            color: '#E60012' },
]

// NYSE 유니버스 (큐레이션, top-100 상위집합 ~116종목).
// NASDAQ-100 같은 단일 지수가 없어 NYSE 상장 대형주(금융·헬스케어·산업재·에너지·소비재 블루칩)로 구성.
// 순서는 무관 — market-cap 라우트가 라이브 시총으로 재정렬해 top-100을 뽑는다. "완전성"만 목표.
// 보통주 + 미국 상장 ADR(TSM·HSBC·BABA·TM·SHEL 등) 포함. 우선주·파생상품 제외.
// ⚠️ 외국 국적이라도 NYSE 정식 상장이면 포함 — 전부 USD 거래라 별도 FX/거래소 로직 불필요.
export const NYSE_COMPANIES: CompanyMeta[] = [
  // ── 기존 큐레이션 ──
  { ticker: 'BRK.B', name: 'Berkshire',         color: '#8B5E20' },
  { ticker: 'LLY',   name: 'Eli Lilly',         color: '#8B5CF6' },
  { ticker: 'JPM',   name: 'JPMorgan',          color: '#005EB8' },
  { ticker: 'V',     name: 'Visa',              color: '#1A1F71' },
  { ticker: 'JNJ',   name: 'J&J',               color: '#D51900' },
  { ticker: 'XOM',   name: 'ExxonMobil',        color: '#1A1A1A' },
  { ticker: 'MA',    name: 'Mastercard',        color: '#EB001B' },
  { ticker: 'ABBV',  name: 'AbbVie',            color: '#071D49' },
  { ticker: 'BAC',   name: 'Bank of America',   color: '#E31837' },
  { ticker: 'CAT',   name: 'Caterpillar',       color: '#FFCD11' },
  { ticker: 'UNH',   name: 'UnitedHealth',      color: '#002677' },
  { ticker: 'CVX',   name: 'Chevron',           color: '#0066B2' },
  { ticker: 'ORCL',  name: 'Oracle',            color: '#F80000' },
  { ticker: 'GE',    name: 'GE Aerospace',      color: '#005EB8' },
  { ticker: 'KO',    name: 'Coca-Cola',         color: '#F40000' },
  { ticker: 'PG',    name: 'P&G',               color: '#003DA5' },
  { ticker: 'MS',    name: 'Morgan Stanley',    color: '#002855' },
  { ticker: 'HD',    name: 'Home Depot',        color: '#F96302' },
  { ticker: 'GS',    name: 'Goldman Sachs',     color: '#002F6C' },
  { ticker: 'MRK',   name: 'Merck',             color: '#00857C' },
  { ticker: 'PM',    name: 'Philip Morris',     color: '#005CB9' },
  { ticker: 'RTX',   name: 'RTX',               color: '#E4002B' },
  { ticker: 'WFC',   name: 'Wells Fargo',       color: '#D71E28' },
  { ticker: 'CRM',   name: 'Salesforce',        color: '#00A1E0' },
  { ticker: 'AXP',   name: 'American Express',  color: '#006FCF' },
  { ticker: 'C',     name: 'Citigroup',         color: '#056DAE' },
  { ticker: 'MCD',   name: "McDonald's",        color: '#FFC72C' },
  { ticker: 'ACN',   name: 'Accenture',         color: '#A100FF' },
  { ticker: 'TSM',   name: 'TSMC',              color: '#0073CE' },
  { ticker: 'HSBC',  name: 'HSBC',              color: '#DB0011' },
  // ── 기술·통신·미디어 ──
  { ticker: 'IBM',   name: 'IBM',               color: '#1F70C1' },
  { ticker: 'NOW',   name: 'ServiceNow',        color: '#62D84E' },
  { ticker: 'UBER',  name: 'Uber',              color: '#000000' },
  { ticker: 'DIS',   name: 'Disney',            color: '#113CCF' },
  { ticker: 'VZ',    name: 'Verizon',           color: '#CD040B' },
  { ticker: 'T',     name: 'AT&T',              color: '#00A8E0' },
  { ticker: 'SAP',   name: 'SAP',               color: '#0FAAFF' },
  { ticker: 'BABA',  name: 'Alibaba',           color: '#FF6A00' },
  // ── 헬스케어 ──
  { ticker: 'TMO',   name: 'Thermo Fisher',     color: '#E71316' },
  { ticker: 'ABT',   name: 'Abbott',            color: '#009CDE' },
  { ticker: 'DHR',   name: 'Danaher',           color: '#0093B2' },
  { ticker: 'MDT',   name: 'Medtronic',         color: '#170F5F' },
  { ticker: 'PFE',   name: 'Pfizer',            color: '#0093D0' },
  { ticker: 'BMY',   name: 'Bristol Myers',     color: '#BE2BBB' },
  { ticker: 'CVS',   name: 'CVS Health',        color: '#CC0000' },
  { ticker: 'CI',    name: 'Cigna',             color: '#00A9E0' },
  { ticker: 'ELV',   name: 'Elevance Health',   color: '#005EB8' },
  { ticker: 'ZTS',   name: 'Zoetis',            color: '#E8450C' },
  { ticker: 'BSX',   name: 'Boston Scientific', color: '#0057B8' },
  { ticker: 'SYK',   name: 'Stryker',           color: '#FFB500' },
  { ticker: 'HCA',   name: 'HCA Healthcare',    color: '#00857E' },
  { ticker: 'NVO',   name: 'Novo Nordisk',      color: '#001965' },
  // ── 금융 ──
  { ticker: 'BLK',   name: 'BlackRock',         color: '#000000' },
  { ticker: 'SPGI',  name: 'S&P Global',        color: '#D6002A' },
  { ticker: 'BX',    name: 'Blackstone',        color: '#000000' },
  { ticker: 'SCHW',  name: 'Charles Schwab',    color: '#009FDA' },
  { ticker: 'ICE',   name: 'Intercontinental E.',color: '#002E5D' },
  { ticker: 'CB',    name: 'Chubb',             color: '#0F1E82' },
  { ticker: 'PGR',   name: 'Progressive',       color: '#0033A0' },
  { ticker: 'MMC',   name: 'Marsh McLennan',    color: '#00A0DF' },
  { ticker: 'AON',   name: 'Aon',               color: '#E4002B' },
  { ticker: 'MET',   name: 'MetLife',           color: '#0090DA' },
  { ticker: 'PRU',   name: 'Prudential',        color: '#0033A0' },
  { ticker: 'AIG',   name: 'AIG',               color: '#002F6C' },
  { ticker: 'COF',   name: 'Capital One',       color: '#004977' },
  { ticker: 'USB',   name: 'U.S. Bancorp',      color: '#0C2074' },
  { ticker: 'PNC',   name: 'PNC Financial',     color: '#F58025' },
  { ticker: 'TFC',   name: 'Truist',            color: '#52327E' },
  { ticker: 'BK',    name: 'BNY',               color: '#0072CE' },
  { ticker: 'KKR',   name: 'KKR',               color: '#000000' },
  { ticker: 'APO',   name: 'Apollo Global',     color: '#00284B' },
  // ── 소비재·소매 ──
  { ticker: 'NKE',   name: 'Nike',              color: '#111111' },
  { ticker: 'LOW',   name: "Lowe's",            color: '#004990' },
  { ticker: 'MO',    name: 'Altria',            color: '#00539B' },
  { ticker: 'TGT',   name: 'Target',            color: '#CC0000' },
  { ticker: 'CL',    name: 'Colgate-Palmolive', color: '#FF0000' },
  { ticker: 'TJX',   name: 'TJX Companies',     color: '#E31837' },
  // ── 산업재 ──
  { ticker: 'UNP',   name: 'Union Pacific',     color: '#001E62' },
  { ticker: 'UPS',   name: 'UPS',               color: '#644117' },
  { ticker: 'BA',    name: 'Boeing',            color: '#0039A6' },
  { ticker: 'LMT',   name: 'Lockheed Martin',   color: '#000000' },
  { ticker: 'DE',    name: 'Deere',             color: '#367C2B' },
  { ticker: 'GD',    name: 'General Dynamics',  color: '#002856' },
  { ticker: 'MMM',   name: '3M',                color: '#FF0000' },
  { ticker: 'ETN',   name: 'Eaton',             color: '#0072CE' },
  { ticker: 'EMR',   name: 'Emerson',           color: '#005EB8' },
  { ticker: 'NOC',   name: 'Northrop Grumman',  color: '#0067B1' },
  { ticker: 'ITW',   name: 'Illinois Tool Wks', color: '#FFD100' },
  { ticker: 'NSC',   name: 'Norfolk Southern',  color: '#000000' },
  // ── 에너지 ──
  { ticker: 'COP',   name: 'ConocoPhillips',    color: '#E01933' },
  { ticker: 'SLB',   name: 'Schlumberger',      color: '#00147E' },
  { ticker: 'EOG',   name: 'EOG Resources',     color: '#003DA5' },
  { ticker: 'WMB',   name: 'Williams',          color: '#E31837' },
  { ticker: 'OXY',   name: 'Occidental',        color: '#ED1B2E' },
  { ticker: 'KMI',   name: 'Kinder Morgan',     color: '#00457C' },
  { ticker: 'PSX',   name: 'Phillips 66',       color: '#ED1C24' },
  { ticker: 'MPC',   name: 'Marathon Petrol.',  color: '#002F6C' },
  { ticker: 'VLO',   name: 'Valero',            color: '#005CB9' },
  // ── 소재 ──
  { ticker: 'SHW',   name: 'Sherwin-Williams',  color: '#0168B3' },
  { ticker: 'APD',   name: 'Air Products',      color: '#0033A0' },
  { ticker: 'FCX',   name: 'Freeport-McMoRan',  color: '#8B5E3C' },
  { ticker: 'ECL',   name: 'Ecolab',            color: '#007AC1' },
  { ticker: 'NEM',   name: 'Newmont',           color: '#D4AF37' },
  // ── 유틸리티 ──
  { ticker: 'NEE',   name: 'NextEra Energy',    color: '#005EB8' },
  { ticker: 'SO',    name: 'Southern Co.',      color: '#00539B' },
  { ticker: 'DUK',   name: 'Duke Energy',       color: '#00789E' },
  // ── 부동산 ──
  { ticker: 'PLD',   name: 'Prologis',          color: '#E9531F' },
  { ticker: 'AMT',   name: 'American Tower',    color: '#C8102E' },
  // ── NYSE 상장 외국 ADR ──
  { ticker: 'TM',    name: 'Toyota',            color: '#EB0A1E' },
  { ticker: 'SHEL',  name: 'Shell',             color: '#FBCE07' },
  { ticker: 'TTE',   name: 'TotalEnergies',     color: '#ED0000' },
  { ticker: 'UL',    name: 'Unilever',          color: '#1F36C7' },
  { ticker: 'SONY',  name: 'Sony',              color: '#000000' },
  { ticker: 'BUD',   name: 'AB InBev',          color: '#C8102E' },
  { ticker: 'BHP',   name: 'BHP',               color: '#E35205' },
  { ticker: 'RIO',   name: 'Rio Tinto',         color: '#CC0000' },
]

// 전 US 티커 합집합 (ALL/NASDAQ/NYSE). us-stats 스냅샷 갱신 대상의 단일 소스.
export const ALL_US_TICKERS = [
  ...new Set([
    ...COMPANIES.map(c => c.ticker),
    ...NASDAQ_COMPANIES.map(c => c.ticker),
    ...NYSE_COMPANIES.map(c => c.ticker),
  ]),
]
