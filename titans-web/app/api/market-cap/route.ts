import { NextResponse } from 'next/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const FINNHUB_TOKEN = process.env.FINNHUB_API_KEY ?? ''
const BASE = 'https://finnhub.io/api/v1'
const OXR_APP_ID = process.env.OPEN_EXCHANGE_RATES_APP_ID ?? ''
// 환율 폴백 (통화당 USD). OXR 장애 시 마지막 성공값(lastGoodForex)이 없을 때만 사용.
const FOREX_FALLBACK = 1450.0   // KRW/USD
const JPY_FALLBACK   = 155.0    // JPY/USD — JPX 시총 환산용
const CNY_FALLBACK   = 7.2      // CNY/USD — SSE 시총 환산용

// FMP(Financial Modeling Prep) — 나스닥 시총 상위 '티커 목록'만 동적으로 확보.
// 실시간 시세는 Finnhub가 담당하고, FMP는 유니버스(어떤 종목이 상위인지)만 제공.
// 시총 순위는 하루 안에 거의 바뀌지 않으므로 1시간 캐시 → FMP 무료(250콜/일) 안에서 여유.
const FMP_API_KEY  = process.env.FMP_API_KEY ?? ''
const FMP_SCREENER = 'https://financialmodelingprep.com/api/v3/stock-screener'
const EXCHANGE_UNIVERSE_TTL_MS = 60 * 60 * 1000  // 1시간
const EXCHANGE_UNIVERSE_SIZE   = 25              // Finnhub 라이브 재정렬 버퍼 (top-20 + 예비 5)

// TSM ADR: 1 ADR = 5 대만 보통주. Finnhub shareOutstanding은 보통주 수(millions)이므로
// 시총 = shareOutstanding / ADR_RATIO × ADR가격(USD) / 1_000_000 으로 실시간 계산
const TSM_ADR_RATIO = 5

// 미국 종목 시총은 라이브가로 재계산(shareOutstanding × 현재가)해 KRX(21초)와 신선도를 맞춘다.
// 단 Finnhub의 shareOutstanding이 부실한 종목(예: BRK.B=1.44M)이 있어, 라이브 재계산값이
// 사전계산 marketCapitalization과 크게 어긋나면 사전계산값으로 폴백한다.
const MCAP_LIVE_TRUST_MIN = 0.5
const MCAP_LIVE_TRUST_MAX = 2.0

const BATCH_SIZE     = 5
const BATCH_DELAY_MS = 200

// Aramco: Tadawul(사우디 증권거래소) 상장, SAR 표시가. 사우디 법정 고정환율 적용.
const ARAMCO_SAR_PER_USD = 3.75
const ARAMCO_META: CompanyMeta = { ticker: '2222.SR', name: 'Saudi Aramco', color: '#007A3D' }

// ⚠️ SpaceX: 실제로는 비상장(private) 기업이라 나스닥 등 어떤 거래소에도 상장돼 있지 않고,
// Finnhub/FMP에 SPCX 티커도 존재하지 않는다. 사용자 요청으로 나스닥 섹션에만 노출하되
// 실시간 시세가 없으므로 최근 보도된 비상장 추정 기업가치를 수동 입력한다(라이브 데이터 아님).
const SPACEX_META: CompanyMeta = { ticker: 'SPCX', name: 'SpaceX', color: '#005288' }
const SPACEX_EST_MARKETCAP_USD_T = 0.4  // 약 $400B — 2025년 보도 기준 추정치

const COMPANIES: CompanyMeta[] = [
  // Top 10
  { ticker: 'NVDA',  name: 'NVIDIA',       color: '#78BB17' },
  { ticker: 'AAPL',  name: 'Apple',        color: '#8E8E93' },
  { ticker: 'MSFT',  name: 'Microsoft',    color: '#0078D4' },
  { ticker: 'GOOGL', name: 'Alphabet',     color: '#EA4335' },
  { ticker: 'AMZN',  name: 'Amazon',       color: '#FF9900' },
  { ticker: 'META',  name: 'Meta',         color: '#4267B2' },
  { ticker: 'TSLA',  name: 'Tesla',        color: '#CC1C1C' },
  { ticker: 'BRK.B', name: 'Berkshire',    color: '#8B5E20' },
  { ticker: 'AVGO',  name: 'Broadcom',     color: '#CC0000' },
  { ticker: 'JPM',   name: 'JPMorgan',     color: '#005EB8' },
  // 글로벌 (ADR 포함)
  { ticker: 'TSM',   name: 'TSMC',         color: '#0073CE' },
  // 11–20위 권 (미국 상장)
  { ticker: 'LLY',   name: 'Eli Lilly',    color: '#8B5CF6' },
  { ticker: 'WMT',   name: 'Walmart',      color: '#007DC6' },
  { ticker: 'V',     name: 'Visa',         color: '#1A1F71' },
  { ticker: 'ORCL',  name: 'Oracle',       color: '#F80000' },
  { ticker: 'XOM',   name: 'ExxonMobil',   color: '#1A1A1A' },
  { ticker: 'MA',    name: 'Mastercard',   color: '#EB001B' },
  { ticker: 'COST',  name: 'Costco',       color: '#005DAA' },
  { ticker: 'NFLX',  name: 'Netflix',      color: '#E50914' },
  { ticker: 'UNH',   name: 'UnitedHealth', color: '#002677' },
  { ticker: 'PLTR',  name: 'Palantir',     color: '#101828' },
  { ticker: 'SPCX',  name: 'SpaceX',       color: '#005288' },
  { ticker: 'AMD',   name: 'AMD',          color: '#ED1C24' },
  { ticker: 'MU',    name: 'Micron',       color: '#00AEEF' },
]

// NASDAQ 정적 폴백 유니버스 — 평소엔 FMP 스크리너로 동적 확보하고,
// FMP 키 미설정/장애 시 이 리스트로 폴백해 나스닥 섹션 top-20을 계산.
// ALL top-20(글로벌)과 종목이 겹치는 것은 정상(섹션 간 중복 허용).
const NASDAQ_COMPANIES: CompanyMeta[] = [
  { ticker: 'NVDA',  name: 'NVIDIA',            color: '#78BB17' },
  { ticker: 'AAPL',  name: 'Apple',             color: '#8E8E93' },
  { ticker: 'MSFT',  name: 'Microsoft',         color: '#0078D4' },
  { ticker: 'GOOGL', name: 'Alphabet',          color: '#EA4335' },
  { ticker: 'AMZN',  name: 'Amazon',            color: '#FF9900' },
  { ticker: 'META',  name: 'Meta',              color: '#4267B2' },
  { ticker: 'AVGO',  name: 'Broadcom',          color: '#CC0000' },
  { ticker: 'TSLA',  name: 'Tesla',             color: '#CC1C1C' },
  { ticker: 'NFLX',  name: 'Netflix',           color: '#E50914' },
  { ticker: 'COST',  name: 'Costco',            color: '#005DAA' },
  { ticker: 'PLTR',  name: 'Palantir',          color: '#101828' },
  { ticker: 'AMD',   name: 'AMD',               color: '#ED1C24' },
  { ticker: 'CSCO',  name: 'Cisco',             color: '#1BA0D7' },
  { ticker: 'ADBE',  name: 'Adobe',             color: '#FA0F00' },
  { ticker: 'TMUS',  name: 'T-Mobile',          color: '#E20074' },
  { ticker: 'INTU',  name: 'Intuit',            color: '#365EBF' },
  { ticker: 'QCOM',  name: 'Qualcomm',          color: '#3253DC' },
  { ticker: 'AMAT',  name: 'Applied Materials', color: '#1A6DB4' },
  { ticker: 'TXN',   name: 'Texas Instruments', color: '#CC0000' },
  { ticker: 'AMGN',  name: 'Amgen',             color: '#0063C3' },
  { ticker: 'ISRG',  name: 'Intuitive Surgical',color: '#486B92' },
  { ticker: 'BKNG',  name: 'Booking',           color: '#003580' },
  { ticker: 'GILD',  name: 'Gilead',            color: '#C8102E' },
  { ticker: 'MU',    name: 'Micron',            color: '#00AEEF' },
]

// NYSE 정적 폴백 유니버스 — NASDAQ과 동일하게 FMP 스크리너 실패 시 폴백.
const NYSE_COMPANIES: CompanyMeta[] = [
  { ticker: 'BRK.B', name: 'Berkshire',        color: '#8B5E20' },
  { ticker: 'JPM',   name: 'JPMorgan',         color: '#005EB8' },
  { ticker: 'LLY',   name: 'Eli Lilly',        color: '#8B5CF6' },
  { ticker: 'V',     name: 'Visa',             color: '#1A1F71' },
  { ticker: 'WMT',   name: 'Walmart',          color: '#007DC6' },
  { ticker: 'ORCL',  name: 'Oracle',           color: '#F80000' },
  { ticker: 'MA',    name: 'Mastercard',       color: '#EB001B' },
  { ticker: 'XOM',   name: 'ExxonMobil',       color: '#1A1A1A' },
  { ticker: 'UNH',   name: 'UnitedHealth',     color: '#002677' },
  { ticker: 'JNJ',   name: 'J&J',              color: '#D51900' },
  { ticker: 'HD',    name: 'Home Depot',       color: '#F96302' },
  { ticker: 'PG',    name: 'P&G',              color: '#003DA5' },
  { ticker: 'ABBV',  name: 'AbbVie',           color: '#071D49' },
  { ticker: 'KO',    name: 'Coca-Cola',        color: '#F40000' },
  { ticker: 'BAC',   name: 'Bank of America',  color: '#E31837' },
  { ticker: 'CVX',   name: 'Chevron',          color: '#0066B2' },
  { ticker: 'CRM',   name: 'Salesforce',       color: '#00A1E0' },
  { ticker: 'WFC',   name: 'Wells Fargo',      color: '#D71E28' },
  { ticker: 'MRK',   name: 'Merck',            color: '#00857C' },
  { ticker: 'ACN',   name: 'Accenture',        color: '#A100FF' },
  { ticker: 'MCD',   name: "McDonald's",       color: '#FFC72C' },
  { ticker: 'TSM',   name: 'TSMC',             color: '#0073CE' },
]

// 큐레이션된 메타(짧은 이름 + 브랜드 색) 조회용. FMP 결과 중 아는 티커는 이걸 재사용하고,
// 모르는 티커는 FMP 이름 + 해시 기반 색으로 대체한다. (iOS 로고는 도메인 미등록 시 이니셜 폴백)
const KNOWN_META: Record<string, CompanyMeta> = Object.fromEntries(
  [...COMPANIES, ...NASDAQ_COMPANIES, ...NYSE_COMPANIES].map(c => [c.ticker, c]),
)

// KRX(한국거래소) 상장 종목 — Yahoo Finance v7 JSON API 경유
// Finnhub 무료 플랜은 KRX 미지원
interface KoreanStockMeta {
  ticker: string
  yahooTicker: string
  name: string
  color: string
}

const KOREAN_STOCKS: KoreanStockMeta[] = [
  { ticker: '005930.KS', yahooTicker: '005930.KS', name: 'Samsung',  color: '#1428A0' },
  { ticker: '000660.KS', yahooTicker: '000660.KS', name: 'SK Hynix', color: '#EA5504' },
]

// KOSPI 시총 상위 종목 (하드코딩 유니버스, 우선주 제외).
// 순위는 하루 안에 거의 안 바뀌므로 정적 관리 → API 콜 절약. 시세/시총만 Naver로 라이브 갱신.
// Finnhub 무료 플랜은 KRX 미지원이라 미국 거래소와 달리 Naver Finance를 사용.
const KOSPI_COMPANIES: KoreanStockMeta[] = [
  { ticker: '005930.KS', yahooTicker: '005930.KS', name: 'Samsung Elec.',    color: '#1428A0' },
  { ticker: '000660.KS', yahooTicker: '000660.KS', name: 'SK Hynix',         color: '#EA5504' },
  { ticker: '402340.KS', yahooTicker: '402340.KS', name: 'SK Square',        color: '#E4002B' },
  { ticker: '009150.KS', yahooTicker: '009150.KS', name: 'Samsung EM',       color: '#1428A0' },
  { ticker: '005380.KS', yahooTicker: '005380.KS', name: 'Hyundai Motor',    color: '#002C5F' },
  { ticker: '373220.KS', yahooTicker: '373220.KS', name: 'LG Energy Sol.',   color: '#A50034' },
  { ticker: '032830.KS', yahooTicker: '032830.KS', name: 'Samsung Life',     color: '#1428A0' },
  { ticker: '207940.KS', yahooTicker: '207940.KS', name: 'Samsung Bio.',     color: '#1428A0' },
  { ticker: '105560.KS', yahooTicker: '105560.KS', name: 'KB Financial',     color: '#FFB819' },
  { ticker: '028260.KS', yahooTicker: '028260.KS', name: 'Samsung C&T',      color: '#1428A0' },
  { ticker: '000270.KS', yahooTicker: '000270.KS', name: 'Kia',              color: '#05141F' },
  { ticker: '055550.KS', yahooTicker: '055550.KS', name: 'Shinhan Fin.',     color: '#0046FF' },
  { ticker: '329180.KS', yahooTicker: '329180.KS', name: 'HD Hyundai HI',    color: '#00A0B0' },
  { ticker: '012330.KS', yahooTicker: '012330.KS', name: 'Hyundai Mobis',    color: '#002C5F' },
  { ticker: '012450.KS', yahooTicker: '012450.KS', name: 'Hanwha Aero.',     color: '#F37021' },
  { ticker: '034730.KS', yahooTicker: '034730.KS', name: 'SK Inc.',          color: '#E4002B' },
  { ticker: '034020.KS', yahooTicker: '034020.KS', name: 'Doosan Enerb.',    color: '#00A9CE' },
  { ticker: '068270.KS', yahooTicker: '068270.KS', name: 'Celltrion',        color: '#00A6D6' },
  { ticker: '086790.KS', yahooTicker: '086790.KS', name: 'Hana Financial',   color: '#008485' },
  { ticker: '006400.KS', yahooTicker: '006400.KS', name: 'Samsung SDI',      color: '#1428A0' },
]

// KOSDAQ 시총 상위 종목 (하드코딩 유니버스). KOSPI와 동일하게 Naver로 라이브 갱신.
// Naver 조회는 거래소 구분 없이 6자리 종목코드만 사용하므로 로직은 KOSPI와 공유.
const KOSDAQ_COMPANIES: KoreanStockMeta[] = [
  { ticker: '196170.KQ', yahooTicker: '196170.KQ', name: 'Alteogen',         color: '#0067AC' },
  { ticker: '247540.KQ', yahooTicker: '247540.KQ', name: 'Ecopro BM',        color: '#008C44' },
  { ticker: '086520.KQ', yahooTicker: '086520.KQ', name: 'Ecopro',           color: '#008C44' },
  { ticker: '277810.KQ', yahooTicker: '277810.KQ', name: 'Rainbow Robotics', color: '#2D2D2D' },
  { ticker: '036930.KQ', yahooTicker: '036930.KQ', name: 'Jusung Eng.',      color: '#004C97' },
  { ticker: '240810.KQ', yahooTicker: '240810.KQ', name: 'Wonik IPS',        color: '#0091D0' },
  { ticker: '058470.KQ', yahooTicker: '058470.KQ', name: 'Leeno Ind.',       color: '#E60012' },
  { ticker: '319660.KQ', yahooTicker: '319660.KQ', name: 'PSK',              color: '#005BAC' },
  { ticker: '298380.KQ', yahooTicker: '298380.KQ', name: 'ABL Bio',          color: '#00A651' },
  { ticker: '039030.KQ', yahooTicker: '039030.KQ', name: 'EO Technics',      color: '#003DA5' },
  { ticker: '028300.KQ', yahooTicker: '028300.KQ', name: 'HLB',              color: '#00A650' },
  { ticker: '222800.KQ', yahooTicker: '222800.KQ', name: 'Simmtech',         color: '#005EAB' },
  { ticker: '000250.KQ', yahooTicker: '000250.KQ', name: 'Samchundang',      color: '#0068B7' },
  { ticker: '440110.KQ', yahooTicker: '440110.KQ', name: 'FADU',             color: '#1A1A1A' },
  { ticker: '141080.KQ', yahooTicker: '141080.KQ', name: 'LigaChem Bio',     color: '#0075C1' },
  { ticker: '214450.KQ', yahooTicker: '214450.KQ', name: 'Pharma Research',  color: '#00953A' },
  { ticker: '108490.KQ', yahooTicker: '108490.KQ', name: 'Robotis',          color: '#EE2E24' },
  { ticker: '403870.KQ', yahooTicker: '403870.KQ', name: 'HPSP',             color: '#005BAC' },
  { ticker: '095610.KQ', yahooTicker: '095610.KQ', name: 'Tes',              color: '#004EA2' },
  { ticker: '095340.KQ', yahooTicker: '095340.KQ', name: 'ISC',              color: '#0060A9' },
]

// JPX(도쿄)·SSE(상하이) 종목도 KoreanStockMeta와 동일 형태(티커/야후티커/이름/색)를 쓴다.
// Finnhub 무료 플랜은 JPX/SSE 미지원 → KRX처럼 Yahoo Finance HTML로 시세/시총을 확보.
type ForeignStockMeta = KoreanStockMeta

// JPX(도쿄증권거래소) 시총 상위 종목 (하드코딩 유니버스). Yahoo `.T` 심볼 사용.
// marketCap은 JPY 단위 → forex.jpy(JPY/USD)로 나눠 USD 환산.
const JPX_COMPANIES: ForeignStockMeta[] = [
  { ticker: '7203.T', yahooTicker: '7203.T', name: 'Toyota',          color: '#EB0A1E' },
  { ticker: '8306.T', yahooTicker: '8306.T', name: 'Mitsubishi UFJ',  color: '#E60000' },
  { ticker: '6758.T', yahooTicker: '6758.T', name: 'Sony',            color: '#000000' },
  { ticker: '6861.T', yahooTicker: '6861.T', name: 'Keyence',         color: '#003DA5' },
  { ticker: '9984.T', yahooTicker: '9984.T', name: 'SoftBank Group',  color: '#EF3E42' },
  { ticker: '9983.T', yahooTicker: '9983.T', name: 'Fast Retailing',  color: '#FF0000' },
  { ticker: '6098.T', yahooTicker: '6098.T', name: 'Recruit',         color: '#FF7A00' },
  { ticker: '8035.T', yahooTicker: '8035.T', name: 'Tokyo Electron',  color: '#003399' },
  { ticker: '4063.T', yahooTicker: '4063.T', name: 'Shin-Etsu Chem.', color: '#005BAC' },
  { ticker: '9432.T', yahooTicker: '9432.T', name: 'NTT',             color: '#2C4B9B' },
  { ticker: '6501.T', yahooTicker: '6501.T', name: 'Hitachi',         color: '#E60027' },
  { ticker: '7974.T', yahooTicker: '7974.T', name: 'Nintendo',        color: '#E60012' },
  { ticker: '8058.T', yahooTicker: '8058.T', name: 'Mitsubishi Corp', color: '#E60012' },
  { ticker: '8001.T', yahooTicker: '8001.T', name: 'Itochu',          color: '#0068B7' },
  { ticker: '6902.T', yahooTicker: '6902.T', name: 'Denso',           color: '#E60027' },
  { ticker: '4519.T', yahooTicker: '4519.T', name: 'Chugai Pharma',   color: '#003F98' },
  { ticker: '6367.T', yahooTicker: '6367.T', name: 'Daikin',          color: '#0097E0' },
  { ticker: '8316.T', yahooTicker: '8316.T', name: 'Sumitomo Mitsui', color: '#00A040' },
  { ticker: '7267.T', yahooTicker: '7267.T', name: 'Honda',           color: '#E60012' },
  { ticker: '6594.T', yahooTicker: '6594.T', name: 'Nidec',           color: '#004098' },
]

// SSE(상하이증권거래소) 시총 상위 종목 (하드코딩 유니버스). Yahoo `.SS` 심볼 사용.
// marketCap은 CNY 단위 → forex.cny(CNY/USD)로 나눠 USD 환산.
const SSE_COMPANIES: ForeignStockMeta[] = [
  { ticker: '600519.SS', yahooTicker: '600519.SS', name: 'Kweichow Moutai', color: '#A5122A' },
  { ticker: '601398.SS', yahooTicker: '601398.SS', name: 'ICBC',            color: '#C7000B' },
  { ticker: '600941.SS', yahooTicker: '600941.SS', name: 'China Mobile',    color: '#005BAC' },
  { ticker: '601288.SS', yahooTicker: '601288.SS', name: 'Agric. Bank',     color: '#00954C' },
  { ticker: '601857.SS', yahooTicker: '601857.SS', name: 'PetroChina',      color: '#E60012' },
  { ticker: '601988.SS', yahooTicker: '601988.SS', name: 'Bank of China',   color: '#AF1E24' },
  { ticker: '600036.SS', yahooTicker: '600036.SS', name: 'China Merch. Bk', color: '#C60C1E' },
  { ticker: '601318.SS', yahooTicker: '601318.SS', name: 'Ping An',         color: '#F26A21' },
  { ticker: '601628.SS', yahooTicker: '601628.SS', name: 'China Life',      color: '#C8161D' },
  { ticker: '600900.SS', yahooTicker: '600900.SS', name: 'Yangtze Power',   color: '#1E88C7' },
  { ticker: '600028.SS', yahooTicker: '600028.SS', name: 'Sinopec',         color: '#E60012' },
  { ticker: '601088.SS', yahooTicker: '601088.SS', name: 'China Shenhua',   color: '#C7000B' },
  { ticker: '600030.SS', yahooTicker: '600030.SS', name: 'CITIC Sec.',      color: '#C8161D' },
  { ticker: '603288.SS', yahooTicker: '603288.SS', name: 'Foshan Haitian',  color: '#C8161D' },
  { ticker: '600276.SS', yahooTicker: '600276.SS', name: 'Hengrui Pharma',  color: '#0096D6' },
  { ticker: '601668.SS', yahooTicker: '601668.SS', name: 'China State Cons.',color: '#C8161D' },
  { ticker: '688981.SS', yahooTicker: '688981.SS', name: 'SMIC',            color: '#00539B' },
  { ticker: '601166.SS', yahooTicker: '601166.SS', name: 'Industrial Bank', color: '#1C4E9D' },
  { ticker: '600887.SS', yahooTicker: '600887.SS', name: 'Yili',            color: '#0066B3' },
  { ticker: '600809.SS', yahooTicker: '600809.SS', name: 'Shanxi Fenjiu',   color: '#A5122A' },
]

// SZSE(선전증권거래소) 시총 상위 종목 (하드코딩 유니버스). Yahoo `.SZ` 심볼 사용.
// marketCap은 CNY 단위 → SSE와 동일하게 forex.cny로 USD 환산.
const SZSE_COMPANIES: ForeignStockMeta[] = [
  { ticker: '300750.SZ', yahooTicker: '300750.SZ', name: 'CATL',            color: '#00A03E' },
  { ticker: '000858.SZ', yahooTicker: '000858.SZ', name: 'Wuliangye',       color: '#C8161D' },
  { ticker: '002594.SZ', yahooTicker: '002594.SZ', name: 'BYD',             color: '#E60012' },
  { ticker: '000333.SZ', yahooTicker: '000333.SZ', name: 'Midea Group',     color: '#1A5CB4' },
  { ticker: '000651.SZ', yahooTicker: '000651.SZ', name: 'Gree Electric',   color: '#005BAC' },
  { ticker: '002415.SZ', yahooTicker: '002415.SZ', name: 'Hikvision',       color: '#E60012' },
  { ticker: '300760.SZ', yahooTicker: '300760.SZ', name: 'Mindray',         color: '#00539B' },
  { ticker: '000001.SZ', yahooTicker: '000001.SZ', name: 'Ping An Bank',    color: '#F26A21' },
  { ticker: '002714.SZ', yahooTicker: '002714.SZ', name: 'Muyuan Foods',    color: '#009944' },
  { ticker: '300059.SZ', yahooTicker: '300059.SZ', name: 'East Money',      color: '#E60012' },
  { ticker: '002475.SZ', yahooTicker: '002475.SZ', name: 'Luxshare',        color: '#004098' },
  { ticker: '000568.SZ', yahooTicker: '000568.SZ', name: 'Luzhou Laojiao',  color: '#B01F24' },
  { ticker: '002304.SZ', yahooTicker: '002304.SZ', name: 'Yanghe Brewery',  color: '#1E5EA8' },
  { ticker: '300124.SZ', yahooTicker: '300124.SZ', name: 'Inovance',        color: '#005BAC' },
  { ticker: '002352.SZ', yahooTicker: '002352.SZ', name: 'SF Holding',      color: '#000000' },
  { ticker: '300015.SZ', yahooTicker: '300015.SZ', name: 'Aier Eye',        color: '#009944' },
  { ticker: '000725.SZ', yahooTicker: '000725.SZ', name: 'BOE Tech.',       color: '#1A9AD6' },
  { ticker: '002230.SZ', yahooTicker: '002230.SZ', name: 'iFlytek',         color: '#E60012' },
  { ticker: '300274.SZ', yahooTicker: '300274.SZ', name: 'Sungrow Power',   color: '#E60012' },
  { ticker: '002460.SZ', yahooTicker: '002460.SZ', name: 'Ganfeng Lithium', color: '#00954C' },
]

// Finnhub 무료: 60 calls/min
// Quote 5개씩 배치(200ms 딜레이), 21초 캐시 → burst rate limit 방지 ✓
// Profile 1시간 캐시 → 서버 재시작 시에만 호출                        ✓
// Forex 1개, 1분 캐시 → ~1 call/min                                 ✓
const QUOTE_TTL_MS   = 21_000
const PROFILE_TTL_MS = 3_600_000
const FOREX_TTL_MS   = 60_000

// ─── Types ───────────────────────────────────────────────────────────────────

interface CompanyMeta {
  ticker: string
  name: string
  color: string
}

interface QuoteData {
  c: number   // current price
  d: number   // change
  dp: number  // change percent
}

interface ProfileData {
  marketCapitalization: number
  shareOutstanding: number  // millions of shares (보통주 기준)
}

interface ForexRates {
  krw: number  // KRW/USD
  jpy: number  // JPY/USD — JPX 환산용
  cny: number  // CNY/USD — SSE 환산용
}

interface OXRResponse {
  rates: Record<string, number>
}

// FMP 스크리너 응답 (필요한 필드만)
interface FMPScreenerRow {
  symbol:      string
  companyName: string
  marketCap:   number
}

interface CacheEntry<T> {
  data: T
  ts: number
}

export interface CompanyResult {
  rank: number
  ticker: string
  name: string
  color: string
  currentPrice: number
  change: number
  changePercent: number
  marketCapUSD: number  // Trillion USD
}

interface KRXQuoteData {
  price:         number
  change:        number
  changePercent: number
  marketCapKRW:  number
}

// Yahoo v7 배치 quote 1건 (현지 통화). JPX/SSE/SZSE 공용.
interface YahooQuote {
  price:         number
  change:        number
  changePercent: number
  marketCap:     number  // 현지 통화(JPY/CNY) 단위
  currency:      string
}

interface NaverStockBasic {
  closePrice?:                  string  // "259,000"
  compareToPreviousClosePrice?: string  // "-500" | "15,000" (하락 시에만 부호 포함)
  fluctuationsRatio?:           string  // "-0.16" | "6.15"
}

// integration 엔드포인트의 totalInfos 항목 (basic에서 marketValue 필드가 제거되어 대체)
interface NaverTotalInfo {
  code:  string  // "marketValue" 등
  key:   string  // "시총"
  value: string  // "1,514조 1,862억"
}

interface NaverStockIntegration {
  totalInfos?: NaverTotalInfo[]
}

// ─── Aramco-Specific Types ────────────────────────────────────────────────────

interface AramcoData {
  priceSAR:      number
  changeSAR:     number
  changePercent: number
  marketCapUSD:  number  // trillion USD
}

// ─── In-Memory Cache ─────────────────────────────────────────────────────────

const quoteCache      = new Map<string, CacheEntry<QuoteData>>()
const profileCache    = new Map<string, CacheEntry<ProfileData>>()
const krxQuoteCache   = new Map<string, CacheEntry<KRXQuoteData>>()
const naverKRXCache   = new Map<string, CacheEntry<KRXQuoteData>>()
// Yahoo v7 배치 quote 결과 캐시 (거래소 키). 폴링(15s)과 QUOTE_TTL(21s) 동기화.
const yahooBatchCache = new Map<string, CacheEntry<Map<string, YahooQuote>>>()
// JPX/SSE/SZSE 개별 종목 stale 폴백 (배치 일부 누락 시 목록 flickering 방지)
const foreignLastGoodCache = new Map<string, Omit<CompanyResult, 'rank'>>()
let forexCache: CacheEntry<ForexRates> | null = null
let aramcoDataCache: CacheEntry<AramcoData> | null = null

// 실패 시 Yahoo Finance에 폭격 방지 — 마지막 실패로부터 60초 쿨다운
const ARAMCO_ERROR_COOLDOWN_MS = 60_000
let aramcoErrorUntil = 0

// 개별 종목 실패 시 stale 데이터 유지용 (목록 flickering 방지)
const krxLastGoodCache     = new Map<string, KRXQuoteData>()
const finnhubLastGoodCache = new Map<string, Omit<CompanyResult, 'rank'>>()

let lastGoodResult: CompanyResult[] | null = null
let lastGoodAt = 0
let lastGoodExchangeRate = FOREX_FALLBACK
// 마지막 성공 환율 전체(KRW/JPY/CNY). OXR 실패 시 통화별 폴백으로 사용.
let lastGoodForex: ForexRates = { krw: FOREX_FALLBACK, jpy: JPY_FALLBACK, cny: CNY_FALLBACK }

// 거래소 전용 피드 상태 (ALL과 분리해 서로 간섭하지 않도록).
// 신규 거래소는 여기 한 줄만 추가하면 확장됨.
interface ExchangeFeedState {
  universeCache:  CacheEntry<CompanyMeta[]> | null  // FMP 티커 목록 캐시 (1시간)
  lastGoodResult: CompanyResult[] | null            // 마지막 성공 랭킹 (stale 폴백)
  lastGoodAt:     number
}
const exchangeFeeds: Record<string, ExchangeFeedState> = {
  NASDAQ: { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
  NYSE:   { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
  KOSPI:  { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
  KOSDAQ: { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
  JPX:    { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
  SSE:    { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
  SZSE:   { universeCache: null, lastGoodResult: null, lastGoodAt: 0 },
}

// ─── Batch Utility ───────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function mapInBatches<T, R>(
  items: T[],
  batchSize: number,
  delayMs: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = []
  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize)
    results.push(...(await Promise.all(batch.map(fn))))
    if (i + batchSize < items.length) await sleep(delayMs)
  }
  return results
}

// ─── Common Yahoo Finance Headers ─────────────────────────────────────────────

const YF_HTML_HEADERS = {
  'User-Agent':      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
}

// ─── Finnhub Fetchers ─────────────────────────────────────────────────────────

async function getQuote(ticker: string): Promise<QuoteData> {
  const hit = quoteCache.get(ticker)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const res = await fetch(
    `${BASE}/quote?symbol=${encodeURIComponent(ticker)}&token=${FINNHUB_TOKEN}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`quote ${ticker} → HTTP ${res.status}`)
  const data: QuoteData = await res.json()
  if (!data.c) throw new Error(`quote ${ticker} → empty response`)
  quoteCache.set(ticker, { data, ts: Date.now() })
  return data
}

async function getProfile(ticker: string): Promise<ProfileData> {
  const hit = profileCache.get(ticker)
  if (hit && Date.now() - hit.ts < PROFILE_TTL_MS) return hit.data

  const res = await fetch(
    `${BASE}/stock/profile2?symbol=${encodeURIComponent(ticker)}&token=${FINNHUB_TOKEN}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`profile ${ticker} → HTTP ${res.status}`)
  const data: ProfileData = await res.json()
  if (!data.marketCapitalization) throw new Error(`profile ${ticker} → marketCapitalization missing`)
  profileCache.set(ticker, { data, ts: Date.now() })
  return data
}

async function getForexRates(): Promise<ForexRates> {
  if (forexCache && Date.now() - forexCache.ts < FOREX_TTL_MS) return forexCache.data

  const res = await fetch(
    `https://openexchangerates.org/api/latest.json?app_id=${OXR_APP_ID}&symbols=KRW,JPY,CNY`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`forex rates → HTTP ${res.status}`)
  const data: OXRResponse = await res.json()
  const krw = data.rates?.KRW
  if (!krw || !isFinite(krw)) throw new Error('forex KRW rate missing or invalid')
  // JPY/CNY는 부분 누락돼도 KRW만 있으면 진행 — 없으면 마지막 성공값으로 폴백.
  const jpy = data.rates?.JPY
  const cny = data.rates?.CNY
  const rates: ForexRates = {
    krw,
    jpy: (jpy && isFinite(jpy)) ? jpy : lastGoodForex.jpy,
    cny: (cny && isFinite(cny)) ? cny : lastGoodForex.cny,
  }
  forexCache = { data: rates, ts: Date.now() }
  lastGoodForex = rates
  return rates
}

// ─── KRX (한국거래소) Fetcher — Yahoo Finance HTML 파싱 ───────────────────────
// Yahoo Finance v7/v8 JSON API는 crumb 인증 필요(429) → Aramco와 동일하게
// finance.yahoo.com HTML 페이지 내 SSR 임베드 JSON에서 직접 파싱.
// marketCap 필드는 KRW 단위 → forexRates.krw(KRW/USD)로 나눠 USD 환산.

async function getKRXQuote(yahooTicker: string): Promise<KRXQuoteData> {
  const cached = krxQuoteCache.get(yahooTicker)
  if (cached && Date.now() - cached.ts < QUOTE_TTL_MS) return cached.data

  try {
    const res = await fetch(
      `https://finance.yahoo.com/quote/${encodeURIComponent(yahooTicker)}/`,
      { headers: YF_HTML_HEADERS, redirect: 'follow', cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`KRX HTML ${yahooTicker} → HTTP ${res.status}`)

    const html = await res.text()
    const scriptRe = /<script[^>]*>(.*?)<\/script>/gs
    let match: RegExpExecArray | null

    while ((match = scriptRe.exec(html)) !== null) {
      const content = match[1]
      if (!content.includes('quoteResponse')) continue
      try {
        const outer = JSON.parse(content)

        // Case 1: quoteResponse가 body 문자열 내부에 중첩된 경우
        let result: any = null
        if (typeof outer.body === 'string') {
          const body = JSON.parse(outer.body)
          result = body?.quoteResponse?.result?.[0]
        }
        // Case 2: quoteResponse가 최상위에 있는 경우
        if (!result) result = outer?.quoteResponse?.result?.[0]
        if (!result) continue

        // 다른 종목 데이터를 잘못 파싱하지 않도록 심볼 검증
        if (result.symbol && result.symbol !== yahooTicker) continue

        const price         = (result.regularMarketPrice?.raw ?? result.regularMarketOpen?.raw ?? 0) as number
        const change        = (result.regularMarketChange?.raw ?? 0) as number
        const changePercent = (result.regularMarketChangePercent?.raw ?? 0) as number
        const marketCapKRW  = (result.marketCap?.raw ?? 0) as number
        if (!price || !marketCapKRW) continue

        const data: KRXQuoteData = { price, change, changePercent, marketCapKRW }
        krxQuoteCache.set(yahooTicker, { data, ts: Date.now() })
        krxLastGoodCache.set(yahooTicker, data)
        return data
      } catch { continue }
    }
    throw new Error(`KRX HTML ${yahooTicker} → quote data not found in page scripts`)
  } catch (err) {
    // Stale 캐시가 있으면 실패해도 이전 데이터 유지 (목록 안정성)
    const stale = krxLastGoodCache.get(yahooTicker) ?? cached?.data
    if (stale) {
      console.warn(`[market-cap] KRX ${yahooTicker} fetch failed, using stale cache`)
      return stale
    }
    throw err
  }
}

// ─── Naver Finance KRX Fetcher ────────────────────────────────────────────────
// Yahoo Finance HTML 스크래핑 대체: Naver Finance 모바일 API
// 인증 불필요, KRX 전용, JSON 직접 반환 → 파싱 오류 없음

// Naver 한국식 시총 표기("1,514조 1,862억")를 KRW 숫자로 변환
// 조 = 10^12, 억 = 10^8. 둘 중 하나만 있는 경우도 처리.
function parseKoreanMarketCap(s: string): number {
  const jo  = s.match(/([\d,]+)\s*조/)
  const eok = s.match(/([\d,]+)\s*억/)
  let total = 0
  if (jo)  total += parseFloat(jo[1].replace(/,/g, ''))  * 1_000_000_000_000
  if (eok) total += parseFloat(eok[1].replace(/,/g, '')) * 100_000_000
  return total
}

async function getNaverKRXQuote(naverCode: string): Promise<KRXQuoteData> {
  const cached = naverKRXCache.get(naverCode)
  if (cached && Date.now() - cached.ts < QUOTE_TTL_MS) return cached.data

  const headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
    'Referer':    'https://m.stock.naver.com/',
  }

  // basic: 현재가/등락 · integration: 시가총액(basic에서 제거되어 별도 호출)
  const [basicRes, integrationRes] = await Promise.all([
    fetch(`https://m.stock.naver.com/api/stock/${naverCode}/basic`,       { headers, cache: 'no-store' }),
    fetch(`https://m.stock.naver.com/api/stock/${naverCode}/integration`, { headers, cache: 'no-store' }),
  ])
  if (!basicRes.ok)       throw new Error(`Naver basic ${naverCode} → HTTP ${basicRes.status}`)
  if (!integrationRes.ok) throw new Error(`Naver integration ${naverCode} → HTTP ${integrationRes.status}`)

  const basic:       NaverStockBasic       = await basicRes.json()
  const integration: NaverStockIntegration = await integrationRes.json()

  const price         = parseFloat((basic.closePrice                  ?? '').replace(/,/g, ''))
  const change        = parseFloat((basic.compareToPreviousClosePrice ?? '0').replace(/,/g, ''))
  const changePercent = parseFloat( basic.fluctuationsRatio           ?? '0')

  const marketCapRaw = integration.totalInfos?.find(i => i.code === 'marketValue')?.value ?? ''
  const marketCapKRW = parseKoreanMarketCap(marketCapRaw)

  if (!price || !marketCapKRW) throw new Error(`Naver ${naverCode} → invalid data (price=${price}, mcap=${marketCapKRW})`)

  const data: KRXQuoteData = { price, change, changePercent, marketCapKRW }
  naverKRXCache.set(naverCode, { data, ts: Date.now() })
  return data
}

async function getKRXResult(
  meta: KoreanStockMeta,
  krwPerUsd: number,
): Promise<Omit<CompanyResult, 'rank'>> {
  // Naver Finance 1차 시도 → Yahoo Finance fallback
  // Yahoo Finance HTML 스크래핑은 .KS 종목 응답 구조 변경으로 불안정
  const naverCode = meta.ticker.replace(/\.(KS|KQ)$/, '')
  let data: KRXQuoteData
  try {
    data = await getNaverKRXQuote(naverCode)
  } catch (naverErr) {
    console.warn(`[market-cap] Naver ${naverCode} failed, trying Yahoo:`, naverErr)
    data = await getKRXQuote(meta.yahooTicker)
  }
  if (!data.marketCapKRW) throw new Error(`KRX ${meta.ticker} → marketCap missing`)
  return {
    ticker:        meta.ticker,
    name:          meta.name,
    color:         meta.color,
    currentPrice:  data.price,
    change:        data.change,
    changePercent: data.changePercent,
    marketCapUSD:  data.marketCapKRW / krwPerUsd / 1_000_000_000_000,
  }
}

// ─── JPX·SSE·SZSE Fetcher (Yahoo Finance v7 배치 quote) ───────────────────────
// Finnhub 무료는 아시아 미지원, Naver는 한국 전용, Yahoo HTML 스크래핑은 20종목
// 배치에서 레이트리밋으로 절반 이상 누락됨. → yfinance와 동일한 방식으로
// crumb+cookie 인증 후 v7 batch quote 한 번에 20종목을 받아 안정성을 확보한다.
// (요청량: 거래소당 20 → 1). marketCap은 현지 통화(JPY/CNY)라 환율로 USD 환산.

const YAHOO_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
const YAHOO_AUTH_TTL_MS = 30 * 60 * 1000  // crumb/cookie는 수 시간 유효 → 30분 캐시

let yahooAuth: { crumb: string; cookie: string; ts: number } | null = null

// fc.yahoo.com에서 세션 쿠키(A1/A3)를 받고, 그 쿠키로 crumb 토큰을 발급받는다.
// 이 둘이 있어야 v7/quote가 429 없이 응답한다.
async function getYahooAuth(): Promise<{ crumb: string; cookie: string }> {
  if (yahooAuth && Date.now() - yahooAuth.ts < YAHOO_AUTH_TTL_MS) {
    return { crumb: yahooAuth.crumb, cookie: yahooAuth.cookie }
  }

  const cookieRes = await fetch('https://fc.yahoo.com/', {
    headers: { 'User-Agent': YAHOO_UA },
    redirect: 'manual',
    cache: 'no-store',
  })
  // undici(Node 18+)의 getSetCookie로 다중 Set-Cookie를 배열로 수집
  const setCookies: string[] = (cookieRes.headers as unknown as { getSetCookie?: () => string[] }).getSetCookie?.() ?? []
  const cookie = setCookies.map(c => c.split(';')[0]).filter(Boolean).join('; ')
  if (!cookie) throw new Error('Yahoo cookie fetch failed')

  const crumbRes = await fetch('https://query1.finance.yahoo.com/v1/test/getcrumb', {
    headers: { 'User-Agent': YAHOO_UA, 'Cookie': cookie },
    cache: 'no-store',
  })
  const crumb = (await crumbRes.text()).trim()
  if (!crumb || crumb.length > 40 || /too many|<html|error/i.test(crumb)) {
    throw new Error(`Yahoo crumb fetch failed: ${crumb.slice(0, 40)}`)
  }

  yahooAuth = { crumb, cookie, ts: Date.now() }
  return { crumb, cookie }
}

async function yahooQuoteFetch(symbols: string[], auth: { crumb: string; cookie: string }): Promise<Response> {
  const url = `https://query1.finance.yahoo.com/v7/finance/quote`
    + `?symbols=${encodeURIComponent(symbols.join(','))}`
    + `&crumb=${encodeURIComponent(auth.crumb)}`
  return fetch(url, {
    headers: { 'User-Agent': YAHOO_UA, 'Cookie': auth.cookie },
    cache: 'no-store',
  })
}

// v7 배치 quote → symbol별 YahooQuote 맵. crumb 만료(401/403/429) 시 1회 재인증 후 재시도.
async function fetchYahooQuotes(symbols: string[]): Promise<Map<string, YahooQuote>> {
  let auth = await getYahooAuth()
  let res  = await yahooQuoteFetch(symbols, auth)
  if (res.status === 401 || res.status === 403 || res.status === 429) {
    yahooAuth = null                       // 만료 추정 → 강제 재발급
    auth = await getYahooAuth()
    res  = await yahooQuoteFetch(symbols, auth)
  }
  if (!res.ok) throw new Error(`Yahoo v7 quote → HTTP ${res.status}`)

  const json   = await res.json()
  const result = json?.quoteResponse?.result
  if (!Array.isArray(result)) throw new Error('Yahoo v7 quote → no result array')

  const map = new Map<string, YahooQuote>()
  for (const q of result) {
    if (!q?.symbol) continue
    map.set(q.symbol, {
      price:         q.regularMarketPrice ?? 0,
      change:        q.regularMarketChange ?? 0,
      changePercent: q.regularMarketChangePercent ?? 0,
      marketCap:     q.marketCap ?? 0,
      currency:      q.currency ?? '',
    })
  }
  return map
}

// 거래소 단위 캐시(QUOTE_TTL) — 폴링마다 배치 1콜을 넘지 않도록.
async function getYahooBatchQuotes(exchange: string, symbols: string[]): Promise<Map<string, YahooQuote>> {
  const hit = yahooBatchCache.get(exchange)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data
  const map = await fetchYahooQuotes(symbols)
  yahooBatchCache.set(exchange, { data: map, ts: Date.now() })
  return map
}

// ─── Aramco Fetcher (Yahoo Finance HTML 파싱) ─────────────────────────────────

async function getAramcoData(): Promise<AramcoData> {
  if (aramcoDataCache && Date.now() - aramcoDataCache.ts < QUOTE_TTL_MS) return aramcoDataCache.data

  // 쿨다운 중에는 stale 캐시 반환 (Yahoo Finance 폭격 방지)
  if (Date.now() < aramcoErrorUntil) {
    if (aramcoDataCache) return aramcoDataCache.data
    throw new Error('Aramco cooldown active, no cached data')
  }

  try {
    const res = await fetch('https://finance.yahoo.com/quote/2222.SR/', {
      headers: YF_HTML_HEADERS,
      redirect: 'follow',
      cache: 'no-store',
    })
    if (!res.ok) throw new Error(`Aramco HTML → HTTP ${res.status}`)

    const html = await res.text()
    const scriptRe = /<script[^>]*>(.*?)<\/script>/gs
    let match: RegExpExecArray | null
    while ((match = scriptRe.exec(html)) !== null) {
      const content = match[1]
      if (!content.includes('2222.SR') || !content.includes('quoteResponse')) continue
      try {
        const outer = JSON.parse(content)
        if (typeof outer.body !== 'string') continue
        const body = JSON.parse(outer.body)
        const result = body?.quoteResponse?.result?.[0]
        if (result?.symbol !== '2222.SR') continue

        const priceSAR      = (result.regularMarketPrice?.raw ?? result.regularMarketOpen?.raw ?? 0) as number
        const changeSAR     = (result.regularMarketChange?.raw ?? 0) as number
        const changePercent = (result.regularMarketChangePercent?.raw ?? 0) as number
        const marketCapSAR  = (result.marketCap?.raw ?? 0) as number
        if (!priceSAR || !marketCapSAR) continue

        const data: AramcoData = {
          priceSAR,
          changeSAR,
          changePercent,
          marketCapUSD: marketCapSAR / ARAMCO_SAR_PER_USD / 1_000_000_000_000,
        }
        aramcoDataCache = { data, ts: Date.now() }
        aramcoErrorUntil = 0
        return data
      } catch { continue }
    }
    throw new Error('Aramco HTML → quote data not found in page scripts')
  } catch (err) {
    aramcoErrorUntil = Date.now() + ARAMCO_ERROR_COOLDOWN_MS
    // Stale 캐시가 있으면 실패해도 이전 데이터 유지
    if (aramcoDataCache) {
      console.warn('[market-cap] Aramco fetch failed, using stale cache:', err)
      return aramcoDataCache.data
    }
    throw err
  }
}

async function getAramcoResult(): Promise<Omit<CompanyResult, 'rank'>> {
  const data = await getAramcoData()
  return {
    ticker:        ARAMCO_META.ticker,
    name:          ARAMCO_META.name,
    color:         ARAMCO_META.color,
    currentPrice:  data.priceSAR,
    change:        data.changeSAR,
    changePercent: data.changePercent,
    marketCapUSD:  data.marketCapUSD,
  }
}

// ─── SpaceX (하드코딩 · 비상장) ────────────────────────────────────────────────
// 실시간 시세 없음. 추정 기업가치를 그대로 사용하며 등락률은 0으로 둔다.
function getSpaceXResult(): Omit<CompanyResult, 'rank'> {
  return {
    ticker:        SPACEX_META.ticker,
    name:          SPACEX_META.name,
    color:         SPACEX_META.color,
    currentPrice:  0,
    change:        0,
    changePercent: 0,
    marketCapUSD:  SPACEX_EST_MARKETCAP_USD_T,
  }
}

// ─── Exchange Universe (FMP Screener) ─────────────────────────────────────────
// FMP 스크리너로 거래소 시총 상위 '티커 목록'만 확보 (실시간 시세는 Finnhub 담당).
// 시총 순위는 하루 안에 거의 안 바뀌므로 1시간 캐시 → FMP 무료(250콜/일) 안에서 여유.
// 키 미설정/실패 시 정적 폴백 리스트(fallback) 사용 → 기존 동작 보장.

// 티커 문자열 해시 → 결정적 HSL → hex. 큐레이션 색이 없는 신규 종목용.
function hslToHex(h: number, s: number, l: number): string {
  s /= 100; l /= 100
  const a = s * Math.min(l, 1 - l)
  const f = (n: number): string => {
    const k = (n + h / 30) % 12
    const c = l - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)))
    return Math.round(255 * c).toString(16).padStart(2, '0')
  }
  return `#${f(0)}${f(8)}${f(4)}`
}

function colorForTicker(ticker: string): string {
  let h = 0
  for (let i = 0; i < ticker.length; i++) h = (h * 31 + ticker.charCodeAt(i)) >>> 0
  return hslToHex(h % 360, 55, 45)
}

async function getExchangeUniverse(
  exchange: string,          // 'NASDAQ' | 'NYSE'
  fallback: CompanyMeta[],
): Promise<CompanyMeta[]> {
  const state  = exchangeFeeds[exchange]
  const cached = state?.universeCache
  if (cached && Date.now() - cached.ts < EXCHANGE_UNIVERSE_TTL_MS) return cached.data
  if (!FMP_API_KEY) return cached?.data ?? fallback

  try {
    const url = `${FMP_SCREENER}?exchange=${exchange}`
      + `&isActivelyTrading=true&isEtf=false&isFund=false`
      + `&marketCapMoreThan=50000000000&limit=100&apikey=${FMP_API_KEY}`
    const res = await fetch(url, { cache: 'no-store' })
    if (!res.ok) throw new Error(`FMP screener ${exchange} → HTTP ${res.status}`)

    const rows: FMPScreenerRow[] = await res.json()
    if (!Array.isArray(rows) || rows.length === 0) throw new Error(`FMP screener ${exchange} → empty`)

    const universe: CompanyMeta[] = rows
      .filter(r => r.symbol && r.marketCap > 0)
      .sort((a, b) => b.marketCap - a.marketCap)
      .slice(0, EXCHANGE_UNIVERSE_SIZE)
      .map(r => KNOWN_META[r.symbol] ?? {
        ticker: r.symbol,
        name:   r.companyName || r.symbol,
        color:  colorForTicker(r.symbol),
      })

    if (state) state.universeCache = { data: universe, ts: Date.now() }
    return universe
  } catch (err) {
    console.warn(`[market-cap:${exchange}] FMP screener failed, using fallback:`, err)
    return cached?.data ?? fallback
  }
}

// ─── Finnhub Company Rows (ALL / NASDAQ 공통) ─────────────────────────────────
// 주어진 회사 목록을 Finnhub quote+profile로 조회해 CompanyResult(rank 제외) 배열로 변환.
// 개별 종목 실패는 stale 캐시 폴백 후 null 처리 — 한 종목 장애가 전체를 막지 않도록.
// quoteCache/profileCache는 ticker 키로 공유되므로 ALL·NASDAQ가 겹치는 종목은 중복 호출되지 않는다.
async function fetchFinnhubRows(
  companies: CompanyMeta[],
): Promise<(Omit<CompanyResult, 'rank'> | null)[]> {
  return mapInBatches(
    companies,
    BATCH_SIZE,
    BATCH_DELAY_MS,
    async (co): Promise<Omit<CompanyResult, 'rank'> | null> => {
      try {
        const [quote, profile] = await Promise.all([
          getQuote(co.ticker),
          getProfile(co.ticker),
        ])
        let marketCapUSD: number
        if (co.ticker === 'TSM') {
          marketCapUSD = profile.shareOutstanding / TSM_ADR_RATIO * quote.c / 1_000_000
        } else {
          const precomputed = profile.marketCapitalization / 1_000_000
          const live        = profile.shareOutstanding * quote.c / 1_000_000
          const ratio       = precomputed > 0 ? live / precomputed : 0
          // shareOutstanding이 신뢰 가능한 범위면 라이브가로 재계산, 아니면 사전계산값 폴백
          marketCapUSD = ratio >= MCAP_LIVE_TRUST_MIN && ratio <= MCAP_LIVE_TRUST_MAX
            ? live
            : precomputed
        }
        const result: Omit<CompanyResult, 'rank'> = {
          ticker:        co.ticker,
          name:          co.name,
          color:         co.color,
          currentPrice:  quote.c,
          change:        quote.d,
          changePercent: quote.dp,
          marketCapUSD,
        }
        finnhubLastGoodCache.set(co.ticker, result)
        return result
      } catch (err) {
        const stale = finnhubLastGoodCache.get(co.ticker)
        if (stale) {
          console.warn(`[market-cap] ${co.ticker} failed, using stale data:`, err)
          return stale
        }
        console.warn(`[market-cap] ${co.ticker} failed, skipping:`, err)
        return null
      }
    },
  )
}

// ─── Route Handler ────────────────────────────────────────────────────────────

// ALL(전 거래소 통합)과 거래소 전용(NASDAQ/NYSE) 피드를 분기.
// 기본(?exchange 없음)은 기존 ALL 동작을 그대로 유지 → 기존 앱 로직 무영향.
export async function GET(req: Request) {
  const exchange = new URL(req.url).searchParams.get('exchange')?.toLowerCase()
  if (exchange === 'nasdaq') return handleExchange('NASDAQ', NASDAQ_COMPANIES)
  if (exchange === 'nyse')   return handleExchange('NYSE',   NYSE_COMPANIES)
  if (exchange === 'kospi')  return handleKoreanExchange('KOSPI',  KOSPI_COMPANIES)
  if (exchange === 'kosdaq') return handleKoreanExchange('KOSDAQ', KOSDAQ_COMPANIES)
  if (exchange === 'jpx')    return handleForeignExchange('JPX',  JPX_COMPANIES,  'jpy')
  if (exchange === 'sse')    return handleForeignExchange('SSE',  SSE_COMPANIES,  'cny')
  if (exchange === 'szse')   return handleForeignExchange('SZSE', SZSE_COMPANIES, 'cny')
  return handleAll()
}

async function handleAll() {
  try {
    if (!FINNHUB_TOKEN) {
      throw new Error('FINNHUB_API_KEY 환경 변수가 설정되지 않았습니다.')
    }

    const forexRates = await getForexRates().catch((err) => {
      console.warn('[market-cap] forex fetch failed, using fallback:', err)
      return lastGoodForex
    })

    // Finnhub 배치, Aramco(Yahoo HTML), KRX(Yahoo JSON) 병렬 실행
    // 개별 종목 실패는 null로 처리 — 한 종목 장애가 전체를 막지 않도록
    const finnhubTask = fetchFinnhubRows(COMPANIES)

    const aramcoTask = getAramcoResult().catch((err) => {
      console.warn('[market-cap] Aramco fetch failed, skipping:', err)
      return null
    })

    const krxTask = Promise.all(
      KOREAN_STOCKS.map(meta =>
        getKRXResult(meta, forexRates.krw).catch((err) => {
          console.warn(`[market-cap] KRX ${meta.ticker} failed, skipping:`, err)
          return null
        }),
      ),
    )

    const [finnhubRows, aramcoResult, krxResults] = await Promise.all([
      finnhubTask,
      aramcoTask,
      krxTask,
    ])

    const allRows = [
      ...finnhubRows,
      aramcoResult,
      ...krxResults,
    ].filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked: CompanyResult[] = allRows
      .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
      .slice(0, 20)
      .map((r, i) => ({ ...r, rank: i + 1 }))

    lastGoodResult = ranked
    lastGoodAt = Date.now()
    lastGoodExchangeRate = forexRates.krw

    return NextResponse.json({ exchangeRate: forexRates.krw, data: ranked, updatedAt: lastGoodAt, stale: false })
  } catch (err) {
    console.error('[market-cap] fetch error:', err)

    if (lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: lastGoodResult, updatedAt: lastGoodAt, stale: true },
        { status: 200 },
      )
    }

    return NextResponse.json(
      { error: String(err) },
      { status: 503 },
    )
  }
}

// 한국거래소 전용 핸들러 (KOSPI/KOSDAQ 공통) — 하드코딩 유니버스를 Naver Finance로
// 실시간 시세/시총 조회 → USD 환산 후 상위 20개 반환. Finnhub 무료는 KRX 미지원이므로
// 미국 거래소(handleExchange)와 달리 getKRXResult(Naver→Yahoo 폴백)를 사용한다.
// ALL/미국 피드와 동일한 응답 형태(exchangeRate/data/updatedAt/stale)를 유지.
async function handleKoreanExchange(exchange: string, companies: KoreanStockMeta[]) {
  const state = exchangeFeeds[exchange]
  try {
    // KRW 환산 표시는 클라이언트가 담당하므로 환율만 함께 전달
    const forexRates = await getForexRates().catch((err) => {
      console.warn(`[market-cap:${exchange}] forex fetch failed, using fallback:`, err)
      return lastGoodForex
    })

    // Naver 폭격 방지 — 배치(5개, 200ms)로 조회. 개별 실패는 stale/skip 처리.
    const rows = await mapInBatches(
      companies,
      BATCH_SIZE,
      BATCH_DELAY_MS,
      (meta): Promise<Omit<CompanyResult, 'rank'> | null> =>
        getKRXResult(meta, forexRates.krw).catch((err) => {
          console.warn(`[market-cap:${exchange}] ${meta.ticker} failed, skipping:`, err)
          return null
        }),
    )
    const allRows = rows.filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked: CompanyResult[] = allRows
      .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
      .slice(0, 20)
      .map((r, i) => ({ ...r, rank: i + 1 }))

    if (state) {
      state.lastGoodResult = ranked
      state.lastGoodAt = Date.now()
    }
    lastGoodExchangeRate = forexRates.krw

    return NextResponse.json({ exchangeRate: forexRates.krw, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)

    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
        { status: 200 },
      )
    }

    return NextResponse.json(
      { error: String(err) },
      { status: 503 },
    )
  }
}

// 해외 거래소 전용 핸들러 (JPX/SSE/SZSE 공통) — 하드코딩 유니버스를 Yahoo v7 배치 quote로
// 한 번에 조회 → currency(jpy/cny) 환율로 USD 환산 후 상위 20개 반환.
// Finnhub 무료는 아시아 미지원, Naver는 한국 전용이라 handleKoreanExchange와 달리
// getYahooBatchQuotes(crumb 인증)를 사용한다. 응답 형태(exchangeRate/data/updatedAt/stale)는 동일.
// exchangeRate는 클라이언트 원화 토글용이라 항상 KRW를 실어 보낸다.
async function handleForeignExchange(
  exchange: string,
  companies: ForeignStockMeta[],
  currency: 'jpy' | 'cny',
) {
  const state = exchangeFeeds[exchange]
  try {
    const forexRates = await getForexRates().catch((err) => {
      console.warn(`[market-cap:${exchange}] forex fetch failed, using fallback:`, err)
      return lastGoodForex
    })
    const ratePerUsd = forexRates[currency]

    // 배치 quote 1콜로 전 종목 조회. 배치에서 누락된 종목은 stale 폴백 → 목록 안정화.
    const quotes = await getYahooBatchQuotes(exchange, companies.map(c => c.yahooTicker))
    const allRows = companies.map((meta): Omit<CompanyResult, 'rank'> | null => {
      const q = quotes.get(meta.yahooTicker)
      if (!q || !q.marketCap || !q.price) {
        const stale = foreignLastGoodCache.get(meta.ticker)
        if (stale) console.warn(`[market-cap:${exchange}] ${meta.ticker} missing in batch, using stale`)
        return stale ?? null
      }
      const row: Omit<CompanyResult, 'rank'> = {
        ticker:        meta.ticker,
        name:          meta.name,
        color:         meta.color,
        currentPrice:  q.price,
        change:        q.change,
        changePercent: q.changePercent,
        marketCapUSD:  q.marketCap / ratePerUsd / 1_000_000_000_000,
      }
      foreignLastGoodCache.set(meta.ticker, row)
      return row
    }).filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked: CompanyResult[] = allRows
      .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
      .slice(0, 20)
      .map((r, i) => ({ ...r, rank: i + 1 }))

    if (state) {
      state.lastGoodResult = ranked
      state.lastGoodAt = Date.now()
    }
    lastGoodExchangeRate = forexRates.krw

    return NextResponse.json({ exchangeRate: forexRates.krw, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)

    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
        { status: 200 },
      )
    }

    return NextResponse.json(
      { error: String(err) },
      { status: 503 },
    )
  }
}

// 거래소 전용 핸들러 (NASDAQ/NYSE 공통) — FMP로 상위 티커 유니버스 확보 →
// Finnhub로 실시간 시총 계산 → 상위 20개 반환.
// ALL과 동일한 응답 형태(exchangeRate/data/updatedAt/stale)를 유지해 클라이언트가 그대로 디코딩.
async function handleExchange(exchange: string, fallback: CompanyMeta[]) {
  const state = exchangeFeeds[exchange]
  try {
    if (!FINNHUB_TOKEN) {
      throw new Error('FINNHUB_API_KEY 환경 변수가 설정되지 않았습니다.')
    }

    // KRW 환산 표시는 클라이언트가 담당하므로 환율만 함께 전달
    const forexRates = await getForexRates().catch((err) => {
      console.warn(`[market-cap:${exchange}] forex fetch failed, using fallback:`, err)
      return lastGoodForex
    })

    const universe = await getExchangeUniverse(exchange, fallback)
    const rows = await fetchFinnhubRows(universe)
    const allRows = rows.filter(
      (r): r is Omit<CompanyResult, 'rank'> => r !== null,
    )

    // SpaceX(비상장)는 Finnhub 유니버스에 없으므로 나스닥 섹션에만 수동 주입 후 함께 정렬.
    if (exchange === 'NASDAQ') allRows.push(getSpaceXResult())

    const ranked: CompanyResult[] = allRows
      .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
      .slice(0, 20)
      .map((r, i) => ({ ...r, rank: i + 1 }))

    if (state) {
      state.lastGoodResult = ranked
      state.lastGoodAt = Date.now()
    }
    lastGoodExchangeRate = forexRates.krw

    return NextResponse.json({ exchangeRate: forexRates.krw, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)

    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
        { status: 200 },
      )
    }

    return NextResponse.json(
      { error: String(err) },
      { status: 503 },
    )
  }
}
