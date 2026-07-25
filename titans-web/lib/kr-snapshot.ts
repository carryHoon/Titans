// ─── 한국(KRX) 데이터 스냅샷 레이어 ─────────────────────────────────────────────
//
// 코스피/코스닥 "종목 시총(market-cap)"과 "지수(market-index)"의 유일한 data.go.kr 진입점.
// 두 라우트가 각자 30분 캐시로 실시간 fetch 하던 구조를 대체한다.
//
// 채택 방식: "발행 창(window) 동안만 촘촘히 폴링 → 새 영업일(basDt) 감지되면 스냅샷으로 굳히고,
//            유저 요청은 스냅샷만 읽는다".
//   · 폴러(startKrPoller)가 백그라운드에서 data.go.kr을 주기적으로 프로브해 새 영업일이
//     올라오면 KOSPI+KOSDAQ 전종목 + 전 지수를 한 번에 받아 스냅샷으로 영속화한다.
//   · getKrxDataset()/getKrIndexDataset()(유저 경로)은 업스트림을 부르지 않고 스냅샷만 반환한다.
//   · 스냅샷 부재(콜드 스타트)일 때만 동기 부트스트랩 fetch를 한 번 수행한다.
//
// ▷ 저장소 추상화(SnapshotStore): 지금은 FileStore(JSON 파일)로 구현한다. 상용 서버리스
//   전환 시 KvStore(Upstash/Vercel KV) 하나만 구현해 교체하면 폴러·라우트 코드는 손대지 않는다.
// ▷ 트리거 추상화: 로컬/상시 프로세스는 in-process 창 폴러(startKrPoller)로 refreshIfNew()를
//   호출한다. 서버리스 전환 시 이 호출을 Vercel Cron 라우트가 대신 하도록 바꾸면 된다.

import { promises as fs } from 'fs'
import path from 'path'

// ─── data.go.kr 공통 ───────────────────────────────────────────────────────────

const DATA_GO_KR_KEY = process.env.DATA_GO_KR_KEY

const DATA_GO_KRX_URL =
  'https://apis.data.go.kr/1160100/service/GetStockSecuritiesInfoService/getStockPriceInfo'
const DATA_GO_INDEX_URL =
  'https://apis.data.go.kr/1160100/service/GetMarketIndexInfoService/getStockMarketIndex'

// KST 기준 YYYYMMDD 문자열 (UTC+9로 보정 후 UTC 필드 읽기).
function kstDateStr(msFromNow: number): string {
  const kst = new Date(Date.now() + msFromNow + 9 * 60 * 60 * 1000)
  const y = kst.getUTCFullYear()
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0')
  const d = String(kst.getUTCDate()).padStart(2, '0')
  return `${y}${m}${d}`
}

// ─── KRX 종목 (금융위 주식시세정보) ─────────────────────────────────────────────

interface DataGoStockItem {
  basDt:      string
  srtnCd:     string
  itmsNm:     string
  mrktCtg:    string
  clpr:       string
  vs:         string
  fltRt:      string
  mrktTotAmt: string
}

interface DataGoStockResponse {
  response?: {
    header?: { resultCode?: string; resultMsg?: string }
    body?: { totalCount?: number; items?: { item?: DataGoStockItem[] } | '' }
  }
}

export interface KrxRow {
  code:          string
  name:          string
  market:        'KOSPI' | 'KOSDAQ'
  price:         number
  change:        number
  changePercent: number
  marketCapKRW:  number
}

export interface KrxDataset {
  basDt:  string
  kospi:  KrxRow[]
  kosdaq: KrxRow[]
  byCode: Map<string, KrxRow>
}

// 스팩(SPAC)만 제외 — 인수목적회사라 시총 순위 의미가 없다. 우선주는 KRX 공식 순위에 포함되므로 노출.
function isRankable(name: string): boolean {
  if (/스팩/.test(name)) return false
  return true
}

// 특정 시장(mrktCls)·기준일(basDt)의 전 종목을 1콜로 받아 정규화.
async function fetchKrxMarket(mrktCls: 'KOSPI' | 'KOSDAQ', basDt: string): Promise<KrxRow[]> {
  const params = new URLSearchParams({
    serviceKey: DATA_GO_KR_KEY!,
    resultType: 'json',
    numOfRows:  '2500',
    pageNo:     '1',
    mrktCls,
    basDt,
  })
  const res = await fetch(`${DATA_GO_KRX_URL}?${params.toString()}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`data.go.kr ${mrktCls} ${basDt} → HTTP ${res.status}`)

  const json: DataGoStockResponse = await res.json()
  const code = json.response?.header?.resultCode
  if (code && code !== '00') {
    throw new Error(`data.go.kr ${mrktCls} → ${code} ${json.response?.header?.resultMsg ?? ''}`)
  }

  const items = json.response?.body?.items
  const list = items && typeof items !== 'string' ? items.item ?? [] : []

  const rows: KrxRow[] = []
  for (const it of list) {
    if (!isRankable(it.itmsNm)) continue
    const price        = Number(it.clpr)
    const marketCapKRW = Number(it.mrktTotAmt)
    if (!price || !marketCapKRW) continue
    rows.push({
      code:          it.srtnCd,
      name:          it.itmsNm,
      market:        mrktCls,
      price,
      change:        Number(it.vs)    || 0,
      changePercent: Number(it.fltRt) || 0,
      marketCapKRW,
    })
  }
  return rows
}

// 최근 거래일(basDt) 탐색 — 오늘부터 최대 8일 뒤로 가며 데이터가 있는 첫 날을 찾는다.
// numOfRows=1 프로브로 저렴하게 확인(폴러가 새 영업일을 감지하는 데도 이걸 쓴다).
async function resolveLatestStockBasDt(): Promise<string> {
  for (let i = 0; i < 8; i++) {
    const basDt = kstDateStr(-i * 24 * 60 * 60 * 1000)
    const params = new URLSearchParams({
      serviceKey: DATA_GO_KR_KEY!,
      resultType: 'json',
      numOfRows:  '1',
      pageNo:     '1',
      mrktCls:    'KOSPI',
      basDt,
    })
    const res = await fetch(`${DATA_GO_KRX_URL}?${params.toString()}`, { cache: 'no-store' })
    if (!res.ok) continue
    const json: DataGoStockResponse = await res.json()
    if ((json.response?.body?.totalCount ?? 0) > 0) return basDt
  }
  throw new Error('data.go.kr → 최근 8일 내 거래 데이터 없음')
}

// ─── KRX 지수 (금융위 지수시세정보) ─────────────────────────────────────────────

interface DataGoIndexItem {
  basDt:  string
  idxNm:  string
  idxCsf: string
  clpr:   string
  vs:     string
  fltRt:  string
}

interface DataGoIndexResponse {
  response?: {
    header?: { resultCode?: string; resultMsg?: string }
    body?: { totalCount?: number; items?: { item?: DataGoIndexItem[] } | '' }
  }
}

export interface KrIndexRow { clpr: number; vs: number; fltRt: number }

export interface KrIndexDataset {
  basDt: string
  byKey: Map<string, KrIndexRow>  // "idxCsf|idxNm" → 값
}

export function idxKey(csf: string, nm: string): string {
  return `${csf}|${nm}`
}

// 스냅샷 영속화를 위해 지수 원본(분류·이름 포함)을 배열로 보관한다.
interface PersistedIndexRow { idxCsf: string; idxNm: string; clpr: number; vs: number; fltRt: number }

// 특정 기준일(basDt)의 전 지수를 1콜로 받아 배열로 정규화(휴장일이면 빈 배열).
async function fetchKrIndexDay(basDt: string): Promise<PersistedIndexRow[]> {
  const params = new URLSearchParams({
    serviceKey: DATA_GO_KR_KEY!,
    resultType: 'json',
    numOfRows:  '1000',
    pageNo:     '1',
    basDt,
  })
  const res = await fetch(`${DATA_GO_INDEX_URL}?${params.toString()}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`data.go.kr index ${basDt} → HTTP ${res.status}`)

  const json: DataGoIndexResponse = await res.json()
  const code = json.response?.header?.resultCode
  if (code && code !== '00') {
    throw new Error(`data.go.kr index → ${code} ${json.response?.header?.resultMsg ?? ''}`)
  }

  const items = json.response?.body?.items
  const list = items && typeof items !== 'string' ? items.item ?? [] : []

  const rows: PersistedIndexRow[] = []
  for (const it of list) {
    const clpr = Number(it.clpr)
    if (!clpr) continue
    rows.push({
      idxCsf: it.idxCsf,
      idxNm:  it.idxNm,
      clpr,
      vs:     Number(it.vs)    || 0,
      fltRt:  Number(it.fltRt) || 0,
    })
  }
  return rows
}

// 지수 데이터셋을 preferredBasDt부터 최대 8일 뒤로 가며 데이터 있는 첫 날로 확보.
// (지수 서비스가 종목 서비스와 반영 시점이 다를 수 있어 독립적으로 영업일을 찾는다.)
async function fetchLatestIndex(preferredBasDt: string): Promise<{ basDt: string; rows: PersistedIndexRow[] }> {
  const preferMs = Date.parse(
    `${preferredBasDt.slice(0, 4)}-${preferredBasDt.slice(4, 6)}-${preferredBasDt.slice(6, 8)}T00:00:00Z`,
  )
  for (let i = 0; i < 8; i++) {
    const basDt = kstDateStr(preferMs - Date.now() - i * 24 * 60 * 60 * 1000)
    const rows = await fetchKrIndexDay(basDt)
    if (rows.length > 0) return { basDt, rows }
  }
  throw new Error('data.go.kr index → 최근 8일 내 지수 데이터 없음')
}

// ─── 스냅샷 저장소(SnapshotStore) — 지금은 FileStore ───────────────────────────

interface PersistedSnapshot {
  fetchedAt: number
  stock: { basDt: string; kospi: KrxRow[]; kosdaq: KrxRow[] }
  index: { basDt: string; rows: PersistedIndexRow[] }
}

interface SnapshotStore {
  load(): Promise<PersistedSnapshot | null>
  save(snap: PersistedSnapshot): Promise<void>
}

// 로컬/상시 프로세스용 파일 저장소. Mac(next dev/start)·VPS에서 스냅샷을 .data/에 보관한다.
class FileStore implements SnapshotStore {
  private readonly file = path.join(process.cwd(), '.data', 'kr-snapshot.json')

  async load(): Promise<PersistedSnapshot | null> {
    try {
      const raw = await fs.readFile(this.file, 'utf8')
      return JSON.parse(raw) as PersistedSnapshot
    } catch {
      return null
    }
  }

  async save(snap: PersistedSnapshot): Promise<void> {
    await fs.mkdir(path.dirname(this.file), { recursive: true })
    await fs.writeFile(this.file, JSON.stringify(snap), 'utf8')
  }
}

// 서버리스(Vercel)용 클라우드 저장소 — Upstash Redis REST API.
// 서버리스 함수는 메모리·파일이 호출마다 사라지므로, 여러 인스턴스가 공유하는 "유일한 냉장고".
// 의존성 추가 없이 REST(fetch)로만 접근한다(@upstash/redis SDK 불필요).
class KvStore implements SnapshotStore {
  private readonly url   = process.env.UPSTASH_REDIS_REST_URL!
  private readonly token = process.env.UPSTASH_REDIS_REST_TOKEN!
  private readonly key   = 'kr-snapshot'

  async load(): Promise<PersistedSnapshot | null> {
    const res = await fetch(`${this.url}/get/${this.key}`, {
      headers: { Authorization: `Bearer ${this.token}` },
      cache: 'no-store',
    })
    if (!res.ok) return null
    const json = await res.json() as { result?: string | null }
    if (!json.result) return null
    try { return JSON.parse(json.result) as PersistedSnapshot } catch { return null }
  }

  async save(snap: PersistedSnapshot): Promise<void> {
    // Upstash REST SET: 값은 요청 본문으로 전달(큰 JSON도 안전).
    const res = await fetch(`${this.url}/set/${this.key}`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${this.token}` },
      body:    JSON.stringify(snap),
      cache:   'no-store',
    })
    if (!res.ok) throw new Error(`Upstash set → HTTP ${res.status}`)
  }
}

// 저장소 선택: Upstash 환경변수가 있으면 클라우드(KvStore), 없으면 로컬 파일(FileStore).
// → 코드 변경 없이 배포처만 바뀐다(로컬은 파일, Vercel은 KV).
const store: SnapshotStore =
  process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN
    ? new KvStore()
    : new FileStore()

// 스냅샷에 보관할 시장별 상위 종목 수. 앱은 상위 100개만 쓰고 byCode 조회 대상(삼성·SK하이닉스)도
// 상위권이라, 여유 있게 상위 300개만 저장한다(전 종목 ~2,700개 → 스냅샷 크기·KV 전송량 대폭 절감).
const SNAPSHOT_TOP_N = 300

// ─── 인메모리 현재 스냅샷 + 부트스트랩 ──────────────────────────────────────────

let current: PersistedSnapshot | null = null
let bootstrapping: Promise<void> | null = null

// 새 영업일(basDt)이 올라왔을 때만 전종목+전지수를 받아 스냅샷으로 굳힌다.
// 이미 최신이면 아무것도 안 한다(프로브 1콜만 소모). 폴러/콜드 부트스트랩 공용.
export async function refreshIfNew(): Promise<boolean> {
  if (!DATA_GO_KR_KEY) throw new Error('DATA_GO_KR_KEY 미설정 — 공공데이터포털 인증키 필요')

  // 서버리스(Vercel)는 함수 호출마다 메모리가 비어 current가 null이다. 저장소(KV)의 현재 스냅샷을
  // 먼저 읽어와 비교해야 "이미 최신이면 스킵"이 성립한다(안 그러면 크론마다 불필요하게 전체 재fetch).
  if (!current) current = await store.load()

  const latest = await resolveLatestStockBasDt()
  if (current && current.stock.basDt >= latest) return false  // 이미 최신 — 스킵

  const [kospi, kosdaq, index] = await Promise.all([
    fetchKrxMarket('KOSPI', latest),
    fetchKrxMarket('KOSDAQ', latest),
    fetchLatestIndex(latest),
  ])
  kospi.sort((a, b) => b.marketCapKRW - a.marketCapKRW)
  kosdaq.sort((a, b) => b.marketCapKRW - a.marketCapKRW)

  const snap: PersistedSnapshot = {
    fetchedAt: Date.now(),
    // 앱은 상위 100개만 쓰므로 상위 N개만 저장(KV 전송량·크기 절감). byCode 조회 대상도 상위권.
    stock: { basDt: latest, kospi: kospi.slice(0, SNAPSHOT_TOP_N), kosdaq: kosdaq.slice(0, SNAPSHOT_TOP_N) },
    index,
  }
  current = snap
  await store.save(snap)
  console.log(`[kr-snapshot] refreshed → stock basDt=${latest}, index basDt=${index.basDt}`)
  return true
}

// 스냅샷을 보장한다. 인메모리 → 파일 → (그래도 없으면) 동기 부트스트랩 fetch 순.
// 여러 요청이 동시에 콜드 부트스트랩을 트리거해도 fetch는 1회만 수행한다.
async function ensureSnapshot(): Promise<PersistedSnapshot> {
  if (current) return current

  const loaded = await store.load()
  if (loaded) { current = loaded; return loaded }

  if (!bootstrapping) {
    bootstrapping = refreshIfNew().then(() => {}).finally(() => { bootstrapping = null })
  }
  await bootstrapping
  if (!current) throw new Error('kr-snapshot → 부트스트랩 실패(스냅샷 없음)')
  return current
}

// ─── 유저 경로 read API (라우트가 그대로 호출) ─────────────────────────────────

// KOSPI+KOSDAQ 전종목 데이터셋. 업스트림 호출 없이 스냅샷에서 조회용 Map을 재구성해 반환.
export async function getKrxDataset(): Promise<KrxDataset> {
  const snap = await ensureSnapshot()
  const byCode = new Map<string, KrxRow>()
  for (const r of [...snap.stock.kospi, ...snap.stock.kosdaq]) byCode.set(r.code, r)
  return { basDt: snap.stock.basDt, kospi: snap.stock.kospi, kosdaq: snap.stock.kosdaq, byCode }
}

// 전 지수 데이터셋. 스냅샷의 지수 배열을 "idxCsf|idxNm" → 값 Map으로 재구성해 반환.
export async function getKrIndexDataset(): Promise<KrIndexDataset> {
  const snap = await ensureSnapshot()
  const byKey = new Map<string, KrIndexRow>()
  for (const r of snap.index.rows) {
    byKey.set(idxKey(r.idxCsf, r.idxNm), { clpr: r.clpr, vs: r.vs, fltRt: r.fltRt })
  }
  return { basDt: snap.index.basDt, byKey }
}

// ─── 발행 창(window) 폴러 ───────────────────────────────────────────────────────
// 목표는 실시간이 아니라 "당일 공공데이터포털이 발행한 데이터는 당일 안에 취득"이다.
// 그래서 여유롭게 — KST 장 마감(15:30) 이후 발행 창 동안 30분, 그 외 시간엔 안전망으로 3시간
// 간격으로 프로브한다. 새 영업일이 감지되면 refreshIfNew가 스냅샷을 굳힌다(프로브는 1콜뿐이라
// 이 정도 간격이면 하루 수십 콜 수준 → data.go.kr 한도에 넉넉).
// 상시 프로세스(next dev/start·VPS)에서만 의미가 있으며, 서버리스에선 Vercel Cron이 대신한다.

const DENSE_MS  = 30 * 60 * 1000       // 발행 창(마감 후): 30분
const SPARSE_MS = 3 * 60 * 60 * 1000   // 그 외: 3시간(안전망)

// KST 기준 시(hour). 발행 창(16:00~23:59) 판정에 사용.
function kstHour(): number {
  return new Date(Date.now() + 9 * 60 * 60 * 1000).getUTCHours()
}

function nextPollDelay(): number {
  const h = kstHour()
  return h >= 16 ? DENSE_MS : SPARSE_MS   // 16시 이후 = 마감 후 발행 창
}

// globalThis 싱글턴 가드 — HMR/다중 import 시 폴러가 중복 기동되지 않도록.
const g = globalThis as unknown as { __krPollerStarted?: boolean }

export function startKrPoller(): void {
  if (g.__krPollerStarted) return
  if (!DATA_GO_KR_KEY) return
  if (process.env.KR_POLLER === 'off') return
  if (process.env.NEXT_PHASE === 'phase-production-build') return  // 빌드 중 기동 방지
  // 서버리스(Vercel)에선 in-process 타이머가 함수 종료와 함께 사라져 무의미하다.
  // 그쪽은 GitHub Actions 크론이 /api/internal/refresh-kr을 때려 refreshIfNew를 구동한다.
  if (process.env.VERCEL) return
  g.__krPollerStarted = true

  // 기동 즉시 1회 워밍(파일 스냅샷이 없거나 오래됐으면 새로 받음).
  ensureSnapshot()
    .then(() => refreshIfNew())
    .catch(err => console.warn('[kr-snapshot] initial warm failed:', err))

  const tick = () => {
    refreshIfNew()
      .catch(err => console.warn('[kr-snapshot] poll refresh failed:', err))
      .finally(() => setTimeout(tick, nextPollDelay()))
  }
  setTimeout(tick, nextPollDelay())
  console.log('[kr-snapshot] window poller started')
}
