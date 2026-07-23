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
const EUR_FALLBACK   = 0.92     // EUR/USD — Euronext 시총 환산용

// NASDAQ/NYSE 유니버스는 정적 리스트로 관리한다. FMP 무료 플랜은 스크리너를 더 이상
// 지원하지 않고(레거시 폐지 + 신규 company-screener 유료), 배치 quote·일부 티커(BRK.B)도
// 유료라 실시간 순위 소스로 쓸 수 없다. 실시간 시총·시세는 Finnhub만으로 계산한다.

// ADR(미국예탁증서) 시총 계산: 1 ADR = N 보통주. Finnhub의 사전계산 marketCapitalization은
// ADR 종목에서 부정확/현지통화라 못 쓰고(TSM=TWD, HSBC는 $0.259T로 과소 → 실제 $0.354T),
// shareOutstanding(보통주 수, millions) / ADR비율 × ADR가격(USD) / 1_000_000 으로 직접 계산한다.
// 이 값은 나스닥 공식과 일치한다(예: HSBC 17,183.56M/5 × $103.11 = $354.4B ✓).
// 신규 ADR은 여기 티커:비율만 추가하면 된다.
const ADR_SHARE_RATIO: Record<string, number> = {
  TSM:  5,  // 1 ADR = 5 대만 보통주 (TSMC)
  HSBC: 5,  // 1 ADR = 5 HSBC 보통주 (런던 상장 원주)
}

// 미국 종목 시총은 Finnhub 사전계산 marketCapitalization(정확·일 단위 갱신)을 기준으로,
// 당일 등락(quote.c / quote.pc)만큼만 스케일해 라이브 값을 만든다.
//   liveCap = marketCapitalization × (현재가 / 전일종가)
// 예전 방식(shareOutstanding × 현재가)은 Finnhub shareOutstanding이 부실한 종목(BRK.B는
// BRK.A 데이터라 1.44M로 옴)에서 순위가 크게 틀어졌다. 사전계산 시총은 FMP와 ~1% 이내로
// 일치하고 전 종목에 존재하므로 순위 정확도가 높고, quote가 레이트리밋으로 빠져도
// (ratio=1) 순위는 유지된다. TSM(ADR)만 별도 계산.

const BATCH_SIZE     = 5
const BATCH_DELAY_MS = 200

// Aramco: Tadawul(사우디 증권거래소) 상장, SAR 표시가. 사우디 법정 고정환율 적용.
const ARAMCO_SAR_PER_USD = 3.75
const ARAMCO_META: CompanyMeta = { ticker: '2222.SR', name: 'Saudi Aramco', color: '#007A3D' }

// SpaceX(SPCX): 2026-06-12 나스닥 IPO로 상장 완료 → Finnhub에 실시간 시세/시총이 존재한다.
// (예전엔 비상장이라 추정치 $0.4T를 수동 입력했지만 이제 라이브 데이터로 정확히 계산한다.)
// 다른 상장사와 동일하게 COMPANIES·NASDAQ_COMPANIES에 넣어 Finnhub로 처리한다.

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

// NASDAQ 유니버스 (큐레이션된 시총 상위 후보군, top-20의 상위집합).
// FMP 무료 플랜은 스크리너를 지원하지 않으므로(레거시 폐지 + 신규 엔드포인트 유료) KOSPI·JPX 등과
// 동일하게 정적 유니버스를 유지하고, 실시간 시총은 Finnhub로 계산해 상위 20개를 뽑는다.
// 진짜 top-20이 항상 포함되도록 여유분(버퍼)을 넉넉히 담아두면(현재 ~28개) 순위가 정확해진다.
// 시총 순위는 재정렬되므로 20위 밖 종목이 섞여 있어도 무해하고, ALL과 겹치는 것도 정상.
const NASDAQ_COMPANIES: CompanyMeta[] = [
  { ticker: 'NVDA',  name: 'NVIDIA',            color: '#78BB17' },
  { ticker: 'AAPL',  name: 'Apple',             color: '#8E8E93' },
  { ticker: 'MSFT',  name: 'Microsoft',         color: '#0078D4' },
  { ticker: 'GOOGL', name: 'Alphabet',          color: '#EA4335' },
  { ticker: 'AMZN',  name: 'Amazon',            color: '#FF9900' },
  { ticker: 'META',  name: 'Meta',              color: '#4267B2' },
  { ticker: 'AVGO',  name: 'Broadcom',          color: '#CC0000' },
  { ticker: 'TSLA',  name: 'Tesla',             color: '#CC1C1C' },
  { ticker: 'SPCX',  name: 'SpaceX',            color: '#005288' },
  { ticker: 'MU',    name: 'Micron',            color: '#00AEEF' },
  { ticker: 'WMT',   name: 'Walmart',           color: '#007DC6' },
  { ticker: 'AMD',   name: 'AMD',               color: '#ED1C24' },
  { ticker: 'INTC',  name: 'Intel',             color: '#0068B5' },
  // ASML: 나스닥 'New York Registry Shares'로 상장 → 나스닥 공식 목록에 포함.
  { ticker: 'ASML',  name: 'ASML',              color: '#0B5394' },
  { ticker: 'CSCO',  name: 'Cisco',             color: '#1BA0D7' },
  { ticker: 'AMAT',  name: 'Applied Materials', color: '#1A6DB4' },
  { ticker: 'COST',  name: 'Costco',            color: '#005DAA' },
  { ticker: 'LRCX',  name: 'Lam Research',      color: '#6EBE44' },
  { ticker: 'ARM',   name: 'Arm Holdings',      color: '#1BA8DF' },
  { ticker: 'PLTR',  name: 'Palantir',          color: '#101828' },
  { ticker: 'NFLX',  name: 'Netflix',           color: '#E50914' },
  { ticker: 'KLAC',  name: 'KLA',               color: '#0033A0' },
  { ticker: 'PANW',  name: 'Palo Alto Networks',color: '#FA582D' },
  { ticker: 'TXN',   name: 'Texas Instruments', color: '#CC0000' },
  { ticker: 'LIN',   name: 'Linde',             color: '#005591' },
  { ticker: 'TMUS',  name: 'T-Mobile',          color: '#E20074' },
  { ticker: 'AMGN',  name: 'Amgen',             color: '#0063C3' },
  { ticker: 'ADBE',  name: 'Adobe',             color: '#FA0F00' },
  { ticker: 'INTU',  name: 'Intuit',            color: '#365EBF' },
  { ticker: 'QCOM',  name: 'Qualcomm',          color: '#3253DC' },
  { ticker: 'ISRG',  name: 'Intuitive Surgical',color: '#486B92' },
]

// NYSE 유니버스 (큐레이션된 시총 상위 후보군, top-20의 상위집합) — NASDAQ과 동일 정책.
// ⚠️ 거래소 구분은 Finnhub profile2의 exchange 필드를 기준으로 맞춘다(앱 데이터 소스와 일치).
//    예: Walmart(WMT)는 Finnhub·나스닥 공식 스크리너 모두 NASDAQ으로 분류하므로 NASDAQ에 둔다.
//
// 큐레이션 규칙(무료 플랜엔 스크리너가 없어 '조건식' 대신 리스트에 이 원칙을 적용):
//   ✓ 보통주 + 미국 상장 ADR(이중상장 원주) 포함 — TSM·HSBC 등. 티커는 스폰서드 ADR(bare 심볼).
//   ✗ 우선주(preferred, 예: BAC-PB / BRK.A 아님) · 파생/구조화 증권(warrant·unit·ETN 등) 제외.
//   · ADR 시총: Finnhub marketCapitalization이 이미 USD 총액이면 그대로 사용, TWD 등 현지통화면
//     TSM처럼 별도 환산. (HSBC는 USD 총액이라 별도 계산 불필요)
const NYSE_COMPANIES: CompanyMeta[] = [
  { ticker: 'BRK.B', name: 'Berkshire',        color: '#8B5E20' },
  { ticker: 'LLY',   name: 'Eli Lilly',        color: '#8B5CF6' },
  { ticker: 'JPM',   name: 'JPMorgan',         color: '#005EB8' },
  { ticker: 'V',     name: 'Visa',             color: '#1A1F71' },
  { ticker: 'JNJ',   name: 'J&J',              color: '#D51900' },
  { ticker: 'XOM',   name: 'ExxonMobil',       color: '#1A1A1A' },
  { ticker: 'MA',    name: 'Mastercard',       color: '#EB001B' },
  { ticker: 'ABBV',  name: 'AbbVie',           color: '#071D49' },
  { ticker: 'BAC',   name: 'Bank of America',  color: '#E31837' },
  { ticker: 'CAT',   name: 'Caterpillar',      color: '#FFCD11' },
  { ticker: 'UNH',   name: 'UnitedHealth',     color: '#002677' },
  { ticker: 'CVX',   name: 'Chevron',          color: '#0066B2' },
  { ticker: 'ORCL',  name: 'Oracle',           color: '#F80000' },
  { ticker: 'GE',    name: 'GE Aerospace',     color: '#005EB8' },
  { ticker: 'KO',    name: 'Coca-Cola',        color: '#F40000' },
  { ticker: 'PG',    name: 'P&G',              color: '#003DA5' },
  { ticker: 'MS',    name: 'Morgan Stanley',   color: '#002855' },
  { ticker: 'HD',    name: 'Home Depot',       color: '#F96302' },
  { ticker: 'GS',    name: 'Goldman Sachs',    color: '#002F6C' },
  { ticker: 'MRK',   name: 'Merck',            color: '#00857C' },
  { ticker: 'PM',    name: 'Philip Morris',    color: '#005CB9' },
  { ticker: 'RTX',   name: 'RTX',              color: '#E4002B' },
  { ticker: 'WFC',   name: 'Wells Fargo',      color: '#D71E28' },
  { ticker: 'CRM',   name: 'Salesforce',       color: '#00A1E0' },
  { ticker: 'AXP',   name: 'American Express',  color: '#006FCF' },
  { ticker: 'C',     name: 'Citigroup',        color: '#056DAE' },
  { ticker: 'MCD',   name: "McDonald's",       color: '#FFC72C' },
  { ticker: 'ACN',   name: 'Accenture',        color: '#A100FF' },
  { ticker: 'TSM',   name: 'TSMC',             color: '#0073CE' },
  { ticker: 'HSBC',  name: 'HSBC',             color: '#DB0011' },  // NYSE 상장 스폰서드 ADR
]

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

// SK Hynix: 나스닥 공식 스크리너에는 ADR(American Depositary Shares)로 나스닥 상위권에 오르지만
// Finnhub 무료 플랜엔 US 심볼이 없다(검색 결과 000660.KS만 존재). 동일 기업이므로 한국 상장
// 시총(KRX·Naver)을 그대로 USD 환산해 나스닥 섹션에도 주입한다. 시총은 통화 무관으로 동일해
// 순위가 나스닥 공식과 일치한다. (KOSPI 섹션과 중복 노출은 TSM처럼 정상)
const SKHYNIX_KRX: KoreanStockMeta = { ticker: '000660.KS', yahooTicker: '000660.KS', name: 'SK Hynix', color: '#EA5504' }

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

// Euronext(범유럽 통합 거래소) 시총 상위 종목 (하드코딩 유니버스).
// 파리(.PA)·암스테르담(.AS)·밀라노(.MI) 등 도시별 접미사를 쓰지만 모두 EUR 표시통화라
// currency는 'eur' 하나로 통일. 오슬로(.OL, NOK)는 통화가 달라 이번 범위에서 제외.
// SAP(프랑크푸르트)·노보노디스크(코펜하겐)는 유로넥스트가 아니므로 포함하지 않는다.
// marketCap은 EUR 단위 → forex.eur(EUR/USD)로 나눠 USD 환산. Finnhub 무료는 유럽 미지원 →
// Aramco·KRX와 동일하게 Yahoo Finance HTML 파싱으로 시세/시총 확보.
const EURONEXT_COMPANIES: ForeignStockMeta[] = [
  { ticker: 'ASML.AS',  yahooTicker: 'ASML.AS',  name: 'ASML',              color: '#0B5394' },
  { ticker: 'MC.PA',    yahooTicker: 'MC.PA',    name: 'LVMH',              color: '#2B2B2B' },
  { ticker: 'RMS.PA',   yahooTicker: 'RMS.PA',   name: 'Hermès',            color: '#F37021' },
  { ticker: 'OR.PA',    yahooTicker: 'OR.PA',    name: "L'Oréal",           color: '#000000' },
  { ticker: 'TTE.PA',   yahooTicker: 'TTE.PA',   name: 'TotalEnergies',     color: '#E3001B' },
  { ticker: 'PRX.AS',   yahooTicker: 'PRX.AS',   name: 'Prosus',            color: '#00A0DF' },
  { ticker: 'SAN.PA',   yahooTicker: 'SAN.PA',   name: 'Sanofi',            color: '#7A00E6' },
  { ticker: 'SU.PA',    yahooTicker: 'SU.PA',    name: 'Schneider Elec.',   color: '#3DCD58' },
  { ticker: 'AI.PA',    yahooTicker: 'AI.PA',    name: 'Air Liquide',       color: '#005BAC' },
  { ticker: 'EL.PA',    yahooTicker: 'EL.PA',    name: 'EssilorLuxottica',  color: '#1A1A1A' },
  { ticker: 'RACE.MI',  yahooTicker: 'RACE.MI',  name: 'Ferrari',           color: '#FF2800' },
  { ticker: 'AIR.PA',   yahooTicker: 'AIR.PA',   name: 'Airbus',            color: '#00205B' },
  { ticker: 'SAF.PA',   yahooTicker: 'SAF.PA',   name: 'Safran',            color: '#E2001A' },
  { ticker: 'CDI.PA',   yahooTicker: 'CDI.PA',   name: 'Christian Dior',    color: '#000000' },
  { ticker: 'BNP.PA',   yahooTicker: 'BNP.PA',   name: 'BNP Paribas',       color: '#00915A' },
  { ticker: 'ENEL.MI',  yahooTicker: 'ENEL.MI',  name: 'Enel',              color: '#0072CE' },
  { ticker: 'ADYEN.AS', yahooTicker: 'ADYEN.AS', name: 'Adyen',             color: '#0ABF53' },
  { ticker: 'UCG.MI',   yahooTicker: 'UCG.MI',   name: 'UniCredit',         color: '#E2001A' },
  { ticker: 'ISP.MI',   yahooTicker: 'ISP.MI',   name: 'Intesa Sanpaolo',   color: '#007A33' },
  { ticker: 'DG.PA',    yahooTicker: 'DG.PA',    name: 'Vinci',             color: '#E2001A' },
  { ticker: 'INGA.AS',  yahooTicker: 'INGA.AS',  name: 'ING Group',         color: '#FF6200' },
  { ticker: 'BN.PA',    yahooTicker: 'BN.PA',    name: 'Danone',            color: '#005EB8' },
]

// Finnhub 무료: 60 calls/min
// Quote 5개씩 배치(200ms 딜레이), 21초 캐시 → burst rate limit 방지 ✓
// Profile 1시간 캐시 → 서버 재시작 시에만 호출                        ✓
// Forex 1개, 1시간 캐시 → ~24 calls/day (~720/month) → OXR 무료 1,000/월 한도 안전 ✓
const QUOTE_TTL_MS   = 21_000
const PROFILE_TTL_MS = 3_600_000
const FOREX_TTL_MS   = 3_600_000   // 1시간 (60 × 60 × 1000)

// 미국 종목 '순위 기준 시총'은 Yahoo Finance marketCap을 앵커로 쓴다(나스닥 공식과 잘 맞음, 예:
// Walmart를 Finnhub는 ~10% 부풀리지만 Yahoo는 공식과 일치). 시총·주식수는 하루 안에 거의 안
// 변하므로 6시간 캐시로 안정화하고, Yahoo 실패(429/크럼) 시 마지막 성공값 유지 → 그래도 없으면
// Finnhub 사전계산값으로 자연 폴백한다. 라이브 등락은 그대로 Finnhub quote(c/pc)로 반영.
const US_YAHOO_CAP_TTL_MS = 6 * 60 * 60 * 1000   // 6시간

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
  pc: number  // previous close — 시총 라이브 환산(precomputed × c/pc)에 사용
}

interface ProfileData {
  marketCapitalization: number  // millions USD — Finnhub 사전계산 시총(일 단위 갱신, 정확)
  shareOutstanding: number      // millions of shares (보통주 기준) — TSM ADR 계산에만 사용
}

interface ForexRates {
  krw: number  // KRW/USD
  jpy: number  // JPY/USD — JPX 환산용
  cny: number  // CNY/USD — SSE 환산용
  eur: number  // EUR/USD — Euronext 환산용
}

interface OXRResponse {
  rates: Record<string, number>
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

// 해외 거래소(JPX/SSE/SZSE) 배치 quote 1건 (현지 통화). Yahoo v7 응답에서 매핑.
interface ForeignQuote {
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
// 진행 중 요청 병합(coalescing) — ALL·NASDAQ·NYSE 피드가 같은 티커(BRK.B·JPM·TSM …)를
// 동시에 조회할 때 Finnhub 호출을 1건으로 합쳐 무료 한도(60/min) 소진을 줄인다.
const quoteInFlight   = new Map<string, Promise<QuoteData>>()
const profileInFlight = new Map<string, Promise<ProfileData>>()
const krxQuoteCache   = new Map<string, CacheEntry<KRXQuoteData>>()
const naverKRXCache   = new Map<string, CacheEntry<KRXQuoteData>>()
// 해외 거래소 Yahoo v7 배치 quote 결과 캐시 (거래소 키). QUOTE_TTL로 콜수 절감.
const foreignQuoteCache = new Map<string, CacheEntry<Map<string, ForeignQuote>>>()
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
// 미국 종목 Yahoo marketCap 앵커 캐시 (ticker → 시총 조 단위, 6시간 TTL, 마지막 성공값 유지)
const usYahooCapCache = new Map<string, CacheEntry<number>>()
// Yahoo 실패(429 등) 시 쿨다운 — 매 폴링마다 죽은 Yahoo에 재시도해 지연/부하를 주지 않도록.
const US_YAHOO_CAP_ERROR_COOLDOWN_MS = 10 * 60 * 1000  // 10분
let usYahooCapErrorUntil = 0

let lastGoodResult: CompanyResult[] | null = null
let lastGoodAt = 0
let lastGoodExchangeRate = FOREX_FALLBACK
// 마지막 성공 환율 전체(KRW/JPY/CNY). OXR 실패 시 통화별 폴백으로 사용.
let lastGoodForex: ForexRates = { krw: FOREX_FALLBACK, jpy: JPY_FALLBACK, cny: CNY_FALLBACK, eur: EUR_FALLBACK }

// 거래소 전용 피드 상태 (ALL과 분리해 서로 간섭하지 않도록).
// 신규 거래소는 여기 한 줄만 추가하면 확장됨.
interface ExchangeFeedState {
  lastGoodResult: CompanyResult[] | null            // 마지막 성공 랭킹 (stale 폴백)
  lastGoodAt:     number
}
const exchangeFeeds: Record<string, ExchangeFeedState> = {
  NASDAQ: { lastGoodResult: null, lastGoodAt: 0 },
  NYSE:   { lastGoodResult: null, lastGoodAt: 0 },
  KOSPI:  { lastGoodResult: null, lastGoodAt: 0 },
  KOSDAQ: { lastGoodResult: null, lastGoodAt: 0 },
  JPX:    { lastGoodResult: null, lastGoodAt: 0 },
  SSE:    { lastGoodResult: null, lastGoodAt: 0 },
  SZSE:   { lastGoodResult: null, lastGoodAt: 0 },
  EURONEXT: { lastGoodResult: null, lastGoodAt: 0 },
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

// finance.yahoo.com HTML 페이지에 SSR로 임베드된 v7 quoteResponse를 파싱.
// v7/v8 JSON API는 crumb 인증 + IP 레이트리밋(429)으로 막히지만 HTML 페이지는 응답하므로
// KRX Yahoo 폴백·Aramco·해외 거래소(JPX/SSE/SZSE)가 공통으로 사용한다.
// 한 페이지에 여러 심볼(관련 종목 등)이 임베드되므로 symbol이 일치하는 result만 고른다.
// marketCap.raw는 해당 종목의 표시 통화 단위(KRW/JPY/CNY/SAR …) — 호출부에서 환산.
function parseYahooHtmlQuote(html: string, yahooTicker: string): {
  price: number
  change: number
  changePercent: number
  marketCap: number
} | null {
  const scriptRe = /<script[^>]*>([\s\S]*?)<\/script>/g
  let match: RegExpExecArray | null
  while ((match = scriptRe.exec(html)) !== null) {
    const content = match[1]
    if (!content.includes('quoteResponse')) continue
    try {
      const outer = JSON.parse(content)

      // Case 1: quoteResponse가 body 문자열 내부에 중첩된 경우 / Case 2: 최상위인 경우
      let results: any[] | null = null
      if (typeof outer.body === 'string') {
        results = JSON.parse(outer.body)?.quoteResponse?.result ?? null
      }
      if (!results) results = outer?.quoteResponse?.result ?? null
      if (!Array.isArray(results)) continue

      const result = results.find(r => r?.symbol === yahooTicker)
      if (!result) continue

      const price         = (result.regularMarketPrice?.raw ?? result.regularMarketOpen?.raw ?? 0) as number
      const change        = (result.regularMarketChange?.raw ?? 0) as number
      const changePercent = (result.regularMarketChangePercent?.raw ?? 0) as number
      const marketCap     = (result.marketCap?.raw ?? 0) as number
      if (!price || !marketCap) continue

      return { price, change, changePercent, marketCap }
    } catch { continue }
  }
  return null
}

// ─── Finnhub 전역 레이트리미터 ─────────────────────────────────────────────────
// 무료 플랜은 60 calls/min. ALL·NASDAQ·NYSE 세 피드가 하나의 토큰을 공유하므로
// 각 피드가 quote+profile를 동시 버스트로 쏘면 분당 한도를 넘겨 429가 나고,
// 실패한 종목이 null로 빠져 섹션 목록이 20개 미만(예: 14개)으로 줄어든다.
//
// 논블로킹 슬라이딩 윈도우 예산. 무료 한도(60/min)를 지속적으로 넘겨 429가 쏟아지면
// Finnhub가 토큰을 일시 차단할 수 있으므로, 최근 60초 호출이 예산에 도달하면 '대기하지 않고'
// 즉시 실패시킨다. 그러면 getQuote가 throw → fetchFinnhubRows가 stale 캐시로 폴백하고,
// 부족분은 rankWithBackfill이 직전 랭킹으로 채워 목록은 20개를 유지한다.
// 대기가 없으므로 응답은 항상 빠르고(캐시 히트), 갱신은 "예산 안에서 가능한 만큼만" 이뤄진다.
const FINNHUB_MAX_PER_MIN = 55   // 60 한도 대비 여유
const finnhubCallTimes: number[] = []  // 최근 60초 호출 시각(ms)

function acquireFinnhubSlot(): void {
  const now = Date.now()
  while (finnhubCallTimes.length && now - finnhubCallTimes[0] > 60_000) finnhubCallTimes.shift()
  if (finnhubCallTimes.length >= FINNHUB_MAX_PER_MIN) throw new Error('finnhub rate budget exceeded')
  finnhubCallTimes.push(now)
}

async function finnhubFetch(url: string): Promise<Response> {
  acquireFinnhubSlot()
  return fetch(url, { cache: 'no-store' })
}

// ─── Finnhub Fetchers ─────────────────────────────────────────────────────────

async function getQuote(ticker: string): Promise<QuoteData> {
  const hit = quoteCache.get(ticker)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const pending = quoteInFlight.get(ticker)
  if (pending) return pending

  const task = (async (): Promise<QuoteData> => {
    const res = await finnhubFetch(
      `${BASE}/quote?symbol=${encodeURIComponent(ticker)}&token=${FINNHUB_TOKEN}`,
    )
    if (!res.ok) throw new Error(`quote ${ticker} → HTTP ${res.status}`)
    const data: QuoteData = await res.json()
    if (!data.c) throw new Error(`quote ${ticker} → empty response`)
    quoteCache.set(ticker, { data, ts: Date.now() })
    return data
  })().finally(() => quoteInFlight.delete(ticker))

  quoteInFlight.set(ticker, task)
  return task
}

async function getProfile(ticker: string): Promise<ProfileData> {
  const hit = profileCache.get(ticker)
  if (hit && Date.now() - hit.ts < PROFILE_TTL_MS) return hit.data

  const pending = profileInFlight.get(ticker)
  if (pending) return pending

  const task = (async (): Promise<ProfileData> => {
    const res = await finnhubFetch(
      `${BASE}/stock/profile2?symbol=${encodeURIComponent(ticker)}&token=${FINNHUB_TOKEN}`,
    )
    if (!res.ok) throw new Error(`profile ${ticker} → HTTP ${res.status}`)
    const data: ProfileData = await res.json()
    if (!data.marketCapitalization) throw new Error(`profile ${ticker} → marketCapitalization missing`)
    profileCache.set(ticker, { data, ts: Date.now() })
    return data
  })().finally(() => profileInFlight.delete(ticker))

  profileInFlight.set(ticker, task)
  return task
}

async function getForexRates(): Promise<ForexRates> {
  if (forexCache && Date.now() - forexCache.ts < FOREX_TTL_MS) return forexCache.data

  const res = await fetch(
    `https://openexchangerates.org/api/latest.json?app_id=${OXR_APP_ID}&symbols=KRW,JPY,CNY,EUR`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`forex rates → HTTP ${res.status}`)
  const data: OXRResponse = await res.json()
  const krw = data.rates?.KRW
  if (!krw || !isFinite(krw)) throw new Error('forex KRW rate missing or invalid')
  // JPY/CNY/EUR는 부분 누락돼도 KRW만 있으면 진행 — 없으면 마지막 성공값으로 폴백.
  const jpy = data.rates?.JPY
  const cny = data.rates?.CNY
  const eur = data.rates?.EUR
  const rates: ForexRates = {
    krw,
    jpy: (jpy && isFinite(jpy)) ? jpy : lastGoodForex.jpy,
    cny: (cny && isFinite(cny)) ? cny : lastGoodForex.cny,
    eur: (eur && isFinite(eur)) ? eur : lastGoodForex.eur,
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

    const parsed = parseYahooHtmlQuote(await res.text(), yahooTicker)
    if (!parsed) throw new Error(`KRX HTML ${yahooTicker} → quote data not found in page scripts`)

    const data: KRXQuoteData = {
      price:         parsed.price,
      change:        parsed.change,
      changePercent: parsed.changePercent,
      marketCapKRW:  parsed.marketCap,
    }
    krxQuoteCache.set(yahooTicker, { data, ts: Date.now() })
    krxLastGoodCache.set(yahooTicker, data)
    return data
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

// ─── JPX·SSE·SZSE Fetcher (Tencent qt.gtimg.cn 배치 quote) ───────────────────
// Finnhub 무료는 아시아 미지원, Naver는 한국 전용, FMP 무료는 국제 종목 미지원.
// Yahoo v7 API는 crumb 인증 + IP 레이트리밋(429)으로, HTML은 상당수 심볼 404로 불안정.
// → 텐센트(qt.gtimg.cn)를 쓴다. A주(상하이 sh·선전 sz)와 일본(jp)을 모두 커버하고,
//   현재가·등락률·총시가총액을 IP 차단 없이 1콜 배치로 반환한다(한국의 Naver와 같은 역할).
// 응답은 `v_sh600519="1~名~code~price~...";` 형태의 GBK 인코딩 `~` 구분 문자열.
// 필드 인덱스: [3] 현재가 · [31] 등락 · [32] 등락% · [45] 총시가총액(억 단위 현지통화 JPY/CNY).
// 시총 = f[45] × 1e8(억) → forex(jpy/cny)로 나눠 USD 환산.

const TENCENT_QUOTE_URL = 'https://qt.gtimg.cn/q='

// 야후 심볼(005930.KS류가 아닌 7203.T/600519.SS/300750.SZ) → 텐센트 코드로 변환.
// .SS→sh, .SZ→sz, .T→jp (접미사 제거 후 접두사 부착). 그 외는 매핑 불가로 null.
function tencentCode(ticker: string): string | null {
  if (ticker.endsWith('.SS')) return 'sh' + ticker.slice(0, -3)
  if (ticker.endsWith('.SZ')) return 'sz' + ticker.slice(0, -3)
  if (ticker.endsWith('.T'))  return 'jp' + ticker.slice(0, -2)
  return null
}

// 유니버스 전 종목을 텐센트 1콜 배치로 조회 → 텐센트코드별 ForeignQuote 맵.
// GBK 응답을 디코드해 라인별로 파싱. 데이터 없는(가격/시총 0) 종목은 맵에서 누락.
async function fetchForeignQuotes(tencentCodes: string[]): Promise<Map<string, ForeignQuote>> {
  const res = await fetch(TENCENT_QUOTE_URL + tencentCodes.join(','), {
    headers: { 'Referer': 'https://gu.qq.com/' },
    cache: 'no-store',
  })
  if (!res.ok) throw new Error(`Tencent quote → HTTP ${res.status}`)

  // 종목명(f[1])은 GBK 한자라 정확한 디코드 필요. 숫자/구분자는 ASCII라 파싱엔 영향 없음.
  const text = new TextDecoder('gbk').decode(await res.arrayBuffer())

  const map = new Map<string, ForeignQuote>()
  const lineRe = /v_(\w+)="([^"]*)"/g
  let m: RegExpExecArray | null
  while ((m = lineRe.exec(text)) !== null) {
    const code = m[1]
    const f    = m[2].split('~')
    const price     = parseFloat(f[3])
    const marketCap = parseFloat(f[45]) * 1e8   // f[45]: 총시가총액(억) → 현지통화 원단위
    if (!price || !marketCap || !isFinite(marketCap)) continue
    map.set(code, {
      price,
      change:        parseFloat(f[31]) || 0,
      changePercent: parseFloat(f[32]) || 0,
      marketCap,
      currency:      '',
    })
  }
  return map
}

// 거래소 단위 캐시(QUOTE_TTL) — 폴링마다 배치를 반복하지 않도록.
async function getForeignQuotes(exchange: string, tencentCodes: string[]): Promise<Map<string, ForeignQuote>> {
  const hit = foreignQuoteCache.get(exchange)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data
  const map = await fetchForeignQuotes(tencentCodes)
  foreignQuoteCache.set(exchange, { data: map, ts: Date.now() })
  return map
}

// ─── Yahoo v7 JSON Fetcher (crumb 인증, Euronext 등) ──────────────────────────
// 텐센트가 유럽을 커버하지 않고(=pv_none_match), Finnhub·FMP 무료는 미국 전용이며,
// finance.yahoo.com HTML은 일부 유럽 심볼(RMS.PA·SAN.PA·ENEL.MI 등)을 '결정적으로'
// 404 처리해 벌크 소스로 못 쓴다. 대신 Yahoo v7 quote JSON을 crumb+쿠키로 인증해
// 1콜 배치로 전 종목의 시세·등락·시가총액(표시통화)을 받는다(yfinance와 동일 방식).
// marketCap은 종목 표시통화(EUR 등) 단위 → 호출부에서 forex로 USD 환산.

interface YahooQuoteData {
  price:         number
  change:        number
  changePercent: number
  marketCap:     number  // 현지통화(EUR 등) 단위
  currency:      string
}

// v7 배치 결과 캐시(거래소 키, QUOTE_TTL) + 개별 종목 stale 폴백(목록 안정화)
const yahooV7Cache    = new Map<string, CacheEntry<Map<string, YahooQuoteData>>>()
const yahooV7LastGood = new Map<string, YahooQuoteData>()

// crumb·쿠키는 세션 단위로 재사용(30분). v7 quote가 401/403이면 즉시 무효화해 재발급.
interface YahooAuth { cookie: string; crumb: string; ts: number }
let yahooAuth: YahooAuth | null = null
const YAHOO_AUTH_TTL_MS = 30 * 60 * 1000

// Set-Cookie 헤더들에서 name=value 쌍을 쿠키 맵(name→'name=value')에 병합한다.
// undici(Node fetch)는 getSetCookie()로 개별 쿠키 배열을 준다(구버전은 get 폴백).
function mergeCookies(res: Response, map: Map<string, string>): void {
  const anyH = res.headers as unknown as { getSetCookie?: () => string[] }
  const list = anyH.getSetCookie?.()
    ?? (res.headers.get('set-cookie') ? [res.headers.get('set-cookie') as string] : [])
  for (const raw of list) {
    const pair = raw.split(';')[0].trim()
    const name = pair.split('=')[0]
    if (name) map.set(name, pair)
  }
}

async function getYahooAuth(): Promise<YahooAuth> {
  if (yahooAuth && Date.now() - yahooAuth.ts < YAHOO_AUTH_TTL_MS) return yahooAuth

  // Yahoo Finance의 인증 쿠키(A1 등)는 finance.yahoo.com/ 접속 시 리다이렉트 체인의
  // 각 홉(hop)에서 Set-Cookie로 심어진다. Node.js fetch는 redirect:'follow' 시 중간
  // 홉의 Set-Cookie를 누락하므로, redirect:'manual'로 홉을 직접 따라가며 쿠키를 누적한다.
  const cookieMap = new Map<string, string>()
  let url = 'https://finance.yahoo.com/'
  for (let hop = 0; hop < 6; hop++) {
    const res = await fetch(url, {
      headers: { ...YF_HTML_HEADERS, ...(cookieMap.size ? { Cookie: [...cookieMap.values()].join('; ') } : {}) },
      redirect: 'manual',
      cache: 'no-store',
    })
    mergeCookies(res, cookieMap)
    if (res.status < 300 || res.status >= 400) break
    const location = res.headers.get('location')
    if (!location) break
    url = location.startsWith('http') ? location : new URL(location, url).toString()
  }

  const cookie = [...cookieMap.values()].join('; ')
  if (!cookie) throw new Error('Yahoo auth → cookie 확보 실패')

  // crumb 확보 — query2는 query1보다 rate-limit이 여유로워 서버 환경에서 더 안정적.
  const crumbRes = await fetch('https://query2.finance.yahoo.com/v1/test/getcrumb', {
    headers: { ...YF_HTML_HEADERS, Cookie: cookie }, cache: 'no-store',
  })
  const crumb = (await crumbRes.text()).trim()
  if (!crumbRes.ok || !crumb || /too many|<html/i.test(crumb)) {
    throw new Error(`Yahoo auth → crumb 실패 (HTTP ${crumbRes.status}: ${crumb.slice(0, 40)})`)
  }

  yahooAuth = { cookie, crumb, ts: Date.now() }
  return yahooAuth
}

// 유니버스 전 종목을 v7 quote 1콜 배치로 조회 → 심볼별 ForeignQuote 맵. 거래소 키로 캐시.
async function getYahooV7Quotes(exchange: string, symbols: string[]): Promise<Map<string, YahooQuoteData>> {
  const hit = yahooV7Cache.get(exchange)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const { cookie, crumb } = await getYahooAuth()
  const url = 'https://query2.finance.yahoo.com/v7/finance/quote'
    + `?symbols=${encodeURIComponent(symbols.join(','))}&crumb=${encodeURIComponent(crumb)}`
  const res = await fetch(url, { headers: { ...YF_HTML_HEADERS, Cookie: cookie }, cache: 'no-store' })
  if (res.status === 401 || res.status === 403) yahooAuth = null  // crumb 만료 → 다음 호출서 재발급
  if (!res.ok) throw new Error(`Yahoo v7 ${exchange} → HTTP ${res.status}`)

  const json = await res.json()
  const results: any[] = json?.quoteResponse?.result ?? []
  const map = new Map<string, YahooQuoteData>()
  for (const r of results) {
    const price     = r.regularMarketPrice as number
    const marketCap = r.marketCap as number
    if (!price || !marketCap || !isFinite(marketCap)) continue
    const q: YahooQuoteData = {
      price,
      change:        (r.regularMarketChange as number) ?? 0,
      changePercent: (r.regularMarketChangePercent as number) ?? 0,
      marketCap,
      currency:      (r.currency as string) ?? '',
    }
    map.set(r.symbol, q)
    yahooV7LastGood.set(r.symbol, q)
  }
  yahooV7Cache.set(exchange, { data: map, ts: Date.now() })
  return map
}

// ─── US 종목 Yahoo marketCap 앵커 ─────────────────────────────────────────────
// 미국 종목의 순위 기준 시총을 Yahoo v7 배치로 확보한다. Finnhub 사전계산값보다 나스닥 공식과
// 잘 맞고(예: WMT), 심볼 제한도 없다. 6시간 캐시라 배치 호출은 하루 몇 번뿐 → Yahoo 부하 최소.

// 우리 티커 → Yahoo 미국 심볼. BRK.B→BRK-B. ADR(TSM·HSBC)은 별도 계산이라 제외(null).
function usYahooSymbol(ticker: string): string | null {
  if (ADR_SHARE_RATIO[ticker]) return null
  return ticker.replace(/\./g, '-')
}

// Yahoo v7 배치 quote에서 marketCap(USD)만 뽑아 심볼→시총(USD) 맵으로. (자체 캐시 없음: 6시간
// 캐시는 usYahooCapCache가 담당) crumb 만료 시 무효화해 다음 호출서 재발급.
async function fetchYahooCapsBatch(yahooSyms: string[]): Promise<Map<string, number>> {
  const { cookie, crumb } = await getYahooAuth()
  const url = 'https://query2.finance.yahoo.com/v7/finance/quote'
    + `?symbols=${encodeURIComponent(yahooSyms.join(','))}&crumb=${encodeURIComponent(crumb)}`
  const res = await fetch(url, { headers: { ...YF_HTML_HEADERS, Cookie: cookie }, cache: 'no-store' })
  if (res.status === 401 || res.status === 403) yahooAuth = null
  if (!res.ok) throw new Error(`Yahoo US caps → HTTP ${res.status}`)
  const json = await res.json()
  const out = new Map<string, number>()
  for (const r of (json?.quoteResponse?.result ?? []) as any[]) {
    const mc = r.marketCap as number
    if (mc && isFinite(mc)) out.set(r.symbol as string, mc)
  }
  return out
}

// 요청 티커 중 캐시가 만료(6시간)된 것만 골라 Yahoo 배치 1콜로 갱신, usYahooCapCache에 저장.
// 실패해도 조용히 넘어가고 마지막 성공값을 유지한다(호출부에서 Finnhub 폴백).
async function refreshUsYahooCaps(tickers: string[]): Promise<void> {
  const now = Date.now()
  if (now < usYahooCapErrorUntil) return  // 쿨다운 중 — Finnhub 폴백 유지

  const yahooSyms: string[] = []
  const symToTicker = new Map<string, string>()
  for (const t of tickers) {
    const hit = usYahooCapCache.get(t)
    if (hit && now - hit.ts < US_YAHOO_CAP_TTL_MS) continue
    const ys = usYahooSymbol(t)
    if (!ys) continue
    yahooSyms.push(ys)
    symToTicker.set(ys, t)
  }
  if (yahooSyms.length === 0) return
  try {
    const caps = await fetchYahooCapsBatch(yahooSyms)
    let got = 0
    for (const [ys, t] of symToTicker) {
      const mc = caps.get(ys)
      if (mc && mc > 0) { usYahooCapCache.set(t, { data: mc / 1_000_000_000_000, ts: now }); got++ }
    }
    // 응답이 왔지만 시총이 하나도 안 잡히면(엔드포인트 잠김 등) 잠시 쉰다.
    if (got === 0) usYahooCapErrorUntil = now + US_YAHOO_CAP_ERROR_COOLDOWN_MS
  } catch (err) {
    usYahooCapErrorUntil = now + US_YAHOO_CAP_ERROR_COOLDOWN_MS
    console.warn('[market-cap] US Yahoo marketCap refresh failed, cooling down; Finnhub fallback in use:', err)
  }
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
    const scriptRe = /<script[^>]*>([\s\S]*?)<\/script>/g
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


// ─── Finnhub Company Rows (ALL / NASDAQ / NYSE 공통) ──────────────────────────
// 주어진 회사 목록을 Finnhub로 조회해 CompanyResult(rank 제외) 배열로 변환.
//
// 순위는 profile.marketCapitalization(사전계산 시총, 1시간 캐시 → 거의 항상 웜)으로 정한다.
// quote(시세, 21초 캐시)는 무료 한도(60/min)에서 자주 레이트리밋에 걸리므로, quote가 빠져도
// 프로필만 있으면 종목을 살려 목록이 20개 밑으로 줄지 않게 한다:
//   · quote 실패 → 만료된 quote 캐시라도 사용, 그마저 없으면 시세 0·등락 0(순위는 사전계산 시총 기준).
//   · TSM만 사전계산 시총이 TWD라 ADR가로 별도 계산 → 시세가 꼭 필요하므로 없으면 stale로 폴백.
// profile 자체가 실패하면 finnhubLastGoodCache(직전 성공값)로 폴백, 그것도 없으면 null(제외).
async function fetchFinnhubRows(
  companies: CompanyMeta[],
): Promise<(Omit<CompanyResult, 'rank'> | null)[]> {
  // 콜드 스타트에서 무료 한도(60/min)를 quote·profile이 나눠 쓰면 목록 뒤쪽 종목이 예산
  // 고갈로 계속 굶어(warm 실패) 순위에서 영구 누락된다. 순위 기준은 profile(1시간 캐시)이므로
  // 1) 프로필을 먼저 배치로 확보해 우선 warm시키고 → 2) 남는 예산으로 시세를 채운다.
  // 실패 시 만료된 캐시라도 재사용(persistence)해, 한 번 warm된 종목은 목록에서 사라지지 않는다.
  // 순위 앵커: Yahoo marketCap(6시간 캐시, 나스닥 공식과 잘 맞음). 실패 시 Finnhub로 폴백.
  await refreshUsYahooCaps(companies.map(c => c.ticker))

  const profiles = await mapInBatches(companies, BATCH_SIZE, BATCH_DELAY_MS,
    async (co): Promise<ProfileData | null> => {
      try { return await getProfile(co.ticker) }
      catch { return profileCache.get(co.ticker)?.data ?? null }  // 만료 캐시 폴백
    })
  const quotes = await mapInBatches(companies, BATCH_SIZE, BATCH_DELAY_MS,
    async (co): Promise<QuoteData | null> => {
      try { return await getQuote(co.ticker) }
      catch { return quoteCache.get(co.ticker)?.data ?? null }    // 만료 캐시 폴백
    })

  return companies.map((co, i): Omit<CompanyResult, 'rank'> | null => {
    const profile = profiles[i]
    const quote   = quotes[i]
    const yahooCapT = usYahooCapCache.get(co.ticker)?.data  // Yahoo 앵커(있으면 우선)

    // 순위 기준(프로필 또는 Yahoo 앵커)이 아예 없으면 직전 성공값으로 폴백, 그것도 없으면 제외.
    if (!profile && yahooCapT == null) return finnhubLastGoodCache.get(co.ticker) ?? null

    const adrRatio = ADR_SHARE_RATIO[co.ticker]
    let marketCapUSD: number
    if (adrRatio) {
      // ADR(TSM·HSBC 등): 사전계산 marketCapitalization이 부정확/현지통화라 못 쓴다.
      // 보통주수 / ADR비율 × ADR가격으로 직접 계산(나스닥 공식과 일치, 이미 라이브라 c/pc 불필요).
      // 시세·프로필이 없으면 계산 불가 → 아래에서 stale 폴백되도록 0으로 둔다.
      marketCapUSD = (profile && quote) ? profile.shareOutstanding / adrRatio * quote.c / 1_000_000 : 0
    } else {
      // 기준 시총(조 단위): Yahoo 앵커 우선, 없으면 Finnhub 사전계산값.
      // 당일 등락(c/pc)만큼만 라이브 스케일해 KRX(21초) 신선도와 맞춘다.
      const baseT  = yahooCapT ?? (profile ? profile.marketCapitalization / 1_000_000 : 0)
      const ratio  = quote && quote.pc > 0 ? quote.c / quote.pc : 1
      marketCapUSD = baseT * ratio
    }

    // 시총이 0(주로 TSM에서 시세 없음)이면 직전 성공값을 유지해 목록 안정화.
    if (marketCapUSD <= 0) {
      const stale = finnhubLastGoodCache.get(co.ticker)
      if (stale) return stale
    }

    const result: Omit<CompanyResult, 'rank'> = {
      ticker:        co.ticker,
      name:          co.name,
      color:         co.color,
      currentPrice:  quote?.c  ?? 0,
      change:        quote?.d  ?? 0,
      changePercent: quote?.dp ?? 0,
      marketCapUSD,
    }
    finnhubLastGoodCache.set(co.ticker, result)
    return result
  })
}

// ─── Ranking Helper ───────────────────────────────────────────────────────────
// 신선 데이터를 시총순 상위 N개로 랭킹하되, 레이트리밋 등으로 이번 폴링이 N개를
// 못 채우면 직전 성공 랭킹(previous)으로 빈자리를 메워 섹션이 20개 밑으로 내려가지
// 않게 한다. 신선 데이터가 항상 우선하고, 중복 티커는 신선본을 유지한다.
function rankWithBackfill(
  fresh: Omit<CompanyResult, 'rank'>[],
  previous: CompanyResult[] | null,
  limit = 20,
): CompanyResult[] {
  const seen   = new Set(fresh.map(r => r.ticker))
  const merged: Omit<CompanyResult, 'rank'>[] = [...fresh]
  if (previous && merged.length < limit) {
    for (const p of previous) {
      if (merged.length >= limit) break
      if (seen.has(p.ticker)) continue
      const { rank: _rank, ...rest } = p
      merged.push(rest)
      seen.add(p.ticker)
    }
  }
  return merged
    .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
    .slice(0, limit)
    .map((r, i) => ({ ...r, rank: i + 1 }))
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
  if (exchange === 'euronext') return handleYahooExchange('EURONEXT', EURONEXT_COMPANIES, 'eur')
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

    const ranked = rankWithBackfill(allRows, lastGoodResult)

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

// 해외 거래소 전용 핸들러 (JPX/SSE/SZSE 공통) — 하드코딩 유니버스를 텐센트 배치 quote로
// 한 번에 조회 → currency(jpy/cny) 환율로 USD 환산 후 상위 20개 반환.
// Finnhub 무료는 아시아 미지원, Naver는 한국 전용이라 handleKoreanExchange와 달리
// getForeignQuotes(텐센트 배치)를 사용한다. 응답 형태(exchangeRate/data/updatedAt/stale)는 동일.
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

    // 티커 → 텐센트 코드 매핑(변환 불가 종목은 제외). 배치 1콜로 전 종목 조회.
    const codes = companies
      .map(c => tencentCode(c.ticker))
      .filter((c): c is string => c !== null)
    const quotes = await getForeignQuotes(exchange, codes)
    const allRows = companies.map((meta): Omit<CompanyResult, 'rank'> | null => {
      const code = tencentCode(meta.ticker)
      const q    = code ? quotes.get(code) : undefined
      // 배치에서 누락된 종목은 stale 폴백 → 목록 안정화.
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

// Yahoo Finance HTML에서 개별 종목 시세·시총을 파싱해 CompanyResult를 만든다.
// v7 배치가 실패했을 때 Euronext 종목별 폴백으로 사용. 실패 시 foreignLastGoodCache stale 반환.
async function getEuronextHtmlResult(
  meta: ForeignStockMeta,
  eurPerUsd: number,
): Promise<Omit<CompanyResult, 'rank'> | null> {
  try {
    const res = await fetch(
      `https://finance.yahoo.com/quote/${encodeURIComponent(meta.yahooTicker)}/`,
      { headers: YF_HTML_HEADERS, redirect: 'follow', cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`Euronext HTML ${meta.ticker} → HTTP ${res.status}`)
    const parsed = parseYahooHtmlQuote(await res.text(), meta.yahooTicker)
    if (!parsed) throw new Error(`Euronext HTML ${meta.ticker} → quote not found in page`)
    const row: Omit<CompanyResult, 'rank'> = {
      ticker:        meta.ticker,
      name:          meta.name,
      color:         meta.color,
      currentPrice:  parsed.price,
      change:        parsed.change,
      changePercent: parsed.changePercent,
      marketCapUSD:  parsed.marketCap / eurPerUsd / 1_000_000_000_000,
    }
    foreignLastGoodCache.set(meta.ticker, row)
    return row
  } catch (err) {
    const stale = foreignLastGoodCache.get(meta.ticker)
    if (stale) {
      console.warn(`[market-cap:EURONEXT] ${meta.ticker} HTML failed, using stale:`, err)
      return stale
    }
    console.warn(`[market-cap:EURONEXT] ${meta.ticker} HTML failed, skipping:`, err)
    return null
  }
}

// Yahoo v7 기반 해외 거래소 핸들러 (Euronext 등) — crumb 인증 v7 배치 1콜로 전 종목 조회.
// v7 실패 시 getEuronextHtmlResult 개별 HTML 폴백으로 전환해 데이터 공백을 방지한다.
// 응답 형태(exchangeRate/data/updatedAt/stale)는 다른 피드와 동일.
async function handleYahooExchange(
  exchange: string,
  companies: ForeignStockMeta[],
  currency: 'eur',
) {
  const state = exchangeFeeds[exchange]
  try {
    const forexRates = await getForexRates().catch((err) => {
      console.warn(`[market-cap:${exchange}] forex fetch failed, using fallback:`, err)
      return lastGoodForex
    })
    const ratePerUsd = forexRates[currency]

    // 1차: Yahoo v7 crumb 인증 배치 (1콜). 실패 시 2차 개별 HTML 폴백으로 전환.
    let allRows: Omit<CompanyResult, 'rank'>[]
    try {
      const quotes = await getYahooV7Quotes(exchange, companies.map(c => c.yahooTicker))
      allRows = companies.map((meta): Omit<CompanyResult, 'rank'> | null => {
        const q = quotes.get(meta.yahooTicker) ?? yahooV7LastGood.get(meta.yahooTicker)
        if (!q || !q.marketCap || !q.price) {
          if (!q) console.warn(`[market-cap:${exchange}] ${meta.ticker} missing in batch`)
          return null
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
    } catch (v7err) {
      // v7 crumb 인증 실패(서버 환경 쿠키 제한 등) → 개별 HTML 폴백.
      // 일부 유럽 심볼은 Yahoo HTML 404지만, stale 캐시로 보완해 목록 안정화.
      console.warn(`[market-cap:${exchange}] Yahoo v7 failed, falling back to HTML per-symbol:`, v7err)
      const rows = await mapInBatches(companies, 3, 300,
        (meta) => getEuronextHtmlResult(meta, ratePerUsd),
      )
      allRows = rows.filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)
    }

    // 일부 종목이 누락돼도 직전 성공 랭킹으로 보강해 20개 유지.
    const ranked = rankWithBackfill(allRows, state?.lastGoodResult)

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

// 거래소 전용 핸들러 (NASDAQ/NYSE 공통) — 정적 유니버스를 Finnhub로 실시간 시총 계산 →
// 상위 20개 반환. ALL과 동일한 응답 형태(exchangeRate/data/updatedAt/stale)를 유지해 클라이언트가 그대로 디코딩.
async function handleExchange(exchange: string, universe: CompanyMeta[]) {
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

    const rows = await fetchFinnhubRows(universe)
    const allRows = rows.filter(
      (r): r is Omit<CompanyResult, 'rank'> => r !== null,
    )

    // SK Hynix: 나스닥 공식엔 ADR로 상위권이지만 Finnhub 무료엔 US 심볼이 없어 유니버스로 못 잡는다.
    // 한국 상장(000660.KS) 시총을 USD 환산해 나스닥 섹션에 주입 → 공식 순위와 일치시킨다.
    if (exchange === 'NASDAQ') {
      const hynix = await getKRXResult(SKHYNIX_KRX, forexRates.krw).catch((err) => {
        console.warn('[market-cap:NASDAQ] SK Hynix inject failed, skipping:', err)
        return null
      })
      if (hynix) allRows.push(hynix)
    }

    // 레이트리밋 등으로 일부 종목이 빠져도 직전 성공 랭킹으로 보강해 20개 유지.
    const ranked = rankWithBackfill(allRows, state?.lastGoodResult)

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
