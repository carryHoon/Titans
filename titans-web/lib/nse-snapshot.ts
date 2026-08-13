// ─── 인도 NSE 시총 기준값(stats) 스냅샷 레이어 ────────────────────────────────
//
// NSE(XNSE) 종목의 시총 기준값(/statistics: market_cap INR + shares)을 하루 1회 스냅샷으로 굳힌다.
// 라우트(유저 경로)는 이 스냅샷을 base로 쓰고, quote(close/prevClose)가 있으면 라이브 스케일링
// (cap = statsCap × close/prevClose)한다. quote 결손 시 stats 시총 + 전일 스냅샷 대비로 폴백.
// USD 환산은 라우트에서 fx(USD/INR)로. 네이티브 INR로 저장(환율이 스냅샷 시각에 얼지 않도록).
//
// 구조·페이싱·읽기 TTL은 cn-snapshot과 동일. 저장소 lib/snapshot-store 공유, key='nse-stats'.
// 전 종목 단일 mic(XNSE)이라 cn의 mic 분기가 없다.

import { createSnapshotStore } from './snapshot-store'
import { NSE_COMPANIES, NSE_MIC } from './nse-universe'

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'
const STATS_TTL_MS    = 24 * 3_600_000

// TD /statistics는 콜당 ~50 크레딧. Venture 610/분 ÷ 50 ≈ 12콜/분 상한 → 6s(=10콜/분=500크레딧/분)로
// 유저 quote 트래픽(~80/분)까지 얹혀도 429를 피한다. cn-snapshot과 동일한 사유·수치.
const STATS_GAP_MS      = 6_000
const RETRY_COOLDOWN_MS = 30_000

export interface NseStatEntry {
  capINR: number
  shares: number
}

export interface NseSnapshot {
  fetchedAt: number
  asOfDate:  string                          // IST(UTC+5:30) YYYY-MM-DD — prev 롤링 판정용
  current:   Record<string, NseStatEntry>    // symbol → {capINR, shares}
  prev:      Record<string, number>          // symbol → 전 영업일 capINR (EOD 등락% 계산용)
}

const store = createSnapshotStore<NseSnapshot>('nse-stats')

let current:    NseSnapshot | null = null
let refreshing: Promise<{ updated: number; failed: number }> | null = null
let loadedAt = 0  // current를 store에서 마지막으로 읽은 시각(읽기 경로 TTL 재로드용)

// 인도 표준시(IST=UTC+5:30) 기준 YYYY-MM-DD. prev 롤링용이라 근사로 충분.
function istDateStr(): string {
  const k = new Date(Date.now() + (5 * 60 + 30) * 60_000)
  const y = k.getUTCFullYear()
  const m = String(k.getUTCMonth() + 1).padStart(2, '0')
  const d = String(k.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

// 단일 종목 /statistics → {capINR, shares}. 심볼+mic_code(XNSE)로 특정.
async function fetchStat(symbol: string): Promise<NseStatEntry> {
  const res = await fetch(
    `${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&mic_code=${NSE_MIC}&apikey=${TWELVE_DATA_KEY}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`nse-stats ${symbol} → HTTP ${res.status}`)
  const data = await res.json()
  if (data.status === 'error') throw new Error(`nse-stats ${symbol} → ${data.message}`)
  const stats  = data?.statistics
  const capINR = stats?.valuations_metrics?.market_capitalization as number | undefined
  const shares = stats?.stock_statistics?.shares_outstanding as number | undefined
  if (!capINR) throw new Error(`nse-stats ${symbol} → market_capitalization 없음`)
  return { capINR, shares: shares && shares > 0 ? shares : 0 }
}

export async function refreshNseStats(): Promise<{ updated: number; failed: number }> {
  if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (refreshing) return refreshing

  refreshing = (async () => {
    if (!current) current = await store.load()
    const prevCurrent = current?.current ?? {}
    const next: Record<string, NseStatEntry> = { ...prevCurrent }

    // 실패 시 직전값 유지. attempt는 남은 심볼 목록을 받아 실패분을 돌려준다.
    const attempt = async (symbols: string[]): Promise<string[]> => {
      const failed: string[] = []
      for (let i = 0; i < symbols.length; i++) {
        try {
          next[symbols[i]] = await fetchStat(symbols[i])
        } catch (err) {
          failed.push(symbols[i])
          console.warn(`[nse-stats] ${symbols[i]} 실패, 직전값 유지:`, err instanceof Error ? err.message : err)
        }
        if (i < symbols.length - 1) await new Promise(r => setTimeout(r, STATS_GAP_MS))
      }
      return failed
    }

    let failed = await attempt(NSE_COMPANIES.map(c => c.symbol))
    if (failed.length > 0) {
      console.warn(`[nse-stats] ${failed.length}개 실패 → ${RETRY_COOLDOWN_MS / 1000}s 후 재시도`)
      await new Promise(r => setTimeout(r, RETRY_COOLDOWN_MS))
      failed = await attempt(failed)
    }

    const todayDate = istDateStr()
    const prev: Record<string, number> =
      current && current.asOfDate !== todayDate
        ? Object.fromEntries(Object.entries(prevCurrent).map(([s, e]) => [s, e.capINR]))
        : current?.prev ?? {}

    const updated = NSE_COMPANIES.length - failed.length
    const snap: NseSnapshot = { fetchedAt: Date.now(), asOfDate: todayDate, current: next, prev }
    current = snap
    loadedAt = Date.now()  // 방금 갱신 → 읽기 경로 재조회 억제
    await store.save(snap)
    console.log(`[nse-stats] refreshed → ${updated}/${NSE_COMPANIES.length} ok, ${failed.length} failed, asOf=${todayDate}`)
    return { updated, failed: failed.length }
  })().finally(() => { refreshing = null })

  return refreshing
}

// ─── 유저 경로 read API ─────────────────────────────────────────────────────────

export interface NseStatsRead {
  cap:  Record<string, NseStatEntry>  // symbol → {capINR, shares} (base = 전일 종가 시총)
  prev: Record<string, number>        // symbol → 전 영업일 capINR
}

// 읽기 경로 재로드 주기. 웜 인스턴스가 옛 스냅샷을 계속 서빙하지 않도록 이 TTL마다 store 재조회.
const READ_REFRESH_MS = 5 * 60_000

async function ensureLoaded(): Promise<void> {
  if (current && Date.now() - loadedAt < READ_REFRESH_MS) return
  const loaded = await store.load()
  if (loaded) { current = loaded }
  loadedAt = Date.now()  // 결손(null)이어도 타임스탬프 갱신 → 매 요청 재조회 방지
}

export async function getNseStats(): Promise<NseStatsRead> {
  await ensureLoaded()
  return { cap: current?.current ?? {}, prev: current?.prev ?? {} }
}

export function startNseStatsWarm(): void {
  if (process.env.VERCEL) return
  if (!TWELVE_DATA_KEY) return
  if (process.env.NEXT_PHASE === 'phase-production-build') return

  const g = globalThis as unknown as { __nseStatsWarmed?: boolean }
  if (g.__nseStatsWarmed) return
  g.__nseStatsWarmed = true

  ensureLoaded()
    .then(() => {
      const stale = !current || Date.now() - current.fetchedAt > STATS_TTL_MS
      if (stale) return refreshNseStats().then(() => {})
    })
    .catch(err => console.warn('[nse-stats] initial warm failed:', err))
}
