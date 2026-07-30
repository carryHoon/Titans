import { NextResponse } from 'next/server'
import { getUsdKrwQuote } from '@/lib/fx'
import { getKrxDataset, startKrPoller } from '@/lib/kr-snapshot'
import { getUsStats, startUsStatsWarm } from '@/lib/us-stats'
import {
  COMPANIES,
  NASDAQ_COMPANIES,
  NYSE_COMPANIES,
  ADR_SHARE_OUTSTANDING_M,
  type CompanyMeta,
} from '@/lib/us-universe'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// KR 스냅샷 폴러 기동 (market-cap / market-index 공유 싱글턴)
startKrPoller()
// US stats 부팅 워밍 (로컬/상시 프로세스 전용; 서버리스는 크론이 채운다)
startUsStatsWarm()

// ─── Twelve Data (quote 전용) ──────────────────────────────────────────────────
// Venture 플랜: 610 credits/min. 이 라우트(유저 경로)는 /quote(1 credit/종목, 20s TTL)만 쓴다.
// 시총 기준값(/statistics)은 lib/us-stats 스냅샷 레이어가 마감 후 1회 갱신 → 유저 경로는 read만.
// ⇒ 정상 운용 ~80 credits/min, 유저 요청이 stats fetch 지연·버스트를 절대 떠안지 않는다.

const TWELVE_DATA_KEY = process.env.TWELVE_DATA_API_KEY ?? ''
const TD_BASE         = 'https://api.twelvedata.com'

// ─── KRX (한국거래소) ──────────────────────────────────────────────────────────
// 공공데이터포털 금융위원회_주식시세정보 — EOD D-1 데이터, 무료·라이선스 클린.
// 유니버스·시세·시총은 kr-snapshot 레이어가 동적으로 관리(상위 100개 이상).
// 아래 배열은 "종목코드 → 영문명/색" 표시 메타의 소스로만 사용. 없는 종목은 한글명+기본색 폴백.

interface KoreanStockMeta {
  ticker: string
  name:   string
  color:  string
}

// ALL 피드에 포함될 KRX 종목 (시총 상위권 한국 기업)
const KOREAN_STOCKS: KoreanStockMeta[] = [
  { ticker: '005930.KS', name: 'Samsung',  color: '#1428A0' },
  { ticker: '000660.KS', name: 'SK Hynix', color: '#EA5504' },
]

// SK Hynix: NASDAQ 공식에는 ADR로 상위권에 오르지만, Twelve Data에 US 심볼이 없어
// KRX 시총(000660.KS)을 USD 환산해 NASDAQ 섹션에 주입 → 나스닥 공식 순위와 일치.
const SKHYNIX_KRX: KoreanStockMeta = { ticker: '000660.KS', name: 'SK Hynix', color: '#EA5504' }

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
const KRX_META: Record<string, { name: string; color: string }> = Object.fromEntries(
  [...KOSPI_COMPANIES, ...KOSDAQ_COMPANIES].map(c => [
    c.ticker.replace(/\.(KS|KQ)$/, ''),
    { name: c.name, color: c.color },
  ]),
)
const KRX_DEFAULT_COLOR = '#3182F6'

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
  lastBasDt?:     string
}
const exchangeFeeds: Record<string, ExchangeFeedState> = {
  NASDAQ: { lastGoodResult: null, lastGoodAt: 0 },
  NYSE:   { lastGoodResult: null, lastGoodAt: 0 },
  KOSPI:  { lastGoodResult: null, lastGoodAt: 0 },
  KOSDAQ: { lastGoodResult: null, lastGoodAt: 0 },
}

// ─── Twelve Data Fetchers (quote 전용) ─────────────────────────────────────────

async function getQuote(ticker: string): Promise<QuoteData> {
  const hit = quoteCache.get(ticker)
  if (hit && Date.now() - hit.ts < QUOTE_TTL_MS) return hit.data

  const pending = quoteInFlight.get(ticker)
  if (pending) return pending

  const task = (async (): Promise<QuoteData> => {
    const res = await fetch(
      `${TD_BASE}/quote?symbol=${encodeURIComponent(ticker)}&apikey=${TWELVE_DATA_KEY}`,
      { cache: 'no-store' },
    )
    if (!res.ok) throw new Error(`quote ${ticker} → HTTP ${res.status}`)
    const data = await res.json()
    if (data.status === 'error') throw new Error(`quote ${ticker} → ${data.message}`)
    const q: QuoteData = {
      c:  parseFloat(data.close),
      d:  parseFloat(data.change),
      dp: parseFloat(data.percent_change),
      pc: parseFloat(data.previous_close),
    }
    if (!q.c || !isFinite(q.c)) throw new Error(`quote ${ticker} → 유효하지 않은 응답`)
    quoteCache.set(ticker, { data: q, ts: Date.now() })
    return q
  })().finally(() => quoteInFlight.delete(ticker))

  quoteInFlight.set(ticker, task)
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
  const exchange = new URL(req.url).searchParams.get('exchange')?.toLowerCase()
  if (exchange === 'nasdaq') return handleExchange('NASDAQ', NASDAQ_COMPANIES)
  if (exchange === 'nyse')   return handleExchange('NYSE',   NYSE_COMPANIES)
  if (exchange === 'kospi')  return handleKoreanExchange('KOSPI')
  if (exchange === 'kosdaq') return handleKoreanExchange('KOSDAQ')
  return handleAll()
}

async function handleAll() {
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate = await getKrwRate()

    const [companyRows, krxResults] = await Promise.all([
      fetchRows(COMPANIES),
      Promise.all(
        KOREAN_STOCKS.map(meta =>
          getKRXResult(meta, rate).catch((err) => {
            console.warn(`[market-cap] KRX ${meta.ticker} 실패, 스킵:`, err)
            return null
          }),
        ),
      ),
    ])

    const allRows = [...companyRows, ...krxResults]
      .filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    const ranked = rankWithBackfill(allRows, lastGoodResult)
    lastGoodResult       = ranked
    lastGoodAt           = Date.now()
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, data: ranked, updatedAt: lastGoodAt, stale: false })
  } catch (err) {
    console.error('[market-cap] fetch error:', err)
    if (lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: lastGoodResult, updatedAt: lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 거래소 전용 핸들러 (NASDAQ / NYSE 공통).
// ALL과 동일한 응답 형태(exchangeRate/data/updatedAt/stale)를 유지해 클라이언트 디코딩 공유.
async function handleExchange(exchange: string, universe: CompanyMeta[]) {
  const state = exchangeFeeds[exchange]
  try {
    if (!TWELVE_DATA_KEY) throw new Error('TWELVE_DATA_API_KEY 환경변수 없음')

    const rate = await getKrwRate()
    const rows = await fetchRows(universe)
    const allRows = rows.filter((r): r is Omit<CompanyResult, 'rank'> => r !== null)

    // SK Hynix: KRX 시총을 USD 환산해 NASDAQ 섹션에 주입 → 나스닥 공식 순위와 일치.
    if (exchange === 'NASDAQ') {
      const hynix = await getKRXResult(SKHYNIX_KRX, rate).catch((err) => {
        console.warn('[market-cap:NASDAQ] SK Hynix 주입 실패, 스킵:', err)
        return null
      })
      if (hynix) allRows.push(hynix)
    }

    const ranked = rankWithBackfill(allRows, state?.lastGoodResult, 100)  // NASDAQ/NYSE는 top-100
    if (state) { state.lastGoodResult = ranked; state.lastGoodAt = Date.now() }
    lastGoodExchangeRate = rate

    return NextResponse.json({ exchangeRate: rate, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// 한국거래소 전용 핸들러 (KOSPI / KOSDAQ 공통).
// 공공데이터포털 동적 유니버스에서 시총 상위 100개를 뽑아 USD 환산 후 반환.
async function handleKoreanExchange(exchange: 'KOSPI' | 'KOSDAQ') {
  const state = exchangeFeeds[exchange]
  try {
    const rate   = await getKrwRate()
    const ds     = await getKrxDataset()
    const suffix = exchange === 'KOSPI' ? 'KS' : 'KQ'
    const rows   = exchange === 'KOSPI' ? ds.kospi : ds.kosdaq  // 이미 시총 내림차순

    const ranked: CompanyResult[] = rows.slice(0, 100).map((row, i) => {
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

    return NextResponse.json({ exchangeRate: rate, basDt: ds.basDt, data: ranked, updatedAt: state?.lastGoodAt ?? Date.now(), stale: false })
  } catch (err) {
    console.error(`[market-cap:${exchange}] fetch error:`, err)
    if (state?.lastGoodResult) {
      return NextResponse.json(
        { exchangeRate: lastGoodExchangeRate, basDt: state.lastBasDt, data: state.lastGoodResult, updatedAt: state.lastGoodAt, stale: true },
      )
    }
    return NextResponse.json({ error: String(err) }, { status: 503 })
  }
}

// stats 기준값의 선제 워밍은 lib/us-stats 의 startUsStatsWarm()(로컬)·크론(Vercel)이 담당한다.
// 이 라우트(유저 경로)는 stats를 스냅샷에서 read 만 하므로 여기서 별도 warm-up 을 돌리지 않는다.
