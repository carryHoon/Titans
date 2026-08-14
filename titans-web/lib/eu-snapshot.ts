// ─── Euronext 시총 기준값(stats) 스냅샷 레이어 ─────────────────────────────────
//
// Euronext(파리/암스테르담/밀라노)의 시총 기준값(/statistics: market_cap EUR + shares)을 하루 1회
// 스냅샷으로 굳힌다. 라우트(유저 경로)는 이 스냅샷을 base로 쓰고, quote가 있는 종목(XPAR/XAMS)은
// 요청 시 라이브 스케일링(cap = statsCap × close/prevClose)한다. quote 없는 밀라노(XMIL)는 stats
// 시총을 그대로 쓰고 등락%는 전일 스냅샷 대비로 계산한다. USD 환산은 라우트에서 fx(EUR/USD)로.
//
// us-stats(USD 고정)와 달리 네이티브 EUR로 저장한다(환율이 스냅샷 시각에 얼지 않도록 — KRX/JPX 규약).
// 구조는 jpx-snapshot과 동일(현재 cap+shares + 전일 cap 롤링). 차이는 mic_code disambiguation뿐.
// 저장소는 lib/snapshot-store 공유. key='eu-stats'.

import { createSnapshotStore } from './snapshot-store'
import { EU_COMPANIES } from './eu-universe'

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'
const STATS_TTL_MS    = 24 * 3_600_000

// TD /statistics 는 호출당 ~50 credits(api_usage 실측). Venture 610/분 ÷ 50 ≈ 12콜/분 상한이라
// 옛 2.5s(=24콜/분=1200크레딧/분)로는 후반부 429가 잦았다. 6s(=10콜/분=500크레딧/분)로 늦춰
// 단일 실행에 전 유니버스가 들어오게 한다 → 65종목 ≈ 6.5분. (cn/jpx-snapshot과 동일 사유·수치)
const STATS_GAP_MS      = 6_000
const RETRY_COOLDOWN_MS = 30_000

export interface EuStatEntry {
  capEUR: number
  shares: number
}

export interface EuSnapshot {
  fetchedAt: number
  asOfDate:  string                         // CET(UTC+1 근사) YYYY-MM-DD — prev 롤링 판정용
  current:   Record<string, EuStatEntry>    // symbol → {capEUR, shares}
  prev:      Record<string, number>         // symbol → 전 영업일 capEUR (밀라노 등락% 계산용)
}

const store = createSnapshotStore<EuSnapshot>('eu-stats')

let current:    EuSnapshot | null = null
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

// 단일 종목 /statistics → {capEUR, shares}. 심볼+mic_code로 정확히 특정(파리/암스/밀라노 구분).
async function fetchStat(symbol: string, mic: string): Promise<EuStatEntry> {
  const res = await fetch(
    `${TD_BASE}/statistics?symbol=${encodeURIComponent(symbol)}&mic_code=${mic}&apikey=${TWELVE_DATA_KEY}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`eu-stats ${symbol}/${mic} → HTTP ${res.status}`)
  const data = await res.json()
  if (data.status === 'error') throw new Error(`eu-stats ${symbol}/${mic} → ${data.message}`)
  const stats  = data?.statistics
  const capEUR = stats?.valuations_metrics?.market_capitalization as number | undefined
  const shares = stats?.stock_statistics?.shares_outstanding as number | undefined
  if (!capEUR) throw new Error(`eu-stats ${symbol}/${mic} → market_capitalization 없음`)
  return { capEUR, shares: shares && shares > 0 ? shares : 0 }
}

export async function refreshEuStats(): Promise<{ updated: number; failed: number }> {
  if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (refreshing) return refreshing

  refreshing = (async () => {
    if (!current) current = await store.load()
    const prevCurrent = current?.current ?? {}
    const next: Record<string, EuStatEntry> = { ...prevCurrent }

    // 실패 시 직전값 유지. attempt는 남은 심볼 목록을 받아 실패분을 돌려준다.
    const bySymbol = new Map(EU_COMPANIES.map(c => [c.symbol, c]))
    const attempt = async (symbols: string[]): Promise<string[]> => {
      const failed: string[] = []
      for (let i = 0; i < symbols.length; i++) {
        const c = bySymbol.get(symbols[i])!
        try {
          next[c.symbol] = await fetchStat(c.symbol, c.mic)
        } catch (err) {
          failed.push(c.symbol)
          console.warn(`[eu-stats] ${c.symbol} 실패, 직전값 유지:`, err instanceof Error ? err.message : err)
        }
        if (i < symbols.length - 1) await new Promise(r => setTimeout(r, STATS_GAP_MS))
      }
      return failed
    }

    let failed = await attempt(EU_COMPANIES.map(c => c.symbol))
    if (failed.length > 0) {
      console.warn(`[eu-stats] ${failed.length}개 실패 → ${RETRY_COOLDOWN_MS / 1000}s 후 재시도`)
      await new Promise(r => setTimeout(r, RETRY_COOLDOWN_MS))
      failed = await attempt(failed)
    }

    const todayDate = cetDateStr()
    const prev: Record<string, number> =
      current && current.asOfDate !== todayDate
        ? Object.fromEntries(Object.entries(prevCurrent).map(([s, e]) => [s, e.capEUR]))
        : current?.prev ?? {}

    const updated = EU_COMPANIES.length - failed.length
    const snap: EuSnapshot = { fetchedAt: Date.now(), asOfDate: todayDate, current: next, prev }
    current = snap
    loadedAt = Date.now()  // 방금 갱신 → 읽기 경로 재조회 억제
    await store.save(snap)
    console.log(`[eu-stats] refreshed → ${updated}/${EU_COMPANIES.length} ok, ${failed.length} failed, asOf=${todayDate}`)
    return { updated, failed: failed.length }
  })().finally(() => { refreshing = null })

  return refreshing
}

// ─── 유저 경로 read API ─────────────────────────────────────────────────────────

export interface EuStatsRead {
  cap:      Record<string, EuStatEntry>  // symbol → {capEUR, shares} (base = 전일 종가 시총)
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

export async function getEuStats(): Promise<EuStatsRead> {
  await ensureLoaded()
  return { cap: current?.current ?? {}, prev: current?.prev ?? {}, asOfDate: current?.asOfDate ?? null }
}

export function startEuStatsWarm(): void {
  if (process.env.VERCEL) return
  if (!TWELVE_DATA_KEY) return
  if (process.env.NEXT_PHASE === 'phase-production-build') return

  const g = globalThis as unknown as { __euStatsWarmed?: boolean }
  if (g.__euStatsWarmed) return
  g.__euStatsWarmed = true

  ensureLoaded()
    .then(() => {
      const stale = !current || Date.now() - current.fetchedAt > STATS_TTL_MS
      if (stale) return refreshEuStats().then(() => {})
    })
    .catch(err => console.warn('[eu-stats] initial warm failed:', err))
}
