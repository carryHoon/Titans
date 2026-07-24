import { NextRequest, NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 출시 투표("하트") 집계 엔드포인트.
// - GET            → 준비 중 거래소별 하트 수 { counts: { jpx: n, ... } }
// - POST {market, deviceId}   → 하트 추가 → { market, count }
// - DELETE {market, deviceId} → 하트 취소 → { market, count }
//
// 저장소: 프로덕션은 Upstash Redis(REST, 원자적 SADD/SREM/SCARD), 로컬 dev는 JSON 파일.
// 기기 UUID(deviceId)를 SET에 넣어 세므로 한 기기가 여러 번 눌러도 1로만 집계된다(중복 방지).

// 투표 대상 = 1차 출시에서 "준비 중"인 거래소만 허용(임의 키 오염 방지).
const MARKETS = ['jpx', 'euronext', 'sse', 'szse', 'hkex', 'twse', 'nse'] as const
type MarketKey = (typeof MARKETS)[number]

function isMarket(v: unknown): v is MarketKey {
  return typeof v === 'string' && (MARKETS as readonly string[]).includes(v)
}

// ── 저장소 추상화 ────────────────────────────────────────────────
const REDIS_URL = process.env.UPSTASH_REDIS_REST_URL ?? ''
const REDIS_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN ?? ''
const HAS_REDIS = REDIS_URL !== '' && REDIS_TOKEN !== ''

const key = (m: MarketKey) => `launchvote:${m}`

/** Upstash REST 파이프라인 실행 → 각 명령의 result 배열 반환. */
async function redis(cmds: (string | number)[][]): Promise<unknown[]> {
  const res = await fetch(`${REDIS_URL}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${REDIS_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cmds),
    cache: 'no-store',
  })
  if (!res.ok) throw new Error(`Upstash ${res.status}`)
  const data = (await res.json()) as { result: unknown }[]
  return data.map((d) => d.result)
}

// 로컬 파일 폴백(서버리스가 아닌 dev 전용). shape: { [market]: deviceId[] }
const DATA_FILE = path.join(process.cwd(), '.data', 'launch-votes.json')

async function readFileStore(): Promise<Record<string, string[]>> {
  try {
    return JSON.parse(await fs.readFile(DATA_FILE, 'utf8'))
  } catch {
    return {}
  }
}

async function writeFileStore(store: Record<string, string[]>): Promise<void> {
  await fs.mkdir(path.dirname(DATA_FILE), { recursive: true })
  await fs.writeFile(DATA_FILE, JSON.stringify(store), 'utf8')
}

// ── 집계 연산 ────────────────────────────────────────────────────
async function getCounts(): Promise<Record<MarketKey, number>> {
  const counts = Object.fromEntries(MARKETS.map((m) => [m, 0])) as Record<MarketKey, number>
  if (HAS_REDIS) {
    const results = await redis(MARKETS.map((m) => ['SCARD', key(m)]))
    MARKETS.forEach((m, i) => (counts[m] = Number(results[i]) || 0))
  } else {
    const store = await readFileStore()
    MARKETS.forEach((m) => (counts[m] = new Set(store[m] ?? []).size))
  }
  return counts
}

async function setVote(market: MarketKey, deviceId: string, voted: boolean): Promise<number> {
  if (HAS_REDIS) {
    const cmd = voted ? 'SADD' : 'SREM'
    const [, count] = await redis([
      [cmd, key(market), deviceId],
      ['SCARD', key(market)],
    ])
    return Number(count) || 0
  }
  const store = await readFileStore()
  const set = new Set(store[market] ?? [])
  voted ? set.add(deviceId) : set.delete(deviceId)
  store[market] = [...set]
  await writeFileStore(store)
  return set.size
}

// ── 핸들러 ───────────────────────────────────────────────────────
export async function GET() {
  try {
    return NextResponse.json({ counts: await getCounts() })
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 502 })
  }
}

async function mutate(req: NextRequest, voted: boolean) {
  let body: { market?: unknown; deviceId?: unknown }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'invalid body' }, { status: 400 })
  }
  if (!isMarket(body.market) || typeof body.deviceId !== 'string' || !body.deviceId) {
    return NextResponse.json({ error: 'market/deviceId required' }, { status: 400 })
  }
  try {
    const count = await setVote(body.market, body.deviceId, voted)
    return NextResponse.json({ market: body.market, count })
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 502 })
  }
}

export const POST = (req: NextRequest) => mutate(req, true)
export const DELETE = (req: NextRequest) => mutate(req, false)
