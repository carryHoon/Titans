#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// 시총 순위 정확도 진단 (accuracy diagnostic)
//
// 앱 백엔드(/api/market-cap?exchange=…)의 top-N 결과를 두 기준과 비교해
// "누락(missing)·추가(extra)·순위 어긋남(rank shift)"을 한눈에 리포트한다.
//
//   1) 공식 대비  : scripts/reference/<ex>.json  (공홈에서 확인한 공식 top-N을 직접 입력)
//   2) 베이스라인 : scripts/reference/<ex>.baseline.json  (정확할 때 --save-baseline으로 스냅샷)
//
// 데이터 소스를 EODHD 등으로 바꾼 뒤 이 스크립트를 돌리면, 정확도가
// 공식/과거 대비 떨어졌는지 즉시 확인할 수 있다(추측이 아니라 데이터로).
//
// 사용법:
//   node scripts/accuracy-check.mjs                 # 전체 거래소 점검
//   node scripts/accuracy-check.mjs jpx nasdaq      # 특정 거래소만
//   node scripts/accuracy-check.mjs --save-baseline # 현재 앱 결과를 "정상 기준"으로 저장
//   BASE_URL=http://localhost:3000 TOP_N=20 node scripts/accuracy-check.mjs
// ─────────────────────────────────────────────────────────────────────────────

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __dir   = dirname(fileURLToPath(import.meta.url))
const REF_DIR  = join(__dir, 'reference')
const BASE_URL = process.env.BASE_URL ?? 'http://localhost:3000'
const TOP_N    = Number(process.env.TOP_N ?? 20)

// 1차 출시 범위 = US(NASDAQ/NYSE) + 한국(KOSPI/KOSDAQ). 나머지 거래소는 데이터 소스
// 상업 전환(EODHD) 시 백엔드 피드와 함께 여기에 다시 추가한다.
const EXCHANGES = ['nasdaq', 'nyse', 'kospi', 'kosdaq']

const C = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m',
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m', cyan: '\x1b[36m',
}
const ok   = s => `${C.green}${s}${C.reset}`
const bad  = s => `${C.red}${s}${C.reset}`
const warn = s => `${C.yellow}${s}${C.reset}`

const args = process.argv.slice(2)
const save = args.includes('--save-baseline')
const picked = args.filter(a => !a.startsWith('--'))
const targets = picked.length ? picked : EXCHANGES

// ── 앱 API 호출 ───────────────────────────────────────────────────────────────
async function fetchApp(ex) {
  const res = await fetch(`${BASE_URL}/api/market-cap?exchange=${ex}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const j = await res.json()
  if (!Array.isArray(j.data)) throw new Error(j.error ? `API error: ${j.error}` : 'no data array')
  return {
    stale: !!j.stale,
    list: j.data.map(c => ({ ticker: c.ticker, name: c.name, cap: c.marketCapUSD })),
  }
}

// ── reference JSON 로드 ({ top: [{ticker,name}] } 또는 [{ticker,name}]) ────────
function loadRef(path) {
  if (!existsSync(path)) return null
  const raw = JSON.parse(readFileSync(path, 'utf8'))
  const arr = Array.isArray(raw) ? raw : raw.top
  if (!Array.isArray(arr)) return null
  return { meta: Array.isArray(raw) ? {} : raw, list: arr }
}

// ── 두 순위 리스트 비교 ─────────────────────────────────────────────────────
function diff(appList, refList) {
  const app = appList.slice(0, TOP_N)
  const ref = refList.slice(0, TOP_N)
  const appIdx = new Map(app.map((c, i) => [c.ticker, i]))
  const refIdx = new Map(ref.map((c, i) => [c.ticker, i]))

  const missing = ref.filter(c => !appIdx.has(c.ticker)) // 공식엔 있는데 앱엔 없음 ← 누락(치명)
  const extra   = app.filter(c => !refIdx.has(c.ticker)) // 앱엔 있는데 공식엔 없음

  let maxShift = 0
  const shifts = []
  for (const c of app) {
    if (!refIdx.has(c.ticker)) continue
    const d = appIdx.get(c.ticker) - refIdx.get(c.ticker)
    if (Math.abs(d) > maxShift) maxShift = Math.abs(d)
    if (d !== 0) shifts.push({ ticker: c.ticker, name: c.name, app: appIdx.get(c.ticker) + 1, ref: refIdx.get(c.ticker) + 1 })
  }
  const matched = app.length - extra.length
  return { matched, total: ref.length, missing, extra, maxShift, shifts }
}

function printComparison(label, appList, ref) {
  const r = diff(appList, ref.list)
  const perfect = r.missing.length === 0 && r.extra.length === 0 && r.maxShift === 0
  const good    = r.missing.length === 0
  const badge = perfect ? ok('완벽 일치') : good ? warn('누락 없음(순위差 있음)') : bad(`누락 ${r.missing.length}건`)
  const asOf = ref.meta.asOf ? ` ${C.dim}(${ref.meta.asOf})${C.reset}` : ''
  console.log(`  ${C.bold}${label}${C.reset}${asOf}: ${badge}  ` +
    `일치 ${r.matched}/${r.total} · 최대순위差 ${r.maxShift}`)
  if (r.missing.length) console.log(`    ${bad('누락')}: ${r.missing.map(c => `${c.ticker}(${c.name ?? ''})`).join(', ')}`)
  if (r.extra.length)   console.log(`    ${warn('앱에만')}: ${r.extra.map(c => `${c.ticker}(${c.name ?? ''})`).join(', ')}`)
  if (r.shifts.length)  console.log(`    ${C.dim}순위이동: ${r.shifts.map(s => `${s.ticker} ${s.ref}→${s.app}`).join(', ')}${C.reset}`)
  return { perfect, good, missing: r.missing.length }
}

// ── 메인 ────────────────────────────────────────────────────────────────────
if (!existsSync(REF_DIR)) mkdirSync(REF_DIR, { recursive: true })

console.log(`\n${C.bold}시총 정확도 진단${C.reset}  ${C.dim}(${BASE_URL} · top-${TOP_N})${C.reset}\n`)

let anyMissing = false
for (const ex of targets) {
  process.stdout.write(`${C.cyan}▶ ${ex.toUpperCase()}${C.reset} `)
  let app
  try {
    app = await fetchApp(ex)
  } catch (e) {
    console.log(bad(`앱 API 실패 — ${e.message} (서버 실행 중인지 확인)`))
    continue
  }
  console.log(app.stale ? warn('(stale 캐시 응답)') : '')

  if (save) {
    const path = join(REF_DIR, `${ex}.baseline.json`)
    writeFileSync(path, JSON.stringify({
      source: 'app-baseline', asOf: new Date().toISOString(),
      top: app.list.map(c => ({ ticker: c.ticker, name: c.name })),
    }, null, 2) + '\n')
    console.log(`    ${ok('베이스라인 저장')} → ${path.replace(__dir + '/', '')} (${app.list.length}종목)`)
    continue
  }

  const official = loadRef(join(REF_DIR, `${ex}.json`))
  const baseline = loadRef(join(REF_DIR, `${ex}.baseline.json`))

  if (official) { const r = printComparison('공식 대비', app.list, official); anyMissing ||= r.missing > 0 }
  if (baseline) { const r = printComparison('기준 대비', app.list, baseline); anyMissing ||= r.missing > 0 }

  if (!official && !baseline) {
    console.log(`    ${C.dim}(비교 기준 없음) 현재 앱 top-${Math.min(TOP_N, app.list.length)}:${C.reset}`)
    app.list.slice(0, TOP_N).forEach((c, i) =>
      console.log(`      ${String(i + 1).padStart(2)}. ${c.ticker.padEnd(9)} ${(c.name ?? '').slice(0, 22).padEnd(22)} $${c.cap.toFixed(3)}T`))
    console.log(`    ${C.dim}→ 공식 top-${TOP_N}을 reference/${ex}.json 에 넣거나, --save-baseline 으로 현재값 저장${C.reset}`)
  }
  console.log()
}

console.log(save
  ? ok('\n베이스라인 저장 완료. 이후 소스 변경 뒤 인자 없이 실행하면 이 값과 비교합니다.\n')
  : anyMissing ? bad('\n⚠ 누락이 감지된 거래소가 있습니다. 위 목록을 확인하세요.\n')
               : ok('\n누락 없음.\n'))
