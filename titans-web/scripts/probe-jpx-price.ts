// ─── JPX 일별 종가(price) 취득 가능성 재프로브 (read-only) ─────────────────────────
//
// 목적: TD Venture 플랜에서 JPX 종목의 "일별 종가"를 얻는 엔드포인트가 있는지 확인.
// 있으면 시총 = shares_outstanding(=statistics) × 종가로 매일 움직이는 값을 만들어
// JPX 등락%·순위변동을 살릴 수 있다. (현재 JPX는 /statistics 고정 시총만 있어 변동 0.)
//
// 핵심: JPX는 TD에서 exchange=JPX 파라미터로 식별된다(jpx-snapshot의 /statistics가 이걸로 성공 중).
// 그래서 가격 엔드포인트도 반드시 exchange=JPX(또는 mic_code)로 테스트해야 한다.
// 아무 것도 쓰지 않는다. TWELVE_DATA_API_KEY 만 사용.

const KEY  = process.env.TWELVE_DATA_API_KEY ?? ''
const BASE = 'https://api.twelvedata.com'

if (!KEY) { console.error('TWELVE_DATA_API_KEY 미설정'); process.exit(1) }

const TICKER = '7203'  // Toyota

interface Probe { label: string; path: string }

const probes: Probe[] = [
  // 대조군 — statistics는 exchange=JPX로 성공해야 함(키·파라미터 정상 확인용).
  { label: 'statistics exchange=JPX (대조군)', path: `/statistics?symbol=${TICKER}&exchange=JPX` },
  // 검증된 exchange=JPX 로 각 가격 엔드포인트 테스트.
  { label: 'quote exchange=JPX',         path: `/quote?symbol=${TICKER}&exchange=JPX` },
  { label: 'price exchange=JPX',         path: `/price?symbol=${TICKER}&exchange=JPX` },
  { label: 'eod exchange=JPX',           path: `/eod?symbol=${TICKER}&exchange=JPX` },
  { label: 'time_series 1day exch=JPX',  path: `/time_series?symbol=${TICKER}&exchange=JPX&interval=1day&outputsize=3` },
  // mic_code 후보들도 확인.
  { label: 'quote mic_code=XJPX',        path: `/quote?symbol=${TICKER}&mic_code=XJPX` },
  { label: 'eod mic_code=XJPX',          path: `/eod?symbol=${TICKER}&mic_code=XJPX` },
  { label: 'time_series 1day mic=XJPX',  path: `/time_series?symbol=${TICKER}&mic_code=XJPX&interval=1day&outputsize=3` },
  { label: 'quote mic_code=XTKS',        path: `/quote?symbol=${TICKER}&mic_code=XTKS` },
]

function summarize(json: any): { ok: boolean; note: string } {
  if (json?.status === 'error') return { ok: false, note: `ERROR ${json.code ?? ''} ${json.message ?? ''}`.trim() }
  if (json?.close != null)      return { ok: true,  note: `close=${json.close}` }
  if (json?.price != null)      return { ok: true,  note: `price=${json.price}` }
  if (Array.isArray(json?.values) && json.values.length) {
    const v = json.values
    return { ok: true, note: `values[0].close=${v[0]?.close} @${v[0]?.datetime} (${v.length}rows)` }
  }
  // /statistics 대조군
  const cap = json?.statistics?.valuations_metrics?.market_capitalization
  if (cap != null) return { ok: true, note: `stat market_cap=${cap}` }
  return { ok: false, note: `unrecognized: ${JSON.stringify(json).slice(0, 160)}` }
}

async function run() {
  console.log(`[probe-jpx-price] TICKER=${TICKER}, ${probes.length}개 조합 (exchange=JPX 중심)\n`)
  let priceOk = false
  for (const p of probes) {
    const url = `${BASE}${p.path}&apikey=${KEY}`
    try {
      const res  = await fetch(url, { cache: 'no-store' })
      const json = await res.json().catch(() => ({}))
      const { ok, note } = summarize(json)
      // 가격 신호(대조군 statistics 제외)가 성공했는지 별도 집계
      if (ok && !p.label.startsWith('statistics')) priceOk = true
      console.log(`${ok ? '✅' : '❌'}  ${p.label.padEnd(30)} HTTP ${res.status}  ${note}`)
    } catch (err) {
      console.log(`💥  ${p.label.padEnd(30)} ${err instanceof Error ? err.message : err}`)
    }
    await new Promise(r => setTimeout(r, 1500))
  }
  console.log(`\n[probe-jpx-price] 결론: JPX 일별 가격 취득 ${priceOk ? '가능 ✅ → 정식 구현 가능(시총=주수×종가)' : '불가 ❌ → JPX 정적 수용'}`)
}

run().catch(e => { console.error(e); process.exit(1) })
