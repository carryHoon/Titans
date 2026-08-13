// ─── 중국 A주 유니버스 (단일 소스) ──────────────────────────────────────────────
//
// SSE(상하이 증권거래소, mic=XSHG)와 SZSE(선전 증권거래소, mic=XSHE)를 각각 별도 섹션으로
// 노출한다(앱의 .sse / .szse 칩과 1:1). 통화는 전 종목 CNY 단일(lib/fx에 이미 배선).
// TD 커버리지(라이브 프로브 확인):
//   · XSHG/XSHE 공통 : /statistics(시총 CNY + shares)와 /quote(close/previous_close) 둘 다 제공.
//     ⇒ Euronext XPAR/XAMS식 라이브 스케일링(cap = statsCap × close/prevClose)이 전 종목 가능.
//     단 TD의 A주 quote는 지연/EOD(is_market_open=false)라 등락은 직전 영업일 종가 기준이다.
// 시총 USD 환산은 요청 시점에 fx(USD/CNY)로 한다.
//
// TD엔 A주 시총 스크리너가 없어 유니버스는 정적 큐레이션. 아래 심볼·mic·회사명은 TD
// symbol_search로 전수 검증했다(scripts/cn-validate.mjs). 순서 무관 — 라우트가 시총 재정렬.
// 앱 표시용 ticker = 심볼(우리 셋에서 유일). TD 조회는 심볼+mic_code로 종목을 특정한다.

export interface CnCompanyMeta {
  symbol: string   // TD 심볼(6자리 A주 코드, 앱 표시용 ticker로도 사용)
  mic:    'XSHG' | 'XSHE'  // XSHG=상하이(SSE) / XSHE=선전(SZSE)
  name:   string
  color:  string
}

export const CN_COMPANIES: CnCompanyMeta[] = [
  // ── Shanghai (XSHG / SSE) ──
  { symbol: '600519', mic: 'XSHG', name: 'Kweichow Moutai',     color: '#A5111F' },
  { symbol: '601398', mic: 'XSHG', name: 'ICBC',                color: '#C7000B' },
  { symbol: '601288', mic: 'XSHG', name: 'Agri. Bank of China', color: '#009A44' },
  { symbol: '601939', mic: 'XSHG', name: 'China Constr. Bank',  color: '#003A80' },
  { symbol: '601988', mic: 'XSHG', name: 'Bank of China',       color: '#AF272F' },
  { symbol: '601318', mic: 'XSHG', name: 'Ping An Insurance',   color: '#E60012' },
  { symbol: '600036', mic: 'XSHG', name: 'China Merchants Bank', color: '#C7000B' },
  { symbol: '600900', mic: 'XSHG', name: 'Yangtze Power',       color: '#0072BC' },
  { symbol: '601857', mic: 'XSHG', name: 'PetroChina',          color: '#C8102E' },
  { symbol: '600028', mic: 'XSHG', name: 'Sinopec',             color: '#E4002B' },
  { symbol: '601628', mic: 'XSHG', name: 'China Life',          color: '#C8102E' },
  { symbol: '600941', mic: 'XSHG', name: 'China Mobile',        color: '#0066B3' },
  { symbol: '601088', mic: 'XSHG', name: 'China Shenhua',       color: '#003DA5' },
  { symbol: '600276', mic: 'XSHG', name: 'Hengrui Pharma',      color: '#E60012' },
  { symbol: '601668', mic: 'XSHG', name: 'China State Constr.', color: '#C8102E' },
  { symbol: '600030', mic: 'XSHG', name: 'CITIC Securities',    color: '#C8102E' },
  { symbol: '601166', mic: 'XSHG', name: 'Industrial Bank',     color: '#005BAC' },
  { symbol: '600887', mic: 'XSHG', name: 'Yili Group',          color: '#0060AF' },
  { symbol: '601601', mic: 'XSHG', name: 'China Pacific Ins.',  color: '#C8102E' },
  { symbol: '600809', mic: 'XSHG', name: 'Shanxi Fenjiu',       color: '#A5111F' },
  { symbol: '601012', mic: 'XSHG', name: 'LONGi Green Energy',  color: '#00843D' },
  { symbol: '601899', mic: 'XSHG', name: 'Zijin Mining',        color: '#C8102E' },
  { symbol: '600690', mic: 'XSHG', name: 'Haier Smart Home',    color: '#003DA5' },
  { symbol: '601688', mic: 'XSHG', name: 'Huatai Securities',   color: '#6E2B62' },
  { symbol: '600585', mic: 'XSHG', name: 'Anhui Conch Cement',  color: '#005BAC' },
  { symbol: '601728', mic: 'XSHG', name: 'China Telecom',       color: '#005BAC' },
  { symbol: '601390', mic: 'XSHG', name: 'China Railway Grp',   color: '#C8102E' },
  { symbol: '600438', mic: 'XSHG', name: 'Tongwei',             color: '#0093D0' },
  { symbol: '600104', mic: 'XSHG', name: 'SAIC Motor',          color: '#E4002B' },
  { symbol: '601919', mic: 'XSHG', name: 'COSCO Shipping',      color: '#0072BC' },
  { symbol: '601225', mic: 'XSHG', name: 'Shaanxi Coal',        color: '#1A1A1A' },
  { symbol: '600050', mic: 'XSHG', name: 'China Unicom',        color: '#C8102E' },
  { symbol: '603288', mic: 'XSHG', name: 'Foshan Haitian',      color: '#E4002B' },
  { symbol: '601633', mic: 'XSHG', name: 'Great Wall Motor',    color: '#C8102E' },
  { symbol: '601998', mic: 'XSHG', name: 'China CITIC Bank',    color: '#C8102E' },
  { symbol: '600031', mic: 'XSHG', name: 'Sany Heavy Ind.',     color: '#C8102E' },
  { symbol: '603259', mic: 'XSHG', name: 'WuXi AppTec',         color: '#00A9E0' },
  { symbol: '688981', mic: 'XSHG', name: 'SMIC',                color: '#005BAC' },
  { symbol: '600048', mic: 'XSHG', name: 'Poly Developments',   color: '#C8102E' },
  { symbol: '601766', mic: 'XSHG', name: 'CRRC',                color: '#C8102E' },
  // ── Shenzhen (XSHE / SZSE) ──
  { symbol: '300750', mic: 'XSHE', name: 'CATL',                color: '#1A9E5A' },
  { symbol: '002594', mic: 'XSHE', name: 'BYD',                 color: '#C8102E' },
  { symbol: '000858', mic: 'XSHE', name: 'Wuliangye',           color: '#002E5D' },
  { symbol: '000333', mic: 'XSHE', name: 'Midea Group',         color: '#0075C9' },
  { symbol: '002415', mic: 'XSHE', name: 'Hikvision',           color: '#E60012' },
  { symbol: '000651', mic: 'XSHE', name: 'Gree Electric',       color: '#005BAC' },
  { symbol: '300760', mic: 'XSHE', name: 'Mindray',             color: '#00539B' },
  { symbol: '002714', mic: 'XSHE', name: 'Muyuan Foods',        color: '#00843D' },
  { symbol: '000568', mic: 'XSHE', name: 'Luzhou Laojiao',      color: '#C8102E' },
  { symbol: '002475', mic: 'XSHE', name: 'Luxshare Precision',  color: '#E60012' },
  { symbol: '300059', mic: 'XSHE', name: 'East Money',          color: '#C8102E' },
  { symbol: '000001', mic: 'XSHE', name: 'Ping An Bank',        color: '#E60012' },
  { symbol: '002304', mic: 'XSHE', name: 'Yanghe Brewery',      color: '#003DA5' },
  { symbol: '300124', mic: 'XSHE', name: 'Inovance',            color: '#0060A9' },
  { symbol: '000725', mic: 'XSHE', name: 'BOE Technology',      color: '#1A9E5A' },
  { symbol: '002230', mic: 'XSHE', name: 'iFlytek',             color: '#005BAC' },
  { symbol: '300274', mic: 'XSHE', name: 'Sungrow Power',       color: '#E4002B' },
  { symbol: '002352', mic: 'XSHE', name: 'SF Holding',          color: '#000000' },
  { symbol: '000002', mic: 'XSHE', name: 'China Vanke',         color: '#003DA5' },
  { symbol: '300015', mic: 'XSHE', name: 'Aier Eye Hospital',   color: '#00A0E9' },
  { symbol: '000063', mic: 'XSHE', name: 'ZTE',                 color: '#005BAC' },
  { symbol: '002241', mic: 'XSHE', name: 'GoerTek',             color: '#E60012' },
  { symbol: '000100', mic: 'XSHE', name: 'TCL Technology',      color: '#000000' },
  { symbol: '002460', mic: 'XSHE', name: 'Ganfeng Lithium',     color: '#00843D' },
  { symbol: '300450', mic: 'XSHE', name: 'Lead Intelligent',    color: '#005BAC' },
  { symbol: '002050', mic: 'XSHE', name: 'Sanhua Intelligent',  color: '#0060A9' },
  { symbol: '000338', mic: 'XSHE', name: 'Weichai Power',       color: '#E4002B' },
  { symbol: '002466', mic: 'XSHE', name: 'Tianqi Lithium',      color: '#00843D' },
  { symbol: '000538', mic: 'XSHE', name: 'Yunnan Baiyao',       color: '#00843D' },
  { symbol: '002027', mic: 'XSHE', name: 'Focus Media',         color: '#E60012' },
]
