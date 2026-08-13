// ─── 인도 NSE 유니버스 (단일 소스) ─────────────────────────────────────────────
//
// NSE(National Stock Exchange of India, mic=XNSE) 시총 상위. 통화는 전 종목 INR 단일
// (lib/fx에 USD/INR 배선). TD 커버리지(라이브 프로브 확인): 전 종목 /statistics(INR 시총+shares)
// 와 /quote(close/prevClose) 둘 다 제공 → Euronext/중국식 라이브 스케일링(cap=statsCap×close/prevClose)
// 가능(인도 quote는 지연/EOD일 수 있어 등락은 직전영업일 기준). 시총 USD 환산은 요청 시 fx(USD/INR).
//
// TD엔 NSE 시총 스크리너가 없어 유니버스는 정적 큐레이션. 아래 심볼·회사명은 TD symbol_search로
// 전수 검증했다(mic=XNSE, currency=INR 확인). 순서 무관 — 라우트가 시총 재정렬.
// 앱 표시용 ticker = 심볼. TD 조회는 심볼+mic_code(XNSE)로 종목을 특정한다.

export interface NseCompanyMeta {
  symbol: string   // TD 심볼 (앱 표시용 ticker로도 사용)
  name:   string
  color:  string
}

// 전 종목 mic=XNSE. 라우트가 getQuote/fetchStat에 XNSE를 상수로 넘긴다.
export const NSE_MIC = 'XNSE'

export const NSE_COMPANIES: NseCompanyMeta[] = [
  { symbol: 'RELIANCE',   name: 'Reliance Ind.',   color: '#002F6C' },
  { symbol: 'TCS',        name: 'TCS',             color: '#EE3124' },
  { symbol: 'HDFCBANK',   name: 'HDFC Bank',       color: '#004C8F' },
  { symbol: 'BHARTIARTL', name: 'Bharti Airtel',   color: '#E4002B' },
  { symbol: 'ICICIBANK',  name: 'ICICI Bank',      color: '#F58220' },
  { symbol: 'INFY',       name: 'Infosys',         color: '#007CC3' },
  { symbol: 'SBIN',       name: 'State Bank India', color: '#22409A' },
  { symbol: 'LICI',       name: 'LIC',             color: '#00519E' },
  { symbol: 'ITC',        name: 'ITC',             color: '#0033A0' },
  { symbol: 'HINDUNILVR', name: 'Hind. Unilever',  color: '#00A0DF' },
  { symbol: 'LT',         name: 'Larsen & Toubro', color: '#0072BC' },
  { symbol: 'BAJFINANCE', name: 'Bajaj Finance',   color: '#003F87' },
  { symbol: 'KOTAKBANK',  name: 'Kotak Mahindra',  color: '#ED1C24' },
  { symbol: 'MARUTI',     name: 'Maruti Suzuki',   color: '#0066B3' },
  { symbol: 'SUNPHARMA',  name: 'Sun Pharma',      color: '#F26522' },
  { symbol: 'HCLTECH',    name: 'HCL Tech',        color: '#0F52BA' },
  { symbol: 'AXISBANK',   name: 'Axis Bank',       color: '#97144D' },
  { symbol: 'NTPC',       name: 'NTPC',            color: '#E4002B' },
  { symbol: 'TITAN',      name: 'Titan Company',   color: '#8A2BE2' },
  { symbol: 'ONGC',       name: 'ONGC',            color: '#E4002B' },
  { symbol: 'ADANIENT',   name: 'Adani Ent.',      color: '#0072BC' },
  { symbol: 'TATAMOTORS', name: 'Tata Motors',     color: '#0072CE' },
  { symbol: 'POWERGRID',  name: 'Power Grid',      color: '#F7941E' },
  { symbol: 'ASIANPAINT', name: 'Asian Paints',    color: '#EF3E42' },
  { symbol: 'COALINDIA',  name: 'Coal India',      color: '#1A1A1A' },
  { symbol: 'BAJAJFINSV', name: 'Bajaj Finserv',   color: '#003F87' },
  { symbol: 'WIPRO',      name: 'Wipro',           color: '#341F65' },
  { symbol: 'NESTLEIND',  name: 'Nestlé India',    color: '#63513D' },
  { symbol: 'ULTRACEMCO', name: 'UltraTech Cement', color: '#D71920' },
  { symbol: 'M&M',        name: 'Mahindra',        color: '#E31837' },
]
