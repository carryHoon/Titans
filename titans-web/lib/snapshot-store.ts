// ─── 스냅샷 저장소 추상화(SnapshotStore) ──────────────────────────────────────
//
// "스케줄러(크론/폴러)가 업스트림에서 받아 굳힌 스냅샷을 저장하고, 유저 경로는 그 스냅샷만
//  읽는다"는 공통 패턴의 저장소 계층. KR 시세(kr-snapshot)와 US 시총 기준값(us-stats)이 공유한다.
//
// 저장소 선택은 환경으로 자동 결정된다.
//   · Upstash 환경변수가 있으면 KvStore(서버리스 Vercel — 인스턴스가 공유하는 유일한 냉장고)
//   · 없으면 FileStore(로컬 next dev/start·VPS — .data/ 파일)
// → 배포처만 바뀌고 호출부 코드는 손대지 않는다. key 하나로 여러 스냅샷을 분리 저장한다.

import { promises as fs } from 'fs'
import path from 'path'

export interface SnapshotStore<T> {
  load(): Promise<T | null>
  save(snap: T): Promise<void>
}

// 로컬/상시 프로세스용 파일 저장소. 스냅샷을 .data/<key>.json 에 보관한다.
class FileStore<T> implements SnapshotStore<T> {
  private readonly file: string
  constructor(key: string) {
    this.file = path.join(process.cwd(), '.data', `${key}.json`)
  }

  async load(): Promise<T | null> {
    try {
      const raw = await fs.readFile(this.file, 'utf8')
      return JSON.parse(raw) as T
    } catch {
      return null
    }
  }

  async save(snap: T): Promise<void> {
    await fs.mkdir(path.dirname(this.file), { recursive: true })
    await fs.writeFile(this.file, JSON.stringify(snap), 'utf8')
  }
}

// 서버리스(Vercel)용 클라우드 저장소 — Upstash Redis REST API.
// 서버리스 함수는 메모리·파일이 호출마다 사라지므로, 여러 인스턴스가 공유하는 "유일한 냉장고".
// 의존성 추가 없이 REST(fetch)로만 접근한다(@upstash/redis SDK 불필요).
class KvStore<T> implements SnapshotStore<T> {
  private readonly url   = process.env.UPSTASH_REDIS_REST_URL!
  private readonly token = process.env.UPSTASH_REDIS_REST_TOKEN!
  constructor(private readonly key: string) {}

  async load(): Promise<T | null> {
    const res = await fetch(`${this.url}/get/${this.key}`, {
      headers: { Authorization: `Bearer ${this.token}` },
      cache: 'no-store',
    })
    if (!res.ok) return null
    const json = await res.json() as { result?: string | null }
    if (!json.result) return null
    try { return JSON.parse(json.result) as T } catch { return null }
  }

  async save(snap: T): Promise<void> {
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

// Upstash 환경변수가 있으면 클라우드(KvStore), 없으면 로컬 파일(FileStore).
export function createSnapshotStore<T>(key: string): SnapshotStore<T> {
  return process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN
    ? new KvStore<T>(key)
    : new FileStore<T>(key)
}
