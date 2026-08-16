import { NextResponse } from 'next/server'
import { MARKET_CHART, type MarketChartConfig } from '@/lib/exchanges'
import { fetchKrIndexSeries, startKrPoller } from '@/lib/kr-snapshot'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 홈 상단 스파크라인(거래소별 지수 라인그래프) 데이터 소스.
//   · US(nasdaq/nyse/all) = 대표 ETF의 1일봉 time_series(Twelve Data 상업 라이선스).
//     TD Venture 플랜이 지수 직접조회를 지원하지 않아, US상장 대표 ETF로 지수를 "대변"한다.
//     QQQ=나스닥100, DIA=다우존스, SPY=S&P500. 라벨은 대변 지수명으로 정직하게 표기한다.
//   · KR(kospi/kosdaq)     = 공공데이터포털 지수시세정보(data.go.kr)의 일별 종가(라이선스 0).
//
// 소스↔거래소 매핑은 @/lib/exchanges 의 MARKET_CHART(단일 소스)가 소유한다.
// 그래프는 일별(EOD)이라 하루 1회만 신선하면 충분 → 24h 캐시 + last-good 폴백으로
// 업스트림 호출을 최소화한다(TD 크레딧: 심볼당 1 credit × 하루 1회 = 무시 가능).
startKrPoller()

const TD_BASE = 'https://api.twelvedata.com'
const TD_KEY  = process.env.TWELVE_DATA_API_KEY ?? ''

const CACHE_TTL_MS = 24 * 60 * 60 * 1000  // 24h (EOD 라인은 하루 1회 갱신이면 충분)
const OUTPUT_SIZE  = 30                    // 최근 ~30 거래일

interface ChartPayload {
  exchange:      string
  name:          string
  points:        number[]   // 오래된→최신 종가
  changePercent: number     // 첫→마지막 종가 변화율(%)
  asOf:          number      // ms epoch
  stale:         boolean
}

interface CacheEntry { data: ChartPayload; ts: number }
const cache        = new Map<string, CacheEntry>()
const lastGood     = new Map<string, ChartPayload>()

// ─── TD ETF 1일봉 time_series ───────────────────────────────────────────────────
// /time_series?symbol=QQQ&interval=1day&outputsize=30 — values 는 최신→과거 순. close=문자열.
// mic 지정 시 &mic_code= 로 거래소를 특정한다(XETRA상장 EUR ETF는 mic:'XETR' 없이는 400).
async function fetchTdSeries(symbol: string, mic?: string): Promise<number[]> {
  if (!TD_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  const url = `${TD_BASE}/time_series?symbol=${encodeURIComponent(symbol)}` +
              (mic ? `&mic_code=${encodeURIComponent(mic)}` : '') +
              `&interval=1day&outputsize=${OUTPUT_SIZE}&apikey=${TD_KEY}`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`TD time_series ${symbol} → HTTP ${res.status}`)
  const json = await res.json()
  if (json?.status === 'error') throw new Error(`TD ${symbol} → ${json?.message ?? 'error'}`)
  const values: { close: string }[] = Array.isArray(json?.values) ? json.values : []
  if (values.length === 0) throw new Error(`TD ${symbol} → 빈 time_series`)
  // 최신→과거로 오므로 reverse 해서 오래된→최신 종가 배열로 만든다.
  return values
    .map(v => Number(v.close))
    .filter(n => Number.isFinite(n) && n > 0)
    .reverse()
}

async function buildPayload(param: string, cfg: MarketChartConfig): Promise<ChartPayload> {
  let points: number[]
  if (cfg.source.kind === 'td') {
    points = await fetchTdSeries(cfg.source.symbol, cfg.source.mic)
  } else {
    const series = await fetchKrIndexSeries(cfg.source.idxCsf, cfg.source.idxNm)
    points = series.map(r => r.clpr)
  }
  if (points.length < 2) throw new Error(`${param} → 시계열 포인트 부족(${points.length})`)
  const first = points[0]
  const last  = points[points.length - 1]
  const changePercent = first > 0 ? ((last - first) / first) * 100 : 0
  return {
    exchange:      param,
    name:          cfg.label,
    points,
    changePercent: Math.round(changePercent * 100) / 100,
    asOf:          Date.now(),
    stale:         false,
  }
}

export async function GET(req: Request) {
  const url   = new URL(req.url)
  const param = (url.searchParams.get('exchange') ?? 'all').toLowerCase()
  const cfg   = MARKET_CHART[param]
  if (!cfg) {
    return NextResponse.json({ error: `market-chart: 미지원 거래소(${param})` }, { status: 404 })
  }

  // 캐시 히트(24h TTL)
  const hit = cache.get(param)
  if (hit && Date.now() - hit.ts < CACHE_TTL_MS) {
    return NextResponse.json(hit.data)
  }

  try {
    const data = await buildPayload(param, cfg)
    cache.set(param, { data, ts: Date.now() })
    lastGood.set(param, data)
    return NextResponse.json(data)
  } catch (err) {
    console.error(`[market-chart] ${param} failed:`, err)
    const prev = lastGood.get(param)
    if (prev) return NextResponse.json({ ...prev, stale: true })
    return NextResponse.json({ error: `market-chart: ${param} 데이터 없음` }, { status: 503 })
  }
}
