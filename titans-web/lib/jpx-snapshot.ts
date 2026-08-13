// ─── JPX 시총 스냅샷 레이어 ─────────────────────────────────────────────────────
//
// Twelve Data Venture 플랜은 JPX에 대해 /statistics(펀더멘털)만 제공하고 가격 피드는 주지 않는다
// (/quote·/price·/eod·/time_series 전부 400/No data). 그래서 JPX는 KOSPI/KOSDAQ 처럼 "하루 1회
// 스냅샷"으로 굳히고 유저 경로는 스냅샷만 읽는 EOD 섹션이다. us-stats(US)와 달리 값을 USD가 아니라
// 네이티브 JPY(시총·발행주수)로 저장하고, USD 환산은 요청 시점(market-cap 라우트)에서 fx로 한다
// (KRX와 동일 규약 — FX가 스냅샷 시각에 얼지 않도록).
//   · refreshJpxStats(): 스케줄러(GitHub Actions)가 호출. 전 JPX 유니버스 /statistics 를 순차
//     페이싱으로 받아 스냅샷 저장. 실패 종목은 직전 값 유지. 새 영업일이면 전일 시총(prev)을 롤링.
//   · getJpxDataset(): 유저 경로(라우트)가 호출. 업스트림 없이 스냅샷만 반환(시총 내림차순).
//   · startJpxStatsWarm(): 로컬/상시 프로세스 부팅 워밍(서버리스는 크론이 대신).
//
// 저장소는 lib/snapshot-store 추상화 공유(로컬=파일, Vercel=Upstash). key='jpx-stats'.

import { createSnapshotStore } from './snapshot-store'
import { JPX_COMPANIES, JPX_EXCHANGE_PARAM } from './jpx-universe'

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'
const STATS_TTL_MS    = 24 * 3_600_000  // 로컬 워밍 판정용(스냅샷이 이보다 오래되면 재취득)

// JPX /statistics 는 호출당 ~3 credits(US 50c보다 저렴). 그래도 버스트 방지 위해 2.5초당 1콜로
// 순차 페이싱한다 → 106종목 ≈ 4.4분. 유저 경로가 아니라 스케줄러가 돌므로 시간 제한 없음.
const STATS_GAP_MS      = 2_500
const RETRY_COOLDOWN_MS = 30_000  // 1차 실패(429 등) 종목은 이만큼 쉰 뒤 1회 재시도

// 종목별 시총 기준값(네이티브 JPY)과 발행주수. 주당가격 = capJPY / shares(파생)에 쓴다.
export interface JpxStatEntry {
  capJPY: number
  shares: number
}

export interface JpxSnapshot {
  fetchedAt: number
  asOfDate:  string                         // JST YYYY-MM-DD (prev 롤링 판정용)
  current:   Record<string, JpxStatEntry>   // ticker → {capJPY, shares}
  prev:      Record<string, number>         // ticker → 전 영업일 capJPY (등락% 계산용)
}

const store = createSnapshotStore<JpxSnapshot>('jpx-stats')

let current:    JpxSnapshot | null = null
let refreshing: Promise<{ updated: number; failed: number }> | null = null

// JST(UTC+9) 기준 YYYY-MM-DD.
function jstDateStr(): string {
  const k = new Date(Date.now() + 9 * 3_600_000)
  const y = k.getUTCFullYear()
  const m = String(k.getUTCMonth() + 1).padStart(2, '0')
  const d = String(k.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

// 단일 종목 /statistics → {capJPY, shares}. 심볼 disambiguation 은 ?exchange=JPX.
async function fetchStat(ticker: string): Promise<JpxStatEntry> {
  const res = await fetch(
    `${TD_BASE}/statistics?symbol=${encodeURIComponent(ticker)}&exchange=${JPX_EXCHANGE_PARAM}&apikey=${TWELVE_DATA_KEY}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`jpx-stats ${ticker} → HTTP ${res.status}`)
  const data = await res.json()
  if (data.status === 'error') throw new Error(`jpx-stats ${ticker} → ${data.message}`)
  const stats  = data?.statistics
  const capJPY = stats?.valuations_metrics?.market_capitalization as number | undefined
  const shares = stats?.stock_statistics?.shares_outstanding as number | undefined
  if (!capJPY) throw new Error(`jpx-stats ${ticker} → market_capitalization 없음`)
  return { capJPY, shares: shares && shares > 0 ? shares : 0 }
}

// ─── 갱신(스케줄러 전용) ────────────────────────────────────────────────────────
// 전 JPX 유니버스를 순차 fetch. 실패(429 등) 종목은 30초 쿨다운 후 1회 재시도. 실패 종목은
// 직전 스냅샷 값을 그대로 유지한다. 새 영업일(asOfDate 변경)일 때만 전일 시총(prev)을 롤링.
export async function refreshJpxStats(): Promise<{ updated: number; failed: number }> {
  if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (refreshing) return refreshing

  refreshing = (async () => {
    if (!current) current = await store.load()
    const prevCurrent = current?.current ?? {}
    const next: Record<string, JpxStatEntry> = { ...prevCurrent }  // 실패 종목은 직전 값 유지

    const tickers = JPX_COMPANIES.map(c => c.ticker)

    const attempt = async (list: string[]): Promise<string[]> => {
      const failedTickers: string[] = []
      for (let i = 0; i < list.length; i++) {
        const t = list[i]
        try {
          next[t] = await fetchStat(t)
        } catch (err) {
          failedTickers.push(t)
          console.warn(`[jpx-stats] ${t} 실패, 직전값 유지:`, err instanceof Error ? err.message : err)
        }
        if (i < list.length - 1) await new Promise(r => setTimeout(r, STATS_GAP_MS))
      }
      return failedTickers
    }

    let failedTickers = await attempt(tickers)
    if (failedTickers.length > 0) {
      console.warn(`[jpx-stats] ${failedTickers.length}개 실패 → ${RETRY_COOLDOWN_MS / 1000}s 후 재시도`)
      await new Promise(r => setTimeout(r, RETRY_COOLDOWN_MS))
      failedTickers = await attempt(failedTickers)
    }

    // 전일 시총(prev): 새 영업일이면 직전 스냅샷의 current를 굳혀 롤링, 같은 날 재실행이면 유지.
    const todayDate = jstDateStr()
    const prev: Record<string, number> =
      current && current.asOfDate !== todayDate
        ? Object.fromEntries(Object.entries(prevCurrent).map(([t, e]) => [t, e.capJPY]))
        : current?.prev ?? {}

    const updated = tickers.length - failedTickers.length
    const snap: JpxSnapshot = { fetchedAt: Date.now(), asOfDate: todayDate, current: next, prev }
    current = snap
    await store.save(snap)
    console.log(`[jpx-stats] refreshed → ${updated}/${tickers.length} ok, ${failedTickers.length} failed, asOf=${todayDate}`)
    return { updated, failed: failedTickers.length }
  })().finally(() => { refreshing = null })

  return refreshing
}

// ─── 유저 경로 read API ─────────────────────────────────────────────────────────

export interface JpxRow {
  ticker:     string
  capJPY:     number
  shares:     number
  prevCapJPY: number  // 없으면 capJPY(등락 0 처리)
}

async function ensureLoaded(): Promise<void> {
  if (current) return
  current = await store.load()
}

// 스냅샷을 시총(JPY) 내림차순 배열로 반환. 업스트림 호출 없음. 스냅샷 부재면 빈 배열(라우트가 방어).
export async function getJpxDataset(): Promise<JpxRow[]> {
  await ensureLoaded()
  const cur  = current?.current ?? {}
  const prev = current?.prev ?? {}
  const rows: JpxRow[] = Object.entries(cur)
    .filter(([, e]) => e.capJPY > 0)
    .map(([ticker, e]) => ({
      ticker,
      capJPY:     e.capJPY,
      shares:     e.shares,
      prevCapJPY: prev[ticker] && prev[ticker] > 0 ? prev[ticker] : e.capJPY,
    }))
  rows.sort((a, b) => b.capJPY - a.capJPY)
  return rows
}

// ─── 로컬/상시 프로세스 부팅 워밍 ───────────────────────────────────────────────
// 서버리스(Vercel)에선 크론이 갱신하므로 워밍 불필요. 로컬(next dev/start)·VPS에서만:
// 부팅 시 스냅샷이 없거나 24h 초과면 1회 새로 받는다.
export function startJpxStatsWarm(): void {
  if (process.env.VERCEL) return
  if (!TWELVE_DATA_KEY) return
  if (process.env.NEXT_PHASE === 'phase-production-build') return

  const g = globalThis as unknown as { __jpxStatsWarmed?: boolean }
  if (g.__jpxStatsWarmed) return
  g.__jpxStatsWarmed = true

  ensureLoaded()
    .then(() => {
      const stale = !current || Date.now() - current.fetchedAt > STATS_TTL_MS
      if (stale) return refreshJpxStats().then(() => {})
    })
    .catch(err => console.warn('[jpx-stats] initial warm failed:', err))
}
