import { NextResponse } from 'next/server'
import { getUsdKrwQuote } from '@/lib/fx'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 지수(나스닥/코스피/코스닥) = Yahoo Finance v8/finance/chart (crumb 불필요).
// 달러 환율 = 통합 FX 레이어(@/lib/fx) — 수출입은행 우선, OXR·상수 자동 폴백.
const CACHE_TTL_MS = 15_000

const INDICES = [
  { id: 'usd',    name: '달러 환율', symbol: 'KRW=X'  },
  { id: 'nasdaq', name: '나스닥',    symbol: '^IXIC'   },
  { id: 'kospi',  name: '코스피',    symbol: '^KS11'   },
  { id: 'kosdaq', name: '코스닥',    symbol: '^KQ11'   },
] as const

// ─── Types ────────────────────────────────────────────────────────────────────

interface YahooMeta {
  regularMarketPrice: number
  chartPreviousClose?: number
  previousClose?: number
  regularMarketTime?: number
}

interface YahooChartResponse {
  chart: {
    result: Array<{ meta: YahooMeta }> | null
    error: { code: string; description: string } | null
  }
}

export interface IndexData {
  id: string
  name: string
  value: number
  change: number
  changePercent: number
  updatedAt: number
}

interface CacheEntry {
  data: IndexData[]
  ts: number
}

// ─── In-Memory Cache ──────────────────────────────────────────────────────────

let cache: CacheEntry | null = null
let lastGoodCache: CacheEntry | null = null

// ─── Yahoo Fetcher ──────────────────────────────────────────────────────────

async function fetchYahooChart(symbol: string): Promise<IndexData> {
  const encoded = encodeURIComponent(symbol)
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encoded}?interval=1d&range=1d`

  const res = await fetch(url, {
    headers: { 'User-Agent': 'Mozilla/5.0 (compatible; TitansApp/1.0)' },
    cache: 'no-store',
  })
  if (!res.ok) throw new Error(`Yahoo Finance [${symbol}] → HTTP ${res.status}`)

  const json: YahooChartResponse = await res.json()
  if (json.chart.error) throw new Error(`Yahoo Finance [${symbol}] → ${json.chart.error.description}`)

  const meta = json.chart.result?.[0]?.meta
  if (!meta?.regularMarketPrice) throw new Error(`Yahoo Finance [${symbol}] → 가격 데이터 없음`)

  const prevClose = meta.chartPreviousClose ?? meta.previousClose ?? meta.regularMarketPrice
  const price = meta.regularMarketPrice
  const change = price - prevClose
  const changePercent = prevClose !== 0 ? (change / prevClose) * 100 : 0

  const idx = INDICES.find(i => i.symbol === symbol)!
  return {
    id: idx.id,
    name: idx.name,
    value: price,
    change,
    changePercent,
    updatedAt: (meta.regularMarketTime ?? 0) * 1000,
  }
}

// ─── 달러 환율 (통합 FX 레이어) ─────────────────────────────────────────────────
// 소스 선택·캐시·폴백은 전부 @/lib/fx 가 담당한다(수출입은행 우선 → OXR → 상수).
// 여기선 FxQuote 를 지수 카드(IndexData) 형태로 매핑만 한다.
async function fetchUsdIndex(): Promise<IndexData> {
  const q = await getUsdKrwQuote()
  return {
    id: 'usd',
    name: '달러 환율',
    value: q.rate,
    change: q.change,
    changePercent: q.changePercent,
    updatedAt: q.asOf,
  }
}

// ─── Route Handler ────────────────────────────────────────────────────────────

export async function GET() {
  // 캐시 히트
  if (cache && Date.now() - cache.ts < CACHE_TTL_MS) {
    return NextResponse.json({ data: cache.data, stale: false })
  }

  try {
    // 달러 환율은 Eximbank(폴백 Yahoo), 나머지 지수는 Yahoo. 순서는 INDICES 기준 유지.
    const others = INDICES.filter(i => i.id !== 'usd')
    const [usd, ...rest] = await Promise.all([
      fetchUsdIndex(),
      ...others.map(idx => fetchYahooChart(idx.symbol)),
    ])
    const data = [usd, ...rest]

    cache = { data, ts: Date.now() }
    lastGoodCache = cache

    return NextResponse.json({ data, stale: false })
  } catch (err) {
    console.error('[market-index] fetch error:', err)

    if (lastGoodCache) {
      return NextResponse.json({ data: lastGoodCache.data, stale: true }, { status: 200 })
    }

    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}
