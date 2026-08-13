// 일회성 큐레이션 검증 스크립트 — JPX 후보 코드가 TD에서 올바른 회사로 매핑되는지 확인.
// 커밋 대상 아님(dev 보조). symbol_search는 저렴/무료. 실행: node scripts/jpx-validate.mjs
import fs from 'fs'

const KEY = (fs.readFileSync('.env.local', 'utf8').match(/TWELVE_DATA_API_KEY\s*=\s*"?([^"\n]+)"?/) || [])[1]
if (!KEY) throw new Error('no key')

// 후보: [code, 표시명(영문), 매칭 검증용 키워드]
const CAND = [
  ['7203','Toyota','toyota'],['8306','Mitsubishi UFJ','mitsubishi ufj'],['6758','Sony','sony'],
  ['6861','Keyence','keyence'],['9432','NTT','nippon telegraph'],['6501','Hitachi','hitachi'],
  ['9984','SoftBank Group','softbank group'],['8035','Tokyo Electron','tokyo electron'],
  ['9983','Fast Retailing','fast retailing'],['4063','Shin-Etsu Chemical','shin-etsu'],
  ['8316','Sumitomo Mitsui Fin','sumitomo mitsui financial'],['6098','Recruit','recruit'],
  ['8058','Mitsubishi Corp','mitsubishi corp'],['9433','KDDI','kddi'],['7974','Nintendo','nintendo'],
  ['4568','Daiichi Sankyo','daiichi sankyo'],['4519','Chugai Pharma','chugai'],['7267','Honda','honda'],
  ['8031','Mitsui & Co','mitsui'],['4502','Takeda','takeda'],['8001','Itochu','itochu'],
  ['6981','Murata Mfg','murata'],['6902','Denso','denso'],['7741','Hoya','hoya'],['6954','Fanuc','fanuc'],
  ['8411','Mizuho Financial','mizuho'],['8053','Sumitomo Corp','sumitomo corp'],['8002','Marubeni','marubeni'],
  ['6594','Nidec','nidec'],['4661','Oriental Land','oriental land'],['6367','Daikin','daikin'],
  ['4452','Kao','kao'],['7309','Shimano','shimano'],['5108','Bridgestone','bridgestone'],
  ['6301','Komatsu','komatsu'],['2802','Ajinomoto','ajinomoto'],['6752','Panasonic','panasonic'],
  ['7751','Canon','canon'],['6503','Mitsubishi Electric','mitsubishi electric'],
  ['8766','Tokio Marine','tokio marine'],['8630','Sompo','sompo'],['8725','MS&AD','ms&ad'],
  ['4543','Terumo','terumo'],['7733','Olympus','olympus'],['9434','SoftBank Corp','softbank corp'],
  ['8309','Sumitomo Mitsui Trust','sumitomo mitsui trust'],['3382','Seven & i','seven & i'],
  ['9022','JR Central','central japan railway'],['9020','JR East','east japan railway'],
  ['5401','Nippon Steel','nippon steel'],['5411','JFE Holdings','jfe'],['5713','Sumitomo Metal Mining','sumitomo metal mining'],
  ['2502','Asahi Group','asahi group'],['2503','Kirin','kirin'],['2914','Japan Tobacco','japan tobacco'],
  ['6702','Fujitsu','fujitsu'],['6701','NEC','nec'],['6723','Renesas','renesas'],
  ['6857','Advantest','advantest'],['6146','Disco','disco'],['7735','Screen Holdings','screen'],
  ['6971','Kyocera','kyocera'],['6762','TDK','tdk'],['5802','Sumitomo Electric','sumitomo electric'],
  ['4503','Astellas','astellas'],['4523','Eisai','eisai'],['4528','Ono Pharma','ono pharma'],
  ['4578','Otsuka Holdings','otsuka'],['4507','Shionogi','shionogi'],['8604','Nomura','nomura'],
  ['8601','Daiwa Securities','daiwa'],['8750','Dai-ichi Life','dai-ichi life'],['8591','ORIX','orix'],
  ['9843','Nitori','nitori'],['4901','Fujifilm','fujifilm'],['4612','Nippon Paint','nippon paint'],
  ['8113','Unicharm','unicharm'],['4911','Shiseido','shiseido'],['2587','Suntory Beverage','suntory'],
  ['2801','Kikkoman','kikkoman'],['9735','Secom','secom'],['3659','Nexon','nexon'],
  ['7832','Bandai Namco','bandai namco'],['9766','Konami','konami'],['9697','Capcom','capcom'],
  ['4755','Rakuten','rakuten'],['4385','Mercari','mercari'],['6869','Sysmex','sysmex'],
  ['6645','Omron','omron'],['6506','Yaskawa','yaskawa'],['6273','SMC','smc'],
  ['6326','Kubota','kubota'],['7951','Yamaha','yamaha'],['9101','Nippon Yusen','nippon yusen'],
  ['9104','Mitsui O.S.K.','mitsui o.s.k'],['9107','Kawasaki Kisen','kawasaki kisen'],
  ['6201','Toyota Industries','toyota industries'],['7259','Aisin','aisin'],
  ['9502','Chubu Electric','chubu electric'],['9501','TEPCO','tokyo electric power'],
  ['9503','Kansai Electric','kansai electric'],['9531','Tokyo Gas','tokyo gas'],
  ['1605','INPEX','inpex'],['5020','ENEOS','eneos'],['1925','Daiwa House','daiwa house'],
  ['1928','Sekisui House','sekisui house'],['9532','Osaka Gas','osaka gas'],
]

const norm = s => s.toLowerCase().replace(/\s+/g,' ').trim()
const out = []
for (const [code, disp, kw] of CAND) {
  try {
    const r = await fetch(`https://api.twelvedata.com/symbol_search?symbol=${code}&apikey=${KEY}`)
    const j = await r.json()
    const jpx = (j.data || []).find(d => (d.exchange === 'JPX' || d.mic_code === 'XJPX'))
    if (!jpx) { out.push({ code, disp, ok:false, note:'no JPX entry' }); continue }
    const nm = norm(jpx.instrument_name)
    const match = nm.includes(norm(kw)) || norm(kw).split(' ')[0].length>2 && nm.includes(norm(kw).split(' ')[0])
    out.push({ code, disp, tdName: jpx.instrument_name, cur: jpx.currency, ok: match })
  } catch (e) { out.push({ code, disp, ok:false, note:String(e) }) }
  await new Promise(r=>setTimeout(r,120))
}
const bad = out.filter(o=>!o.ok)
console.log(`TOTAL ${out.length}, MISMATCH/MISSING ${bad.length}`)
for (const b of bad) console.log('  ⚠️', b.code, b.disp, '→', b.tdName||b.note)
console.log('--- all confirmed (code | disp | tdName | cur) ---')
for (const o of out.filter(o=>o.ok)) console.log(`${o.code} | ${o.disp} | ${o.tdName} | ${o.cur}`)
