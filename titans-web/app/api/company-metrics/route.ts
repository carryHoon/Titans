import { NextResponse } from 'next/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 종목 상세 화면(CompanyDetailView)의 "투자 지표 + 배당 소식 + 토스 바로가기 코드" 데이터 소스.
//   · 🇺🇸/글로벌 지표 = Twelve Data /statistics(PER/PBR/PSR/ROE + 시총·발행주수로 주가 역산).
//   · 배당 = TD /dividends(실지급 이력)에서 **정규 배당의 중앙값 × 지급횟수**로 연간화한다.
//     (TD /statistics.forward_annual_dividend_rate 는 직전 이상치 배당을 연간화해 크게 틀림 —
//      예: NVDA 0.25×4=$1.00. /dividends 중앙값(0.01)×4=$0.04 가 토스/실제와 일치.)
//   · Toss 바로가기: US 상품코드는 토스 비공개 검색 API 스크래핑에 의존(라이선스·상표 회색지대)이라
//     상용 배포에서 제거했다. 🇰🇷은 앱이 공개 단축코드로 A+6자리를 로컬 도출한다(백엔드 무관).
//   · 🇰🇷 KOSPI/KOSDAQ = 배당은 공공데이터포털 주식배당정보(GetStocDiviInfoService_V2/getDiviInfo_V2,
//     라이선스 0)로 실제 지급 이력 → 최근 12개월 합으로 연간화 + 주식시세(getStockPriceInfo) 종가로
//     배당수익률 계산. PER/PBR/PSR/ROE는 KR 무료 재배포 소스 미확정이라 아직 미제공(metrics=null).
//     배당이 없으면 supported:false(앱 "곧 제공" 표기). 토스코드는 앱이 로컬 A+6자리 사용.
//
// 응답(iOS CompanyMetricsResponse 계약): { ticker, supported, currency?, metrics?, dividend?, stale }
// EOD/기업액션 데이터라 24h 캐시 + last-good 폴백.

const TD_BASE = 'https://api.twelvedata.com'
const TD_KEY  = process.env.TWELVE_DATA_API_KEY ?? ''

// 🇰🇷 공공데이터포털(금융위) — 단일 계정 키로 주식시세·배당 서비스 공용(company-chart와 동일 키).
const DATA_GO_KR_KEY = process.env.DATA_GO_KR_KEY ?? ''
const KR_PRICE_URL = 'https://apis.data.go.kr/1160100/service/GetStockSecuritiesInfoService/getStockPriceInfo'
const KR_DIV_URL   = 'https://apis.data.go.kr/1160100/GetStocDiviInfoService_V2/getDiviInfo_V2'

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
  stale:     boolean
}

interface CacheEntry { data: Payload; ts: number }
const cache    = new Map<string, CacheEntry>()
const lastGood = new Map<string, Payload>()

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

// ─── 🇰🇷 공공데이터포털: 종가+ISIN + 배당 이력 → 배당 블록 ──────────────────────
function ymdDaysAgo(n: number): string {
  const d = new Date(Date.now() - n * 24 * 60 * 60 * 1000)
  return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`
}
function dashify(ymd8: string): string {
  return ymd8.length === 8 ? `${ymd8.slice(0, 4)}-${ymd8.slice(4, 6)}-${ymd8.slice(6, 8)}` : ymd8
}
/** 배당기준일(record date) → 배당락일(ex-date) ≈ 직전 영업일. "YYYYMMDD" → "YYYY-MM-DD". */
function prevBusinessDayDash(ymd8: string): string | null {
  if (ymd8.length !== 8) return null
  const d = new Date(Number(ymd8.slice(0, 4)), Number(ymd8.slice(4, 6)) - 1, Number(ymd8.slice(6, 8)))
  d.setDate(d.getDate() - 1)
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() - 1)   // 주말 건너뜀
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

/** 단축코드(6자리) → 최신 종가 + ISIN. likeSrtnCd는 부분매칭이라 정확 일치 우선. */
async function fetchKrPriceIsin(shortCode: string): Promise<{ clpr: number; isinCd: string } | null> {
  if (!DATA_GO_KR_KEY) return null
  const params = new URLSearchParams({
    serviceKey: DATA_GO_KR_KEY, resultType: 'json', numOfRows: '10', pageNo: '1',
    beginBasDt: ymdDaysAgo(14), likeSrtnCd: shortCode,
  })
  const res = await fetch(`${KR_PRICE_URL}?${params}`, { cache: 'no-store' })
  if (!res.ok) return null
  const json = await res.json()
  let items = json?.response?.body?.items?.item ?? []
  if (!Array.isArray(items)) items = items ? [items] : []
  const exact = items.filter((it: { srtnCd?: string }) => String(it.srtnCd) === shortCode)
  const pool: { basDt?: string; clpr?: string; isinCd?: string }[] = exact.length ? exact : items
  pool.sort((a, b) => String(b.basDt).localeCompare(String(a.basDt)))   // 최신 basDt
  const top = pool[0]
  if (!top) return null
  const clpr = Number(top.clpr)
  const isinCd = String(top.isinCd ?? '')
  return Number.isFinite(clpr) && clpr > 0 && isinCd ? { clpr, isinCd } : null
}

interface KrDivRow { basDt: string; pay: string | null; amount: number }
/** ISIN → 현금배당 이력(최신순). stckGenrDvdnAmt = 주당 현금배당금(원). */
async function fetchKrDividends(isinCd: string): Promise<KrDivRow[]> {
  const params = new URLSearchParams({
    serviceKey: DATA_GO_KR_KEY, resultType: 'json', numOfRows: '100', pageNo: '1', isinCd,
  })
  const res = await fetch(`${KR_DIV_URL}?${params}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`KR dividends ${isinCd} → HTTP ${res.status}`)
  const json = await res.json()
  let items = json?.response?.body?.items?.item ?? []
  if (!Array.isArray(items)) items = items ? [items] : []
  const rows: KrDivRow[] = items
    .map((it: { dvdnBasDt?: string; cashDvdnPayDt?: string; stckGenrDvdnAmt?: string; stckGenrCashDvdnRt?: string }) => ({
      basDt:  String(it.dvdnBasDt ?? ''),
      pay:    it.cashDvdnPayDt ? String(it.cashDvdnPayDt) : null,
      amount: Number(it.stckGenrDvdnAmt ?? it.stckGenrCashDvdnRt ?? 0),
    }))
    .filter((r: KrDivRow) => r.basDt.length === 8 && Number.isFinite(r.amount) && r.amount > 0)
  rows.sort((a, b) => b.basDt.localeCompare(a.basDt))   // 최신순
  return rows
}

/** KR 배당 블록. 최근 12개월 실지급 합으로 연간화(공식 데이터라 합계=실제 연배당). 배당 없으면 null. */
function buildKrDividend(rows: KrDivRow[], clpr: number): DividendBlock | null {
  if (rows.length === 0) return null
  const cutoff = ymdDaysAgo(365)
  const recent = rows.filter(r => r.basDt >= cutoff)
  const pool = recent.length > 0 ? recent : rows.slice(0, 4)
  const annual = pool.reduce((s, r) => s + r.amount, 0)
  const freqCount = recent.length > 0 ? recent.length : null
  const latest = rows[0]
  return {
    perShare:  round2(annual),
    yieldPct:  clpr > 0 ? round2(annual / clpr * 100) : null,
    freqCount,
    exDate:    prevBusinessDayDash(latest.basDt),   // 배당락일 ≈ 배당기준일 -1영업일
    payDate:   latest.pay ? dashify(latest.pay) : null,
  }
}

export async function GET(req: Request) {
  const url      = new URL(req.url)
  const ticker   = (url.searchParams.get('ticker') ?? '').trim()
  const exchange = (url.searchParams.get('exchange') ?? '').trim().toLowerCase()

  if (!ticker) {
    return NextResponse.json({ error: 'company-metrics: ticker 필요' }, { status: 400 })
  }

  const key = ticker
  const hit = cache.get(key)
  if (hit && Date.now() - hit.ts < CACHE_TTL_MS) {
    return NextResponse.json(hit.data)
  }

  // 🇰🇷 배당(공공데이터포털). 지표(PER/PBR 등)는 미제공(metrics 생략). 실패/무배당이면 supported:false.
  if (isKR(ticker)) {
    try {
      const shortCode = ticker.split('.')[0]
      const pi = await fetchKrPriceIsin(shortCode)
      if (!pi) throw new Error(`KR ${shortCode} → 종가/ISIN 없음`)
      const rows = await fetchKrDividends(pi.isinCd)
      const dividend = buildKrDividend(rows, pi.clpr) ?? undefined
      const data: Payload = { ticker, supported: !!dividend, currency: 'KRW', dividend, stale: false }
      cache.set(key, { data, ts: Date.now() })
      if (dividend) lastGood.set(key, data)
      return NextResponse.json(data)
    } catch (err) {
      console.error(`[company-metrics] KR ${key} failed:`, err)
      const prev = lastGood.get(key)
      if (prev) return NextResponse.json({ ...prev, stale: true })
      return NextResponse.json({ ticker, supported: false, stale: false } satisfies Payload)
    }
  }

  try {
    const stats = await fetchStatistics(ticker)
    // 배당은 실패해도 흡수 — 지표는 유지.
    const divs = await fetchDividends(ticker).catch(() => [] as TdDiv[])
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
