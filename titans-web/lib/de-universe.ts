// ─── 독일 FWB 유니버스 (단일 소스) ───────────────────────────────────────────
//
// FWB(Deutsche Börse, mic=XETR) 시총 상위 = 독일 대표지수 DAX 40 구성종목 중심. 통화는 전 종목
// EUR 단일(lib/fx에 이미 배선 — Euronext와 공유). TD 커버리지(라이브 프로브 확인, 2026-08-14):
// 대형주 전부 /quote(close/prevClose) + /statistics(시총 EUR + shares) 둘 다 제공 →
// Euronext XPAR/XAMS식 라이브 스케일링(cap = statsCap × close/prevClose)이 전 종목 가능.
// (Euronext 밀라노(XMIL)식 quote 미제공 EOD 분기는 FWB엔 불필요 — 단일 mic·전종목 라이브.)
//
// TD엔 FWB 시총 스크리너가 없어 유니버스는 정적 큐레이션(jpx/cn/nse/eu와 동일). 아래 심볼·회사명은
// TD symbol_search로 전수 검증한다(scripts/de-validate.mjs, mic=XETR·currency=EUR 확인). 순서 무관
// — 라우트가 시총 재정렬. 앱 표시용 ticker = 심볼. TD 조회는 심볼+mic_code(XETR)로 종목을 특정한다.

export interface DeCompanyMeta {
  symbol: string   // TD 심볼 (앱 표시용 ticker로도 사용)
  name:   string
  color:  string
}

// 전 종목 mic=XETR. 라우트가 getQuote/fetchStat에 XETR를 상수로 넘긴다.
export const DE_MIC = 'XETR'

export const DE_COMPANIES: DeCompanyMeta[] = [
  { symbol: 'SAP',  name: 'SAP',                 color: '#008FD3' },
  { symbol: 'SIE',  name: 'Siemens',             color: '#009999' },
  { symbol: 'DTE',  name: 'Deutsche Telekom',    color: '#E20074' },
  { symbol: 'ALV',  name: 'Allianz',             color: '#003781' },
  { symbol: 'MUV2', name: 'Munich Re',           color: '#00437B' },
  { symbol: 'MBG',  name: 'Mercedes-Benz',       color: '#1A1A1A' },
  { symbol: 'BMW',  name: 'BMW',                 color: '#0066B1' },
  { symbol: 'IFX',  name: 'Infineon',            color: '#004A96' },
  { symbol: 'BAS',  name: 'BASF',                color: '#004A96' },
  { symbol: 'ADS',  name: 'Adidas',              color: '#000000' },
  { symbol: 'DBK',  name: 'Deutsche Bank',       color: '#0018A8' },
  { symbol: 'DHL',  name: 'DHL Group',           color: '#FFCC00' },
  { symbol: 'DB1',  name: 'Deutsche Börse',      color: '#003366' },
  { symbol: 'SHL',  name: 'Siemens Healthineers', color: '#00646E' },
  { symbol: 'ENR',  name: 'Siemens Energy',      color: '#1B1534' },
  { symbol: 'RHM',  name: 'Rheinmetall',         color: '#004B32' },
  { symbol: 'VOW3', name: 'Volkswagen',          color: '#001E50' },
  { symbol: 'P911', name: 'Porsche AG',          color: '#B12B28' },
  { symbol: 'PAH3', name: 'Porsche SE',          color: '#B12B28' },
  { symbol: 'MRK',  name: 'Merck KGaA',          color: '#EB3C96' },
  { symbol: 'RWE',  name: 'RWE',                 color: '#1D3A8F' },
  { symbol: 'EOAN', name: 'E.ON',                color: '#E2001A' },
  { symbol: 'BAYN', name: 'Bayer',               color: '#89D329' },
  { symbol: 'DTG',  name: 'Daimler Truck',       color: '#00677F' },
  { symbol: 'MTX',  name: 'MTU Aero Engines',    color: '#004F9F' },
  { symbol: 'HEI',  name: 'Heidelberg Materials', color: '#005CA9' },
  { symbol: 'HNR1', name: 'Hannover Rück',       color: '#003781' },
  { symbol: 'BEI',  name: 'Beiersdorf',          color: '#003C7D' },
  { symbol: 'HEN3', name: 'Henkel',              color: '#E1000F' },
  { symbol: 'VNA',  name: 'Vonovia',             color: '#00A0AF' },
  { symbol: 'CBK',  name: 'Commerzbank',         color: '#FFCC00' },
  { symbol: 'SY1',  name: 'Symrise',             color: '#00975F' },
  { symbol: 'FRE',  name: 'Fresenius',           color: '#0069B4' },
  { symbol: 'CON',  name: 'Continental',         color: '#FFA500' },
  { symbol: 'QIA',  name: 'Qiagen',              color: '#005B94' },
  { symbol: 'BNR',  name: 'Brenntag',            color: '#005AA0' },
  { symbol: 'SRT3', name: 'Sartorius',           color: '#FFED00' },
  { symbol: 'ZAL',  name: 'Zalando',             color: '#FF6900' },
  { symbol: 'AIR',  name: 'Airbus',              color: '#00205B' },
]
