// ─── DART(전자공시) 기반 종목코드 → 홈페이지 도메인 해석 ──────────────────────────
//
// 목적: 공공데이터포털 동적 유니버스(getKrxDataset)에 새로 진입한 KOSPI/KOSDAQ 종목이
//   앱에서 로고를 얻을 수 있도록, 6자리 종목코드에서 기업 공식 홈페이지 도메인을 자동 추출한다.
//   앱(SwiftUI BrandLogoTile)은 이 도메인으로 Clearbit/Brandfetch/파비콘 로고를 "핫링크"
//   폴백으로 로드한다. 즉 로고를 우리 서버에 다운로드·재호스팅하지 않는다
//   → 트레이드마크·제3자 ToS(재배포 제한) 리스크를 최소화한다.
//
// 파이프라인: 종목코드 → (corpCode 매핑) → corp_code → company.json.hm_url → 순수 도메인.
//   · corpCode 매핑표(corpCode.xml, zip)는 전체 공시대상 회사 목록이라 크므로, 미지의 코드가
//     실제로 있을 때 한 번만 내려받아 메모리에 (stockCode→corp_code)로 캐싱한다.
//     이미 아는(캐시된) 코드만 들어오면 corpCode.xml은 아예 받지 않는다.
//   · 해석 결과(code→domain, 실패 시 null)는 KV/파일에 장기 캐싱한다(도메인은 거의 안 변함).
//     null도 캐싱하되 짧은 재시도 주기를 둬, 일시 실패가 영구 공백이 되지 않게 한다.
//
// 모두 best-effort: DART_API_KEY 미설정이나 네트워크/한도 실패 시 조용히 도메인 없이 넘어가며,
// 가격·시총 스냅샷 파이프라인을 절대 막지 않는다(앱은 텍스트 이니셜로 자연 폴백).

import zlib from 'zlib'
import { promises as fs } from 'fs'
import path from 'path'

const DART_KEY     = process.env.DART_API_KEY
const CORPCODE_URL = 'https://opendart.fss.or.kr/api/corpCode.xml'
const COMPANY_URL  = 'https://opendart.fss.or.kr/api/company.json'

// 성공(도메인 확보)은 오래 캐싱, 실패(null)는 짧게 캐싱해 주기적으로 재시도.
const OK_TTL_MS   = 90 * 24 * 60 * 60 * 1000   // 90일
const NULL_TTL_MS = 7  * 24 * 60 * 60 * 1000   // 7일

// ─── 해석 결과 영속 캐시 (kr-snapshot의 저장소 패턴과 동일: Upstash 있으면 KV, 없으면 파일) ──

interface DomainEntry { domain: string | null; ts: number }
type DomainCache = Record<string, DomainEntry>

const KV_KEY = 'kr-domains'

function cacheFile(): string {
  return path.join(process.cwd(), '.data', 'kr-domains.json')
}

async function loadCache(): Promise<DomainCache> {
  const url   = process.env.UPSTASH_REDIS_REST_URL
  const token = process.env.UPSTASH_REDIS_REST_TOKEN
  if (url && token) {
    try {
      const res = await fetch(`${url}/get/${KV_KEY}`, {
        headers: { Authorization: `Bearer ${token}` }, cache: 'no-store',
      })
      if (!res.ok) return {}
      const json = await res.json() as { result?: string | null }
      return json.result ? JSON.parse(json.result) as DomainCache : {}
    } catch { return {} }
  }
  try {
    return JSON.parse(await fs.readFile(cacheFile(), 'utf8')) as DomainCache
  } catch { return {} }
}

async function saveCache(cache: DomainCache): Promise<void> {
  const url   = process.env.UPSTASH_REDIS_REST_URL
  const token = process.env.UPSTASH_REDIS_REST_TOKEN
  if (url && token) {
    await fetch(`${url}/set/${KV_KEY}`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${token}` },
      body:    JSON.stringify(cache),
      cache:   'no-store',
    }).catch(() => {})
    return
  }
  const file = cacheFile()
  await fs.mkdir(path.dirname(file), { recursive: true })
  await fs.writeFile(file, JSON.stringify(cache), 'utf8').catch(() => {})
}

let memCache: DomainCache | null = null

// ─── corpCode.xml(zip) — stockCode → corp_code 매핑 ─────────────────────────────

let corpMap: Map<string, string> | null = null
let corpMapLoading: Promise<Map<string, string>> | null = null

// ZIP(단일 파일: CORPCODE.xml)에서 첫 엔트리를 꺼내 UTF-8 문자열로.
// 의존성 없이 built-in zlib만 사용 — 중앙 디렉터리(EOCD)에서 첫 파일 로컬 헤더 위치를
// 계산해 deflate(raw)로 해제한다(compressed size는 중앙 디렉터리 값이 항상 신뢰 가능).
function unzipFirst(buf: Buffer): string {
  // EOCD(End Of Central Directory, 시그니처 0x06054b50) — 주석이 있을 수 있어 뒤에서부터 탐색.
  let eocd = -1
  for (let i = buf.length - 22; i >= 0; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break }
  }
  if (eocd < 0) throw new Error('corpCode zip → EOCD 없음')

  const cdOffset = buf.readUInt32LE(eocd + 16)
  if (buf.readUInt32LE(cdOffset) !== 0x02014b50) throw new Error('corpCode zip → 중앙디렉터리 손상')

  const method      = buf.readUInt16LE(cdOffset + 10)
  const compSize    = buf.readUInt32LE(cdOffset + 20)
  const localOffset = buf.readUInt32LE(cdOffset + 42)

  if (buf.readUInt32LE(localOffset) !== 0x04034b50) throw new Error('corpCode zip → 로컬헤더 손상')
  const lNameLen  = buf.readUInt16LE(localOffset + 26)
  const lExtraLen = buf.readUInt16LE(localOffset + 28)
  const dataStart = localOffset + 30 + lNameLen + lExtraLen
  const data      = buf.subarray(dataStart, dataStart + compSize)

  const out = method === 0 ? data : zlib.inflateRawSync(data)   // 0=stored, 8=deflate
  return out.toString('utf8')
}

async function ensureCorpMap(): Promise<Map<string, string>> {
  if (corpMap) return corpMap
  if (corpMapLoading) return corpMapLoading

  corpMapLoading = (async () => {
    const res = await fetch(`${CORPCODE_URL}?crtfc_key=${DART_KEY}`, { cache: 'no-store' })
    if (!res.ok) throw new Error(`DART corpCode → HTTP ${res.status}`)
    const xml = unzipFirst(Buffer.from(await res.arrayBuffer()))

    // <list><corp_code>8자리</corp_code>…<stock_code>6자리(비상장은 공백)</stock_code>…</list>
    const map = new Map<string, string>()
    const re = /<list>([\s\S]*?)<\/list>/g
    let m: RegExpExecArray | null
    while ((m = re.exec(xml)) !== null) {
      const block = m[1]
      const stock = /<stock_code>\s*([0-9]{6})\s*<\/stock_code>/.exec(block)?.[1]
      if (!stock) continue
      const corp = /<corp_code>\s*([0-9]{8})\s*<\/corp_code>/.exec(block)?.[1]
      if (corp) map.set(stock, corp)
    }
    if (map.size === 0) throw new Error('corpCode.xml → 매핑 0건(형식 변경 의심)')
    corpMap = map
    return map
  })()

  try {
    return await corpMapLoading
  } catch (err) {
    corpMapLoading = null   // 실패 시 다음 호출에서 재시도 가능하도록 초기화
    throw err
  }
}

// ─── 도메인 정규화 & 단일 코드 해석 ─────────────────────────────────────────────

// hm_url → 순수 도메인(스킴·경로·www·포트 제거). 점이 없으면(유효 도메인 아님) null.
function normalizeDomain(raw: string | undefined | null): string | null {
  if (!raw) return null
  let s = raw.trim()
  if (!s) return null
  if (!/^https?:\/\//i.test(s)) s = 'http://' + s
  try {
    const host = new URL(s).hostname.toLowerCase().replace(/^www\./, '')
    return host.includes('.') ? host : null
  } catch {
    return null
  }
}

// 단일 종목코드 해석. corpMap에 없거나 hm_url이 없으면 null.
// DART 한도초과('020')는 일시 장애라 throw해(배치 중단·캐시 안 함) 다음 기회에 재시도한다.
async function resolveOne(code: string): Promise<string | null> {
  const map  = await ensureCorpMap()
  // 우선주(예: 삼성전자우 005935)는 corpCode.xml에 본주 코드(005930)만 있어 직접 매핑이 없다.
  // 끝자리가 0이 아니면 본주(첫 5자리 + "0")로 폴백해 같은 회사 도메인·로고를 공유한다.
  const corp = map.get(code) ?? (code.endsWith('0') ? undefined : map.get(code.slice(0, 5) + '0'))
  if (!corp) return null

  const res = await fetch(`${COMPANY_URL}?crtfc_key=${DART_KEY}&corp_code=${corp}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(`DART company ${code} → HTTP ${res.status}`)
  const json = await res.json() as { status?: string; hm_url?: string }
  if (json.status === '020') throw new Error('DART 사용한도 초과(020)')
  if (json.status && json.status !== '000') return null   // 013(데이터 없음) 등 → 도메인 없음으로 캐싱
  return normalizeDomain(json.hm_url)
}

// ─── 공개 API ───────────────────────────────────────────────────────────────────

// 주어진 종목코드들의 도메인을 반환(code → domain). 캐시 우선, 미해석분만 DART로 채운다.
// best-effort: 키 미설정·실패 시 가능한 만큼만 채우고 조용히 반환한다(예외를 던지지 않음).
export async function enrichDomains(codes: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>()
  if (!DART_KEY || codes.length === 0) return out

  if (!memCache) memCache = await loadCache()
  const now = Date.now()

  // 유효 캐시가 없는 코드만 해석 대상으로 추린다(중복 제거).
  const stale = new Set<string>()
  for (const code of codes) {
    const e = memCache[code]
    if (e && now - e.ts < (e.domain ? OK_TTL_MS : NULL_TTL_MS)) {
      if (e.domain) out.set(code, e.domain)
      continue
    }
    stale.add(code)
  }
  if (stale.size === 0) return out

  let dirty = false
  // 순차 처리(대상은 보통 소수). corpMap 다운로드/한도초과 등 치명 실패면 남은 코드는 이번엔 포기.
  for (const code of stale) {
    try {
      const domain = await resolveOne(code)
      memCache[code] = { domain, ts: Date.now() }
      dirty = true
      if (domain) out.set(code, domain)
    } catch (err) {
      console.warn('[dart-domain] resolve aborted:', err)
      break
    }
  }
  if (dirty) await saveCache(memCache)
  return out
}
