import { NextResponse } from 'next/server'
import { getUsdKrwQuote } from '@/lib/fx'
import { getKrIndexDataset, idxKey, startKrPoller } from '@/lib/kr-snapshot'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 한국 지수 데이터도 스냅샷 레이어(@/lib/kr-snapshot)가 소유한다. 폴러를 기동해두면
// (market-cap와 공유·싱글턴) 새 영업일마다 종목+지수 스냅샷이 함께 갱신된다.
startKrPoller()

// 지수 카드 데이터 소스(선언적):
//   · 달러 환율        = 통합 FX 레이어(@/lib/fx) — Twelve Data(상업), 한국 장중 라이브·장외 종가 고정
//   · 코스피/코스닥 …  = 공공데이터포털 금융위원회_지수시세정보(EOD/D-1)
//
// ※ NASDAQ 지수: TD Venture 플랜 미지원, 상업 라이선스 소스 미확보로 제거.
//   향후 TD 지수 지원 확인(Bogdan) 시 IndexData 추가 가능.
// 새 한국 지수는 KR_INDICES 배열에 한 줄 추가하면 카드가 자동으로 늘어난다.
const CACHE_TTL_MS = 15_000

// 공공데이터포털 지수시세정보에서 가져올 한국 지수 카드.
// idxNm(지수명)+idxCsf(지수분류)로 해당 API의 지수를 특정한다(이름 충돌 방지).
// 카드 노출 순서 = 이 배열 순서. 지수 추가는 여기 한 줄이면 끝.
const KR_INDICES: { id: string; name: string; idxNm: string; idxCsf: string }[] = [
  { id: 'kospi',   name: '코스피',     idxNm: '코스피',     idxCsf: 'KOSPI시리즈'  },
  { id: 'kosdaq',  name: '코스닥',     idxNm: '코스닥',     idxCsf: 'KOSDAQ시리즈' },
  { id: 'krx300',  name: 'KRX 300',   idxNm: 'KRX 300',   idxCsf: 'KRX시리즈'    },
  { id: 'krxSemi', name: 'KRX 반도체', idxNm: 'KRX 반도체', idxCsf: 'KRX시리즈'    },
]

// ─── Types ────────────────────────────────────────────────────────────────────

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

// ─── 달러 환율 (통합 FX 레이어) ─────────────────────────────────────────────────
// 소스 선택·캐시·폴백은 전부 @/lib/fx 가 담당한다(Twelve Data → last-good → 상수).
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

// ─── 한국 지수 — 스냅샷 레이어에서 조회 ────────────────────────────────────────
// 지수 데이터셋(getKrIndexDataset)과 data.go.kr 접근 로직은 @/lib/kr-snapshot 이 소유한다.
// 발행 창 폴러가 새 영업일마다 종목+지수를 함께 스냅샷으로 굳히고, 여기선 업스트림 호출 없이
// 그 스냅샷을 읽어 카드(IndexData[])로 매핑만 한다. 종목 시총 섹션과 기준일(basDt)이 일치한다.

// KR_INDICES 설정을 지수 카드(IndexData[])로 변환. 데이터셋에 없는 지수는 조용히 건너뛴다.
async function fetchKrIndexCards(): Promise<IndexData[]> {
  const ds = await getKrIndexDataset()
  // basDt("YYYYMMDD") → 한국 장 마감(15:30 KST ≈ 06:30 UTC) 근사 타임스탬프.
  const y = Number(ds.basDt.slice(0, 4))
  const m = Number(ds.basDt.slice(4, 6)) - 1
  const d = Number(ds.basDt.slice(6, 8))
  const updatedAt = Date.UTC(y, m, d, 6, 30)

  const cards: IndexData[] = []
  for (const cfg of KR_INDICES) {
    const row = ds.byKey.get(idxKey(cfg.idxCsf, cfg.idxNm))
    if (!row) continue
    cards.push({
      id: cfg.id,
      name: cfg.name,
      value: row.clpr,
      change: row.vs,
      changePercent: row.fltRt,
      updatedAt,
    })
  }
  if (cards.length === 0) throw new Error('data.go.kr index → 설정된 한국 지수를 응답에서 찾지 못함')
  return cards
}

// ─── Route Handler ────────────────────────────────────────────────────────────

// 카드 소스 2종(달러 / 한국 지수). 소스별로 독립 로드해 한 소스가 실패해도
// 나머지 카드는 유지되도록 한다(부분 실패 내성). 노출 순서 = 이 배열 순서로 평탄화.
const SOURCES: { ids: string[]; task: () => Promise<IndexData[]> }[] = [
  { ids: ['usd'],                       task: async () => [await fetchUsdIndex()] },
  { ids: KR_INDICES.map(i => i.id),     task: fetchKrIndexCards },
]

export async function GET() {
  // 캐시 히트
  if (cache && Date.now() - cache.ts < CACHE_TTL_MS) {
    return NextResponse.json({ data: cache.data, stale: false })
  }

  const settled = await Promise.allSettled(SOURCES.map(s => s.task()))
  const lastById = new Map((lastGoodCache?.data ?? []).map(d => [d.id, d]))

  let anyFail = false
  const data: IndexData[] = []
  settled.forEach((res, i) => {
    if (res.status === 'fulfilled') {
      data.push(...res.value)
    } else {
      // 소스 실패 → 마지막 성공 카드로 폴백(있으면)
      anyFail = true
      console.error(`[market-index] source [${SOURCES[i].ids.join(',')}] failed:`, res.reason)
      for (const id of SOURCES[i].ids) {
        const prev = lastById.get(id)
        if (prev) data.push(prev)
      }
    }
  })

  if (data.length === 0) {
    if (lastGoodCache) return NextResponse.json({ data: lastGoodCache.data, stale: true }, { status: 200 })
    return NextResponse.json({ error: 'market-index: 모든 소스 실패' }, { status: 503 })
  }

  cache = { data, ts: Date.now() }
  lastGoodCache = cache
  return NextResponse.json({ data, stale: anyFail })
}
