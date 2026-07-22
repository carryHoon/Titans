import { NextResponse } from 'next/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// Yahoo Finance v8/finance/chart — crumb 불필요, 가장 안정적
// 장중: ~15초 지연 실시간 / 장외: 직전 종가
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

// ─── Fetcher ──────────────────────────────────────────────────────────────────

async function fetchYahooChart(symbol: string): Promise<IndexData & { id: string; name: string }> {
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

// ─── Route Handler ────────────────────────────────────────────────────────────

export async function GET() {
  // 캐시 히트
  if (cache && Date.now() - cache.ts < CACHE_TTL_MS) {
    return NextResponse.json({ data: cache.data, stale: false })
  }

  try {
    const data = await Promise.all(INDICES.map(idx => fetchYahooChart(idx.symbol)))

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
