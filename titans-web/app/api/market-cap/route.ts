import { NextResponse } from 'next/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const FINNHUB_TOKEN = process.env.FINNHUB_API_KEY ?? ''
const BASE = 'https://finnhub.io/api/v1'
const OXR_APP_ID = process.env.OPEN_EXCHANGE_RATES_APP_ID ?? ''
const FOREX_FALLBACK = 1450.0

// TSM ADR: 1 ADR = 5 대만 보통주. Finnhub shareOutstanding은 보통주 수(millions)이므로
// 시총 = shareOutstanding / ADR_RATIO × ADR가격(USD) / 1_000_000 으로 실시간 계산
const TSM_ADR_RATIO = 5

// 미국 종목 시총은 라이브가로 재계산(shareOutstanding × 현재가)해 KRX(21초)와 신선도를 맞춘다.
// 단 Finnhub의 shareOutstanding이 부실한 종목(예: BRK.B=1.44M)이 있어, 라이브 재계산값이
// 사전계산 marketCapitalization과 크게 어긋나면 사전계산값으로 폴백한다.
const MCAP_LIVE_TRUST_MIN = 0.5
const MCAP_LIVE_TRUST_MAX = 2.0

const BATCH_SIZE     = 5
const BATCH_DELAY_MS = 200

// Aramco: Tadawul(사우디 증권거래소) 상장, SAR 표시가. 사우디 법정 고정환율 적용.
const ARAMCO_SAR_PER_USD = 3.75
const ARAMCO_META: CompanyMeta = { ticker: '2222.SR', name: 'Saudi Aramco', color: '#007A3D' }

const COMPANIES: CompanyMeta[] = [
  // Top 10
  { ticker: 'NVDA',  name: 'NVIDIA',       color: '#78BB17' },
  { ticker: 'AAPL',  name: 'Apple',        color: '#8E8E93' },
  { ticker: 'MSFT',  name: 'Microsoft',    color: '#0078D4' },
  { ticker: 'GOOGL', name: 'Alphabet',     color: '#EA4335' },
  { ticker: 'AMZN',  name: 'Amazon',       color: '#FF9900' },
  { ticker: 'META',  name: 'Meta',         color: '#4267B2' },
  { ticker: 'TSLA',  name: 'Tesla',        color: '#CC1C1C' },
  { ticker: 'BRK.B', name: 'Berkshire',    color: '#8B5E20' },
  { ticker: 'AVGO',  name: 'Broadcom',     color: '#CC0000' },
  { ticker: 'JPM',   name: 'JPMorgan',     color: '#005EB8' },
  // 글로벌 (ADR 포함)
  { ticker: 'TSM',   name: 'TSMC',         color: '#0073CE' },
  // 11–20위 권 (미국 상장)
  { ticker: 'LLY',   name: 'Eli Lilly',    color: '#8B5CF6' },
  { ticker: 'WMT',   name: 'Walmart',      color: '#007DC6' },
  { ticker: 'V',     name: 'Visa',         color: '#1A1F71' },
  { ticker: 'ORCL',  name: 'Oracle',       color: '#F80000' },
  { ticker: 'XOM',   name: 'ExxonMobil',   color: '#1A1A1A' },
  { ticker: 'MA',    name: 'Mastercard',   color: '#EB001B' },
  { ticker: 'COST',  name: 'Costco',       color: '#005DAA' },
  { ticker: 'NFLX',  name: 'Netflix',      color: '#E50914' },
  { ticker: 'UNH',   name: 'UnitedHealth', color: '#002677' },
  { ticker: 'PLTR',  name: 'Palantir',     color: '#101828' },
  { ticker: 'SPCX',  name: 'SpaceX',       color: '#005288' },
  { ticker: 'AMD',   name: 'AMD',          color: '#ED1C24' },
  { ticker: 'MU',    name: 'Micron',       color: '#00AEEF' },
]

// KRX(한국거래소) 상장 종목 — Yahoo Finance v7 JSON API 경유
// Finnhub 무료 플랜은 KRX 미지원
interface KoreanStockMeta {
  ticker: string
  yahooTicker: string
  name: string
  color: string
}

const KOREAN_STOCKS: KoreanStockMeta[] = [
  { ticker: '005930.KS', yahooTicker: '005930.KS', name: 'Samsung',  color: '#1428A0' },
  { ticker: '000660.KS', yahooTicker: '000660.KS', name: 'SK Hynix', color: '#EA5504' },
]

// Finnhub 무료: 60 calls/min
// Quote 5개씩 배치(200ms 딜레이), 21초 캐시 → burst rate limit 방지 ✓
// Profile 1시간 캐시 → 서버 재시작 시에만 호출                        ✓
// Forex 1개, 1분 캐시 → ~1 call/min                                 ✓
const QUOTE_TTL_MS   = 21_000
const PROFILE_TTL_MS = 3_600_000
const FOREX_TTL_MS   = 60_000

// ─── Types ───────────────────────────────────────────────────────────────────

interface CompanyMeta {
  ticker: string
  name: string
  color: string
}

interface QuoteData {
  c: number   // current price
  d: number   // change
  dp: number  // change percent
}

interface ProfileData {
  marketCapitalization: number
  shareOutstanding: number  // millions of shares (보통주 기준)
}

interface ForexRates {
  krw: number
}

interface OXRResponse {
  rates: Record<string, number>
}

interface CacheEntry<T> {
  data: T
  ts: number
}

export interface CompanyResult {
  rank: number
  ticker: string
  name: string
  color: string
  currentPrice: number
  change: number
  changePercent: number
  marketCapUSD: number  // Trillion USD
}

interface KRXQuoteData {
  price:         number
  change:        number
  changePercent: number
  marketCapKRW:  number
}

interface NaverStockBasic {
  closePrice?:                  string  // "259,000"
  compareToPreviousClosePrice?: string  // "-500" | "15,000" (하락 시에만 부호 포함)
  fluctuationsRatio?:           string  // "-0.16" | "6.15"
}

// integration 엔드포인트의 totalInfos 항목 (basic에서 marketValue 필드가 제거되어 대체)
interface NaverTotalInfo {
  code:  string  // "marketValue" 등
  key:   string  // "시총"
  value: string  // "1,514조 1,862억"
}

interface NaverStockIntegration {
  totalInfos?: NaverTotalInfo[]
}

// ─── Aramco-Specific Types ────────────────────────────────────────────────────

interface AramcoData {
  priceSAR:      number
  changeSAR:     number
  changePercent: number
  marketCapUSD:  number  // trillion USD
}

// ─── In-Memory Cache ─────────────────────────────────────────────────────────

const quoteCache      = new Map<string, CacheEntry<QuoteData>>()
const profileCache    = new Map<string, CacheEntry<ProfileData>>()
const krxQuoteCache   = new Map<string, CacheEntry<KRXQuoteData>>()
const naverKRXCache   = new Map<string, CacheEntry<KRXQuoteData>>()
let forexCache: CacheEntry<ForexRates> | null = null
let aramcoDataCache: CacheEntry<AramcoData> | null = null

// 실패 시 Yahoo Finance에 폭격 방지 — 마지막 실패로부터 60초 쿨다운
const ARAMCO_ERROR_COOLDOWN_MS = 60_000
let aramcoErrorUntil = 0

// 개별 종목 실패 시 stale 데이터 유지용 (목록 flickering 방지)
const krxLastGoodCache     = new Map<string, KRXQuoteData>()
const finnhubLastGoodCache = new Map<string, Omit<CompanyResult, 'rank'>>()

let lastGoodResult: CompanyResult[] | null = null
let lastGoodAt = 0
let lastGoodExchangeRate = FOREX_FALLBACK

// ─── Batch Utility ───────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function mapInBatches<T, R>(
  items: T[],
  batchSize: number,
  delayMs: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = []
  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize)
    results.push(...(await Promise.all(batch.map(fn))))
    if (i + batchSize < items.length) await sleep(delayMs)
  }
  return results
}

// ─── Common Yahoo Finance Headers ─────────────────────────────────────────────

const YF_HTML_HEADERS = {
  'User-Agent':      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
}

// ─── Finnhub Fetchers ─────────────────────────────────────────────────────────

async function getQuote(ticker: string): Promise<QuoteData> {
  const hit = quoteCache.get(ticker)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const res = await fetch(
    `${BASE}/quote?symbol=${encodeURIComponent(ticker)}&token=${FINNHUB_TOKEN}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`quote ${ticker} → HTTP ${res.status}`)
  const data: QuoteData = await res.json()
  if (!data.c) throw new Error(`quote ${ticker} → empty response`)
  quoteCache.set(ticker, { data, ts: Date.now() })
  return data
}

async function getProfile(ticker: string): Promise<ProfileData> {
  const hit = profileCache.get(ticker)
  if (hit && Date.now() - hit.ts < PROFILE_TTL_MS) return hit.data

  const res = await fetch(
    `${BASE}/stock/profile2?symbol=${encodeURIComponent(ticker)}&token=${FINNHUB_TOKEN}`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`profile ${ticker} → HTTP ${res.status}`)
  const data: ProfileData = await res.json()
  if (!data.marketCapitalization) throw new Error(`profile ${ticker} → marketCapitalization missing`)
  profileCache.set(ticker, { data, ts: Date.now() })
  return data
}

async function getForexRates(): Promise<ForexRates> {
  if (forexCache && Date.now() - forexCache.ts < FOREX_TTL_MS) return forexCache.data

  const res = await fetch(
    `https://openexchangerates.org/api/latest.json?app_id=${OXR_APP_ID}&symbols=KRW`,
    { cache: 'no-store' },
  )
  if (!res.ok) throw new Error(`forex rates → HTTP ${res.status}`)
  const data: OXRResponse = await res.json()
  const krw = data.rates?.KRW
  if (!krw || !isFinite(krw)) throw new Error('forex KRW rate missing or invalid')
  const rates = { krw }
  forexCache = { data: rates, ts: Date.now() }
  return rates
}

// ─── KRX (한국거래소) Fetcher — Yahoo Finance HTML 파싱 ───────────────────────
// Yahoo Finance v7/v8 JSON API는 crumb 인증 필요(429) → Aramco와 동일하게
// finance.yahoo.com HTML 페이지 내 SSR 임베드 JSON에서 직접 파싱.
// marketCap 필드는 KRW 단위 → forexRates.krw(KRW/USD)로 나눠 USD 환산.

async function getKRXQuote(yahooTicker: string): Promise<KRXQuoteData> {
  const cached = krxQuoteCache.get(yahooTicker)
  if (cached && Date.now() - cached.ts < QUOTE_TTL_MS) return cached.data

  try {
    const res = await fetch(
      `https://finance.yahoo.com/quote/${encodeURIComponent(yahooTicker)}/`,
      { headers: YF_HTML_HEADERS, redirect: 'follow', cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`KRX HTML ${yahooTicker} → HTTP ${res.status}`)

    const html = await res.text()
    const scriptRe = /<script[^>]*>(.*?)<\/script>/gs
    let match: RegExpExecArray | null

    while ((match = scriptRe.exec(html)) !== null) {
      const content = match[1]
      if (!content.includes('quoteResponse')) continue
      try {
        const outer = JSON.parse(content)

        // Case 1: quoteResponse가 body 문자열 내부에 중첩된 경우
        let result: any = null
        if (typeof outer.body === 'string') {
          const body = JSON.parse(outer.body)
          result = body?.quoteResponse?.result?.[0]
        }
        // Case 2: quoteResponse가 최상위에 있는 경우
        if (!result) result = outer?.quoteResponse?.result?.[0]
        if (!result) continue

        // 다른 종목 데이터를 잘못 파싱하지 않도록 심볼 검증
        if (result.symbol && result.symbol !== yahooTicker) continue

        const price         = (result.regularMarketPrice?.raw ?? result.regularMarketOpen?.raw ?? 0) as number
        const change        = (result.regularMarketChange?.raw ?? 0) as number
        const changePercent = (result.regularMarketChangePercent?.raw ?? 0) as number
        const marketCapKRW  = (result.marketCap?.raw ?? 0) as number
        if (!price || !marketCapKRW) continue

        const data: KRXQuoteData = { price, change, changePercent, marketCapKRW }
        krxQuoteCache.set(yahooTicker, { data, ts: Date.now() })
        krxLastGoodCache.set(yahooTicker, data)
        return data
      } catch { continue }
    }
    throw new Error(`KRX HTML ${yahooTicker} → quote data not found in page scripts`)
  } catch (err) {
    // Stale 캐시가 있으면 실패해도 이전 데이터 유지 (목록 안정성)
    const stale = krxLastGoodCache.get(yahooTicker) ?? cached?.data
    if (stale) {
      console.warn(`[market-cap] KRX ${yahooTicker} fetch failed, using stale cache`)
      return stale
    }
    throw err
  }
}

// ─── Naver Finance KRX Fetcher ────────────────────────────────────────────────
// Yahoo Finance HTML 스크래핑 대체: Naver Finance 모바일 API
// 인증 불필요, KRX 전용, JSON 직접 반환 → 파싱 오류 없음

// Naver 한국식 시총 표기("1,514조 1,862억")를 KRW 숫자로 변환
// 조 = 10^12, 억 = 10^8. 둘 중 하나만 있는 경우도 처리.
function parseKoreanMarketCap(s: string): number {
  const jo  = s.match(/([\d,]+)\s*조/)
  const eok = s.match(/([\d,]+)\s*억/)
  let total = 0
  if (jo)  total += parseFloat(jo[1].replace(/,/g, ''))  * 1_000_000_000_000
  if (eok) total += parseFloat(eok[1].replace(/,/g, '')) * 100_000_000
  return total
}

async function getNaverKRXQuote(naverCode: string): Promise<KRXQuoteData> {
  const cached = naverKRXCache.get(naverCode)
  if (cached && Date.now() - cached.ts < QUOTE_TTL_MS) return cached.data

  const headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
    'Referer':    'https://m.stock.naver.com/',
  }

  // basic: 현재가/등락 · integration: 시가총액(basic에서 제거되어 별도 호출)
  const [basicRes, integrationRes] = await Promise.all([
    fetch(`https://m.stock.naver.com/api/stock/${naverCode}/basic`,       { headers, cache: 'no-store' }),
    fetch(`https://m.stock.naver.com/api/stock/${naverCode}/integration`, { headers, cache: 'no-store' }),
  ])
  if (!basicRes.ok)       throw new Error(`Naver basic ${naverCode} → HTTP ${basicRes.status}`)
  if (!integrationRes.ok) throw new Error(`Naver integration ${naverCode} → HTTP ${integrationRes.status}`)

  const basic:       NaverStockBasic       = await basicRes.json()
  const integration: NaverStockIntegration = await integrationRes.json()

  const price         = parseFloat((basic.closePrice                  ?? '').replace(/,/g, ''))
  const change        = parseFloat((basic.compareToPreviousClosePrice ?? '0').replace(/,/g, ''))
  const changePercent = parseFloat( basic.fluctuationsRatio           ?? '0')

  const marketCapRaw = integration.totalInfos?.find(i => i.code === 'marketValue')?.value ?? ''
  const marketCapKRW = parseKoreanMarketCap(marketCapRaw)

  if (!price || !marketCapKRW) throw new Error(`Naver ${naverCode} → invalid data (price=${price}, mcap=${marketCapKRW})`)

  const data: KRXQuoteData = { price, change, changePercent, marketCapKRW }
  naverKRXCache.set(naverCode, { data, ts: Date.now() })
  return data
}

async function getKRXResult(
  meta: KoreanStockMeta,
  krwPerUsd: number,
): Promise<Omit<CompanyResult, 'rank'>> {
  // Naver Finance 1차 시도 → Yahoo Finance fallback
  // Yahoo Finance HTML 스크래핑은 .KS 종목 응답 구조 변경으로 불안정
  const naverCode = meta.ticker.replace('.KS', '')
  let data: KRXQuoteData
  try {
    data = await getNaverKRXQuote(naverCode)
  } catch (naverErr) {
    console.warn(`[market-cap] Naver ${naverCode} failed, trying Yahoo:`, naverErr)
    data = await getKRXQuote(meta.yahooTicker)
  }
  if (!data.marketCapKRW) throw new Error(`KRX ${meta.ticker} → marketCap missing`)
  return {
    ticker:        meta.ticker,
    name:          meta.name,
    color:         meta.color,
    currentPrice:  data.price,
    change:        data.change,
    changePercent: data.changePercent,
    marketCapUSD:  data.marketCapKRW / krwPerUsd / 1_000_000_000_000,
  }
}

// ─── Aramco Fetcher (Yahoo Finance HTML 파싱) ─────────────────────────────────

async function getAramcoData(): Promise<AramcoData> {
  if (aramcoDataCache && Date.now() - aramcoDataCache.ts < QUOTE_TTL_MS) return aramcoDataCache.data

  // 쿨다운 중에는 stale 캐시 반환 (Yahoo Finance 폭격 방지)
  if (Date.now() < aramcoErrorUntil) {
    if (aramcoDataCache) return aramcoDataCache.data
    throw new Error('Aramco cooldown active, no cached data')
  }

  try {
    const res = await fetch('https://finance.yahoo.com/quote/2222.SR/', {
      headers: YF_HTML_HEADERS,
      redirect: 'follow',
      cache: 'no-store',
    })
    if (!res.ok) throw new Error(`Aramco HTML → HTTP ${res.status}`)

    const html = await res.text()
    const scriptRe = /<script[^>]*>(.*?)<\/script>/gs
    let match: RegExpExecArray | null
    while ((match = scriptRe.exec(html)) !== null) {
      const content = match[1]
      if (!content.includes('2222.SR') || !content.includes('quoteResponse')) continue
      try {
        const outer = JSON.parse(content)
        if (typeof outer.body !== 'string') continue
        const body = JSON.parse(outer.body)
        const result = body?.quoteResponse?.result?.[0]
        if (result?.symbol !== '2222.SR') continue

        const priceSAR      = (result.regularMarketPrice?.raw ?? result.regularMarketOpen?.raw ?? 0) as number
        const changeSAR     = (result.regularMarketChange?.raw ?? 0) as number
        const changePercent = (result.regularMarketChangePercent?.raw ?? 0) as number
        const marketCapSAR  = (result.marketCap?.raw ?? 0) as number
        if (!priceSAR || !marketCapSAR) continue

        const data: AramcoData = {
          priceSAR,
          changeSAR,
          changePercent,
          marketCapUSD: marketCapSAR / ARAMCO_SAR_PER_USD / 1_000_000_000_000,
        }
        aramcoDataCache = { data, ts: Date.now() }
        aramcoErrorUntil = 0
        return data
      } catch { continue }
    }
    throw new Error('Aramco HTML → quote data not found in page scripts')
  } catch (err) {
    aramcoErrorUntil = Date.now() + ARAMCO_ERROR_COOLDOWN_MS
    // Stale 캐시가 있으면 실패해도 이전 데이터 유지
    if (aramcoDataCache) {
      console.warn('[market-cap] Aramco fetch failed, using stale cache:', err)
      return aramcoDataCache.data
    }
    throw err
  }
}

async function getAramcoResult(): Promise<Omit<CompanyResult, 'rank'>> {
  const data = await getAramcoData()
  return {
    ticker:        ARAMCO_META.ticker,
    name:          ARAMCO_META.name,
    color:         ARAMCO_META.color,
    currentPrice:  data.priceSAR,
    change:        data.changeSAR,
    changePercent: data.changePercent,
    marketCapUSD:  data.marketCapUSD,
  }
}

// ─── Route Handler ────────────────────────────────────────────────────────────

export async function GET() {
  try {
    if (!FINNHUB_TOKEN) {
      throw new Error('FINNHUB_API_KEY 환경 변수가 설정되지 않았습니다.')
    }

    const forexRates = await getForexRates().catch((err) => {
      console.warn('[market-cap] forex fetch failed, using fallback:', err)
      return { krw: lastGoodExchangeRate }
    })

    // Finnhub 배치, Aramco(Yahoo HTML), KRX(Yahoo JSON) 병렬 실행
    // 개별 종목 실패는 null로 처리 — 한 종목 장애가 전체를 막지 않도록
    const finnhubTask = mapInBatches(
      COMPANIES,
      BATCH_SIZE,
      BATCH_DELAY_MS,
      async (co): Promise<Omit<CompanyResult, 'rank'> | null> => {
        try {
          const [quote, profile] = await Promise.all([
            getQuote(co.ticker),
            getProfile(co.ticker),
          ])
          let marketCapUSD: number
          if (co.ticker === 'TSM') {
            marketCapUSD = profile.shareOutstanding / TSM_ADR_RATIO * quote.c / 1_000_000
          } else {
            const precomputed = profile.marketCapitalization / 1_000_000
            const live        = profile.shareOutstanding * quote.c / 1_000_000
            const ratio       = precomputed > 0 ? live / precomputed : 0
            // shareOutstanding이 신뢰 가능한 범위면 라이브가로 재계산, 아니면 사전계산값 폴백
            marketCapUSD = ratio >= MCAP_LIVE_TRUST_MIN && ratio <= MCAP_LIVE_TRUST_MAX
              ? live
              : precomputed
          }
          const result: Omit<CompanyResult, 'rank'> = {
            ticker:        co.ticker,
            name:          co.name,
            color:         co.color,
            currentPrice:  quote.c,
            change:        quote.d,
            changePercent: quote.dp,
            marketCapUSD,
          }
          finnhubLastGoodCache.set(co.ticker, result)
          return result
        } catch (err) {
          const stale = finnhubLastGoodCache.get(co.ticker)
          if (stale) {
            console.warn(`[market-cap] ${co.ticker} failed, using stale data:`, err)
            return stale
          }
          console.warn(`[market-cap] ${co.ticker} failed, skipping:`, err)
          return null
        }
      },
    )

    const aramcoTask = getAramcoResult().catch((err) => {
      console.warn('[market-cap] Aramco fetch failed, skipping:', err)
      return null
    })

    const krxTask = Promise.all(
      KOREAN_STOCKS.map(meta =>
        getKRXResult(meta, forexRates.krw).catch((err) => {
          console.warn(`[market-cap] KRX ${meta.ticker} failed, skipping:`, err)
          return null
        }),
      ),
    )

    const [finnhubRows, aramcoResult, krxResults] = await Promise.all([
      finnhubTask,
      aramcoTask,
      krxTask,
    ])

    const allRows = [
      ...finnhubRows,
      aramcoResult,
      ...krxResults,
    ].filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked: CompanyResult[] = allRows
      .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
      .slice(0, 20)
      .map((r, i) => ({ ...r, rank: i + 1 }))

    lastGoodResult = ranked
    lastGoodAt = Date.now()
    lastGoodExchangeRate = forexRates.krw

    return NextResponse.json({ exchangeRate: forexRates.krw, data: ranked, updatedAt: lastGoodAt, stale: false })
  } catch (err) {
    console.error('[market-cap] fetch error:', err)

    if (lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: lastGoodResult, updatedAt: lastGoodAt, stale: true },
        { status: 200 },
      )
    }

    return NextResponse.json(
      { error: String(err) },
      { status: 503 },
    )
  }
}
