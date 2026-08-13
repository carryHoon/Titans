// ─── Euronext 유니버스 (단일 소스) ─────────────────────────────────────────────
//
// Euronext 섹션 = 파리(XPAR)+암스테르담(XAMS)+밀라노(XMIL/Borsa Italiana) 시총 상위 통합.
// 전부 유로존이라 통화는 EUR 단일(lib/fx에 이미 배선). TD 커버리지(라이브 프로브 확인):
//   · XPAR/XAMS : /quote(라이브 가격) + /statistics(시총) 둘 다 제공 → 라이브 스케일링 가능
//   · XMIL      : /quote 미제공, /statistics만 제공 → JPX식 EOD(스케일링 없이 stats 시총)
// 엔진(eu-snapshot + route.handleEuExchange)은 종목별로 quote가 있으면 라이브 스케일링하고,
// 없으면(밀라노) stats 시총을 그대로 쓴다. 시총 USD 환산은 요청 시점에 fx(EUR/USD)로 한다.
//
// TD엔 Euronext 시총 스크리너가 없어 유니버스는 정적 큐레이션. 아래 65종목은 심볼·mic·회사명을
// TD symbol_search로 전수 검증했다(scripts/eu-validate.mjs). 순서 무관 — 라우트가 시총 재정렬.
// 앱 표시용 ticker = 심볼(우리 셋에서 유일). TD 조회는 심볼+mic_code로 종목을 특정한다.

export interface EuCompanyMeta {
  symbol: string   // TD 심볼 (앱 표시용 ticker로도 사용)
  mic:    string   // 'XPAR' | 'XAMS' | 'XMIL' — TD disambiguation(mic_code)
  name:   string
  color:  string
}

export const EU_COMPANIES: EuCompanyMeta[] = [
  // ── Paris (XPAR) ──
  { symbol: 'MC',    mic: 'XPAR', name: 'LVMH',              color: '#4A2C1A' },
  { symbol: 'OR',    mic: 'XPAR', name: "L'Oréal",           color: '#000000' },
  { symbol: 'RMS',   mic: 'XPAR', name: 'Hermès',            color: '#FF7300' },
  { symbol: 'TTE',   mic: 'XPAR', name: 'TotalEnergies',     color: '#ED0000' },
  { symbol: 'SAN',   mic: 'XPAR', name: 'Sanofi',            color: '#7A00E6' },
  { symbol: 'AI',    mic: 'XPAR', name: 'Air Liquide',       color: '#004A98' },
  { symbol: 'SU',    mic: 'XPAR', name: 'Schneider Elec.',   color: '#3DCD58' },
  { symbol: 'EL',    mic: 'XPAR', name: 'EssilorLuxottica',  color: '#003DA5' },
  { symbol: 'AIR',   mic: 'XPAR', name: 'Airbus',            color: '#00205B' },
  { symbol: 'CDI',   mic: 'XPAR', name: 'Christian Dior',    color: '#1A1A1A' },
  { symbol: 'BNP',   mic: 'XPAR', name: 'BNP Paribas',       color: '#00915A' },
  { symbol: 'DG',    mic: 'XPAR', name: 'Vinci',             color: '#005EB8' },
  { symbol: 'SAF',   mic: 'XPAR', name: 'Safran',            color: '#003A70' },
  { symbol: 'CS',    mic: 'XPAR', name: 'AXA',               color: '#00008F' },
  { symbol: 'KER',   mic: 'XPAR', name: 'Kering',            color: '#000000' },
  { symbol: 'BN',    mic: 'XPAR', name: 'Danone',            color: '#005CA9' },
  { symbol: 'RI',    mic: 'XPAR', name: 'Pernod Ricard',     color: '#B8860B' },
  { symbol: 'CAP',   mic: 'XPAR', name: 'Capgemini',         color: '#0070AD' },
  { symbol: 'ACA',   mic: 'XPAR', name: 'Crédit Agricole',   color: '#009597' },
  { symbol: 'GLE',   mic: 'XPAR', name: 'Société Générale',  color: '#E60028' },
  { symbol: 'ENGI',  mic: 'XPAR', name: 'Engie',             color: '#00AAFF' },
  { symbol: 'ML',    mic: 'XPAR', name: 'Michelin',          color: '#27509B' },
  { symbol: 'ORA',   mic: 'XPAR', name: 'Orange',            color: '#FF7900' },
  { symbol: 'PUB',   mic: 'XPAR', name: 'Publicis',          color: '#00004B' },
  { symbol: 'LR',    mic: 'XPAR', name: 'Legrand',           color: '#E2001A' },
  { symbol: 'VIE',   mic: 'XPAR', name: 'Veolia',            color: '#00AEC7' },
  { symbol: 'HO',    mic: 'XPAR', name: 'Thales',            color: '#005A9C' },
  { symbol: 'DSY',   mic: 'XPAR', name: 'Dassault Sys.',     color: '#005386' },
  { symbol: 'RNO',   mic: 'XPAR', name: 'Renault',           color: '#FFCC33' },
  { symbol: 'SGO',   mic: 'XPAR', name: 'Saint-Gobain',      color: '#0067B1' },
  { symbol: 'STMPA', mic: 'XPAR', name: 'STMicro',           color: '#03234B' },
  { symbol: 'EN',    mic: 'XPAR', name: 'Bouygues',          color: '#009EE0' },
  // ── Amsterdam (XAMS) ──
  { symbol: 'ASML',  mic: 'XAMS', name: 'ASML',              color: '#0B5394' },
  { symbol: 'PRX',   mic: 'XAMS', name: 'Prosus',            color: '#EF3E42' },
  { symbol: 'ADYEN', mic: 'XAMS', name: 'Adyen',             color: '#0ABF53' },
  { symbol: 'HEIA',  mic: 'XAMS', name: 'Heineken',          color: '#008200' },
  { symbol: 'UMG',   mic: 'XAMS', name: 'Universal Music',   color: '#000000' },
  { symbol: 'ASM',   mic: 'XAMS', name: 'ASM Intl',          color: '#005EB8' },
  { symbol: 'WKL',   mic: 'XAMS', name: 'Wolters Kluwer',    color: '#E5202E' },
  { symbol: 'PHIA',  mic: 'XAMS', name: 'Philips',           color: '#0B5ED7' },
  { symbol: 'INGA',  mic: 'XAMS', name: 'ING',               color: '#FF6200' },
  { symbol: 'AD',    mic: 'XAMS', name: 'Ahold Delhaize',    color: '#007D40' },
  { symbol: 'EXO',   mic: 'XAMS', name: 'Exor',              color: '#1A1A1A' },
  { symbol: 'AKZA',  mic: 'XAMS', name: 'Akzo Nobel',        color: '#0033A0' },
  { symbol: 'NN',    mic: 'XAMS', name: 'NN Group',          color: '#EE7203' },
  { symbol: 'ABN',   mic: 'XAMS', name: 'ABN AMRO',          color: '#004C3F' },
  { symbol: 'KPN',   mic: 'XAMS', name: 'KPN',               color: '#00C300' },
  { symbol: 'DSFIR', mic: 'XAMS', name: 'DSM-Firmenich',     color: '#5B2A86' },
  // ── Milan (XMIL) — quote 미제공, stats(EOD)만 ──
  { symbol: 'RACE',  mic: 'XMIL', name: 'Ferrari',           color: '#DC0000' },
  { symbol: 'ENEL',  mic: 'XMIL', name: 'Enel',              color: '#0072CE' },
  { symbol: 'ISP',   mic: 'XMIL', name: 'Intesa Sanpaolo',   color: '#007A33' },
  { symbol: 'UCG',   mic: 'XMIL', name: 'UniCredit',         color: '#E4002B' },
  { symbol: 'G',     mic: 'XMIL', name: 'Generali',          color: '#C8102E' },
  { symbol: 'STLAM', mic: 'XMIL', name: 'Stellantis',        color: '#1A1A1A' },
  { symbol: 'ENI',   mic: 'XMIL', name: 'Eni',               color: '#FCE500' },
  { symbol: 'TIT',   mic: 'XMIL', name: 'Telecom Italia',    color: '#E4002B' },
  { symbol: 'PST',   mic: 'XMIL', name: 'Poste Italiane',    color: '#003DA5' },
  { symbol: 'SRG',   mic: 'XMIL', name: 'Snam',              color: '#003DA5' },
  { symbol: 'MB',    mic: 'XMIL', name: 'Mediobanca',        color: '#B01E28' },
  { symbol: 'BAMI',  mic: 'XMIL', name: 'Banco BPM',         color: '#009640' },
  { symbol: 'TRN',   mic: 'XMIL', name: 'Terna',             color: '#EE7203' },
  { symbol: 'MONC',  mic: 'XMIL', name: 'Moncler',           color: '#1A1A1A' },
  { symbol: 'PIRC',  mic: 'XMIL', name: 'Pirelli',           color: '#FFCC00' },
  { symbol: 'CPR',   mic: 'XMIL', name: 'Campari',           color: '#E4002B' },
  { symbol: 'LDO',   mic: 'XMIL', name: 'Leonardo',          color: '#1A1A1A' },
]
