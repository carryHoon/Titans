import { NextResponse } from 'next/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 종목 상세 화면(CompanyDetailView)의 "투자 지표 + 배당 소식" 데이터 소스(토스 오마주).
//   · 🇺🇸/글로벌 = Twelve Data /statistics(펀더멘털). PER/PBR/PSR/ROE·배당수익률·주당배당금·
//     배당락일·지급빈도를 한 콜로 제공(벤처플랜 display 허용). 비율지표는 통화무관.
//   · 🇰🇷 KOSPI/KOSDAQ = 아직 소스 미연동(TD는 KR 펀더멘털 미제공, 공공데이터포털 배당서비스 미구독).
//     supported=false 로 정직하게 "준비 중"을 반환한다. KR 소스 확보 시 이 라우트만 확장하면 됨.
//
// 응답 스키마(iOS CompanyMetricsResponse 계약과 1:1):
//   { ticker, supported, currency?, metrics?:{per,pbr,psr,roePct,divYieldPct}, dividend?:{...} }
// EOD/기업액션 데이터라 24h 캐시 + last-good 폴백.

const TD_BASE = 'https://api.twelvedata.com'
const TD_KEY  = process.env.TWELVE_DATA_API_KEY ?? ''

const CACHE_TTL_MS = 24 * 60 * 60 * 1000   // 24h

const isKR = (ticker: string) => /\.(KS|KQ)$/i.test(ticker)

// 주당배당금 표기용 통화(거래소 파라미터 기반). 비율지표는 통화무관이라 무영향.
const CURRENCY_BY_EXCHANGE: Record<string, string> = {
  nasdaq: 'USD', nyse: 'USD', all: 'USD',
  euronext: 'EUR', fwb: 'EUR',
  jpx: 'JPY', sse: 'CNY', szse: 'CNY', nse: 'INR',
}

// 지급빈도 문자열 → 연간 지급 횟수(사용자 표기용). 미상이면 null.
function freqToCount(freq: string | null | undefined): number | null {
  switch ((freq ?? '').toLowerCase()) {
    case 'annually':    case 'annual':     return 1
    case 'semi-annually': case 'semiannual': return 2
    case 'quarterly':   return 4
    case 'monthly':     return 12
    default:            return null
  }
}

interface DividendBlock {
  perShare:  number | null   // 주당 연 배당금(해당 통화)
  yieldPct:  number | null   // 배당수익률(%)
  freqCount: number | null   // 연간 지급 횟수
  exDate:    string | null   // 배당락일 "YYYY-MM-DD"
  payDate:   string | null   // 지급일
}
interface Metrics {
  per:        number | null
  pbr:        number | null
  psr:        number | null
  roePct:     number | null   // ROE(%)
  divYieldPct: number | null  // 배당수익률(%) — 지표 그리드용(dividend.yieldPct와 동일값)
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
/** 소수 배율(0.0349) → 퍼센트(3.49), 소수 2자리 반올림. */
const toPct = (v: unknown): number | null => {
  const n = num(v)
  return n == null ? null : Math.round(n * 1000) / 10
}
const round2 = (v: number | null): number | null => (v == null ? null : Math.round(v * 100) / 100)

async function fetchTdStatistics(symbol: string): Promise<Payload> {
  if (!TD_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  const url = `${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&apikey=${TD_KEY}`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`TD statistics ${symbol} → HTTP ${res.status}`)
  const json = await res.json()
  if (json?.status === 'error') throw new Error(`TD ${symbol} → ${json?.message ?? 'error'}`)

  const s  = json?.statistics ?? {}
  const v  = s.valuations_metrics ?? {}
  const f  = s.financials ?? {}
  const dv = s.dividends_and_splits ?? {}

  const divYieldPct = toPct(dv.forward_annual_dividend_yield) ?? toPct(dv.trailing_annual_dividend_yield)
  const metrics: Metrics = {
    per:        round2(num(v.trailing_pe)),
    pbr:        round2(num(v.price_to_book_mrq)),
    psr:        round2(num(v.price_to_sales_ttm)),
    roePct:     toPct(f.return_on_equity_ttm),
    divYieldPct,
  }
  const dividend: DividendBlock = {
    perShare:  round2(num(dv.forward_annual_dividend_rate) ?? num(dv.trailing_annual_dividend_rate)),
    yieldPct:  divYieldPct,
    freqCount: freqToCount(dv.dividend_frequency),
    exDate:    typeof dv.ex_dividend_date === 'string' ? dv.ex_dividend_date : null,
    payDate:   typeof dv.dividend_date === 'string' ? dv.dividend_date : null,
  }
  return { ticker: symbol, supported: true, metrics, dividend, stale: false }
}

export async function GET(req: Request) {
  const url      = new URL(req.url)
  const ticker   = (url.searchParams.get('ticker') ?? '').trim()
  const exchange = (url.searchParams.get('exchange') ?? '').trim().toLowerCase()

  if (!ticker) {
    return NextResponse.json({ error: 'company-metrics: ticker 필요' }, { status: 400 })
  }

  // KR은 아직 소스 미연동 — 정직하게 준비 중.
  if (isKR(ticker)) {
    return NextResponse.json({ ticker, supported: false, stale: false } satisfies Payload)
  }

  const key = ticker
  const hit = cache.get(key)
  if (hit && Date.now() - hit.ts < CACHE_TTL_MS) {
    return NextResponse.json(hit.data)
  }

  try {
    const data = await fetchTdStatistics(ticker)
    data.currency = CURRENCY_BY_EXCHANGE[exchange] ?? 'USD'
    cache.set(key, { data, ts: Date.now() })
    lastGood.set(key, data)
    return NextResponse.json(data)
  } catch (err) {
    console.error(`[company-metrics] ${key} failed:`, err)
    const prev = lastGood.get(key)
    if (prev) return NextResponse.json({ ...prev, stale: true })
    // 실패해도 앱이 깨지지 않게 supported=false로 폴백(플레이스홀더 표시).
    return NextResponse.json({ ticker, supported: false, stale: false } satisfies Payload)
  }
}
