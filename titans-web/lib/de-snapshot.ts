// ─── 독일 FWB 시총 기준값(stats) 스냅샷 레이어 ───────────────────────────────
//
// FWB(Deutsche Börse) 대형주의 시총 기준값(/statistics: market_cap EUR + shares)을 하루 1회
// 스냅샷으로 굳힌다. 라우트(유저 경로)는 이 스냅샷을 base로 쓰고, quote가 있는 종목(FWB는 전 종목
// quote 有)은 요청 시 라이브 스케일링(cap = statsCap × close/prevClose)한다. quote가 일시적으로
// 없으면 stats 시총 그대로 + 전일 스냅샷 대비 등락%로 폴백한다. USD 환산은 라우트에서 fx(EUR/USD)로.
//
// us-stats(USD 고정)와 달리 네이티브 EUR로 저장한다(환율이 스냅샷 시각에 얼지 않도록 — KRX/JPX/EU 규약).
// 구조는 eu-snapshot과 동일(현재 cap+shares + 전일 cap 롤링). 차이는 단일 mic(XETR)뿐.
// 저장소는 lib/snapshot-store 공유. key='de-stats'.

import { createSnapshotStore } from './snapshot-store'
import { DE_COMPANIES, DE_MIC } from './de-universe'

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'
const STATS_TTL_MS    = 24 * 3_600_000

// TD /statistics 는 호출당 ~50 credits(api_usage 실측). Venture 610/분 ÷ 50 ≈ 12콜/분 상한이라
// 옛 2.5s(=24콜/분=1200크레딧/분)로는 후반부 429가 잦았다. 6s(=10콜/분=500크레딧/분)로 늦춰
// 단일 실행에 전 유니버스가 들어오게 한다 → 39종목 ≈ 4분. (cn/nse/jpx/eu-snapshot과 동일 사유·수치)
const STATS_GAP_MS      = 6_000
const RETRY_COOLDOWN_MS = 30_000

export interface DeStatEntry {
  capEUR: number
  shares: number
}

export interface DeSnapshot {
  fetchedAt: number
  asOfDate:  string                         // CET(UTC+1 근사) YYYY-MM-DD — prev 롤링 판정용
  current:   Record<string, DeStatEntry>    // symbol → {capEUR, shares}
  prev:      Record<string, number>         // symbol → 전 영업일 capEUR (등락% 계산용)
}

const store = createSnapshotStore<DeSnapshot>('de-stats')

let current:    DeSnapshot | null = null
let refreshing: Promise<{ updated: number; failed: number }> | null = null
let loadedAt = 0  // current를 store에서 마지막으로 읽은 시각(읽기 경로 TTL 재로드용)

// 유럽 대륙 시간대(CET, 서머타임 무시 근사) 기준 YYYY-MM-DD. prev 롤링용이라 근사로 충분.
function cetDateStr(): string {
  const k = new Date(Date.now() + 1 * 3_600_000)
  const y = k.getUTCFullYear()
  const m = String(k.getUTCMonth() + 1).padStart(2, '0')
  const d = String(k.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

// 단일 종목 /statistics → {capEUR, shares}. 심볼+mic_code(XETR)로 종목을 특정한다.
async function fetchStat(symbol: string): Promise<DeStatEntry> {
  const res = await fetch(
    `${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&mic_code=${DE_MIC}&apikey=${TWELVE_DATA_KEY}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`de-stats ${symbol} → HTTP ${res.status}`)
  const data = await res.json()
  if (data.status === 'error') throw new Error(`de-stats ${symbol} → ${data.message}`)
  const stats  = data?.statistics
  const capEUR = stats?.valuations_metrics?.market_capitalization as number | undefined
  const shares = stats?.stock_statistics?.shares_outstanding as number | undefined
  if (!capEUR) throw new Error(`de-stats ${symbol} → market_capitalization 없음`)
  return { capEUR, shares: shares && shares > 0 ? shares : 0 }
}

export async function refreshDeStats(): Promise<{ updated: number; failed: number }> {
  if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (refreshing) return refreshing

  refreshing = (async () => {
    if (!current) current = await store.load()
    const prevCurrent = current?.current ?? {}
    const next: Record<string, DeStatEntry> = { ...prevCurrent }

    // 실패 시 직전값 유지. attempt는 남은 심볼 목록을 받아 실패분을 돌려준다.
    const bySymbol = new Map(DE_COMPANIES.map(c => [c.symbol, c]))
    const attempt = async (symbols: string[]): Promise<string[]> => {
      const failed: string[] = []
      for (let i = 0; i < symbols.length; i++) {
        const c = bySymbol.get(symbols[i])!
        try {
          next[c.symbol] = await fetchStat(c.symbol)
        } catch (err) {
          failed.push(c.symbol)
          console.warn(`[de-stats] ${c.symbol} 실패, 직전값 유지:`, err instanceof Error ? err.message : err)
        }
        if (i < symbols.length - 1) await new Promise(r => setTimeout(r, STATS_GAP_MS))
      }
      return failed
    }

    let failed = await attempt(DE_COMPANIES.map(c => c.symbol))
    if (failed.length > 0) {
      console.warn(`[de-stats] ${failed.length}개 실패 → ${RETRY_COOLDOWN_MS / 1000}s 후 재시도`)
      await new Promise(r => setTimeout(r, RETRY_COOLDOWN_MS))
      failed = await attempt(failed)
    }

    const todayDate = cetDateStr()
    const prev: Record<string, number> =
      current && current.asOfDate !== todayDate
        ? Object.fromEntries(Object.entries(prevCurrent).map(([s, e]) => [s, e.capEUR]))
        : current?.prev ?? {}

    const updated = DE_COMPANIES.length - failed.length
    const snap: DeSnapshot = { fetchedAt: Date.now(), asOfDate: todayDate, current: next, prev }
    current = snap
    loadedAt = Date.now()  // 방금 갱신 → 읽기 경로 재조회 억제
    await store.save(snap)
    console.log(`[de-stats] refreshed → ${updated}/${DE_COMPANIES.length} ok, ${failed.length} failed, asOf=${todayDate}`)
    return { updated, failed: failed.length }
  })().finally(() => { refreshing = null })

  return refreshing
}

// ─── 유저 경로 read API ─────────────────────────────────────────────────────────

export interface DeStatsRead {
  cap:      Record<string, DeStatEntry>  // symbol → {capEUR, shares} (base = 전일 종가 시총)
  prev:     Record<string, number>       // symbol → 전 영업일 capEUR
  asOfDate: string | null                // 스냅샷 거래일 YYYY-MM-DD (기준일 표기용). 없으면 null.
}

// 읽기 경로 재로드 주기. 서버리스 웜 인스턴스가 옛 스냅샷을 계속 서빙하지 않도록 이 TTL마다 store
// 재조회(크론이 Upstash 갱신해도 인스턴스 재활용 전엔 옛 스냅샷을 내던 문제 방지). Upstash GET 1회.
const READ_REFRESH_MS = 5 * 60_000

async function ensureLoaded(): Promise<void> {
  if (current && Date.now() - loadedAt < READ_REFRESH_MS) return
  const loaded = await store.load()
  if (loaded) { current = loaded }
  loadedAt = Date.now()  // 결손(null)이어도 타임스탬프 갱신 → 매 요청 재조회 방지
}

export async function getDeStats(): Promise<DeStatsRead> {
  await ensureLoaded()
  return { cap: current?.current ?? {}, prev: current?.prev ?? {}, asOfDate: current?.asOfDate ?? null }
}

export function startDeStatsWarm(): void {
  if (process.env.VERCEL) return
  if (!TWELVE_DATA_KEY) return
  if (process.env.NEXT_PHASE === 'phase-production-build') return

  const g = globalThis as unknown as { __deStatsWarmed?: boolean }
  if (g.__deStatsWarmed) return
  g.__deStatsWarmed = true

  ensureLoaded()
    .then(() => {
      const stale = !current || Date.now() - current.fetchedAt > STATS_TTL_MS
      if (stale) return refreshDeStats().then(() => {})
    })
    .catch(err => console.warn('[de-stats] initial warm failed:', err))
}
