import { NextResponse } from 'next/server'
import fs   from 'fs'
import path from 'path'
import { getUsdKrwQuote } from '@/lib/fx'
import { getKrxDataset, startKrPoller } from '@/lib/kr-snapshot'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// KR 스냅샷 폴러 기동 (market-cap / market-index 공유 싱글턴)
startKrPoller()

// ─── Twelve Data ──────────────────────────────────────────────────────────────
// Venture 플랜: 610 credits/min, 무제한 daily.
// /quote 1 credit/종목 (20s TTL) · /statistics ~10 credits/종목 (24h TTL + 디스크 영속)
// 정상 운용: ~80 credits/min (quotes only). 재시작 시 디스크 캐시 복원 → cold-start burst 없음.
// 429 시 statsErrUntil(5분 쿨다운)으로 재시도 폭주 차단.

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'

// ─── 가격 기반 시총 계산 (stats 없이 발행주수 × 가격으로 직접 계산) ───────────────
// 대상: ADR(USD가격) + SAR 종목(Tadawul). /statistics가 부정확하거나 미지원인 종목.
// 합병·분할 없는 한 발행주수는 거의 변하지 않음. (최근 갱신: 2026-07)

// ADR: 발행주수(M) × ADR가격(USD) / 1,000,000 = 시총(T USD)
const ADR_SHARE_RATIO: Record<string, number> = {
  TSM:  5,  // TSMC: 1 ADR = 5 대만 보통주
  HSBC: 5,  // HSBC: 1 ADR = 5 런던 보통주
}
const ADR_SHARE_OUTSTANDING_M: Record<string, number> = {
  TSM:  5165,  // 보통주 25825M ÷ ADR비율 5 = 5165M ADR
  HSBC: 3437,  // 보통주 17183M ÷ ADR비율 5 = 3437M ADR
}

// SAR 종목 (Tadawul): /statistics가 market_capitalization을 SAR로 반환 → USD 변환 필요.
// SAR/USD 법정 고정환율(3.75)로 나누면 정확한 USD 시총.
// EOD 가격 기반 라이브 스케일링(stats × close/prev_close)은 일반 종목과 동일.
const SAR_PER_USD = 3.75  // 사우디 리얄 법정 고정환율 (1946년~)
const SAR_STATS_TICKERS = new Set(['2222:TADAWUL'])

// ─── 유니버스 ──────────────────────────────────────────────────────────────────
// NASDAQ·NYSE 유니버스는 정적 큐레이션 리스트로 관리한다.
// 실시간 스크리너 없이도 상위 20개가 항상 포함되도록 여유 있게 구성하고,
// 실시간 시총(Twelve Data /statistics + /quote 스케일링)으로 재정렬해 상위 20개를 뽑는다.

const COMPANIES: CompanyMeta[] = [
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

// NASDAQ 유니버스 (큐레이션, top-20 상위집합).
// ⚠️ Walmart(WMT) 등 NASDAQ 공식 상장 종목은 NYSE가 아닌 여기에 둔다.
const NASDAQ_COMPANIES: CompanyMeta[] = [
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
]

// NYSE 유니버스 (큐레이션, top-20 상위집합).
// 보통주 + 미국 상장 ADR(TSM·HSBC 등) 포함. 우선주·파생상품 제외.
const NYSE_COMPANIES: CompanyMeta[] = [
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
]

// ─── KRX (한국거래소) ──────────────────────────────────────────────────────────
// 공공데이터포털 금융위원회_주식시세정보 — EOD D-1 데이터, 무료·라이선스 클린.
// 유니버스·시세·시총은 kr-snapshot 레이어가 동적으로 관리(상위 100개 이상).
// 아래 배열은 "종목코드 → 영문명/색" 표시 메타의 소스로만 사용. 없는 종목은 한글명+기본색 폴백.

interface KoreanStockMeta {
  ticker: string
  name:   string
  color:  string
}

// ALL 피드에 포함될 KRX 종목 (시총 상위권 한국 기업)
const KOREAN_STOCKS: KoreanStockMeta[] = [
  { ticker: '005930.KS', name: 'Samsung',  color: '#1428A0' },
  { ticker: '000660.KS', name: 'SK Hynix', color: '#EA5504' },
]

// SK Hynix: NASDAQ 공식에는 ADR로 상위권에 오르지만, Twelve Data에 US 심볼이 없어
// KRX 시총(000660.KS)을 USD 환산해 NASDAQ 섹션에 주입 → 나스닥 공식 순위와 일치.
const SKHYNIX_KRX: KoreanStockMeta = { ticker: '000660.KS', name: 'SK Hynix', color: '#EA5504' }

const KOSPI_COMPANIES: KoreanStockMeta[] = [
  { ticker: '005930.KS', name: 'Samsung Elec.',    color: '#1428A0' },
  { ticker: '000660.KS', name: 'SK Hynix',         color: '#EA5504' },
  { ticker: '402340.KS', name: 'SK Square',        color: '#E4002B' },
  { ticker: '009150.KS', name: 'Samsung EM',       color: '#1428A0' },
  { ticker: '005380.KS', name: 'Hyundai Motor',    color: '#002C5F' },
  { ticker: '373220.KS', name: 'LG Energy Sol.',   color: '#A50034' },
  { ticker: '032830.KS', name: 'Samsung Life',     color: '#1428A0' },
  { ticker: '207940.KS', name: 'Samsung Bio.',     color: '#1428A0' },
  { ticker: '105560.KS', name: 'KB Financial',     color: '#FFB819' },
  { ticker: '028260.KS', name: 'Samsung C&T',      color: '#1428A0' },
  { ticker: '000270.KS', name: 'Kia',              color: '#05141F' },
  { ticker: '055550.KS', name: 'Shinhan Fin.',     color: '#0046FF' },
  { ticker: '329180.KS', name: 'HD Hyundai HI',    color: '#00A0B0' },
  { ticker: '012330.KS', name: 'Hyundai Mobis',    color: '#002C5F' },
  { ticker: '012450.KS', name: 'Hanwha Aero.',     color: '#F37021' },
  { ticker: '034730.KS', name: 'SK Inc.',          color: '#E4002B' },
  { ticker: '034020.KS', name: 'Doosan Enerb.',    color: '#00A9CE' },
  { ticker: '068270.KS', name: 'Celltrion',        color: '#00A6D6' },
  { ticker: '086790.KS', name: 'Hana Financial',   color: '#008485' },
  { ticker: '006400.KS', name: 'Samsung SDI',      color: '#1428A0' },
]

const KOSDAQ_COMPANIES: KoreanStockMeta[] = [
  { ticker: '196170.KQ', name: 'Alteogen',         color: '#0067AC' },
  { ticker: '247540.KQ', name: 'Ecopro BM',        color: '#008C44' },
  { ticker: '086520.KQ', name: 'Ecopro',           color: '#008C44' },
  { ticker: '277810.KQ', name: 'Rainbow Robotics', color: '#2D2D2D' },
  { ticker: '036930.KQ', name: 'Jusung Eng.',      color: '#004C97' },
  { ticker: '240810.KQ', name: 'Wonik IPS',        color: '#0091D0' },
  { ticker: '058470.KQ', name: 'Leeno Ind.',       color: '#E60012' },
  { ticker: '319660.KQ', name: 'PSK',              color: '#005BAC' },
  { ticker: '298380.KQ', name: 'ABL Bio',          color: '#00A651' },
  { ticker: '039030.KQ', name: 'EO Technics',      color: '#003DA5' },
  { ticker: '028300.KQ', name: 'HLB',              color: '#00A650' },
  { ticker: '222800.KQ', name: 'Simmtech',         color: '#005EAB' },
  { ticker: '000250.KQ', name: 'Samchundang',      color: '#0068B7' },
  { ticker: '440110.KQ', name: 'FADU',             color: '#1A1A1A' },
  { ticker: '141080.KQ', name: 'LigaChem Bio',     color: '#0075C1' },
  { ticker: '214450.KQ', name: 'Pharma Research',  color: '#00953A' },
  { ticker: '108490.KQ', name: 'Robotis',          color: '#EE2E24' },
  { ticker: '403870.KQ', name: 'HPSP',             color: '#005BAC' },
  { ticker: '095610.KQ', name: 'Tes',              color: '#004EA2' },
  { ticker: '095340.KQ', name: 'ISC',              color: '#0060A9' },
]

// 종목코드(6자리) → 영문명·색 맵. kr-snapshot 동적 유니버스에 없는 종목은 한글명+기본색 폴백.
const KRX_META: Record<string, { name: string; color: string }> = Object.fromEntries(
  [...KOSPI_COMPANIES, ...KOSDAQ_COMPANIES].map(c => [
    c.ticker.replace(/\.(KS|KQ)$/, ''),
    { name: c.name, color: c.color },
  ]),
)
const KRX_DEFAULT_COLOR = '#3182F6'

// ─── Types ───────────────────────────────────────────────────────────────────

interface CompanyMeta {
  ticker: string
  name:   string
  color:  string
}

interface QuoteData {
  c:  number  // current price
  d:  number  // change
  dp: number  // change percent
  pc: number  // previous close — 시총 라이브 스케일링(stats × c/pc)에 사용
}

interface StatsData {
  marketCapUSD: number  // trillion USD
}

interface CacheEntry<T> {
  data: T
  ts:   number
}

export interface CompanyResult {
  rank:          number
  ticker:        string
  name:          string
  color:         string
  currentPrice:  number
  change:        number
  changePercent: number
  marketCapUSD:  number  // trillion USD
  domain?:       string  // 홈페이지 도메인 (KRX 종목 로고 폴백용)
}

// ─── In-Memory Caches ─────────────────────────────────────────────────────────

const QUOTE_TTL_MS = 20_000
const STATS_TTL_MS = 24 * 3_600_000  // 24h — 하루 1회만 갱신. 디스크 영속으로 재시작 후에도 유지.

const quoteCache    = new Map<string, CacheEntry<QuoteData>>()
const quoteInFlight = new Map<string, Promise<QuoteData>>()
const statsCache    = new Map<string, CacheEntry<StatsData>>()
const statsInFlight = new Map<string, Promise<StatsData>>()

// 종목별 마지막 성공 데이터. 레이트리밋 등 일시 실패 시 stale 데이터로 빈자리 없이 유지.
const lastGoodCompanyCache = new Map<string, Omit<CompanyResult, 'rank'>>()

let lastGoodResult: CompanyResult[] | null = null
let lastGoodAt               = 0
let lastGoodExchangeRate      = 1450.0  // KRW/USD 초기값 (최후 방어선)

interface ExchangeFeedState {
  lastGoodResult: CompanyResult[] | null
  lastGoodAt:     number
  lastBasDt?:     string
}
const exchangeFeeds: Record<string, ExchangeFeedState> = {
  NASDAQ: { lastGoodResult: null, lastGoodAt: 0 },
  NYSE:   { lastGoodResult: null, lastGoodAt: 0 },
  KOSPI:  { lastGoodResult: null, lastGoodAt: 0 },
  KOSDAQ: { lastGoodResult: null, lastGoodAt: 0 },
}

// ─── Stats 디스크 영속 ─────────────────────────────────────────────────────────
// 서버 재시작 후에도 24h TTL stats가 파일에서 복원되어 cold-start burst(~550 credits) 원천 차단.
// 경로: titans-web/.data/stats-cache.json (root .gitignore에서 제외됨)

const STATS_PERSIST_PATH = path.join(process.cwd(), '.data', 'stats-cache.json')
let   statsCacheLoaded   = false

function loadStatsCacheFromDisk(): void {
  if (statsCacheLoaded) return
  statsCacheLoaded = true
  try {
    const raw = JSON.parse(fs.readFileSync(STATS_PERSIST_PATH, 'utf-8')) as
      Record<string, { marketCapUSD: number; ts: number }>
    const now = Date.now()
    let n = 0
    for (const [ticker, { marketCapUSD, ts }] of Object.entries(raw)) {
      if (now - ts < STATS_TTL_MS) {
        statsCache.set(ticker, { data: { marketCapUSD }, ts })
        n++
      }
    }
    if (n > 0) console.log(`[market-cap] stats 디스크 캐시 복원: ${n}개`)
  } catch { /* 파일 없음 또는 파싱 오류 — 무시하고 빈 캐시로 시작 */ }
}

function saveStatsCacheToDisk(): void {
  try {
    fs.mkdirSync(path.dirname(STATS_PERSIST_PATH), { recursive: true })
    const out: Record<string, { marketCapUSD: number; ts: number }> = {}
    for (const [ticker, { data, ts }] of statsCache) {
      out[ticker] = { marketCapUSD: data.marketCapUSD, ts }
    }
    fs.writeFileSync(STATS_PERSIST_PATH, JSON.stringify(out, null, 2), 'utf-8')
  } catch (err) {
    console.warn('[market-cap] stats 디스크 저장 실패:', err)
  }
}

// ─── Stats 429 쿨다운 ─────────────────────────────────────────────────────────
// 429 발생 시 5분 쿨다운으로 재시도 폭주(최대 8,181 credits/min) 차단.
const STATS_ERR_COOLDOWN_MS = 5 * 60_000
let   statsErrUntil          = 0

// ─── Twelve Data Fetchers ─────────────────────────────────────────────────────

async function getQuote(ticker: string): Promise<QuoteData> {
  const hit = quoteCache.get(ticker)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const pending = quoteInFlight.get(ticker)
  if (pending) return pending

  const task = (async (): Promise<QuoteData> => {
    const res = await fetch(
      `${TD_BASE}/quote?symbol=${encodeURIComponent(ticker)}&apikey=${TWELVE_DATA_KEY}`,
      { cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`quote ${ticker} → HTTP ${res.status}`)
    const data = await res.json()
    if (data.status === 'error') throw new Error(`quote ${ticker} → ${data.message}`)
    const q: QuoteData = {
      c:  parseFloat(data.close),
      d:  parseFloat(data.change),
      dp: parseFloat(data.percent_change),
      pc: parseFloat(data.previous_close),
    }
    if (!q.c || !isFinite(q.c)) throw new Error(`quote ${ticker} → 유효하지 않은 응답`)
    quoteCache.set(ticker, { data: q, ts: Date.now() })
    return q
  })().finally(() => quoteInFlight.delete(ticker))

  quoteInFlight.set(ticker, task)
  return task
}

// 시총 기준값: /statistics → market_capitalization(절대 USD 정수, e.g. AAPL ≈ 4.99 × 10^12).
// 24h TTL + 디스크 영속. ALL/NASDAQ/NYSE 피드가 동시에 같은 티커를 요청해도 statsInFlight로 1회만 호출.
async function getStats(ticker: string): Promise<StatsData> {
  const hit = statsCache.get(ticker)
  if (hit && Date.now() - hit.ts < STATS_TTL_MS) return hit.data

  const pending = statsInFlight.get(ticker)
  if (pending) return pending

  const task = (async (): Promise<StatsData> => {
    const res = await fetch(
      `${TD_BASE}/statistics?symbol=${encodeURIComponent(ticker)}&apikey=${TWELVE_DATA_KEY}`,
      { cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`stats ${ticker} → HTTP ${res.status}`)
    const data = await res.json()
    if (data.status === 'error') throw new Error(`stats ${ticker} → ${data.message}`)
    const mc = data?.statistics?.valuations_metrics?.market_capitalization as number | undefined
    if (!mc) throw new Error(`stats ${ticker} → market_capitalization 없음`)
    // SAR 종목: TD가 market_capitalization을 현지 통화(SAR)로 반환 → USD 변환 후 저장
    const mcUsd = SAR_STATS_TICKERS.has(ticker) ? mc / SAR_PER_USD : mc
    const result: StatsData = { marketCapUSD: mcUsd / 1_000_000_000_000 }
    statsCache.set(ticker, { data: result, ts: Date.now() })
    setImmediate(saveStatsCacheToDisk)  // 성공마다 즉시 저장 — 프로세스 중단 시에도 보존
    return result
  })().finally(() => statsInFlight.delete(ticker))

  statsInFlight.set(ticker, task)
  return task
}

// ADR 및 캐시 유효 종목 스킵. 429 시 5분 쿨다운으로 폭주 차단. 성공 후 디스크 저장.
async function refreshTdStats(tickers: string[]): Promise<void> {
  loadStatsCacheFromDisk()
  if (Date.now() < statsErrUntil) return

  const now     = Date.now()
  const toFetch = tickers.filter(t => {
    if (ADR_SHARE_RATIO[t]) return false  // ADR: 발행주수 × USD가격으로 직접 계산 (stats 불필요)
    const hit = statsCache.get(t)
    return !hit || now - hit.ts > STATS_TTL_MS
    // SAR 종목(2222:TADAWUL)은 stats를 사용 — SAR→USD 변환은 getStats() 내부에서 처리
  })
  if (toFetch.length === 0) return

  let rateLimitCount = 0
  await Promise.all(
    toFetch.map(t =>
      getStats(t).catch((err: unknown) => {
        if (err instanceof Error && err.message.includes('429')) rateLimitCount++
      }),
    ),
  )

  // 25% 이상 429: 계획적 rate limit → 5분 쿨다운. 소수 실패는 일시 오류로 허용.
  if (rateLimitCount > 0 && rateLimitCount >= Math.ceil(toFetch.length * 0.25)) {
    statsErrUntil = Date.now() + STATS_ERR_COOLDOWN_MS
    console.warn(`[market-cap] stats 429 (${rateLimitCount}/${toFetch.length}) → 5분 쿨다운`)
  }
}

// ─── FX ──────────────────────────────────────────────────────────────────────

async function getKrwRate(): Promise<number> {
  try {
    return (await getUsdKrwQuote()).rate
  } catch {
    return lastGoodExchangeRate
  }
}

// ─── KRX — 스냅샷 레이어 조회 ─────────────────────────────────────────────────

async function getKRXResult(
  meta: KoreanStockMeta,
  krwPerUsd: number,
): Promise<Omit<CompanyResult, 'rank'>> {
  const code = meta.ticker.replace(/\.(KS|KQ)$/, '')
  const ds   = await getKrxDataset()
  const row  = ds.byCode.get(code)
  if (!row || !row.marketCapKRW) throw new Error(`KRX ${meta.ticker} → marketCap 없음`)
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

// ─── 종목 행 생성 (ALL / NASDAQ / NYSE 공통) ──────────────────────────────────
// 시총 = stats 기준값(24h 캐시) × (현재가 / 전일종가) 라이브 스케일링.
// ADR(TSM·HSBC): 하드코딩된 발행주수 × ADR가격으로 직접 계산(stats 사용 안 함).
// quote 실패 시: 만료 캐시 → lastGoodCompanyCache(직전 성공) 순으로 폴백.

async function fetchRows(
  companies: CompanyMeta[],
): Promise<(Omit<CompanyResult, 'rank'> | null)[]> {
  await refreshTdStats(companies.map(c => c.ticker))

  const quotes = await Promise.all(
    companies.map(async (co): Promise<QuoteData | null> => {
      try { return await getQuote(co.ticker) }
      catch { return quoteCache.get(co.ticker)?.data ?? null }  // 만료 캐시 폴백
    }),
  )

  return companies.map((co, i): Omit<CompanyResult, 'rank'> | null => {
    const quote  = quotes[i]
    const tdCapT = statsCache.get(co.ticker)?.data?.marketCapUSD

    if (!quote && tdCapT == null) return lastGoodCompanyCache.get(co.ticker) ?? null

    const adrShares = ADR_SHARE_OUTSTANDING_M[co.ticker]
    let marketCapUSD: number

    if (adrShares) {
      // ADR: 발행주수(M) × ADR가격(USD) / 1M → 시총(T USD)
      marketCapUSD = quote ? adrShares * quote.c / 1_000_000 : 0
    } else {
      // 일반 + SAR 종목: stats 기준값(SAR→USD 변환은 getStats 내부에서 완료) × 당일 등락 비율
      const ratio  = quote && quote.pc > 0 ? quote.c / quote.pc : 1
      marketCapUSD = (tdCapT ?? 0) * ratio
    }

    if (marketCapUSD <= 0) {
      const stale = lastGoodCompanyCache.get(co.ticker)
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
    lastGoodCompanyCache.set(co.ticker, result)
    return result
  })
}

// ─── Ranking Helper ───────────────────────────────────────────────────────────
// 신선 데이터를 시총 내림차순 상위 N개로 랭킹.
// 레이트리밋 등으로 N개를 못 채우면 직전 성공 랭킹(previous)으로 보강 → 섹션이 20개 밑으로 내려가지 않도록.

function rankWithBackfill(
  fresh:    Omit<CompanyResult, 'rank'>[],
  previous: CompanyResult[] | null,
  limit     = 20,
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
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate = await getKrwRate()

    const [companyRows, krxResults] = await Promise.all([
      fetchRows(COMPANIES),
      Promise.all(
        KOREAN_STOCKS.map(meta =>
          getKRXResult(meta, rate).catch((err) => {
            console.warn(`[market-cap] KRX ${meta.ticker} 실패, 스킵:`, err)
            return null
          }),
        ),
      ),
    ])

    const allRows = [...companyRows, ...krxResults]
      .filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked = rankWithBackfill(allRows, lastGoodResult)
    lastGoodResult       = ranked
    lastGoodAt           = Date.now()
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, data: ranked, updatedAt: lastGoodAt, stale: false })
  } catch (err) {
    console.error('[market-cap] fetch error:', err)
    if (lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: lastGoodResult, updatedAt: lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 거래소 전용 핸들러 (NASDAQ / NYSE 공통).
// ALL과 동일한 응답 형태(exchangeRate/data/updatedAt/stale)를 유지해 클라이언트 디코딩 공유.
async function handleExchange(exchange: string, universe: CompanyMeta[]) {
  const state = exchangeFeeds[exchange]
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate = await getKrwRate()
    const rows = await fetchRows(universe)
    const allRows = rows.filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    // SK Hynix: KRX 시총을 USD 환산해 NASDAQ 섹션에 주입 → 나스닥 공식 순위와 일치.
    if (exchange === 'NASDAQ') {
      const hynix = await getKRXResult(SKHYNIX_KRX, rate).catch((err) => {
        console.warn('[market-cap:NASDAQ] SK Hynix 주입 실패, 스킵:', err)
        return null
      })
      if (hynix) allRows.push(hynix)
    }

    const ranked = rankWithBackfill(allRows, state?.lastGoodResult)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 한국거래소 전용 핸들러 (KOSPI / KOSDAQ 공통).
// 공공데이터포털 동적 유니버스에서 시총 상위 100개를 뽑아 USD 환산 후 반환.
async function handleKoreanExchange(exchange: 'KOSPI' | 'KOSDAQ') {
  const state = exchangeFeeds[exchange]
  try {
    const rate   = await getKrwRate()
    const ds     = await getKrxDataset()
    const suffix = exchange === 'KOSPI' ? 'KS' : 'KQ'
    const rows   = exchange === 'KOSPI' ? ds.kospi : ds.kosdaq  // 이미 시총 내림차순

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
        domain:        row.domain,  // DART 해석 도메인 → 앱 로고 폴백
      }
    })

    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now(); state.lastBasDt = ds.basDt }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, basDt: ds.basDt, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, basDt: state.lastBasDt, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// ─── 서버 기동 시 선제 Warm-up ────────────────────────────────────────────────
// 1) 디스크 캐시 복원 → statsCache 즉시 채워짐 (재시작 = 0 credits)
// 2) 미캐시 종목은 3개씩 4초 간격으로 stagger 발사 → 450 credits/min (한도 610 내 유지)
//    전량 병렬 발사 시: 59개 × 10 credits = 590 credits 순간 버스트 → 429 유발
//    stagger 시: 3 × 4s = 450/min → quote 55/min 포함 505/min → 여유 105/min

const ALL_US_TICKERS = [
  ...new Set([
    ...COMPANIES.map(c => c.ticker),
    ...NASDAQ_COMPANIES.map(c => c.ticker),
    ...NYSE_COMPANIES.map(c => c.ticker),
  ]),
]

void (async () => {
  loadStatsCacheFromDisk()
  const now = Date.now()
  const toFetch = ALL_US_TICKERS.filter(t => {
    if (ADR_SHARE_RATIO[t]) return false
    const hit = statsCache.get(t)
    return !hit || now - hit.ts > STATS_TTL_MS
  })
  for (let i = 0; i < toFetch.length; i += 3) {
    await Promise.all(toFetch.slice(i, i + 3).map(t => getStats(t).catch(() => null)))
    if (i + 3 < toFetch.length) await new Promise(r => setTimeout(r, 4_000))
  }
})()
