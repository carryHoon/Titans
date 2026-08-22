import { NextResponse } from 'next/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 종목 상세 화면(CompanyDetailView)의 "투자 지표 + 배당 소식 + 토스 바로가기 코드" 데이터 소스.
//   · 🇺🇸/글로벌 지표 = Twelve Data /statistics(PER/PBR/PSR/ROE + 시총·발행주수로 주가 역산).
//   · 배당 = TD /dividends(실지급 이력)에서 **정규 배당의 중앙값 × 지급횟수**로 연간화한다.
//     (TD /statistics.forward_annual_dividend_rate 는 직전 이상치 배당을 연간화해 크게 틀림 —
//      예: NVDA 0.25×4=$1.00. /dividends 중앙값(0.01)×4=$0.04 가 토스/실제와 일치.)
//   · tossCode = 토스 US 종목 상품코드(US{IPO일}001). 토스 공개 검색 API로 티커→코드 해석·영구 캐시.
//     (토스 앱 딥링크는 티커가 아니라 이 코드를 요구 — 티커 딥링크는 "지원하지 않는 주식" 처리됨.)
//   · 🇰🇷 KOSPI/KOSDAQ = 지표/배당 소스 미연동 → supported:false(앱이 "곧 제공" 표기). 토스코드는 앱이 로컬 A+6자리 사용.
//
// 응답(iOS CompanyMetricsResponse 계약): { ticker, supported, currency?, metrics?, dividend?, tossCode?, stale }
// EOD/기업액션 데이터라 24h 캐시 + last-good 폴백. tossCode는 불변이라 영구 캐시.

const TD_BASE = 'https://api.twelvedata.com'
const TD_KEY  = process.env.TWELVE_DATA_API_KEY ?? ''

const CACHE_TTL_MS = 24 * 60 * 60 * 1000   // 24h
const YEAR_MS      = 365 * 24 * 60 * 60 * 1000

const isKR = (ticker: string) => /\.(KS|KQ)$/i.test(ticker)

// 주당배당금 표기용 통화(거래소 파라미터 기반). 비율지표는 통화무관이라 무영향.
const CURRENCY_BY_EXCHANGE: Record<string, string> = {
  nasdaq: 'USD', nyse: 'USD', all: 'USD',
  euronext: 'EUR', fwb: 'EUR',
  jpx: 'JPY', sse: 'CNY', szse: 'CNY', nse: 'INR',
}

interface DividendBlock {
  perShare:  number | null   // 주당 연 배당금(정규 배당 중앙값 × 지급횟수)
  yieldPct:  number | null   // 배당수익률(%) = 연배당 / 주가
  freqCount: number | null   // 연간 지급 횟수(최근 12개월 실지급 횟수)
  exDate:    string | null   // 최근 배당락일 "YYYY-MM-DD"
  payDate:   string | null   // 지급일(/statistics)
}
interface Metrics {
  per:         number | null
  pbr:         number | null
  psr:         number | null
  roePct:      number | null   // ROE(%)
  divYieldPct: number | null   // 배당수익률(%) — dividend.yieldPct와 동일값(지표 그리드용)
}
interface Payload {
  ticker:    string
  supported: boolean
  currency?: string
  metrics?:  Metrics
  dividend?: DividendBlock
  tossCode?: string
  stale:     boolean
}

interface CacheEntry { data: Payload; ts: number }
const cache    = new Map<string, CacheEntry>()
const lastGood = new Map<string, Payload>()
// 토스 상품코드는 종목당 불변 → 영구 캐시(200 응답 시에만 저장, 네트워크 오류는 미저장해 재시도 허용).
const tossCodeCache = new Map<string, string | null>()

const num = (v: unknown): number | null => {
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}
const toPct = (v: unknown): number | null => {
  const n = num(v)
  return n == null ? null : Math.round(n * 1000) / 10
}
const round2 = (v: number | null): number | null => (v == null ? null : Math.round(v * 100) / 100)

function median(nums: number[]): number | null {
  const a = nums.filter(n => Number.isFinite(n) && n > 0).sort((x, y) => x - y)
  if (a.length === 0) return null
  const m = Math.floor(a.length / 2)
  return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2
}

// ─── TD /statistics: 밸류에이션 + 주가 역산(시총/발행주수) ────────────────────────
interface StatsResult {
  per: number | null; pbr: number | null; psr: number | null; roePct: number | null
  price: number | null; payDate: string | null
}
async function fetchStatistics(symbol: string): Promise<StatsResult> {
  if (!TD_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  const res = await fetch(`${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&apikey=${TD_KEY}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`TD statistics ${symbol} → HTTP ${res.status}`)
  const json = await res.json()
  if (json?.status === 'error') throw new Error(`TD ${symbol} → ${json?.message ?? 'error'}`)
  const s  = json?.statistics ?? {}
  const v  = s.valuations_metrics ?? {}
  const f  = s.financials ?? {}
  const st = s.stock_statistics ?? {}
  const dv = s.dividends_and_splits ?? {}

  const marketCap = num(v.market_capitalization)
  const shares    = num(st.shares_outstanding)
  const price     = (marketCap != null && shares != null && shares > 0) ? marketCap / shares : null
  return {
    per:    round2(num(v.trailing_pe)),
    pbr:    round2(num(v.price_to_book_mrq)),
    psr:    round2(num(v.price_to_sales_ttm)),
    roePct: toPct(f.return_on_equity_ttm),
    price,
    payDate: typeof dv.dividend_date === 'string' ? dv.dividend_date : null,
  }
}

// ─── TD /dividends: 실지급 이력 → 정규 배당 중앙값 연간화 ─────────────────────────
interface TdDiv { ex_date: string; amount: number }
async function fetchDividends(symbol: string): Promise<TdDiv[]> {
  // ⚠️ range 미지정 시 TD는 최신 1건만 반환 → 반드시 기간을 줘 최근 지급 이력을 확보한다(연간화·중앙값용).
  const res = await fetch(`${TD_BASE}/dividends?symbol=${encodeURIComponent(symbol)}&range=2y&apikey=${TD_KEY}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`TD dividends ${symbol} → HTTP ${res.status}`)
  const json = await res.json()
  if (json?.status === 'error') throw new Error(`TD ${symbol} → ${json?.message ?? 'error'}`)
  const arr: unknown[] = Array.isArray(json?.dividends) ? json.dividends : []
  return arr
    .map(d => ({ ex_date: String((d as { ex_date?: string }).ex_date ?? ''), amount: Number((d as { amount?: number }).amount) }))
    .filter(d => d.ex_date && Number.isFinite(d.amount) && d.amount > 0)
}

/** 배당 블록 계산. 최근 12개월 실지급의 중앙값 × 지급횟수로 연간화(이상치에 강건). 배당 없으면 null. */
function buildDividend(divs: TdDiv[], price: number | null, payDate: string | null): DividendBlock | null {
  if (divs.length === 0) return null
  const cutoff = Date.now() - YEAR_MS
  const recent = divs.filter(d => Date.parse(d.ex_date) >= cutoff)
  const pool = recent.length > 0 ? recent : divs.slice(0, 4)
  const freqCount = recent.length > 0 ? recent.length : null
  const med = median(pool.map(d => d.amount))
  const annual = (med != null && freqCount) ? med * freqCount : null
  const yieldPct = (annual != null && price != null && price > 0) ? round2(annual / price * 100) : null
  return {
    perShare:  round2(annual),
    yieldPct,
    freqCount,
    exDate:    divs[0]?.ex_date ?? null,   // /dividends는 최신순
    payDate,
  }
}

// ─── 토스 US 상품코드 해석(공개 검색 API) ────────────────────────────────────────
// POST wts-info-api.tossinvest.com/.../wts-auto-complete → items[].productCode(US{IPO일}001).
// 심볼 정확 일치 + 코드가 US로 시작하는 항목만 채택(ETF·유사티커 오매칭 방지).
async function fetchTossCode(ticker: string): Promise<string | null> {
  if (tossCodeCache.has(ticker)) return tossCodeCache.get(ticker) ?? null
  const res = await fetch(
    `https://wts-info-api.tossinvest.com/api/v3/search-all/wts-auto-complete?query=${encodeURIComponent(ticker)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0' },
      body: JSON.stringify({ query: ticker, sections: [{ type: 'PRODUCT', option: { addIntegratedSearchResult: true } }] }),
      cache: 'no-store',
    },
  )
  if (!res.ok) throw new Error(`toss search ${ticker} → HTTP ${res.status}`)  // 미저장(재시도 허용)
  const json = await res.json()
  const result: unknown[] = Array.isArray(json?.result) ? json.result : []
  const product = result.find(r => (r as { type?: string }).type === 'PRODUCT') as { data?: { items?: unknown[] } } | undefined
  const items: unknown[] = product?.data?.items ?? []
  const up = ticker.toUpperCase()
  const hit = items.find(it => {
    const o = it as { symbol?: string; productCode?: string; code?: string }
    const code = String(o.productCode ?? o.code ?? '')
    return String(o.symbol ?? '').toUpperCase() === up && /^US\d/.test(code)
  }) as { productCode?: string; code?: string } | undefined
  const code = hit ? String(hit.productCode ?? hit.code) : null
  tossCodeCache.set(ticker, code)   // 200 응답이면 결과(코드/없음) 영구 캐시
  return code
}

export async function GET(req: Request) {
  const url      = new URL(req.url)
  const ticker   = (url.searchParams.get('ticker') ?? '').trim()
  const exchange = (url.searchParams.get('exchange') ?? '').trim().toLowerCase()

  if (!ticker) {
    return NextResponse.json({ error: 'company-metrics: ticker 필요' }, { status: 400 })
  }

  // KR은 지표/배당 소스 미연동 — 정직하게 준비 중(토스코드는 앱이 로컬 처리).
  if (isKR(ticker)) {
    return NextResponse.json({ ticker, supported: false, stale: false } satisfies Payload)
  }

  const key = ticker
  const hit = cache.get(key)
  if (hit && Date.now() - hit.ts < CACHE_TTL_MS) {
    return NextResponse.json(hit.data)
  }

  try {
    const stats = await fetchStatistics(ticker)
    // 배당·토스코드는 병렬(실패해도 각자 흡수 — 지표는 유지).
    const [divs, tossCode] = await Promise.all([
      fetchDividends(ticker).catch(() => [] as TdDiv[]),
      fetchTossCode(ticker).catch(() => null),
    ])
    const dividend = buildDividend(divs, stats.price, stats.payDate) ?? undefined
    const metrics: Metrics = {
      per: stats.per, pbr: stats.pbr, psr: stats.psr, roePct: stats.roePct,
      divYieldPct: dividend?.yieldPct ?? null,
    }
    const data: Payload = {
      ticker,
      supported: true,
      currency: CURRENCY_BY_EXCHANGE[exchange] ?? 'USD',
      metrics,
      dividend,
      tossCode: tossCode ?? undefined,
      stale: false,
    }
    cache.set(key, { data, ts: Date.now() })
    lastGood.set(key, data)
    return NextResponse.json(data)
  } catch (err) {
    console.error(`[company-metrics] ${key} failed:`, err)
    const prev = lastGood.get(key)
    if (prev) return NextResponse.json({ ...prev, stale: true })
    return NextResponse.json({ ticker, supported: false, stale: false } satisfies Payload)
  }
}
