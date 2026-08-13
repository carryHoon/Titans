// 일회성 큐레이션 검증(커밋 대상 아님, dev 보조) — de-universe.DE_COMPANIES 전 심볼이 TD에서
// (1) mic=XETR·통화 EUR·회사명으로 올바로 매핑되고 (2) /statistics 시총(EUR)을 실제로 주는지 확인.
// 시총 없는(NaN) 종목은 DROP 후보로 출력 → 유니버스에서 제외/교정한다.
// 실행: node scripts/de-validate.mjs
import fs from 'fs'
import { DE_COMPANIES, DE_MIC } from '../lib/de-universe.ts'

const env = (fs.existsSync('.env.local') ? fs.readFileSync('.env.local','utf8') : '') +
            (fs.existsSync('.env') ? fs.readFileSync('.env','utf8') : '')
const KEY = (env.match(/TWELVE_DATA_API_KEY\s*=\s*"?([^"\n]+)"?/) || [])[1]
if (!KEY) throw new Error('no key')
const B = 'https://api.twelvedata.com'

const norm = s => (s||'').toLowerCase().replace(/\s+/g,' ').trim()
const num  = x => { const n = parseFloat(x); return Number.isFinite(n) ? n : NaN }
// 회사명 매칭 키워드(표시명 첫 단어 소문자) — TD instrument_name 부분일치 확인용
const kw = c => norm(c.name.split(/[\s.]/)[0])

const rows = []
for (const c of DE_COMPANIES) {
  const r = { sym: c.symbol, disp: c.name }
  try {
    const s = await (await fetch(`${B}/symbol_search?symbol=${encodeURIComponent(c.symbol)}&apikey=${KEY}`)).json()
    const hit = (s.data||[]).find(d => d.mic_code === DE_MIC)
    r.mic = hit ? hit.mic_code : 'NO XETR'
    r.cur = hit ? hit.currency : ''
    r.tdName = hit ? hit.instrument_name : ''
    r.nameOk = hit ? norm(hit.instrument_name).includes(kw(c)) : false
    await new Promise(t=>setTimeout(t,150))
    const st = await (await fetch(`${B}/statistics?symbol=${c.symbol}&mic_code=${DE_MIC}&apikey=${KEY}`)).json()
    r.cap = st.status==='error' ? NaN : num(st?.statistics?.valuations_metrics?.market_capitalization)
    await new Promise(t=>setTimeout(t,5200))  // /statistics=50cr, 610/min÷50≈12/min → ~5.2s gap
  } catch(e){ r.err = String(e) }
  rows.push(r)
  console.log(
    `${r.sym.padEnd(6)} mic=${String(r.mic).padEnd(8)} cur=${String(r.cur).padEnd(4)} `+
    `name=${r.nameOk?'OK ':'⚠️ '} cap=${Number.isFinite(r.cap)?(r.cap/1e9).toFixed(1)+'B':'NaN'}  ${r.tdName||r.err||''}`
  )
}

const badMic  = rows.filter(r => r.mic !== DE_MIC)
const badCur  = rows.filter(r => r.cur && r.cur !== 'EUR')
const badName = rows.filter(r => r.mic === DE_MIC && !r.nameOk)
const noCap   = rows.filter(r => !Number.isFinite(r.cap))
console.log(`\n=== SUMMARY (${rows.length} symbols) ===`)
console.log(`mic≠XETR: ${badMic.length}  ${badMic.map(r=>r.sym).join(',')}`)
console.log(`cur≠EUR : ${badCur.length}  ${badCur.map(r=>r.sym).join(',')}`)
console.log(`name mismatch: ${badName.length}  ${badName.map(r=>r.sym+'→'+r.tdName).join(' | ')}`)
console.log(`NO market_cap (DROP 후보): ${noCap.length}  ${noCap.map(r=>r.sym).join(',')}`)
