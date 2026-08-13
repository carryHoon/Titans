// ─── US 시총 기준값(stats) 스냅샷 레이어 ───────────────────────────────────────
//
// Twelve Data /statistics 의 market_capitalization(≈발행주수×전일종가)은 하루 한 번, 미국 장
// 마감 후에만 의미 있게 바뀐다(장중 변동은 market-cap 라우트가 /quote 20s로 라이브 스케일링).
// 그래서 stats는 "스케줄러가 마감 후 1회 받아 스냅샷으로 굳히고, 유저 경로는 스냅샷만 읽는다".
//   · refreshUsStats(): 외부 스케줄러(Vercel Cron → /api/internal/refresh-us)가 호출. 전 종목
//     /statistics 를 3개씩 4초 stagger 로 받아(크레딧 버스트 방지) 스냅샷 저장. 실패 종목은
//     직전 값을 유지해 빈자리가 생기지 않는다.
//   · getUsStats(): 유저 경로(fetchRows)가 호출. 업스트림 없이 스냅샷 map 만 반환.
//   · startUsStatsWarm(): 로컬/상시 프로세스 전용 부팅 워밍(서버리스는 크론이 대신).
//
// 저장소는 lib/snapshot-store 추상화를 공유한다(로컬=파일, Vercel=Upstash). key='us-stats'.

import { createSnapshotStore } from './snapshot-store'
import { ALL_TD_TICKERS } from './exchanges'
import {
  ADR_SHARE_RATIO,
  SAR_PER_USD,
  SAR_STATS_TICKERS,
} from './us-universe'

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'
const STATS_TTL_MS    = 24 * 3_600_000  // 로컬 워밍 판정용(스냅샷이 이보다 오래되면 재취득)

// /statistics 는 호출당 50 credits (Venture 610/min). 동시 quote 트래픽 여유(~110/min)를 남기고
// stats는 ~500 credits/min(= 10콜/min = 6초당 1콜)로 순차 페이싱한다 → 429 폭주 방지.
// 전체 ~58종목 × 6초 ≈ 6분. 유저 경로가 아니라 스케줄러(GitHub Actions)가 도므로 시간 제한 없음.
const STATS_GAP_MS      = 6_000
const RETRY_COOLDOWN_MS = 30_000  // 1차 실패(429 등) 종목은 이만큼 쉰 뒤 1회 재시도

// 스냅샷: ticker → 시총 기준값(trillion USD). ADR(TSM·HSBC)은 제외 — 가격기반 직접계산 대상.
export interface UsStatsSnapshot {
  fetchedAt: number
  stats:     Record<string, number>  // ticker → marketCapUSD (trillion)
}

const store = createSnapshotStore<UsStatsSnapshot>('us-stats')

// 인메모리 현재 스냅샷 + 콜드 로드/워밍 가드.
let current:       UsStatsSnapshot | null = null
let refreshing:    Promise<{ updated: number; failed: number }> | null = null

// 단일 종목 /statistics → 시총 기준값(trillion USD).
// SAR 종목(Tadawul): TD가 현지 통화(SAR)로 반환 → 고정환율로 USD 변환.
async function fetchStat(ticker: string): Promise<number> {
  const res = await fetch(
    `${TD_BASE}/statistics?symbol=${encodeURIComponent(ticker)}&apikey=${TWELVE_DATA_KEY}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`stats ${ticker} → HTTP ${res.status}`)
  const data = await res.json()
  if (data.status === 'error') throw new Error(`stats ${ticker} → ${data.message}`)
  const mc = data?.statistics?.valuations_metrics?.market_capitalization as number | undefined
  if (!mc) throw new Error(`stats ${ticker} → market_capitalization 없음`)
  const mcUsd = SAR_STATS_TICKERS.has(ticker) ? mc / SAR_PER_USD : mc
  return mcUsd / 1_000_000_000_000
}

// ─── 갱신(스케줄러 전용) ────────────────────────────────────────────────────────
// 전 US 티커(ADR 제외)를 6초당 1콜로 순차 fetch(≈500 credits/min). 실패(429 등) 종목은
// 30초 쿨다운 후 1회 재시도해 완주율을 높인다. 실패 종목은 직전 스냅샷 값을 그대로 유지한다.
export async function refreshUsStats(): Promise<{ updated: number; failed: number }> {
  if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')

  // 동시 트리거(스케줄러 중복 발사 등) 방지 — 진행 중이면 그 프라미스를 공유한다.
  if (refreshing) return refreshing

  refreshing = (async () => {
    if (!current) current = await store.load()
    const prev = current?.stats ?? {}
    const next: Record<string, number> = { ...prev }  // 실패 종목은 직전 값 유지

    const tickers = ALL_TD_TICKERS.filter(t => !ADR_SHARE_RATIO[t])

    // 리스트를 6초당 1콜로 순차 처리하고, 실패한 티커 목록을 돌려준다.
    const attempt = async (list: string[]): Promise<string[]> => {
      const failedTickers: string[] = []
      for (let i = 0; i < list.length; i++) {
        const t = list[i]
        try {
          next[t] = await fetchStat(t)
        } catch (err) {
          failedTickers.push(t)
          console.warn(`[us-stats] ${t} 실패, 직전값 유지:`, err instanceof Error ? err.message : err)
        }
        if (i < list.length - 1) await new Promise(r => setTimeout(r, STATS_GAP_MS))
      }
      return failedTickers
    }

    let failedTickers = await attempt(tickers)
    if (failedTickers.length > 0) {
      console.warn(`[us-stats] ${failedTickers.length}개 실패 → ${RETRY_COOLDOWN_MS / 1000}s 후 재시도`)
      await new Promise(r => setTimeout(r, RETRY_COOLDOWN_MS))
      failedTickers = await attempt(failedTickers)
    }

    const updated = tickers.length - failedTickers.length
    const snap: UsStatsSnapshot = { fetchedAt: Date.now(), stats: next }
    current = snap
    await store.save(snap)
    console.log(`[us-stats] refreshed → ${updated}/${tickers.length} ok, ${failedTickers.length} failed, ${Object.keys(next).length} total`)
    return { updated, failed: failedTickers.length }
  })().finally(() => { refreshing = null })

  return refreshing
}

// ─── 유저 경로 read API ─────────────────────────────────────────────────────────
// 업스트림 호출 없이 스냅샷만 반환. 스냅샷 부재(첫 배포~첫 크론 사이)면 빈 map → 라우트가
// stale/백필로 방어한다. 스냅샷은 크론(refreshUsStats)이 채운다.

async function ensureLoaded(): Promise<void> {
  if (current) return
  current = await store.load()
}

export async function getUsStats(): Promise<Record<string, number>> {
  await ensureLoaded()
  return current?.stats ?? {}
}

// ─── 로컬/상시 프로세스 부팅 워밍 ───────────────────────────────────────────────
// 서버리스(Vercel)에선 크론이 /api/internal/refresh-us 를 때리므로 워밍 불필요·무의미.
// 로컬 개발(next dev/start)·VPS에서만: 부팅 시 스냅샷이 없거나 24h 초과면 1회 새로 받는다.
export function startUsStatsWarm(): void {
  if (process.env.VERCEL) return
  if (!TWELVE_DATA_KEY) return
  if (process.env.NEXT_PHASE === 'phase-production-build') return  // 빌드 중 기동 방지

  const g = globalThis as unknown as { __usStatsWarmed?: boolean }
  if (g.__usStatsWarmed) return
  g.__usStatsWarmed = true

  ensureLoaded()
    .then(() => {
      const stale = !current || Date.now() - current.fetchedAt > STATS_TTL_MS
      if (stale) return refreshUsStats().then(() => {})
    })
    .catch(err => console.warn('[us-stats] initial warm failed:', err))
}
