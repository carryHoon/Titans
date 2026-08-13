// ─── 중국 A주 시총 기준값(stats) 스냅샷 레이어 ────────────────────────────────
//
// SSE(XSHG)·SZSE(XSHE) A주의 시총 기준값(/statistics: market_cap CNY + shares)을 하루 1회
// 스냅샷으로 굳힌다. 라우트(유저 경로)는 이 스냅샷을 base로 쓰고, quote(close/prevClose)가
// 있으면 요청 시 라이브 스케일링(cap = statsCap × close/prevClose)한다. TD의 A주 quote는
// 지연/EOD라 등락은 직전 영업일 기준이며, quote 결손 시 stats 시총 + 전일 스냅샷 대비로 폴백한다.
// USD 환산은 라우트에서 fx(USD/CNY)로.
//
// us-stats(USD 고정)와 달리 네이티브 CNY로 저장한다(환율이 스냅샷 시각에 얼지 않도록 — KRX/JPX/EU 규약).
// 구조는 eu-snapshot과 동일(현재 cap+shares + 전일 cap 롤링). 저장소는 lib/snapshot-store 공유. key='cn-stats'.

import { createSnapshotStore } from './snapshot-store'
import { CN_COMPANIES } from './cn-universe'

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'
const STATS_TTL_MS    = 24 * 3_600_000

const STATS_GAP_MS      = 2_500
const RETRY_COOLDOWN_MS = 30_000

export interface CnStatEntry {
  capCNY: number
  shares: number
}

export interface CnSnapshot {
  fetchedAt: number
  asOfDate:  string                         // CST(UTC+8) YYYY-MM-DD — prev 롤링 판정용
  current:   Record<string, CnStatEntry>    // symbol → {capCNY, shares}
  prev:      Record<string, number>         // symbol → 전 영업일 capCNY (EOD 등락% 계산용)
}

const store = createSnapshotStore<CnSnapshot>('cn-stats')

let current:    CnSnapshot | null = null
let refreshing: Promise<{ updated: number; failed: number }> | null = null

// 중국 표준시(CST=UTC+8) 기준 YYYY-MM-DD. prev 롤링용이라 근사로 충분.
function cstDateStr(): string {
  const k = new Date(Date.now() + 8 * 3_600_000)
  const y = k.getUTCFullYear()
  const m = String(k.getUTCMonth() + 1).padStart(2, '0')
  const d = String(k.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

// 단일 종목 /statistics → {capCNY, shares}. 심볼+mic_code로 정확히 특정(상하이/선전 구분).
async function fetchStat(symbol: string, mic: string): Promise<CnStatEntry> {
  const res = await fetch(
    `${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&mic_code=${mic}&apikey=${TWELVE_DATA_KEY}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`cn-stats ${symbol}/${mic} → HTTP ${res.status}`)
  const data = await res.json()
  if (data.status === 'error') throw new Error(`cn-stats ${symbol}/${mic} → ${data.message}`)
  const stats  = data?.statistics
  const capCNY = stats?.valuations_metrics?.market_capitalization as number | undefined
  const shares = stats?.stock_statistics?.shares_outstanding as number | undefined
  if (!capCNY) throw new Error(`cn-stats ${symbol}/${mic} → market_capitalization 없음`)
  return { capCNY, shares: shares && shares > 0 ? shares : 0 }
}

export async function refreshCnStats(): Promise<{ updated: number; failed: number }> {
  if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (refreshing) return refreshing

  refreshing = (async () => {
    if (!current) current = await store.load()
    const prevCurrent = current?.current ?? {}
    const next: Record<string, CnStatEntry> = { ...prevCurrent }

    // 실패 시 직전값 유지. attempt는 남은 심볼 목록을 받아 실패분을 돌려준다.
    const bySymbol = new Map(CN_COMPANIES.map(c => [c.symbol, c]))
    const attempt = async (symbols: string[]): Promise<string[]> => {
      const failed: string[] = []
      for (let i = 0; i < symbols.length; i++) {
        const c = bySymbol.get(symbols[i])!
        try {
          next[c.symbol] = await fetchStat(c.symbol, c.mic)
        } catch (err) {
          failed.push(c.symbol)
          console.warn(`[cn-stats] ${c.symbol} 실패, 직전값 유지:`, err instanceof Error ? err.message : err)
        }
        if (i < symbols.length - 1) await new Promise(r => setTimeout(r, STATS_GAP_MS))
      }
      return failed
    }

    let failed = await attempt(CN_COMPANIES.map(c => c.symbol))
    if (failed.length > 0) {
      console.warn(`[cn-stats] ${failed.length}개 실패 → ${RETRY_COOLDOWN_MS / 1000}s 후 재시도`)
      await new Promise(r => setTimeout(r, RETRY_COOLDOWN_MS))
      failed = await attempt(failed)
    }

    const todayDate = cstDateStr()
    const prev: Record<string, number> =
      current && current.asOfDate !== todayDate
        ? Object.fromEntries(Object.entries(prevCurrent).map(([s, e]) => [s, e.capCNY]))
        : current?.prev ?? {}

    const updated = CN_COMPANIES.length - failed.length
    const snap: CnSnapshot = { fetchedAt: Date.now(), asOfDate: todayDate, current: next, prev }
    current = snap
    await store.save(snap)
    console.log(`[cn-stats] refreshed → ${updated}/${CN_COMPANIES.length} ok, ${failed.length} failed, asOf=${todayDate}`)
    return { updated, failed: failed.length }
  })().finally(() => { refreshing = null })

  return refreshing
}

// ─── 유저 경로 read API ─────────────────────────────────────────────────────────

export interface CnStatsRead {
  cap:  Record<string, CnStatEntry>  // symbol → {capCNY, shares} (base = 전일 종가 시총)
  prev: Record<string, number>       // symbol → 전 영업일 capCNY
}

async function ensureLoaded(): Promise<void> {
  if (current) return
  current = await store.load()
}

export async function getCnStats(): Promise<CnStatsRead> {
  await ensureLoaded()
  return { cap: current?.current ?? {}, prev: current?.prev ?? {} }
}

export function startCnStatsWarm(): void {
  if (process.env.VERCEL) return
  if (!TWELVE_DATA_KEY) return
  if (process.env.NEXT_PHASE === 'phase-production-build') return

  const g = globalThis as unknown as { __cnStatsWarmed?: boolean }
  if (g.__cnStatsWarmed) return
  g.__cnStatsWarmed = true

  ensureLoaded()
    .then(() => {
      const stale = !current || Date.now() - current.fetchedAt > STATS_TTL_MS
      if (stale) return refreshCnStats().then(() => {})
    })
    .catch(err => console.warn('[cn-stats] initial warm failed:', err))
}
