// ─── 통합 환율(FX) 레이어 ──────────────────────────────────────────────────────
//
// 앱 전체의 "유일한" 환율 진입점. 지수 섹션의 달러 환율 카드(market-index)와
// 기업 시총 원화/외화 환산(market-cap)이 모두 이 레이어만 호출한다.
//
// ▷ 데이터 소스 = Twelve Data (상업 라이선스). 1차 출시가 유료(상업) 배포이므로
//   비영리 라이선스 소스(수출입은행 KOGL·OXR 무료티어)는 표시 자체가 라이선스 리스크라
//   완전히 제거했다. 실패 시엔 외부 소스로 폴백하지 않고 last-good(직전 성공 TD 값) →
//   최종 상수 순으로만 방어한다(상수는 하드코딩 숫자라 라이선스 무관).
//   ※ TD는 이미 US 시총(quote/statistics)에 쓰는 Venture 구독을 그대로 공유한다.
//
// ▷ 표시 규약: 한국 장 시간(평일 09:00~15:30 KST)엔 60초 TTL로 실시간에 가깝게 갱신하고,
//   그 외 시간(장 마감 후·주말·공휴일)엔 마지막으로 잡은 값(≈장 마감 종가)을 그대로
//   얼려 재호출하지 않는다 → 장중만 라이브, 그 외엔 종가 고정 + API 호출 최소화.
//   캐시·last-good은 모듈 싱글턴이라 유저 수와 무관하게 세션당 ~1 credit/min만 든다.
//
// ▷ 환율 표기 규약: rate = "1 USD 당 해당 통화 금액" (KRW/USD, JPY/USD …).
//   TD forex 심볼 USD/KRW·USD/JPY … 의 close 가 정확히 이 방향이라 그대로 매핑된다.

export type Currency = 'KRW' | 'JPY' | 'CNY' | 'EUR'
export const ALL_CURRENCIES: Currency[] = ['KRW', 'JPY', 'CNY', 'EUR']

/** 환율 한 건. 카드 표시용 등락(change)까지 포함 — 제공 못 하는 소스는 0. */
export interface FxQuote {
  currency: Currency
  rate: number           // 1 USD 당 통화 금액 (KRW/USD 등)
  change: number         // 직전 종가 대비 등락 (같은 단위)
  changePercent: number
  asOf: number           // ms epoch (데이터 시각)
  source: string         // provider 이름 (디버깅/출처표기)
}

/** 데이터 소스 한 개. 지원 통화만 조회하고, 실패 시 throw 하면 서비스가 다음 소스로 폴백한다. */
export interface FxProvider {
  readonly name: string
  readonly supports: readonly Currency[]
  /** 요청 통화 중 이 소스가 채울 수 있는 것만 반환(부분 반환 허용). */
  fetch(currencies: Currency[]): Promise<Partial<Record<Currency, FxQuote>>>
}

// 모든 소스가 죽었을 때의 최종 폴백 상수 (통화당 USD 근사값). 하드코딩 숫자 → 라이선스 무관.
const FALLBACK: Record<Currency, number> = { KRW: 1450, JPY: 155, CNY: 7.2, EUR: 0.92 }

// ─── 시간대 헬퍼 (KST 벽시계) ──────────────────────────────────────────────────
// 서버(Vercel)는 UTC로 돌기 때문에 +9h 보정한 Date를 만들어 getUTC*로 읽는다.
function toKST(d: Date): Date { return new Date(d.getTime() + 9 * 3600 * 1000) }

// 한국 주식시장 정규장 세션: 평일(월~금) 09:00 ~ 15:30 KST.
// 이 창 안에서만 환율을 라이브로 갱신하고, 밖에서는 마지막 값(≈종가)을 얼린다.
// (공휴일은 서버가 알 수 없어 라이브로 취급될 수 있으나, 그날 forex가 열려 있으면 현재가를
//  보여줄 뿐이고 닫혀 있으면 TD가 같은 종가를 돌려줘 무해하다.)
function inKrTradingSession(now: number = Date.now()): boolean {
  const kst = toKST(new Date(now))
  const wd  = kst.getUTCDay()   // 0=일 … 6=토 (KST 기준)
  if (wd === 0 || wd === 6) return false
  const mins = kst.getUTCHours() * 60 + kst.getUTCMinutes()
  return mins >= 9 * 60 && mins < 15 * 60 + 30   // 540 ~ 930
}

// 장중 라이브 TTL. 세션당 ~6.5h → 60s면 ~390 credits(610/min 예산 대비 무시 가능).
const FX_LIVE_TTL_MS = 60_000

// 캐시 신선도: 장중이면 60s TTL, 장외엔 캐시가 있는 한 항상 신선(=재호출 안 함)으로 봐
// 마지막 종가를 얼린다. 장이 다시 열리면 age가 TTL을 넘겨 자연히 라이브로 복귀한다.
function isFxCacheFresh(ts: number): boolean {
  if (inKrTradingSession()) return Date.now() - ts < FX_LIVE_TTL_MS
  return true
}

function fallbackQuote(c: Currency): FxQuote {
  return { currency: c, rate: FALLBACK[c], change: 0, changePercent: 0, asOf: Date.now(), source: 'fallback' }
}

// ─── Provider: Twelve Data forex (전 통화) ─────────────────────────────────────
// /quote?symbol=USD/{CUR} — 심볼당 1 credit. close=현재가, previous_close=직전 종가,
// change/percent_change=직전 종가 대비 등락을 그대로 준다(우리 규약과 방향 일치).
// 여러 통화는 심볼별 병렬 호출(요청 통화 수 × 1 credit). v1은 KRW만 요청.
const TD_BASE = 'https://api.twelvedata.com'
const TD_SYMBOL: Record<Currency, string> = {
  KRW: 'USD/KRW',
  JPY: 'USD/JPY',
  CNY: 'USD/CNY',
  EUR: 'USD/EUR',
}

interface TdQuoteResponse {
  status?: string
  message?: string
  close?: string
  change?: string
  percent_change?: string
  timestamp?: number
  last_quote_at?: number
}

class TwelveDataFxProvider implements FxProvider {
  readonly name = 'twelvedata'
  readonly supports = ['KRW', 'JPY', 'CNY', 'EUR'] as const

  async fetch(currencies: Currency[]): Promise<Partial<Record<Currency, FxQuote>>> {
    const key = process.env.TWELVE_DATA_API_KEY ?? ''
    if (!key) return {}   // 키 미설정 → 폴백(last-good/상수)로 넘어감

    const out: Partial<Record<Currency, FxQuote>> = {}
    await Promise.all(currencies.map(async (c) => {
      try {
        const url = `${TD_BASE}/quote?symbol=${encodeURIComponent(TD_SYMBOL[c])}&apikey=${key}`
        const res = await fetch(url, { cache: 'no-store' })
        if (!res.ok) throw new Error(`Twelve Data ${c} → HTTP ${res.status}`)
        const data = (await res.json()) as TdQuoteResponse
        if (data.status === 'error') throw new Error(`Twelve Data ${c} → ${data.message}`)

        const rate = parseFloat(data.close ?? '')
        if (!Number.isFinite(rate)) throw new Error(`Twelve Data ${c} → 유효하지 않은 close`)
        const change  = parseFloat(data.change ?? '0')
        const pct     = parseFloat(data.percent_change ?? '0')
        const dataSec = data.last_quote_at ?? data.timestamp
        out[c] = {
          currency: c,
          rate,
          change:        Number.isFinite(change) ? change : 0,
          changePercent: Number.isFinite(pct) ? pct : 0,
          asOf:          dataSec ? dataSec * 1000 : Date.now(),
          source:        this.name,
        }
      } catch (err) {
        console.warn(`[fx] twelvedata ${c} 실패:`, err)   // 이 통화는 미채움 → FxService가 폴백
      }
    }))
    return out
  }
}

// ─── FxService: 조회 + 캐시 + 폴백 ──────────────────────────────────────────────
class FxService {
  private cache = new Map<Currency, { quote: FxQuote; ts: number }>()
  private lastGood = new Map<Currency, FxQuote>()

  constructor(private readonly providers: FxProvider[]) {}

  /** 요청한 모든 통화의 환율을 반환(항상 전부 채워짐 — 최악의 경우 상수 폴백). */
  async resolve(currencies: Currency[]): Promise<Record<Currency, FxQuote>> {
    const now = Date.now()
    const out: Partial<Record<Currency, FxQuote>> = {}
    const miss: Currency[] = []

    // 1) 신선한 캐시 히트는 그대로 사용 (장외엔 마지막 종가가 항상 신선 취급됨)
    for (const c of currencies) {
      const hit = this.cache.get(c)
      if (hit && isFxCacheFresh(hit.ts)) out[c] = hit.quote
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

// 단일 상업 소스(Twelve Data). 실패 시 last-good/상수로만 방어(비영리 외부 소스 폴백 없음).
export const fx = new FxService([
  new TwelveDataFxProvider(),
])

// ─── 공개 헬퍼 (라우트가 호출하는 유일한 API) ───────────────────────────────────

// 지수 섹션 "달러 환율" 카드와 기업 시총 원화 환산이 모두 이 헬퍼만 호출한다(USD/KRW + 등락).
// 다통화(JPY/CNY/EUR) 조회는 해외 거래소(JPX/SSE/…)를 1차 출시에서 제외하며 함께 제거했다.
// 상업용 소스로 확장할 때는 fx.resolve(currencies) 를 쓰는 헬퍼를 다시 추가하면 된다.
export async function getUsdKrwQuote(): Promise<FxQuote> {
  return (await fx.resolve(['KRW'])).KRW
}
