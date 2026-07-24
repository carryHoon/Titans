// ─── 통합 환율(FX) 레이어 ──────────────────────────────────────────────────────
//
// 앱 전체의 "유일한" 환율 진입점. 지수 섹션의 달러 환율 카드(market-index)와
// 기업 시총 원화/외화 환산(market-cap)이 모두 이 레이어만 호출한다.
//
// ▷ Provider 추상화: 데이터 소스마다 FxProvider 를 구현해 providers 배열에 등록한다.
//   통화별로 우선순위대로 조회하고, 실패/미지원이면 다음 provider로 폴백한다.
//   → 유료 구독 플랫폼(EODHD 등)으로 전환할 때는 EodhdFxProvider 하나를 만들어
//     providers 배열 "맨 앞"에 넣기만 하면 전 통화가 그쪽으로 넘어가고,
//     기존 Eximbank/OXR은 자동 폴백으로 남는다. (라우트 코드는 손대지 않음)
//
// ▷ 환율 표기 규약: rate = "1 USD 당 해당 통화 금액" (KRW/USD, JPY/USD …).
//   Eximbank 매매기준율·OXR latest.json 모두 이 방향이라 그대로 호환된다.
//
// ▷ 캐시: 통화별 1시간 TTL + last-good carry-forward + 최종 상수 폴백.
//   호출 제한(Eximbank 1,000/일, OXR 1,000/월) 보호 + 소스 장애 시 목록 안정성 확보.

export type Currency = 'KRW' | 'JPY' | 'CNY' | 'EUR'
export const ALL_CURRENCIES: Currency[] = ['KRW', 'JPY', 'CNY', 'EUR']

/** 환율 한 건. 카드 표시용 등락(change)까지 포함 — 제공 못 하는 소스는 0. */
export interface FxQuote {
  currency: Currency
  rate: number           // 1 USD 당 통화 금액 (KRW/USD 등)
  change: number         // 직전 기준 대비 등락 (같은 단위)
  changePercent: number
  asOf: number           // ms epoch
  source: string         // provider 이름 (디버깅/출처표기)
}

/** 데이터 소스 한 개. 지원 통화만 조회하고, 실패 시 throw 하면 서비스가 다음 소스로 폴백한다. */
export interface FxProvider {
  readonly name: string
  readonly supports: readonly Currency[]
  /** 요청 통화 중 이 소스가 채울 수 있는 것만 반환(부분 반환 허용). */
  fetch(currencies: Currency[]): Promise<Partial<Record<Currency, FxQuote>>>
}

// 모든 소스가 죽었을 때의 최종 폴백 상수 (통화당 USD 근사값).
const FALLBACK: Record<Currency, number> = { KRW: 1450, JPY: 155, CNY: 7.2, EUR: 0.92 }
const FX_TTL_MS = 60 * 60 * 1000   // 통화별 캐시 1시간

function fallbackQuote(c: Currency): FxQuote {
  return { currency: c, rate: FALLBACK[c], change: 0, changePercent: 0, asOf: Date.now(), source: 'fallback' }
}

// ─── Provider 1: 한국수출입은행 (KRW 공식 매매기준율) ──────────────────────────────
// 신규 도메인(2025.6.25~). data=AP01(환율), searchdate=YYYYMMDD(영업일).
// 영업일 11시경 1회 갱신 + 주말/공휴일엔 데이터 없음 → 최근 영업일까지 소급 조회한다.
// deal_bas_r = 매매기준율(콤마 포함 문자열). 등락은 직전 영업일 대비로 계산.
const EXIM_URL = 'https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON'

interface EximRow { result: number; cur_unit: string; deal_bas_r: string }

// KST(UTC+9) 벽시계 기준 날짜. 서버(Vercel)는 UTC로 돌기 때문에 보정한다.
function toKST(d: Date): Date { return new Date(d.getTime() + 9 * 3600 * 1000) }
function ymd(kst: Date): string {
  const y = kst.getUTCFullYear()
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0')
  const day = String(kst.getUTCDate()).padStart(2, '0')
  return `${y}${m}${day}`
}

async function eximUsdRate(key: string, dateStr: string): Promise<number | null> {
  const url = `${EXIM_URL}?authkey=${key}&searchdate=${dateStr}&data=AP01`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`Eximbank → HTTP ${res.status}`)
  const rows: unknown = await res.json()
  if (!Array.isArray(rows)) return null   // 주말/공휴일/장전 → 빈 응답
  const usd = (rows as EximRow[]).find(r => r.cur_unit === 'USD' && r.result === 1)
  if (!usd) return null
  const rate = parseFloat(usd.deal_bas_r.replace(/,/g, ''))
  return Number.isFinite(rate) ? rate : null
}

// fromKST부터 과거로 최대 maxDays일 소급하며 첫 유효 환율을 찾는다(주말/공휴일 대응).
async function walkBackRate(key: string, fromKST: Date, maxDays: number): Promise<{ rate: number; day: Date } | null> {
  const d = new Date(fromKST)
  for (let i = 0; i < maxDays; i++) {
    const rate = await eximUsdRate(key, ymd(d))
    if (rate != null) return { rate, day: new Date(d) }
    d.setUTCDate(d.getUTCDate() - 1)
  }
  return null
}

class EximbankProvider implements FxProvider {
  readonly name = 'koreaexim'
  readonly supports = ['KRW'] as const

  async fetch(currencies: Currency[]): Promise<Partial<Record<Currency, FxQuote>>> {
    if (!currencies.includes('KRW')) return {}
    const key = process.env.KOREAEXIM_API_KEY ?? ''
    if (!key) return {}   // 키 미설정 → 다음 provider(OXR)로 폴백

    const latest = await walkBackRate(key, toKST(new Date()), 7)
    if (!latest) throw new Error('Eximbank USD 환율 데이터 없음')

    // 직전 영업일 환율로 등락 계산
    const prevStart = new Date(latest.day)
    prevStart.setUTCDate(prevStart.getUTCDate() - 1)
    const prev = await walkBackRate(key, prevStart, 7)
    const prevRate = prev?.rate ?? latest.rate
    const change = latest.rate - prevRate

    return {
      KRW: {
        currency: 'KRW',
        rate: latest.rate,
        change,
        changePercent: prevRate !== 0 ? (change / prevRate) * 100 : 0,
        asOf: Date.now(),
        source: this.name,
      },
    }
  }
}

// ─── Provider 2: Open Exchange Rates (KRW/JPY/CNY/EUR) ─────────────────────────
// 무료 250콜/일·1,000콜/월. base=USD 고정, latest.json 한 번에 전 통화 반환.
// 등락(change) 미제공 → 0. (JPX/SSE/SZSE/Euronext 시총 환산엔 등락 불필요)
class OxrProvider implements FxProvider {
  readonly name = 'openexchangerates'
  readonly supports = ['KRW', 'JPY', 'CNY', 'EUR'] as const

  async fetch(currencies: Currency[]): Promise<Partial<Record<Currency, FxQuote>>> {
    const appId = process.env.OPEN_EXCHANGE_RATES_APP_ID ?? ''
    if (!appId) return {}

    const res = await fetch(
      `https://openexchangerates.org/api/latest.json?app_id=${appId}&symbols=KRW,JPY,CNY,EUR`,
      { cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`OXR → HTTP ${res.status}`)
    const data = (await res.json()) as { rates?: Record<string, number> }

    const now = Date.now()
    const out: Partial<Record<Currency, FxQuote>> = {}
    for (const c of currencies) {
      const r = data.rates?.[c]
      if (r && Number.isFinite(r)) {
        out[c] = { currency: c, rate: r, change: 0, changePercent: 0, asOf: now, source: this.name }
      }
    }
    return out
  }
}

// ─── (예시) Provider N: 유료 구독 플랫폼 ────────────────────────────────────────
// 유료 전환 시 아래처럼 구현해 providers 배열 "맨 앞"에 추가하면 전 통화가 이쪽으로 넘어가고
// Eximbank/OXR은 자동 폴백으로 남는다. 라우트 코드는 전혀 손대지 않는다.
//
// class EodhdFxProvider implements FxProvider {
//   readonly name = 'eodhd'
//   readonly supports = ['KRW', 'JPY', 'CNY', 'EUR'] as const
//   async fetch(currencies: Currency[]): Promise<Partial<Record<Currency, FxQuote>>> {
//     const key = process.env.EODHD_API_KEY ?? ''
//     if (!key) return {}
//     // EODHD real-time FX (예: KRW.FOREX) 조회 → FxQuote 매핑
//     ...
//   }
// }

// ─── FxService: 우선순위 조회 + 캐시 + 폴백 ─────────────────────────────────────
class FxService {
  private cache = new Map<Currency, { quote: FxQuote; ts: number }>()
  private lastGood = new Map<Currency, FxQuote>()

  constructor(private readonly providers: FxProvider[]) {}

  /** 요청한 모든 통화의 환율을 반환(항상 전부 채워짐 — 최악의 경우 상수 폴백). */
  async resolve(currencies: Currency[]): Promise<Record<Currency, FxQuote>> {
    const now = Date.now()
    const out: Partial<Record<Currency, FxQuote>> = {}
    const miss: Currency[] = []

    // 1) 신선한 캐시 히트는 그대로 사용
    for (const c of currencies) {
      const hit = this.cache.get(c)
      if (hit && now - hit.ts < FX_TTL_MS) out[c] = hit.quote
      else miss.push(c)
    }

    // 2) 우선순위대로 provider 조회 — 각 통화는 먼저 성공한 소스가 채운다
    for (const p of this.providers) {
      const want = miss.filter(c => p.supports.includes(c) && !out[c])
      if (want.length === 0) continue
      try {
        const quotes = await p.fetch(want)
        for (const c of want) {
          const q = quotes[c]
          if (q) {
            out[c] = q
            this.cache.set(c, { quote: q, ts: now })
            this.lastGood.set(c, q)
          }
        }
      } catch (err) {
        console.warn(`[fx] provider "${p.name}" failed:`, err)
      }
    }

    // 3) 남은 통화는 last-good(stale) → 최종 상수 폴백
    for (const c of currencies) {
      if (!out[c]) out[c] = this.lastGood.get(c) ?? fallbackQuote(c)
    }
    return out as Record<Currency, FxQuote>
  }
}

// 우선순위: KRW는 수출입은행(공식) 우선, 나머지 통화는 OXR. 유료 전환 시 맨 앞에 EODHD 추가.
export const fx = new FxService([
  new EximbankProvider(),
  new OxrProvider(),
  // new EodhdFxProvider(),   // ← 유료 구독 시 이 줄만 추가하면 전 통화가 EODHD로 전환됨
])

// ─── 공개 헬퍼 (라우트가 호출하는 유일한 API) ───────────────────────────────────

// 지수 섹션 "달러 환율" 카드와 기업 시총 원화 환산이 모두 이 헬퍼만 호출한다(USD/KRW + 등락).
// 다통화(JPY/CNY/EUR) 조회는 해외 거래소(JPX/SSE/…)를 1차 출시에서 제외하며 함께 제거했다.
// 상업용 소스로 확장할 때는 fx.resolve(currencies) 를 쓰는 헬퍼를 다시 추가하면 된다.
export async function getUsdKrwQuote(): Promise<FxQuote> {
  return (await fx.resolve(['KRW'])).KRW
}
