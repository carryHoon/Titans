// 일회성 큐레이션 검증 스크립트 — 중국 A주(SSE/XSHG·SZSE/XSHE) 후보가 TD에서 올바른
// 회사·거래소로 매핑되고 /statistics 시총을 주는지 확인. dev 보조(커밋됨, JPX/EU와 동일 관행).
// 실행: npx tsx --env-file=.env.local scripts/cn-validate.mjs  또는  node scripts/cn-validate.mjs
import fs from 'fs'

const KEY = process.env.TWELVE_DATA_API_KEY
  || (fs.readFileSync('.env.local', 'utf8').match(/TWELVE_DATA_API_KEY\s*=\s*"?([^"\n]+)"?/) || [])[1]
if (!KEY) throw new Error('no key')

// [symbol, mic, 표시명(영문), 매칭 검증 키워드]
const CAND = [
  // ── Shanghai (XSHG / SSE) ──
  ['600519','XSHG','Kweichow Moutai','moutai'],
  ['601398','XSHG','ICBC','industrial and commercial bank'],
  ['601288','XSHG','Agri. Bank of China','agricultural bank'],
  ['601939','XSHG','China Constr. Bank','construction bank'],
  ['601988','XSHG','Bank of China','bank of china'],
  ['601318','XSHG','Ping An Insurance','ping an'],
  ['600036','XSHG','China Merchants Bank','merchants bank'],
  ['600900','XSHG','Yangtze Power','yangtze power'],
  ['601857','XSHG','PetroChina','petrochina'],
  ['600028','XSHG','Sinopec','sinopec'],
  ['601628','XSHG','China Life','china life'],
  ['600941','XSHG','China Mobile','china mobile'],
  ['601088','XSHG','China Shenhua','shenhua'],
  ['600276','XSHG','Hengrui Pharma','hengrui'],
  ['601668','XSHG','China State Constr.','china state construction'],
  ['600030','XSHG','CITIC Securities','citic securities'],
  ['601166','XSHG','Industrial Bank','industrial bank'],
  ['600887','XSHG','Yili Group','yili'],
  ['601601','XSHG','China Pacific Ins.','china pacific'],
  ['600809','XSHG','Shanxi Fenjiu','fenjiu'],
  ['601012','XSHG','LONGi Green Energy','longi'],
  ['601899','XSHG','Zijin Mining','zijin'],
  ['600690','XSHG','Haier Smart Home','haier'],
  ['601688','XSHG','Huatai Securities','huatai'],
  ['600585','XSHG','Anhui Conch Cement','conch'],
  ['601728','XSHG','China Telecom','china telecom'],
  ['601390','XSHG','China Railway Grp','china railway group'],
  ['600438','XSHG','Tongwei','tongwei'],
  ['600104','XSHG','SAIC Motor','saic'],
  ['601919','XSHG','COSCO Shipping','cosco'],
  ['601225','XSHG','Shaanxi Coal','shaanxi coal'],
  ['600050','XSHG','China Unicom','unicom'],
  ['603288','XSHG','Foshan Haitian','haitian'],
  ['601633','XSHG','Great Wall Motor','great wall'],
  ['601998','XSHG','China CITIC Bank','citic bank'],
  ['600031','XSHG','Sany Heavy Ind.','sany'],
  ['603259','XSHG','WuXi AppTec','wuxi apptec'],
  ['688981','XSHG','SMIC','semiconductor manufacturing'],
  ['600048','XSHG','Poly Developments','poly'],
  ['601766','XSHG','CRRC','crrc'],
  // ── Shenzhen (XSHE / SZSE) ──
  ['300750','XSHE','CATL','contemporary amperex'],
  ['002594','XSHE','BYD','byd'],
  ['000858','XSHE','Wuliangye','wuliangye'],
  ['000333','XSHE','Midea Group','midea'],
  ['002415','XSHE','Hikvision','hikvision'],
  ['000651','XSHE','Gree Electric','gree'],
  ['300760','XSHE','Mindray','mindray'],
  ['002714','XSHE','Muyuan Foods','muyuan'],
  ['000568','XSHE','Luzhou Laojiao','luzhou'],
  ['002475','XSHE','Luxshare Precision','luxshare'],
  ['300059','XSHE','East Money','east money'],
  ['000001','XSHE','Ping An Bank','ping an bank'],
  ['002304','XSHE','Yanghe Brewery','yanghe'],
  ['300124','XSHE','Inovance','inovance'],
  ['000725','XSHE','BOE Technology','boe'],
  ['002230','XSHE','iFlytek','iflytek'],
  ['300274','XSHE','Sungrow Power','sungrow'],
  ['002352','XSHE','SF Holding','s.f. holding'],
  ['000002','XSHE','China Vanke','vanke'],
  ['300015','XSHE','Aier Eye Hospital','aier'],
  ['000063','XSHE','ZTE','zte'],
  ['002241','XSHE','GoerTek','goertek'],
  ['000100','XSHE','TCL Technology','tcl'],
  ['002460','XSHE','Ganfeng Lithium','ganfeng'],
  ['300450','XSHE','Lead Intelligent','lead intelligent'],
  ['002050','XSHE','Sanhua Intelligent','sanhua'],
  ['000338','XSHE','Weichai Power','weichai'],
  ['002466','XSHE','Tianqi Lithium','tianqi'],
  ['000538','XSHE','Yunnan Baiyao','baiyao'],
  ['002027','XSHE','Focus Media','focus media'],
]

const norm = s => s.toLowerCase().replace(/\s+/g, ' ').trim()
const out = []
for (const [sym, mic, disp, kw] of CAND) {
  const row = { sym, mic, disp }
  try {
    const s = await (await fetch(`https://api.twelvedata.com/symbol_search?symbol=${sym}&apikey=${KEY}`)).json()
    const hit = (s.data || []).find(d => d.mic_code === mic)
      || (s.data || []).find(d => ['XSHG', 'XSHE', 'SSE', 'SZSE'].includes(d.mic_code))
    row.tdName = hit?.instrument_name
    row.cur    = hit?.currency
    row.searchOk = !!hit && norm(hit.instrument_name).includes(norm(kw).split(' ')[0])
    await new Promise(r => setTimeout(r, 200))
    const st = await (await fetch(`https://api.twelvedata.com/statistics?symbol=${sym}&mic_code=${mic}&apikey=${KEY}`)).json()
    if (st.status === 'error') { row.statsErr = st.message?.slice(0, 50) }
    else {
      row.cap    = st?.statistics?.valuations_metrics?.market_capitalization
      row.shares = st?.statistics?.stock_statistics?.shares_outstanding
    }
  } catch (e) { row.exc = String(e) }
  out.push(row)
  await new Promise(r => setTimeout(r, 250))
}

const bad = out.filter(o => !o.searchOk || !o.cap)
console.log(`TOTAL ${out.length} | name-mismatch/no-cap ${bad.length}`)
for (const b of bad) console.log('  ⚠️', b.sym, b.mic, b.disp, '→', b.tdName || '(no hit)', b.statsErr || b.exc || (b.cap ? '' : 'no cap'))
console.log('--- confirmed (sym | mic | disp | tdName | cur | capCNY(억) ) ---')
for (const o of out.filter(o => o.searchOk && o.cap)) {
  console.log(`${o.sym} | ${o.mic} | ${o.disp} | ${o.tdName} | ${o.cur} | ${(o.cap / 1e8).toFixed(0)}`)
}
