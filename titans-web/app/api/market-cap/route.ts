import { NextResponse } from 'next/server'
import { getUsdKrwQuote, getFxRates, type Currency } from '@/lib/fx'
import { getKrxDataset, startKrPoller } from '@/lib/kr-snapshot'
import { getJpxDataset, getJpxAsOfDate, startJpxStatsWarm } from '@/lib/jpx-snapshot'
import { getEuStats, startEuStatsWarm } from '@/lib/eu-snapshot'
import { EU_COMPANIES } from '@/lib/eu-universe'
import { getCnStats, startCnStatsWarm } from '@/lib/cn-snapshot'
import { CN_COMPANIES } from '@/lib/cn-universe'
import { getNseStats, startNseStatsWarm } from '@/lib/nse-snapshot'
import { NSE_COMPANIES, NSE_MIC } from '@/lib/nse-universe'
import { getDeStats, startDeStatsWarm } from '@/lib/de-snapshot'
import { DE_COMPANIES, DE_MIC } from '@/lib/de-universe'
import { getUsStats, startUsStatsWarm } from '@/lib/us-stats'
import { ADR_SHARE_OUTSTANDING_M, type CompanyMeta } from '@/lib/us-universe'
import {
  EXCHANGES,
  ALL_FEED,
  getExchange,
  KRX_META,
  KRX_DEFAULT_COLOR,
  type ExchangeConfig,
  type KoreanStockMeta,
} from '@/lib/exchanges'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// KR 스냅샷 폴러 기동 (market-cap / market-index 공유 싱글턴)
startKrPoller()
// US stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startUsStatsWarm()
// JPX stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startJpxStatsWarm()
// Euronext stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startEuStatsWarm()
// 중국 A주 stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startCnStatsWarm()
// 인도 NSE stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startNseStatsWarm()
// 독일 FWB stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startDeStatsWarm()

// ─── Twelve Data (quote 전용) ──────────────────────────────────────────────────
// Venture 플랜: 610 credits/min. 이 라우트(유저 경로)는 /quote(1 credit/종목, 20s TTL)만 쓴다.
// 시총 기준값(/statistics)은 lib/us-stats 스냅샷 레이어가 마감 후 1회 갱신 → 유저 경로는 read만.
// ⇒ 정상 운용 ~80 credits/min, 유저 요청이 stats fetch 지연·버스트를 절대 떠안지 않는다.

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'

// ─── 거래소 정의 ────────────────────────────────────────────────────────────────
// 유니버스·시세·시총·주입·표시메타는 전부 lib/exchanges 의 EXCHANGES / ALL_FEED config가 소유한다.
// 거래소 추가는 이 라우트가 아니라 config에 항목을 더하는 것으로 이뤄진다.

// ─── Types ───────────────────────────────────────────────────────────────────

interface QuoteData {
  c:  number  // current price
  d:  number  // change
  dp: number  // change percent
  pc: number  // previous close — 시총 라이브 스케일링(stats × c/pc)에 사용
}

interface CacheEntry<T> {
  data: T
  ts:   number
}

export interface CompanyResult {
  rank:            number
  previousRank?:   number  // 전일 종가 기준 순위 (US 계산; KR은 클라이언트가 basDt로 계산)
  ticker:          string
  name:            string
  color:           string
  currentPrice:    number
  change:          number
  changePercent:   number
  marketCapUSD:    number  // trillion USD — 라이브 시총(랭킹 기준)
  prevCloseCapUSD: number  // trillion USD — 전일 종가 기준 시총(previousRank 계산용). 응답엔 포함되나 클라이언트는 무시.
  domain?:         string  // 홈페이지 도메인 (KRX 종목 로고 폴백용)
}

// ─── In-Memory Caches ─────────────────────────────────────────────────────────

// 60s: NASDAQ/NYSE top-100 확장으로 활성 티커 합집합이 커져도 읽기 크레딧을 예산 내로 유지.
// (분당 크레딧 = 합집합 × 60/TTL초 → 60s면 합집합~230이 ~230/min, Venture 610 대비 여유.)
const QUOTE_TTL_MS = 60_000

const quoteCache    = new Map<string, CacheEntry<QuoteData>>()
const quoteInFlight = new Map<string, Promise<QuoteData>>()

// 종목별 마지막 성공 데이터. 레이트리밋 등 일시 실패 시 stale 데이터로 빈자리 없이 유지.
const lastGoodCompanyCache = new Map<string, Omit<CompanyResult, 'rank'>>()

let lastGoodResult: CompanyResult[] | null = null
let lastGoodAt               = 0
let lastGoodExchangeRate      = 1450.0  // KRW/USD 초기값 (최후 방어선)

interface ExchangeFeedState {
  lastGoodResult: CompanyResult[] | null
  lastGoodAt:     number
  lastBasDt?:     string          // KRX 기준일(YYYYMMDD)
  lastAsOf?:      string | null   // EOD 계열(JPX/CN/NSE/EU/DE) 스냅샷 거래일(YYYY-MM-DD) — 앱 기준일 표기용
}
// 거래소별 마지막 성공 피드 상태. EXCHANGES config에서 자동 생성 → 거래소 추가 시 여기 수정 불필요.
const exchangeFeeds: Record<string, ExchangeFeedState> = Object.fromEntries(
  EXCHANGES.map(e => [e.code, { lastGoodResult: null, lastGoodAt: 0 } as ExchangeFeedState]),
)

// ─── Twelve Data Fetchers (quote 전용) ─────────────────────────────────────────

// micCode 지정 시 심볼을 mic_code로 특정(Euronext 등 다중거래소 심볼 충돌 방지). 캐시 키에도 반영.
async function getQuote(ticker: string, micCode?: string): Promise<QuoteData> {
  const key = micCode ? `${ticker}:${micCode}` : ticker
  const hit = quoteCache.get(key)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const pending = quoteInFlight.get(key)
  if (pending) return pending

  const task = (async (): Promise<QuoteData> => {
    const micParam = micCode ? `&mic_code=${micCode}` : ''
    const res = await fetch(
      `${TD_BASE}/quote?symbol=${encodeURIComponent(ticker)}${micParam}&apikey=${TWELVE_DATA_KEY}`,
      { cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`quote ${key} → HTTP ${res.status}`)
    const data = await res.json()
    if (data.status === 'error') throw new Error(`quote ${key} → ${data.message}`)
    const q: QuoteData = {
      c:  parseFloat(data.close),
      d:  parseFloat(data.change),
      dp: parseFloat(data.percent_change),
      pc: parseFloat(data.previous_close),
    }
    if (!q.c || !isFinite(q.c)) throw new Error(`quote ${key} → 유효하지 않은 응답`)
    quoteCache.set(key, { data: q, ts: Date.now() })
    return q
  })().finally(() => quoteInFlight.delete(key))

  quoteInFlight.set(key, task)
  return task
}

// ─── FX ──────────────────────────────────────────────────────────────────────

async function getKrwRate(): Promise<number> {
  try {
    return (await getUsdKrwQuote()).rate
  } catch {
    return lastGoodExchangeRate
  }
}

// 다통화 표시용 rate 맵({KRW,JPY,CNY,EUR}). fx 레이어가 통화별 캐시·상수폴백을 하므로 항상 채워진다.
// KRW는 위 getKrwRate와 동일 fx 캐시를 공유(중복 호출해도 캐시 히트). 전체 실패 시 KRW만이라도 채워 반환.
async function getFxRateMap(krwFallback: number): Promise<Record<Currency, number>> {
  try {
    return await getFxRates()
  } catch {
    return { KRW: krwFallback, JPY: 155, CNY: 7.2, EUR: 0.92, INR: 83 }
  }
}

// ─── KRX — 스냅샷 레이어 조회 ─────────────────────────────────────────────────

async function getKRXResult(
  meta: KoreanStockMeta,
  krwPerUsd: number,
): Promise<Omit<CompanyResult, 'rank'>> {
  const code = meta.ticker.replace(/\.(KS|KQ)$/, '')
  const ds   = await getKrxDataset()
  const row  = ds.byCode.get(code)
  if (!row || !row.marketCapKRW) throw new Error(`KRX ${meta.ticker} → marketCap 없음`)
  const capT = row.marketCapKRW / krwPerUsd / 1_000_000_000_000
  return {
    ticker:          meta.ticker,
    name:            meta.name,
    color:           meta.color,
    currentPrice:    row.price,
    change:          row.change,
    changePercent:   row.changePercent,
    marketCapUSD:    capT,
    prevCloseCapUSD: capT,  // KR은 EOD(D-1) — 장중 변동 없음. ALL 피드 상대순위 비교용으로만 사용.
  }
}

// ─── 종목 행 생성 (ALL / NASDAQ / NYSE 공통) ──────────────────────────────────
// 시총 = stats 기준값(us-stats 스냅샷) × (현재가 / 전일종가) 라이브 스케일링.
// ADR(TSM·HSBC): 하드코딩된 발행주수 × ADR가격으로 직접 계산(stats 사용 안 함).
// quote 실패 시: 만료 캐시 → lastGoodCompanyCache(직전 성공) 순으로 폴백.

async function fetchRows(
  companies: CompanyMeta[],
): Promise<(Omit<CompanyResult, 'rank'> | null)[]> {
  // stats 기준값은 스냅샷(크론이 마감 후 1회 갱신)에서 read — 유저 경로는 업스트림 호출 없음.
  const stats = await getUsStats()

  const quotes = await Promise.all(
    companies.map(async (co): Promise<QuoteData | null> => {
      try { return await getQuote(co.ticker) }
      catch { return quoteCache.get(co.ticker)?.data ?? null }  // 만료 캐시 폴백
    }),
  )

  return companies.map((co, i): Omit<CompanyResult, 'rank'> | null => {
    const quote  = quotes[i]
    const tdCapT = stats[co.ticker]

    if (!quote && tdCapT == null) return lastGoodCompanyCache.get(co.ticker) ?? null

    const adrShares = ADR_SHARE_OUTSTANDING_M[co.ticker]
    let marketCapUSD:    number  // 라이브 시총(현재가 기준)
    let prevCloseCapUSD: number  // 전일 종가 기준 시총(previousRank 계산용)

    if (adrShares) {
      // ADR: 발행주수(M) × 가격(USD) / 1M → 시총(T USD). 라이브=현재가, 전일=전일종가.
      marketCapUSD    = quote ? adrShares * quote.c  / 1_000_000 : 0
      prevCloseCapUSD = quote ? adrShares * quote.pc / 1_000_000 : 0
    } else {
      // 일반 + SAR: stats 기준값(≈발행주수×전일종가) 자체가 전일 종가 시총.
      // 라이브 = 그 값 × 당일 등락 비율(현재가/전일종가).
      const ratio     = quote && quote.pc > 0 ? quote.c / quote.pc : 1
      prevCloseCapUSD = tdCapT ?? 0
      marketCapUSD    = prevCloseCapUSD * ratio
    }

    if (marketCapUSD <= 0) {
      const stale = lastGoodCompanyCache.get(co.ticker)
      if (stale) return stale
    }

    const result: Omit<CompanyResult, 'rank'> = {
      ticker:          co.ticker,
      name:            co.name,
      color:           co.color,
      currentPrice:    quote?.c  ?? 0,
      change:          quote?.d  ?? 0,
      changePercent:   quote?.dp ?? 0,
      marketCapUSD,
      prevCloseCapUSD,
    }
    lastGoodCompanyCache.set(co.ticker, result)
    return result
  })
}

// ─── Ranking Helper ───────────────────────────────────────────────────────────
// 신선 데이터를 시총 내림차순 상위 N개로 랭킹.
// 레이트리밋 등으로 N개를 못 채우면 직전 성공 랭킹(previous)으로 보강 → 섹션이 20개 밑으로 내려가지 않도록.

function rankWithBackfill(
  fresh:    Omit<CompanyResult, 'rank'>[],
  previous: CompanyResult[] | null,
  limit     = 20,
): CompanyResult[] {
  const seen   = new Set(fresh.map(r => r.ticker))
  const merged: Omit<CompanyResult, 'rank'>[] = [...fresh]

  if (previous && merged.length < limit) {
    for (const p of previous) {
      if (merged.length >= limit) break
      if (seen.has(p.ticker)) continue
      const { rank: _rank, ...rest } = p
      merged.push(rest)
      seen.add(p.ticker)
    }
  }

  // 전일 종가 기준 순위: 같은 후보 풀을 prevCloseCap 내림차순으로 정렬해 티커→순위 맵 구성.
  // 라이브 순위(marketCapUSD)와 비교해 클라이언트가 화살표(delta)를 그린다.
  const prevRankMap = new Map<string, number>()
  ;[...merged]
    .filter(r => r.prevCloseCapUSD > 0)
    .sort((a, b) => b.prevCloseCapUSD - a.prevCloseCapUSD)
    .forEach((r, i) => prevRankMap.set(r.ticker, i + 1))

  return merged
    .sort((a, b) => b.marketCapUSD - a.marketCapUSD)
    .slice(0, limit)
    .map((r, i) => ({ ...r, rank: i + 1, previousRank: prevRankMap.get(r.ticker) }))
}

// ─── Route Handler ────────────────────────────────────────────────────────────

export async function GET(req: Request) {
  const param  = new URL(req.url).searchParams.get('exchange')?.toLowerCase()
  const config = param ? getExchange(param) : undefined
  if (config) return handleExchange(config)
  return handleAll()
}

async function handleAll() {
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate = await getKrwRate()
    const rates = await getFxRateMap(rate)

    const [companyRows, krxResults] = await Promise.all([
      fetchRows(ALL_FEED.tdUniverse),
      Promise.all(
        ALL_FEED.krxInjections.map(meta =>
          getKRXResult(meta, rate).catch((err) => {
            console.warn(`[market-cap] KRX ${meta.ticker} 실패, 스킵:`, err)
            return null
          }),
        ),
      ),
    ])

    const allRows = [...companyRows, ...krxResults]
      .filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked = rankWithBackfill(allRows, lastGoodResult, ALL_FEED.rankLimit)
    lastGoodResult       = ranked
    lastGoodAt           = Date.now()
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, data: ranked, updatedAt: lastGoodAt, stale: false })
  } catch (err) {
    console.error('[market-cap] fetch error:', err)
    if (lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), data: lastGoodResult, updatedAt: lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// config 구동 거래소 핸들러. capModel로 TD(발행주수×가격) / KRX(EOD 스냅샷) 경로를 가른다.
// ALL과 동일한 응답 형태(exchangeRate/data/updatedAt/stale, KRX는 basDt 추가)를 유지해 클라이언트 디코딩 공유.
async function handleExchange(config: ExchangeConfig) {
  switch (config.capModel.kind) {
    case 'krx': return handleKrxExchange(config, config.capModel.suffix)
    case 'jpx': return handleJpxExchange(config)
    case 'eu':  return handleEuExchange(config)
    case 'cn':  return handleCnExchange(config, config.capModel.mic)
    case 'nse': return handleNseExchange(config)
    case 'de':  return handleDeExchange(config)
    default:    return handleTdExchange(config)
  }
}

// TD 계열(NASDAQ / NYSE): 큐레이션 유니버스를 stats×quote로 재정렬, config.injections 주입.
async function handleTdExchange(config: ExchangeConfig) {
  const state = exchangeFeeds[config.code]
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate = await getKrwRate()
    const rates = await getFxRateMap(rate)
    const rows = await fetchRows(config.universe ?? [])
    const allRows = rows.filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    // 주입 종목(예: SK Hynix): KRX 시총을 USD 환산해 이 섹션에 주입 → 공식 순위와 일치.
    for (const inj of config.injections ?? []) {
      const row = await getKRXResult(inj, rate).catch((err) => {
        console.warn(`[market-cap:${config.code}] ${inj.ticker} 주입 실패, 스킵:`, err)
        return null
      })
      if (row) allRows.push(row)
    }

    const ranked = rankWithBackfill(allRows, state?.lastGoodResult, config.rankLimit)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, asOf: state?.lastAsOf ?? null, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), asOf: state.lastAsOf ?? null, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// KRX 계열(KOSPI / KOSDAQ): 공공데이터포털 동적 유니버스에서 시총 상위 N개를 USD 환산 후 반환.
async function handleKrxExchange(config: ExchangeConfig, suffix: 'KS' | 'KQ') {
  const state = exchangeFeeds[config.code]
  try {
    const rate   = await getKrwRate()
    const rates  = await getFxRateMap(rate)
    const ds     = await getKrxDataset()
    const rows   = suffix === 'KS' ? ds.kospi : ds.kosdaq  // 이미 시총 내림차순

    const ranked: CompanyResult[] = rows.slice(0, config.rankLimit).map((row, i) => {
      const meta = KRX_META[row.code]
      return {
        rank:          i + 1,
        ticker:        `${row.code}.${suffix}`,
        name:          meta?.name ?? row.name,
        color:         meta?.color ?? KRX_DEFAULT_COLOR,
        currentPrice:    row.price,
        change:          row.change,
        changePercent:   row.changePercent,
        marketCapUSD:    row.marketCapKRW / rate / 1_000_000_000_000,
        prevCloseCapUSD: row.marketCapKRW / rate / 1_000_000_000_000,  // KR previousRank는 클라이언트가 basDt로 계산
        domain:          row.domain,  // DART 해석 도메인 → 앱 로고 폴백
      }
    })

    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now(); state.lastBasDt = ds.basDt }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, basDt: ds.basDt, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), basDt: state.lastBasDt, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// JPX 계열: TD /statistics 스냅샷(jpx-snapshot, 네이티브 JPY)에서 상위 N개를 USD 환산 후 반환.
// TD가 JPX 가격 피드를 안 줘 라이브 스케일링 불가 → 주당가격=capJPY/shares(파생), 등락%=전일
// 스냅샷 시총 대비 자체계산(EOD). US/KRX와 동일 응답 형태를 유지해 클라이언트 디코딩을 공유한다.
async function handleJpxExchange(config: ExchangeConfig) {
  const state = exchangeFeeds[config.code]
  // 유니버스(config)에서 ticker → 표시메타(영문명·색) 맵 구성.
  const meta = new Map((config.universe ?? []).map(c => [c.ticker, c]))
  try {
    const rate  = await getKrwRate()               // 응답 exchangeRate(원화 카드)용 — US/KRX와 동일
    const rates = await getFxRateMap(rate)          // 다통화 표시 + JPY 환산에 사용
    const jpyPerUsd = rates.JPY
    if (!jpyPerUsd || jpyPerUsd <= 0) throw new Error('JPY 환율 없음')

    const ds = await getJpxDataset()
    if (state) state.lastAsOf = await getJpxAsOfDate()
    const rows: Omit<CompanyResult, 'rank'>[] = ds.map((r) => {
      const m         = meta.get(r.ticker)
      const price     = r.shares > 0 ? r.capJPY     / r.shares : 0  // 주당가격(JPY, 파생)
      const prevPrice = r.shares > 0 ? r.prevCapJPY / r.shares : 0
      const changePct = r.prevCapJPY > 0 ? (r.capJPY - r.prevCapJPY) / r.prevCapJPY * 100 : 0
      return {
        ticker:          r.ticker,
        name:            m?.name  ?? r.ticker,
        color:           m?.color ?? '#3182F6',
        currentPrice:    price,                                     // JPY 주당가격
        change:          price - prevPrice,                         // JPY 등락
        changePercent:   changePct,
        marketCapUSD:    r.capJPY     / jpyPerUsd / 1_000_000_000_000,
        prevCloseCapUSD: r.prevCapJPY / jpyPerUsd / 1_000_000_000_000,
      }
    })

    // 등락 없는 EOD라 라이브 재정렬은 무의미하지만, previousRank(전일 대비 화살표) 계산과
    // 백필(일시 스냅샷 결손 방어)을 US/KRX와 동일하게 얻으려 rankWithBackfill 을 재사용한다.
    const ranked = rankWithBackfill(rows, state?.lastGoodResult, config.rankLimit)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, asOf: state?.lastAsOf ?? null, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), asOf: state.lastAsOf ?? null, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// Euronext 계열: eu-snapshot(네이티브 EUR stats)을 base로, quote 있는 종목(XPAR/XAMS)은 라이브
// 스케일링(cap=statsCap×close/prevClose), 없는 종목(XMIL)은 stats 시총 + 전일 스냅샷 대비 등락%.
// EUR→USD 환산은 요청 시점 fx. US/KRX/JPX와 동일 응답 형태 유지.
async function handleEuExchange(config: ExchangeConfig) {
  const state = exchangeFeeds[config.code]
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate  = await getKrwRate()
    const rates = await getFxRateMap(rate)
    const eurPerUsd = rates.EUR
    if (!eurPerUsd || eurPerUsd <= 0) throw new Error('EUR 환율 없음')

    const { cap, prev, asOfDate } = await getEuStats()
    if (state) state.lastAsOf = asOfDate

    // quote 가능 종목(XPAR/XAMS)만 라이브 quote 병렬 조회. 실패는 만료 캐시로 폴백(없으면 EOD 처리).
    const quotes = await Promise.all(
      EU_COMPANIES.map(async (co): Promise<QuoteData | null> => {
        if (co.mic === 'XMIL') return null                  // 밀라노는 quote 미제공 → EOD 경로
        try { return await getQuote(co.symbol, co.mic) }
        catch { return quoteCache.get(`${co.symbol}:${co.mic}`)?.data ?? null }
      }),
    )

    const rows: Omit<CompanyResult, 'rank'>[] = []
    EU_COMPANIES.forEach((co, i) => {
      const base = cap[co.symbol]
      if (!base || !base.capEUR) {
        const stale = lastGoodCompanyCache.get(co.symbol)
        if (stale) rows.push(stale)
        return
      }
      const quote = quotes[i]
      let capEUR: number, prevCapEUR: number, price: number, change: number, changePct: number

      if (quote && quote.pc > 0) {
        // 라이브: stats base(≈전일 종가 시총) × 당일 등락 비율. 등락/가격은 quote 그대로(EUR).
        const ratio = quote.c / quote.pc
        prevCapEUR  = base.capEUR
        capEUR      = base.capEUR * ratio
        price       = quote.c
        change      = quote.d
        changePct   = quote.dp
      } else {
        // EOD(밀라노 등): stats 시총 그대로. 등락%는 전일 스냅샷 대비, 가격은 cap/shares 파생.
        const prevCap = prev[co.symbol] && prev[co.symbol] > 0 ? prev[co.symbol] : base.capEUR
        prevCapEUR = prevCap
        capEUR     = base.capEUR
        price      = base.shares > 0 ? base.capEUR / base.shares : 0
        const prevPrice = base.shares > 0 ? prevCap / base.shares : 0
        change     = price - prevPrice
        changePct  = prevCap > 0 ? (base.capEUR - prevCap) / prevCap * 100 : 0
      }

      const result: Omit<CompanyResult, 'rank'> = {
        ticker:          co.symbol,
        name:            co.name,
        color:           co.color,
        currentPrice:    price,                                    // EUR 주당가격
        change,
        changePercent:   changePct,
        marketCapUSD:    capEUR     / eurPerUsd / 1_000_000_000_000,
        prevCloseCapUSD: prevCapEUR / eurPerUsd / 1_000_000_000_000,
      }
      lastGoodCompanyCache.set(co.symbol, result)
      rows.push(result)
    })

    const ranked = rankWithBackfill(rows, state?.lastGoodResult, config.rankLimit)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, asOf: state?.lastAsOf ?? null, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), asOf: state.lastAsOf ?? null, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 중국 A주 계열(SSE / SZSE): cn-snapshot(네이티브 CNY stats)을 base로, quote(close/prevClose)로
// 라이브 스케일링. A주 quote는 지연/EOD라 등락은 직전 영업일 기준이며, quote 결손 시 stats 시총 +
// 전일 스냅샷 대비 등락%로 폴백한다. mic으로 상하이(XSHG)/선전(XSHE) 유니버스를 가른다.
// CNY→USD 환산은 요청 시점 fx. US/KRX/JPX/EU와 동일 응답 형태 유지.
async function handleCnExchange(config: ExchangeConfig, mic: 'XSHG' | 'XSHE') {
  const state = exchangeFeeds[config.code]
  const companies = CN_COMPANIES.filter(c => c.mic === mic)
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate  = await getKrwRate()
    const rates = await getFxRateMap(rate)
    const cnyPerUsd = rates.CNY
    if (!cnyPerUsd || cnyPerUsd <= 0) throw new Error('CNY 환율 없음')

    const { cap, prev, asOfDate } = await getCnStats()
    if (state) state.lastAsOf = asOfDate

    // 종목별 라이브 quote 병렬 조회. 실패는 만료 캐시로 폴백(없으면 EOD 처리).
    const quotes = await Promise.all(
      companies.map(async (co): Promise<QuoteData | null> => {
        try { return await getQuote(co.symbol, co.mic) }
        catch { return quoteCache.get(`${co.symbol}:${co.mic}`)?.data ?? null }
      }),
    )

    const rows: Omit<CompanyResult, 'rank'>[] = []
    companies.forEach((co, i) => {
      const base = cap[co.symbol]
      if (!base || !base.capCNY) {
        const stale = lastGoodCompanyCache.get(co.symbol)
        if (stale) rows.push(stale)
        return
      }
      const quote = quotes[i]
      let capCNY: number, prevCapCNY: number, price: number, change: number, changePct: number

      if (quote && quote.pc > 0) {
        // 라이브: stats base(≈전일 종가 시총) × 당일 등락 비율. 등락/가격은 quote 그대로(CNY).
        const ratio = quote.c / quote.pc
        prevCapCNY  = base.capCNY
        capCNY      = base.capCNY * ratio
        price       = quote.c
        change      = quote.d
        changePct   = quote.dp
      } else {
        // EOD 폴백: stats 시총 그대로. 등락%는 전일 스냅샷 대비, 가격은 cap/shares 파생.
        const prevCap = prev[co.symbol] && prev[co.symbol] > 0 ? prev[co.symbol] : base.capCNY
        prevCapCNY = prevCap
        capCNY     = base.capCNY
        price      = base.shares > 0 ? base.capCNY / base.shares : 0
        const prevPrice = base.shares > 0 ? prevCap / base.shares : 0
        change     = price - prevPrice
        changePct  = prevCap > 0 ? (base.capCNY - prevCap) / prevCap * 100 : 0
      }

      const result: Omit<CompanyResult, 'rank'> = {
        ticker:          co.symbol,
        name:            co.name,
        color:           co.color,
        currentPrice:    price,                                    // CNY 주당가격
        change,
        changePercent:   changePct,
        marketCapUSD:    capCNY     / cnyPerUsd / 1_000_000_000_000,
        prevCloseCapUSD: prevCapCNY / cnyPerUsd / 1_000_000_000_000,
      }
      lastGoodCompanyCache.set(co.symbol, result)
      rows.push(result)
    })

    const ranked = rankWithBackfill(rows, state?.lastGoodResult, config.rankLimit)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, asOf: state?.lastAsOf ?? null, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), asOf: state.lastAsOf ?? null, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 인도 NSE 계열: nse-snapshot(네이티브 INR stats)을 base로, quote(close/prevClose)로 라이브 스케일링.
// quote 결손 시 stats 시총 + 전일 스냅샷 대비로 폴백. 전 종목 단일 mic(XNSE). INR→USD는 요청 시 fx.
// cn 핸들러와 동일 구조(mic 분기만 없음). US/KRX/JPX/EU/CN과 동일 응답 형태 유지.
async function handleNseExchange(config: ExchangeConfig) {
  const state = exchangeFeeds[config.code]
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate  = await getKrwRate()
    const rates = await getFxRateMap(rate)
    const inrPerUsd = rates.INR
    if (!inrPerUsd || inrPerUsd <= 0) throw new Error('INR 환율 없음')

    const { cap, prev, asOfDate } = await getNseStats()
    if (state) state.lastAsOf = asOfDate

    const quotes = await Promise.all(
      NSE_COMPANIES.map(async (co): Promise<QuoteData | null> => {
        try { return await getQuote(co.symbol, NSE_MIC) }
        catch { return quoteCache.get(`${co.symbol}:${NSE_MIC}`)?.data ?? null }
      }),
    )

    const rows: Omit<CompanyResult, 'rank'>[] = []
    NSE_COMPANIES.forEach((co, i) => {
      const base = cap[co.symbol]
      if (!base || !base.capINR) {
        const stale = lastGoodCompanyCache.get(co.symbol)
        if (stale) rows.push(stale)
        return
      }
      const quote = quotes[i]
      let capINR: number, prevCapINR: number, price: number, change: number, changePct: number

      if (quote && quote.pc > 0) {
        // 라이브: stats base(≈전일 종가 시총) × 당일 등락 비율. 등락/가격은 quote 그대로(INR).
        const ratio = quote.c / quote.pc
        prevCapINR  = base.capINR
        capINR      = base.capINR * ratio
        price       = quote.c
        change      = quote.d
        changePct   = quote.dp
      } else {
        // EOD 폴백: stats 시총 그대로. 등락%는 전일 스냅샷 대비, 가격은 cap/shares 파생.
        const prevCap = prev[co.symbol] && prev[co.symbol] > 0 ? prev[co.symbol] : base.capINR
        prevCapINR = prevCap
        capINR     = base.capINR
        price      = base.shares > 0 ? base.capINR / base.shares : 0
        const prevPrice = base.shares > 0 ? prevCap / base.shares : 0
        change     = price - prevPrice
        changePct  = prevCap > 0 ? (base.capINR - prevCap) / prevCap * 100 : 0
      }

      const result: Omit<CompanyResult, 'rank'> = {
        ticker:          co.symbol,
        name:            co.name,
        color:           co.color,
        currentPrice:    price,                                    // INR 주당가격
        change,
        changePercent:   changePct,
        marketCapUSD:    capINR     / inrPerUsd / 1_000_000_000_000,
        prevCloseCapUSD: prevCapINR / inrPerUsd / 1_000_000_000_000,
      }
      lastGoodCompanyCache.set(co.symbol, result)
      rows.push(result)
    })

    const ranked = rankWithBackfill(rows, state?.lastGoodResult, config.rankLimit)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, asOf: state?.lastAsOf ?? null, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), asOf: state.lastAsOf ?? null, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 독일 FWB 계열: de-snapshot(네이티브 EUR stats)을 base로, quote(close/prevClose)로 라이브 스케일링.
// quote 결손 시 stats 시총 + 전일 스냅샷 대비로 폴백. 전 종목 단일 mic(XETR). EUR→USD는 요청 시 fx.
// nse 핸들러와 동일 구조(통화만 EUR). US/KRX/JPX/EU/CN/NSE와 동일 응답 형태 유지.
async function handleDeExchange(config: ExchangeConfig) {
  const state = exchangeFeeds[config.code]
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate  = await getKrwRate()
    const rates = await getFxRateMap(rate)
    const eurPerUsd = rates.EUR
    if (!eurPerUsd || eurPerUsd <= 0) throw new Error('EUR 환율 없음')

    const { cap, prev, asOfDate } = await getDeStats()
    if (state) state.lastAsOf = asOfDate

    const quotes = await Promise.all(
      DE_COMPANIES.map(async (co): Promise<QuoteData | null> => {
        try { return await getQuote(co.symbol, DE_MIC) }
        catch { return quoteCache.get(`${co.symbol}:${DE_MIC}`)?.data ?? null }
      }),
    )

    const rows: Omit<CompanyResult, 'rank'>[] = []
    DE_COMPANIES.forEach((co, i) => {
      const base = cap[co.symbol]
      if (!base || !base.capEUR) {
        const stale = lastGoodCompanyCache.get(co.symbol)
        if (stale) rows.push(stale)
        return
      }
      const quote = quotes[i]
      let capEUR: number, prevCapEUR: number, price: number, change: number, changePct: number

      if (quote && quote.pc > 0) {
        // 라이브: stats base(≈전일 종가 시총) × 당일 등락 비율. 등락/가격은 quote 그대로(EUR).
        const ratio = quote.c / quote.pc
        prevCapEUR  = base.capEUR
        capEUR      = base.capEUR * ratio
        price       = quote.c
        change      = quote.d
        changePct   = quote.dp
      } else {
        // EOD 폴백: stats 시총 그대로. 등락%는 전일 스냅샷 대비, 가격은 cap/shares 파생.
        const prevCap = prev[co.symbol] && prev[co.symbol] > 0 ? prev[co.symbol] : base.capEUR
        prevCapEUR = prevCap
        capEUR     = base.capEUR
        price      = base.shares > 0 ? base.capEUR / base.shares : 0
        const prevPrice = base.shares > 0 ? prevCap / base.shares : 0
        change     = price - prevPrice
        changePct  = prevCap > 0 ? (base.capEUR - prevCap) / prevCap * 100 : 0
      }

      const result: Omit<CompanyResult, 'rank'> = {
        ticker:          co.symbol,
        name:            co.name,
        color:           co.color,
        currentPrice:    price,                                    // EUR 주당가격
        change,
        changePercent:   changePct,
        marketCapUSD:    capEUR     / eurPerUsd / 1_000_000_000_000,
        prevCloseCapUSD: prevCapEUR / eurPerUsd / 1_000_000_000_000,
      }
      lastGoodCompanyCache.set(co.symbol, result)
      rows.push(result)
    })

    const ranked = rankWithBackfill(rows, state?.lastGoodResult, config.rankLimit)
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, exchangeRates: rates, asOf: state?.lastAsOf ?? null, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${config.code}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, exchangeRates: await getFxRateMap(lastGoodExchangeRate), asOf: state.lastAsOf ?? null, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// stats 기준값의 선제 워밍은 lib/us-stats 의 startUsStatsWarm()(로컬)·크론(Vercel)이 담당한다.
// 이 라우트(유저 경로)는 stats를 스냅샷에서 read 만 하므로 여기서 별도 warm-up 을 돌리지 않는다.
