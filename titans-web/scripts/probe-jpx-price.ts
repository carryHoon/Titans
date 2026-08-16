// ─── JPX 일별 종가(price) 취득 가능성 재프로브 (read-only) ─────────────────────────
//
// 목적: TD Venture 플랜에서 JPX 종목의 "일별 종가"를 얻는 심볼체계/엔드포인트가 있는지 확인.
// 있으면 시총 = shares_outstanding(=statistics) × 종가로 매일 움직이는 값을 만들어
// JPX 등락%·순위변동을 살릴 수 있다. (현재 JPX는 /statistics 고정 시총만 있어 변동 0.)
//
// 아무 것도 쓰지 않는다(스냅샷/Upstash 무관). TWELVE_DATA_API_KEY 만 사용.
// 실행: (titans-web) TWELVE_DATA_API_KEY=... npx tsx scripts/probe-jpx-price.ts
//       또는 GitHub Actions "Probe JPX price (manual)" 수동 실행.

const KEY  = process.env.TWELVE_DATA_API_KEY ?? ''
const BASE = 'https://api.twelvedata.com'

if (!KEY) { console.error('TWELVE_DATA_API_KEY 미설정'); process.exit(1) }

// 대표 종목 1개(Toyota 7203)로 신용(credit) 아끼며 매트릭스 프로브.
const TICKER = '7203'

interface Probe { label: string; path: string }

const probes: Probe[] = [
  { label: 'quote exchange=XTKS',        path: `/quote?symbol=${TICKER}&exchange=XTKS` },
  { label: 'quote mic_code=XTKS',        path: `/quote?symbol=${TICKER}&mic_code=XTKS` },
  { label: 'quote exchange=Tokyo',       path: `/quote?symbol=${TICKER}&exchange=Tokyo` },
  { label: 'quote symbol=7203.T',        path: `/quote?symbol=${TICKER}.T` },
  { label: 'quote symbol=7203:XTKS',     path: `/quote?symbol=${TICKER}:XTKS` },
  { label: 'price exchange=XTKS',        path: `/price?symbol=${TICKER}&exchange=XTKS` },
  { label: 'eod exchange=XTKS',          path: `/eod?symbol=${TICKER}&exchange=XTKS` },
  { label: 'eod mic_code=XTKS',          path: `/eod?symbol=${TICKER}&mic_code=XTKS` },
  { label: 'eod symbol=7203.T',          path: `/eod?symbol=${TICKER}.T` },
  { label: 'time_series 1day exch=XTKS', path: `/time_series?symbol=${TICKER}&exchange=XTKS&interval=1day&outputsize=2` },
  { label: 'time_series 1day mic=XTKS',  path: `/time_series?symbol=${TICKER}&mic_code=XTKS&interval=1day&outputsize=2` },
  { label: 'time_series 1day 7203.T',    path: `/time_series?symbol=${TICKER}.T&interval=1day&outputsize=2` },
]

// 응답에서 "쓸만한 종가 신호"를 뽑아 요약(있으면 OK, 없으면 error 메시지).
function summarize(json: any): { ok: boolean; note: string } {
  if (json?.status === 'error') return { ok: false, note: `ERROR ${json.code ?? ''} ${json.message ?? ''}`.trim() }
  if (json?.close != null)      return { ok: true,  note: `close=${json.close}` }                       // /quote
  if (json?.price != null)      return { ok: true,  note: `price=${json.price}` }                       // /price
  if (Array.isArray(json?.values) && json.values.length) {
    const v = json.values
    return { ok: true, note: `values[0].close=${v[0]?.close} (${v.length} rows, latest ${v[0]?.datetime})` }
  }
  if (json?.datetime && json?.close != null) return { ok: true, note: `eod close=${json.close} @${json.datetime}` }
  return { ok: false, note: `unrecognized: ${JSON.stringify(json).slice(0, 160)}` }
}

async function run() {
  console.log(`[probe-jpx-price] TICKER=${TICKER}, ${probes.length}개 조합 테스트\n`)
  let anyOk = false
  for (const p of probes) {
    const url = `${BASE}${p.path}&apikey=${KEY}`
    try {
      const res  = await fetch(url, { cache: 'no-store' })
      const json = await res.json().catch(() => ({}))
      const { ok, note } = summarize(json)
      if (ok) anyOk = true
      console.log(`${ok ? '✅' : '❌'}  ${p.label.padEnd(26)} HTTP ${res.status}  ${note}`)
    } catch (err) {
      console.log(`💥  ${p.label.padEnd(26)} ${err instanceof Error ? err.message : err}`)
    }
    await new Promise(r => setTimeout(r, 1500))  // 페이싱(429 회피)
  }
  console.log(`\n[probe-jpx-price] 결론: JPX 종가 취득 ${anyOk ? '가능한 조합 있음 ✅ → 정식 구현 가능' : '불가(전부 실패) ❌ → JPX 정적 수용'}`)
}

run().catch(e => { console.error(e); process.exit(1) })
