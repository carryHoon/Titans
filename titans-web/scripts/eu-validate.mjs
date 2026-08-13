// 일회성 큐레이션 검증 — Euronext 후보 [symbol, mic, 표시명]이 TD에서 올바른 회사·mic로
// 매핑되는지 확인 + 시총(EUR)/quote 가용성까지 조회해 랭킹·라이브여부 사전 파악.
// 커밋 대상 아님(dev 보조). 실행: node scripts/eu-validate.mjs
import fs from 'fs'
const KEY = (fs.readFileSync('.env.local', 'utf8').match(/TWELVE_DATA_API_KEY\s*=\s*"?([^"\n]+)"?/) || [])[1]
if (!KEY) throw new Error('no key')

// [symbol, mic, 표시명, 매칭 키워드]
const CAND = [
  // Paris (XPAR)
  ['MC','XPAR','LVMH','lvmh'],['OR','XPAR',"L'Oréal",'oréal'],['RMS','XPAR','Hermès','hermès'],
  ['TTE','XPAR','TotalEnergies','total'],['SAN','XPAR','Sanofi','sanofi'],['AI','XPAR','Air Liquide','air liquide'],
  ['SU','XPAR','Schneider Electric','schneider'],['EL','XPAR','EssilorLuxottica','essilor'],
  ['AIR','XPAR','Airbus','airbus'],['CDI','XPAR','Christian Dior','dior'],['BNP','XPAR','BNP Paribas','bnp'],
  ['DG','XPAR','Vinci','vinci'],['SAF','XPAR','Safran','safran'],['CS','XPAR','AXA','axa'],
  ['KER','XPAR','Kering','kering'],['BN','XPAR','Danone','danone'],['RI','XPAR','Pernod Ricard','pernod'],
  ['CAP','XPAR','Capgemini','capgemini'],['ACA','XPAR','Crédit Agricole','agricole'],['GLE','XPAR','Société Générale','générale'],
  ['ENGI','XPAR','Engie','engie'],['ML','XPAR','Michelin','michelin'],['ORA','XPAR','Orange','orange'],
  ['PUB','XPAR','Publicis','publicis'],['LR','XPAR','Legrand','legrand'],['VIE','XPAR','Veolia','veolia'],
  ['HO','XPAR','Thales','thales'],['DSY','XPAR','Dassault Systèmes','dassault'],['RNO','XPAR','Renault','renault'],
  ['SGO','XPAR','Saint-Gobain','gobain'],['STLAP','XPAR','Stellantis','stellantis'],['STMPA','XPAR','STMicro','stmicro'],
  ['EN','XPAR','Bouygues','bouygues'],['GTT','XPAR','GTT','gtt'],['ES','XPAR','Essilor','essilor'],
  // Amsterdam (XAMS)
  ['ASML','XAMS','ASML','asml'],['PRX','XAMS','Prosus','prosus'],['ADYEN','XAMS','Adyen','adyen'],
  ['HEIA','XAMS','Heineken','heineken'],['UMG','XAMS','Universal Music','universal music'],
  ['ASM','XAMS','ASM Intl','asm'],['WKL','XAMS','Wolters Kluwer','wolters'],['PHIA','XAMS','Philips','philips'],
  ['INGA','XAMS','ING','ing'],['AD','XAMS','Ahold Delhaize','ahold'],['EXO','XAMS','Exor','exor'],
  ['AKZA','XAMS','Akzo Nobel','akzo'],['NN','XAMS','NN Group','nn group'],['ABN','XAMS','ABN AMRO','abn'],
  ['KPN','XAMS','KPN','kpn'],['DSM','XAMS','DSM-Firmenich','dsm'],['DSFIR','XAMS','DSM-Firmenich','dsm'],
  // Milan (XMIL)
  ['RACE','XMIL','Ferrari','ferrari'],['ENEL','XMIL','Enel','enel'],['ISP','XMIL','Intesa Sanpaolo','intesa'],
  ['UCG','XMIL','UniCredit','unicredit'],['G','XMIL','Generali','generali'],['STLAM','XMIL','Stellantis','stellantis'],
  ['ENI','XMIL','Eni','eni'],['TIT','XMIL','Telecom Italia','telecom italia'],['PST','XMIL','Poste Italiane','poste'],
  ['SRG','XMIL','Snam','snam'],['MB','XMIL','Mediobanca','mediobanca'],['BAMI','XMIL','Banco BPM','banco bpm'],
  ['TRN','XMIL','Terna','terna'],['MONC','XMIL','Moncler','moncler'],['PIRC','XMIL','Pirelli','pirelli'],
  ['CPR','XMIL','Campari','campari'],['LDO','XMIL','Leonardo','leonardo'],['RACE2','XMIL','x','x'],
]

const norm = s => s.toLowerCase().replace(/\s+/g,' ').trim()
const out = []
for (const [sym, mic, disp, kw] of CAND) {
  try {
    const r = await fetch(`https://api.twelvedata.com/symbol_search?symbol=${encodeURIComponent(sym)}&apikey=${KEY}`)
    const j = await r.json()
    const hit = (j.data || []).find(d => d.mic_code === mic)
    if (!hit) { out.push({ sym, mic, disp, ok:false, note:`no ${mic} entry` }); continue }
    const nm = norm(hit.instrument_name)
    const match = nm.includes(norm(kw))
    out.push({ sym, mic, disp, tdName: hit.instrument_name, cur: hit.currency, ok: match })
  } catch (e) { out.push({ sym, mic, disp, ok:false, note:String(e) }) }
  await new Promise(r=>setTimeout(r,110))
}
const bad = out.filter(o=>!o.ok)
console.log(`TOTAL ${out.length}, MISMATCH/MISSING ${bad.length}`)
for (const b of bad) console.log('  ⚠️', b.sym, b.mic, b.disp, '→', b.tdName||b.note)
console.log('--- confirmed (sym | mic | disp | tdName | cur) ---')
for (const o of out.filter(o=>o.ok)) console.log(`${o.sym} | ${o.mic} | ${o.disp} | ${o.tdName} | ${o.cur}`)
