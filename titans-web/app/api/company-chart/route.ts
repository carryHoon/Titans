import { NextResponse } from 'next/server'
import { getUsdKrwQuote } from '@/lib/fx'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 종목 상세 화면(CompanyDetailView)의 "시가총액 히스토리" 데이터 소스.
//   · 🇰🇷 KOSPI/KOSDAQ(.KS/.KQ) = 공공데이터포털 getStockPriceInfo 의 mrktTotAmt(일별 공식 시가총액).
//       likeSrtnCd(단축코드) + beginBasDt/endBasDt(날짜범위)로 종목별 일별 시총을 직접 받는다(재계산 불필요).
//       라이선스 0. 단, 이 API는 2020년 이후 데이터만 제공한다(그 이전은 없음).
//   · 🇺🇸/글로벌 = Twelve Data time_series(일봉 종가, 상장~현재·split 조정) × 현재 발행주식수(/statistics).
//       TD는 과거 발행주식수를 안 주므로(엔터프라이즈 전용) "종가×현재주식수" 재구성 = 근사치.
//       스플릿은 반영되나 자사주매입/증자가 큰 종목은 과거 절대값에 오차 → 앱이 '추정치' 각주를 단다.
//
// 응답 스키마는 iOS CompanyChartResponse 계약과 1:1: { ticker, name, points:[{date,capUSD}], stale?, error? }
// capUSD 단위 = trillion USD(앱 전역 규약). EOD(하루 1회 변동)라 24h 캐시 + last-good 폴백.

const TD_BASE = 'https://api.twelvedata.com'
const TD_KEY  = process.env.TWELVE_DATA_API_KEY ?? ''

const DATA_GO_KR_KEY = process.env.DATA_GO_KR_KEY
const KR_STOCK_URL =
  'https://apis.data.go.kr/1160100/service/GetStockSecuritiesInfoService/getStockPriceInfo'

const CACHE_TTL_MS = 24 * 60 * 60 * 1000   // 24h

type Range = 'w1' | 'm1' | 'm3' | 'y1' | 'y5' | 'all'

// 기간별: 조회할 달력일 수(all=null=최대), 최종 다운샘플 포인트 상한.
const RANGE_DAYS: Record<Range, number | null> = {
  w1: 7, m1: 30, m3: 90, y1: 365, y5: 365 * 5, all: null,
}
const RANGE_MAXPTS: Record<Range, number> = {
  w1: 8, m1: 24, m3: 60, y1: 120, y5: 180, all: 240,
}

interface ChartPoint { date: string; capUSD: number }
interface Payload { ticker: string; name: string; points: ChartPoint[]; stale: boolean }

interface CacheEntry { data: Payload; ts: number }
const cache    = new Map<string, CacheEntry>()
const lastGood = new Map<string, Payload>()

// ─── 공통 유틸 ────────────────────────────────────────────────────────────────

/** 오래된→최신 배열을 최대 maxPts개로 균등 다운샘플(첫·마지막 보존). */
function downsample<T>(arr: T[], maxPts: number): T[] {
  if (arr.length <= maxPts) return arr
  const out: T[] = []
  const step = (arr.length - 1) / (maxPts - 1)
  for (let i = 0; i < maxPts; i++) out.push(arr[Math.round(i * step)])
  // 마지막 원소 보장
  if (out[out.length - 1] !== arr[arr.length - 1]) out[out.length - 1] = arr[arr.length - 1]
  return out
}

function ymd(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
function yyyymmdd(d: Date): string { return ymd(d).replace(/-/g, '') }
function daysAgo(n: number): Date { return new Date(Date.now() - n * 24 * 60 * 60 * 1000) }

const isKR = (ticker: string) => /\.(KS|KQ)$/i.test(ticker)

// ─── 🇰🇷 공공데이터포털: 종목 일별 시가총액(mrktTotAmt) ─────────────────────────
async function fetchKrCaps(ticker: string, range: Range): Promise<{ name: string; points: ChartPoint[] }> {
  if (!DATA_GO_KR_KEY) throw new Error('DATA_GO_KR_KEY 미설정')
  const code = ticker.split('.')[0]                       // "005930.KS" → "005930"
  const days = RANGE_DAYS[range]
  // all/장기는 이 API 하한(2020~)까지. beginBasDt를 넉넉히 과거로 두면 제공 최초일부터 반환된다.
  const begin = days == null ? '20000101' : yyyymmdd(daysAgo(days))
  const end   = yyyymmdd(new Date())

  const params = new URLSearchParams({
    serviceKey: DATA_GO_KR_KEY,
    resultType: 'json',
    likeSrtnCd: code,
    beginBasDt: begin,
    endBasDt:   end,
    numOfRows:  '3000',
  })
  const res = await fetch(`${KR_STOCK_URL}?${params.toString()}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`data.go.kr ${code} → HTTP ${res.status}`)
  const json = await res.json()
  const body = json?.response?.body
  let items = body?.items?.item ?? []
  if (!Array.isArray(items)) items = items ? [items] : []
  if (items.length === 0) throw new Error(`data.go.kr ${code} → 데이터 없음`)

  const krwPerUsd = (await getUsdKrwQuote()).rate
  const name = String(items[0]?.itmsNm ?? code)

  // basDt 오름차순(오래된→최신). mrktTotAmt(KRW) → trillion USD.
  const points: ChartPoint[] = items
    .map((it: { basDt: string; mrktTotAmt: string }) => ({
      basDt: String(it.basDt),
      capKRW: Number(it.mrktTotAmt),
    }))
    .filter((r: { basDt: string; capKRW: number }) => r.basDt && Number.isFinite(r.capKRW) && r.capKRW > 0)
    .sort((a: { basDt: string }, b: { basDt: string }) => a.basDt.localeCompare(b.basDt))
    .map((r: { basDt: string; capKRW: number }) => ({
      date: `${r.basDt.slice(0, 4)}-${r.basDt.slice(4, 6)}-${r.basDt.slice(6, 8)}`,
      capUSD: r.capKRW / krwPerUsd / 1_000_000_000_000,
    }))

  return { name, points: downsample(points, RANGE_MAXPTS[range]) }
}

// ─── 🇺🇸/글로벌 Twelve Data: 일봉 종가 × 현재 발행주식수 ───────────────────────
interface TdBar { datetime: string; close: string }

/** time_series 1콜(newest→oldest). end_date 지정 시 그 이전 구간. */
async function tdSeriesCall(symbol: string, outputsize: number, endDate?: string): Promise<TdBar[]> {
  const url = `${TD_BASE}/time_series?symbol=${encodeURIComponent(symbol)}` +
              `&interval=1day&outputsize=${outputsize}` +
              (endDate ? `&end_date=${endDate}` : '') +
              `&apikey=${TD_KEY}`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`TD time_series ${symbol} → HTTP ${res.status}`)
  const json = await res.json()
  if (json?.status === 'error') throw new Error(`TD ${symbol} → ${json?.message ?? 'error'}`)
  return Array.isArray(json?.values) ? json.values : []
}

/** 현재 발행주식수(/statistics). 실패 시 0. */
async function tdSharesOutstanding(symbol: string): Promise<number> {
  const url = `${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&apikey=${TD_KEY}`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) return 0
  const json = await res.json()
  const n = Number(json?.statistics?.stock_statistics?.shares_outstanding)
  return Number.isFinite(n) && n > 0 ? n : 0
}

async function fetchUsCaps(symbol: string, range: Range): Promise<{ name: string; points: ChartPoint[] }> {
  if (!TD_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')

  const shares = await tdSharesOutstanding(symbol)
  if (shares <= 0) throw new Error(`TD ${symbol} → shares_outstanding 없음`)

  const days = RANGE_DAYS[range]
  const bars: TdBar[] = []

  if (days != null) {
    // 유한 기간: 1콜로 충분(≤ y5 ≈ 1250 거래일 < 5000).
    const need = Math.min(5000, Math.ceil(days * 0.72) + 5)
    bars.push(...await tdSeriesCall(symbol, need))
  } else {
    // all: 상장일까지 슬라이딩 페이지네이션(콜당 5000, 최대 8콜 ≈ 40000 거래일).
    let endDate: string | undefined = undefined
    for (let call = 0; call < 8; call++) {
      const chunk = await tdSeriesCall(symbol, 5000, endDate)
      if (chunk.length === 0) break
      bars.push(...chunk)
      if (chunk.length < 5000) break
      // 다음 페이지: 가장 오래된 날짜의 하루 전까지.
      const oldest = chunk[chunk.length - 1]?.datetime
      if (!oldest) break
      const d = new Date(`${oldest}T00:00:00Z`)
      d.setUTCDate(d.getUTCDate() - 1)
      endDate = ymd(d)
    }
  }
  if (bars.length < 2) throw new Error(`TD ${symbol} → 시계열 부족(${bars.length})`)

  // newest→oldest 로 오므로 뒤집어 오래된→최신. 시총(trillion USD) = close × shares / 1e12.
  const asc = bars
    .map(b => ({ date: b.datetime.slice(0, 10), close: Number(b.close) }))
    .filter(b => b.date && Number.isFinite(b.close) && b.close > 0)
    .reverse()

  // 중복 날짜 제거(페이지 경계) — 날짜 기준 유니크.
  const seen = new Set<string>()
  const points: ChartPoint[] = []
  for (const b of asc) {
    if (seen.has(b.date)) continue
    seen.add(b.date)
    points.push({ date: b.date, capUSD: (b.close * shares) / 1_000_000_000_000 })
  }

  return { name: symbol, points: downsample(points, RANGE_MAXPTS[range]) }
}

// ─── 라우트 ──────────────────────────────────────────────────────────────────
export async function GET(req: Request) {
  const url    = new URL(req.url)
  const ticker = (url.searchParams.get('ticker') ?? '').trim()
  const rangeQ = (url.searchParams.get('range') ?? 'm3').toLowerCase()
  const range: Range = (['w1', 'm1', 'm3', 'y1', 'y5', 'all'] as Range[]).includes(rangeQ as Range)
    ? (rangeQ as Range) : 'm3'

  if (!ticker) {
    return NextResponse.json({ error: 'company-chart: ticker 필요' }, { status: 400 })
  }

  const key = `${ticker}|${range}`
  const hit = cache.get(key)
  if (hit && Date.now() - hit.ts < CACHE_TTL_MS) {
    return NextResponse.json(hit.data)
  }

  try {
    const { name, points } = isKR(ticker)
      ? await fetchKrCaps(ticker, range)
      : await fetchUsCaps(ticker, range)
    if (points.length < 2) throw new Error('포인트 부족')

    const data: Payload = { ticker, name, points, stale: false }
    cache.set(key, { data, ts: Date.now() })
    lastGood.set(key, data)
    return NextResponse.json(data)
  } catch (err) {
    console.error(`[company-chart] ${key} failed:`, err)
    const prev = lastGood.get(key)
    if (prev) return NextResponse.json({ ...prev, stale: true })
    return NextResponse.json({ error: `company-chart: ${ticker} 데이터 없음` }, { status: 503 })
  }
}
