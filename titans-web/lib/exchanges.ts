// ─── 거래소 config (단일 소스) ────────────────────────────────────────────────
//
// "거래소 = 데이터"로 표현하는 config 테이블. market-cap 라우트의 거래소 디스패치와
// us-stats 스냅샷 레이어의 갱신 대상이 이 파일 하나를 읽는다. 거래소를 추가할 때
// route.ts에 분기를 심는 대신 EXCHANGES에 항목을 더하면 되도록 한다.
//
// 원칙: 큰 큐레이션 배열(NASDAQ/NYSE/COMPANIES)은 데이터 계층(us-universe)에 그대로 두고,
//       config는 그것을 "참조"만 한다. 값은 옮기지 않는다.

import { COMPANIES, NASDAQ_COMPANIES, NYSE_COMPANIES, type CompanyMeta } from './us-universe'
import { JPX_COMPANIES } from './jpx-universe'

// ─── KRX 표시 메타 ─────────────────────────────────────────────────────────────
// 유니버스·시세·시총은 kr-snapshot 레이어가 동적으로 관리(상위 100개 이상).
// 아래 배열은 "종목코드 → 영문명/색" 표시 메타의 소스로만 사용. 없는 종목은 한글명+기본색 폴백.

export interface KoreanStockMeta {
  ticker: string
  name:   string
  color:  string
}

// ALL 피드에 포함될 KRX 종목 (시총 상위권 한국 기업)
export const KOREAN_STOCKS: KoreanStockMeta[] = [
  { ticker: '005930.KS', name: 'Samsung',  color: '#1428A0' },
  { ticker: '000660.KS', name: 'SK Hynix', color: '#EA5504' },
]

// SK Hynix: NASDAQ 공식에는 ADR로 상위권에 오르지만, Twelve Data에 US 심볼이 없어
// KRX 시총(000660.KS)을 USD 환산해 NASDAQ 섹션에 주입 → 나스닥 공식 순위와 일치.
export const SKHYNIX_KRX: KoreanStockMeta = { ticker: '000660.KS', name: 'SK Hynix', color: '#EA5504' }

const KOSPI_COMPANIES: KoreanStockMeta[] = [
  { ticker: '005930.KS', name: 'Samsung Elec.',    color: '#1428A0' },
  { ticker: '000660.KS', name: 'SK Hynix',         color: '#EA5504' },
  { ticker: '402340.KS', name: 'SK Square',        color: '#E4002B' },
  { ticker: '009150.KS', name: 'Samsung EM',       color: '#1428A0' },
  { ticker: '005380.KS', name: 'Hyundai Motor',    color: '#002C5F' },
  { ticker: '373220.KS', name: 'LG Energy Sol.',   color: '#A50034' },
  { ticker: '032830.KS', name: 'Samsung Life',     color: '#1428A0' },
  { ticker: '207940.KS', name: 'Samsung Bio.',     color: '#1428A0' },
  { ticker: '105560.KS', name: 'KB Financial',     color: '#FFB819' },
  { ticker: '028260.KS', name: 'Samsung C&T',      color: '#1428A0' },
  { ticker: '000270.KS', name: 'Kia',              color: '#05141F' },
  { ticker: '055550.KS', name: 'Shinhan Fin.',     color: '#0046FF' },
  { ticker: '329180.KS', name: 'HD Hyundai HI',    color: '#00A0B0' },
  { ticker: '012330.KS', name: 'Hyundai Mobis',    color: '#002C5F' },
  { ticker: '012450.KS', name: 'Hanwha Aero.',     color: '#F37021' },
  { ticker: '034730.KS', name: 'SK Inc.',          color: '#E4002B' },
  { ticker: '034020.KS', name: 'Doosan Enerb.',    color: '#00A9CE' },
  { ticker: '068270.KS', name: 'Celltrion',        color: '#00A6D6' },
  { ticker: '086790.KS', name: 'Hana Financial',   color: '#008485' },
  { ticker: '006400.KS', name: 'Samsung SDI',      color: '#1428A0' },
]

const KOSDAQ_COMPANIES: KoreanStockMeta[] = [
  { ticker: '196170.KQ', name: 'Alteogen',         color: '#0067AC' },
  { ticker: '247540.KQ', name: 'Ecopro BM',        color: '#008C44' },
  { ticker: '086520.KQ', name: 'Ecopro',           color: '#008C44' },
  { ticker: '277810.KQ', name: 'Rainbow Robotics', color: '#2D2D2D' },
  { ticker: '036930.KQ', name: 'Jusung Eng.',      color: '#004C97' },
  { ticker: '240810.KQ', name: 'Wonik IPS',        color: '#0091D0' },
  { ticker: '058470.KQ', name: 'Leeno Ind.',       color: '#E60012' },
  { ticker: '319660.KQ', name: 'PSK',              color: '#005BAC' },
  { ticker: '298380.KQ', name: 'ABL Bio',          color: '#00A651' },
  { ticker: '039030.KQ', name: 'EO Technics',      color: '#003DA5' },
  { ticker: '028300.KQ', name: 'HLB',              color: '#00A650' },
  { ticker: '222800.KQ', name: 'Simmtech',         color: '#005EAB' },
  { ticker: '000250.KQ', name: 'Samchundang',      color: '#0068B7' },
  { ticker: '440110.KQ', name: 'FADU',             color: '#1A1A1A' },
  { ticker: '141080.KQ', name: 'LigaChem Bio',     color: '#0075C1' },
  { ticker: '214450.KQ', name: 'Pharma Research',  color: '#00953A' },
  { ticker: '108490.KQ', name: 'Robotis',          color: '#EE2E24' },
  { ticker: '403870.KQ', name: 'HPSP',             color: '#005BAC' },
  { ticker: '095610.KQ', name: 'Tes',              color: '#004EA2' },
  { ticker: '095340.KQ', name: 'ISC',              color: '#0060A9' },
]

// 종목코드(6자리) → 영문명·색 맵. kr-snapshot 동적 유니버스에 없는 종목은 한글명+기본색 폴백.
export const KRX_META: Record<string, { name: string; color: string }> = Object.fromEntries(
  [...KOSPI_COMPANIES, ...KOSDAQ_COMPANIES].map(c => [
    c.ticker.replace(/\.(KS|KQ)$/, ''),
    { name: c.name, color: c.color },
  ]),
)
export const KRX_DEFAULT_COLOR = '#3182F6'

// ─── 거래소 config ─────────────────────────────────────────────────────────────

// capModel: 시총 기준값을 어디서/어떻게 얻는가
//   · td  : TD /statistics 스냅샷(us-stats) × (quote 현재가/전일종가) 라이브 스케일링
//   · krx : data.go.kr 스냅샷(kr-snapshot)이 시총을 직접 제공(EOD, 라이브 스케일링 없음)
//   · jpx : TD /statistics 스냅샷(jpx-snapshot)이 네이티브 JPY 시총 제공 → 요청 시 USD 환산(EOD).
//           TD가 JPX 가격 피드를 안 줘 라이브 스케일링 불가 — 등락%는 전일 스냅샷 대비 자체계산.
//   · eu  : TD /statistics 스냅샷(eu-snapshot, 네이티브 EUR) base + quote 있는 종목(XPAR/XAMS)은
//           라이브 스케일링, 없는 종목(XMIL)은 EOD. 유니버스는 eu-universe(EuCompanyMeta+mic) 소유.
//   · cn  : TD /statistics 스냅샷(cn-snapshot, 네이티브 CNY) base + quote(close/prevClose)로 라이브
//           스케일링(A주 quote는 지연/EOD). mic으로 SSE(XSHG)/SZSE(XSHE) 섹션을 가른다.
//           유니버스는 cn-universe(CnCompanyMeta+mic) 소유 → route가 mic으로 필터.
//   · nse : TD /statistics 스냅샷(nse-snapshot, 네이티브 INR) base + quote 라이브 스케일링. 전 종목
//           단일 mic(XNSE). 유니버스는 nse-universe 소유 → route가 직접 참조(config.universe 미사용).
//   · de  : TD /statistics 스냅샷(de-snapshot, 네이티브 EUR) base + quote 라이브 스케일링. 전 종목
//           단일 mic(XETR = Deutsche Börse XETRA). 유니버스는 de-universe 소유 → route가 직접 참조.
export type CapModel =
  | { kind: 'td' }
  | { kind: 'krx'; suffix: 'KS' | 'KQ' }
  | { kind: 'jpx' }
  | { kind: 'eu' }
  | { kind: 'cn'; mic: 'XSHG' | 'XSHE' }
  | { kind: 'nse' }
  | { kind: 'de' }

export interface ExchangeConfig {
  code:       string             // 'NASDAQ' | 'NYSE' | 'KOSPI' | 'KOSDAQ'
  param:      string             // ?exchange= 값 (소문자)
  rankLimit:  number             // 거래소 페이지 top-N
  capModel:   CapModel
  universe?:  CompanyMeta[]      // td: 큐레이션 유니버스 (us-universe 재사용)
  injections?: KoreanStockMeta[] // td: 타 소스에서 끌어와 주입할 행(SK Hynix → NASDAQ)
}

export const EXCHANGES: ExchangeConfig[] = [
  { code: 'NASDAQ', param: 'nasdaq', rankLimit: 100, capModel: { kind: 'td' },  universe: NASDAQ_COMPANIES, injections: [SKHYNIX_KRX] },
  { code: 'NYSE',   param: 'nyse',   rankLimit: 100, capModel: { kind: 'td' },  universe: NYSE_COMPANIES },
  { code: 'KOSPI',  param: 'kospi',  rankLimit: 100, capModel: { kind: 'krx', suffix: 'KS' } },
  { code: 'KOSDAQ', param: 'kosdaq', rankLimit: 100, capModel: { kind: 'krx', suffix: 'KQ' } },
  { code: 'JPX',    param: 'jpx',    rankLimit: 100, capModel: { kind: 'jpx' }, universe: JPX_COMPANIES },
  // Euronext 유니버스(mic 포함)는 eu-universe가 소유 → route가 직접 참조(config.universe 미사용).
  { code: 'EURONEXT', param: 'euronext', rankLimit: 100, capModel: { kind: 'eu' } },
  // 중국 A주 유니버스(mic 포함)는 cn-universe가 소유 → route가 mic으로 필터(config.universe 미사용).
  { code: 'SSE',  param: 'sse',  rankLimit: 100, capModel: { kind: 'cn', mic: 'XSHG' } },
  { code: 'SZSE', param: 'szse', rankLimit: 100, capModel: { kind: 'cn', mic: 'XSHE' } },
  // NSE 유니버스는 nse-universe가 소유 → route가 직접 참조(config.universe 미사용).
  { code: 'NSE',  param: 'nse',  rankLimit: 100, capModel: { kind: 'nse' } },
  // 독일 XETRA 유니버스(단일 mic XETR)는 de-universe가 소유 → route가 직접 참조(config.universe 미사용).
  { code: 'XETRA', param: 'xetra', rankLimit: 100, capModel: { kind: 'de' } },
]

// ALL 피드: US 큐레이션(COMPANIES) + KRX 상위 몇 종목 주입 후 top-20.
export const ALL_FEED = {
  rankLimit:     20,
  tdUniverse:    COMPANIES,
  krxInjections: KOREAN_STOCKS,
}

const byParam = new Map(EXCHANGES.map(e => [e.param, e]))
export function getExchange(param: string): ExchangeConfig | undefined {
  return byParam.get(param)
}

// us-stats 갱신 대상 = ALL 피드 td 유니버스 + 모든 거래소 td 유니버스의 합집합.
// (기존 us-universe.ALL_US_TICKERS 와 동일 집합 — 단일 소스로 통합.)
export const ALL_TD_TICKERS: string[] = [
  ...new Set([
    ...ALL_FEED.tdUniverse.map(c => c.ticker),
    ...EXCHANGES
      .filter(e => e.capModel.kind === 'td')
      .flatMap(e => (e.universe ?? []).map(c => c.ticker)),
  ]),
]
