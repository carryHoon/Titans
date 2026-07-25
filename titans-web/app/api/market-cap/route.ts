import { NextResponse } from 'next/server'
import { getUsdKrwQuote } from '@/lib/fx'
import { getKrxDataset, startKrPoller } from '@/lib/kr-snapshot'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 코스피/코스닥 데이터는 스냅샷 레이어(@/lib/kr-snapshot)가 소유한다. 발행 창 폴러를 기동해
// 새 영업일이 올라오면 백그라운드로 스냅샷을 갱신하고, 아래 getKrxDataset은 그 스냅샷만 읽는다.
startKrPoller()

const FINNHUB_TOKEN = process.env.FINNHUB_API_KEY ?? ''
const BASE = 'https://finnhub.io/api/v1'
// 환율(KRW/USD)은 통합 FX 레이어(@/lib/fx)에서 조회한다 — 소스/캐시/폴백 일원화.
// 지수 섹션 달러 환율 카드와 동일하게 수출입은행 매매기준율을 쓴다(값 일치).
// 아래 상수는 lastGoodExchangeRate 초기값(최후 방어선)으로만 사용.
const FOREX_FALLBACK = 1450.0   // KRW/USD

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

// KOSPI 큐레이션 메타 (영문명·브랜드색). 유니버스·시세·시총은 이제
// 공공데이터포털(금융위 주식시세정보)에서 매일 EOD로 동적으로 뽑으므로(getKrxDataset),
// 이 배열은 "종목코드 → 영문명/색" 표시 메타의 소스로만 쓰인다.
// 여기에 없는 신규 상위 종목은 공공데이터포털의 한글 종목명 + 기본색으로 폴백 표시된다.
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

// KOSDAQ 큐레이션 메타. KOSPI_COMPANIES와 동일하게 표시용 영문명/색 소스로만 사용.
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

// 종목코드(6자리, 접미사 없음) → 영문명·색 큐레이션 메타. 위 두 배열에서 자동 생성.
// 공공데이터포털 동적 유니버스에 이 메타가 없는 신규 종목은 한글명 + 기본색으로 폴백 표시된다.
const KRX_META: Record<string, { name: string; color: string }> = Object.fromEntries(
  [...KOSPI_COMPANIES, ...KOSDAQ_COMPANIES].map(c => [
    c.ticker.replace(/\.(KS|KQ)$/, ''),
    { name: c.name, color: c.color },
  ]),
)
const KRX_DEFAULT_COLOR = '#3182F6'

// Finnhub 무료: 60 calls/min
// Quote 5개씩 배치(200ms 딜레이), 21초 캐시 → burst rate limit 방지 ✓
// Profile 1시간 캐시 → 서버 재시작 시에만 호출                        ✓
// 환율은 @/lib/fx 가 자체 1시간 캐시로 호출 제한을 관리한다.
const QUOTE_TTL_MS   = 21_000
const PROFILE_TTL_MS = 3_600_000

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

// KRX 종목 응답/정규화 타입(DataGoStockItem·KrxRow·KrxDataset)은 스냅샷 레이어(@/lib/kr-snapshot)로 이동했다.

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
let aramcoDataCache: CacheEntry<AramcoData> | null = null

// 실패 시 Yahoo Finance에 폭격 방지 — 마지막 실패로부터 60초 쿨다운
const ARAMCO_ERROR_COOLDOWN_MS = 60_000
let aramcoErrorUntil = 0

// 개별 종목 실패 시 stale 데이터 유지용 (목록 flickering 방지)
const finnhubLastGoodCache = new Map<string, Omit<CompanyResult, 'rank'>>()
// 미국 종목 Yahoo marketCap 앵커 캐시 (ticker → 시총 조 단위, 6시간 TTL, 마지막 성공값 유지)
const usYahooCapCache = new Map<string, CacheEntry<number>>()
// Yahoo 실패(429 등) 시 쿨다운 — 매 폴링마다 죽은 Yahoo에 재시도해 지연/부하를 주지 않도록.
const US_YAHOO_CAP_ERROR_COOLDOWN_MS = 10 * 60 * 1000  // 10분
let usYahooCapErrorUntil = 0

let lastGoodResult: CompanyResult[] | null = null
let lastGoodAt = 0
let lastGoodExchangeRate = FOREX_FALLBACK

// 거래소 전용 피드 상태 (ALL과 분리해 서로 간섭하지 않도록).
// 신규 거래소는 여기 한 줄만 추가하면 확장됨.
interface ExchangeFeedState {
  lastGoodResult: CompanyResult[] | null            // 마지막 성공 랭킹 (stale 폴백)
  lastGoodAt:     number
  lastBasDt?:     string                            // KRX 기준일("YYYYMMDD") — stale 응답에도 유지
}
const exchangeFeeds: Record<string, ExchangeFeedState> = {
  NASDAQ: { lastGoodResult: null, lastGoodAt: 0 },
  NYSE:   { lastGoodResult: null, lastGoodAt: 0 },
  KOSPI:  { lastGoodResult: null, lastGoodAt: 0 },
  KOSDAQ: { lastGoodResult: null, lastGoodAt: 0 },
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

// 환율(KRW/USD)은 @/lib/fx 의 getUsdKrwQuote 로 조회한다(수출입은행 우선 → OXR → 상수 폴백).
// 소스 우선순위·캐시·last-good은 모두 그 레이어가 담당한다. 여기선 예외 시 마지막 성공
// 환율(lastGoodExchangeRate)로 폴백만 처리한다.
async function getKrwRate(): Promise<number> {
  try {
    return (await getUsdKrwQuote()).rate
  } catch (err) {
    console.warn('[market-cap] forex fetch failed, using last-good:', err)
    return lastGoodExchangeRate
  }
}

// ─── KRX (한국거래소) — 스냅샷 레이어에서 조회 ─────────────────────────────────
// 코스피/코스닥 종목 데이터셋은 @/lib/kr-snapshot 이 소유한다(발행 창 폴러가 새 영업일마다
// 스냅샷을 굳히고, getKrxDataset은 업스트림 호출 없이 그 스냅샷만 읽는다). data.go.kr 접근·
// basDt 탐색·정규화 로직은 전부 그 모듈에 있다.

// ALL·NASDAQ 피드가 특정 KRX 종목(삼성전자·SK하이닉스)을 코드로 조회할 때 사용.
// 공유 데이터셋에서 조회하므로 추가 API 콜 없이 큐레이션 메타(영문명/색)로 매핑한다.
async function getKRXResult(
  meta: KoreanStockMeta,
  krwPerUsd: number,
): Promise<Omit<CompanyResult, 'rank'>> {
  const code = meta.ticker.replace(/\.(KS|KQ)$/, '')
  const ds = await getKrxDataset()
  const row = ds.byCode.get(code)
  if (!row || !row.marketCapKRW) throw new Error(`KRX ${meta.ticker} → marketCap missing`)
  return {
    ticker:        meta.ticker,
    name:          meta.name,
    color:         meta.color,
    currentPrice:  row.price,
    change:        row.change,
    changePercent: row.changePercent,
    marketCapUSD:  row.marketCapKRW / krwPerUsd / 1_000_000_000_000,
  }
}

// ─── Yahoo 인증(crumb+쿠키) — 미국 종목 marketCap 앵커용 ────────────────────────
// finance.yahoo.com HTML은 일부 심볼을 404 처리해 벌크 소스로 못 쓰므로, Yahoo v7 quote
// JSON을 crumb+쿠키로 인증해 1콜 배치로 미국 종목의 시총(USD)을 받는다(refreshUsYahooCaps).

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
  if (exchange === 'kospi')  return handleKoreanExchange('KOSPI')
  if (exchange === 'kosdaq') return handleKoreanExchange('KOSDAQ')
  return handleAll()
}

async function handleAll() {
  try {
    if (!FINNHUB_TOKEN) {
      throw new Error('FINNHUB_API_KEY 환경 변수가 설정되지 않았습니다.')
    }

    const rate = await getKrwRate()

    // Finnhub 배치, Aramco(Yahoo HTML), KRX(Yahoo JSON) 병렬 실행
    // 개별 종목 실패는 null로 처리 — 한 종목 장애가 전체를 막지 않도록
    const finnhubTask = fetchFinnhubRows(COMPANIES)

    const aramcoTask = getAramcoResult().catch((err) => {
      console.warn('[market-cap] Aramco fetch failed, skipping:', err)
      return null
    })

    const krxTask = Promise.all(
      KOREAN_STOCKS.map(meta =>
        getKRXResult(meta, rate).catch((err) => {
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
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, data: ranked, updatedAt: lastGoodAt, stale: false })
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

// 한국거래소 전용 핸들러 (KOSPI/KOSDAQ 공통) — 공공데이터포털 EOD 데이터셋에서 해당 시장의
// 시총 상위 100개를 동적으로 뽑아 USD 환산 후 반환. 영문명·브랜드색은 KRX_META로 오버레이하고,
// 큐레이션에 없는 신규 종목은 한글 종목명 + 기본색으로 폴백한다(JPX 동적 유니버스와 동일 패턴).
// ALL/미국 피드와 동일한 응답 형태(exchangeRate/data/updatedAt/stale)를 유지.
async function handleKoreanExchange(exchange: 'KOSPI' | 'KOSDAQ') {
  const state = exchangeFeeds[exchange]
  try {
    // KRW 환산 표시는 클라이언트가 담당하므로 환율만 함께 전달
    const rate = await getKrwRate()

    const ds = await getKrxDataset()
    const suffix = exchange === 'KOSPI' ? 'KS' : 'KQ'
    const rows = exchange === 'KOSPI' ? ds.kospi : ds.kosdaq  // 이미 시총 내림차순 정렬됨

    // 상위 100개로 확장. getKrxDataset이 이미 전 종목을 1콜로 받아 캐싱하므로
    // 추가 외부 호출 없이 슬라이스 범위만 넓히면 된다(서버 부하 증가 없음).
    const ranked: CompanyResult[] = rows.slice(0, 100).map((row, i) => {
      const meta = KRX_META[row.code]
      return {
        rank:          i + 1,
        ticker:        `${row.code}.${suffix}`,
        name:          meta?.name ?? row.name,
        color:         meta?.color ?? KRX_DEFAULT_COLOR,
        currentPrice:  row.price,
        change:        row.change,
        changePercent: row.changePercent,
        marketCapUSD:  row.marketCapKRW / rate / 1_000_000_000_000,
      }
    })

    if (state) {
      state.lastGoodResult = ranked
      state.lastGoodAt = Date.now()
      state.lastBasDt = ds.basDt
    }
    lastGoodExchangeRate = rate

    // basDt: KRX 기준일("YYYYMMDD"). 공공데이터포털은 EOD(D-1)라 클라이언트가 "YYYY.MM.DD 종가 기준"으로 표기한다.
    return NextResponse.json({ exchangeRate: rate, basDt: ds.basDt, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)

    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, basDt: state.lastBasDt, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
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
    const rate = await getKrwRate()

    const rows = await fetchFinnhubRows(universe)
    const allRows = rows.filter(
      (r): r is Omit<CompanyResult, 'rank'> => r !== null,
    )

    // SK Hynix: 나스닥 공식엔 ADR로 상위권이지만 Finnhub 무료엔 US 심볼이 없어 유니버스로 못 잡는다.
    // 한국 상장(000660.KS) 시총을 USD 환산해 나스닥 섹션에 주입 → 공식 순위와 일치시킨다.
    if (exchange === 'NASDAQ') {
      const hynix = await getKRXResult(SKHYNIX_KRX, rate).catch((err) => {
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
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
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
