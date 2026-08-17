// ─── 순위 히스토리(rank-history) 적재 레이어 ─────────────────────────────────────
//
// 목적: "어제 8위 → 오늘 5위", "3개월 만에 재추월" 같은 순위변동 서사를 만들려면 과거 순위가
// 필요하다. 데이터는 소급 취득이 불가능하므로 지금부터 매일 EOD 순위를 굳혀 쌓는다.
//
// 저장 대상(라이선스): Twelve Data가 서면으로 허용한 "순위 계산·순위 변화 분석(파생 데이터, 내부
// 사용)" 범위에 맞춰 **파생값(순위)만** 저장한다. 원본 가격/시총은 저장하지 않는다(역산 불가).
// 공공데이터포털(KR)은 공공누리 범위 내 2차 가공 → 문제 없음.
//
// 무엇을 "순위"로 굳히나: 유저가 보는 순위는 market-cap 라우트가 EOD 시총(전일 종가 기준)으로
// 정렬해 만든다. 여기서도 각 스냅샷의 **네이티브 EOD 시총**을 그대로 내림차순 정렬해 동일한 순위를
// 재현한다(거래소 내 정렬은 통화 스케일에 불변이라 FX 불필요 — ALL/NASDAQ의 KRW 주입분만 예외).
// 라이브 quote는 쓰지 않으므로 추가 TD 크레딧 소모가 없고, 실행 시각과 무관하게 결정적이다.
//
// 저장 구조: 피드별 키 `rank-hist:<feed>` 에 90일 링버퍼(오래된→최신). 각 항목은
//   { date: 'YYYY-MM-DD', rank: { [ticker]: 순위(1-base) } }.
// 날짜로 멱등: 최신 항목의 date가 이번 거래일과 같으면 append하지 않는다(주말·휴장·중복 실행 무해).
//
// 실행: scripts/capture-history.ts(GitHub Actions 크론)가 refresh-* 갱신 이후 하루 1회 호출.

import { createSnapshotStore } from './snapshot-store'
import { getUsStats, getUsStatsFetchedAt } from './us-stats'
import { getKrxDataset } from './kr-snapshot'
import { getJpxDataset, getJpxAsOfDate } from './jpx-snapshot'
import { getEuStats } from './eu-snapshot'
import { getCnStats } from './cn-snapshot'
import { getNseStats } from './nse-snapshot'
import { getDeStats } from './de-snapshot'
import { getUsdKrwQuote } from './fx'
import { EU_COMPANIES } from './eu-universe'
import { CN_COMPANIES } from './cn-universe'
import { NSE_COMPANIES } from './nse-universe'
import { DE_COMPANIES } from './de-universe'
import { COMPANIES, NASDAQ_COMPANIES, NYSE_COMPANIES } from './us-universe'
import { KOREAN_STOCKS, SKHYNIX_KRX, ALL_FEED, EXCHANGES } from './exchanges'

// ─── 저장 모델 ─────────────────────────────────────────────────────────────────

export interface RankHistoryEntry {
  date: string                      // 거래일 'YYYY-MM-DD'
  rank: Record<string, number>      // ticker → 순위(1-base)
}

// 보관 일수(링버퍼 상한). 90거래일 ≈ 4개월치 → 주간·월간·분기 서사를 모두 커버한다.
const HISTORY_DAYS = 90

const key = (feed: string) => `rank-hist:${feed}`

// ─── 날짜 유틸 ─────────────────────────────────────────────────────────────────

// YYYYMMDD(data.go.kr basDt) → YYYY-MM-DD
function dashDate(yyyymmdd: string): string {
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`
}

// ms → 지정 타임존의 달력 날짜(YYYY-MM-DD). US 계열 피드의 거래일 산출용(ET).
function zonedDate(ms: number, timeZone: string): string {
  // en-CA 로케일은 YYYY-MM-DD 포맷을 보장한다.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(ms))
}

// ─── 순위 계산 헬퍼 ─────────────────────────────────────────────────────────────

// {ticker, cap} 목록을 시총 내림차순으로 정렬해 상위 limit개의 ticker→순위(1-base) 맵을 만든다.
// cap이 없거나 0 이하인 항목은 순위 대상에서 제외한다.
function rankByCap(rows: { ticker: string; cap: number }[], limit: number): Record<string, number> {
  const rank: Record<string, number> = {}
  rows
    .filter(r => r.cap > 0)
    .sort((a, b) => b.cap - a.cap)
    .slice(0, limit)
    .forEach((r, i) => { rank[r.ticker] = i + 1 })
  return rank
}

// 피드 1개의 EOD 순위와 거래일을 계산한다. 계산 불가(스냅샷 결손 등)면 null.
interface FeedRanking { date: string; rank: Record<string, number> }

// US 계열(ALL/NASDAQ/NYSE) 공통 거래일: us-stats 스냅샷을 굳힌 시각의 ET 날짜.
async function usTradingDate(): Promise<string | null> {
  const fetchedAt = await getUsStatsFetchedAt()
  return fetchedAt ? zonedDate(fetchedAt, 'America/New_York') : null
}

// KRW 시총(원)을 USD 조 단위로 환산. ALL/NASDAQ에 주입되는 KR 종목을 USD 시총과 비교하기 위함.
function krwCapToUsdT(marketCapKRW: number, krwPerUsd: number): number {
  return marketCapKRW / krwPerUsd / 1_000_000_000_000
}

// ─── 피드별 EOD 순위 계산 ───────────────────────────────────────────────────────

async function rankAll(): Promise<FeedRanking | null> {
  const date = await usTradingDate()
  if (!date) return null
  const stats = await getUsStats()
  const ds    = await getKrxDataset()
  const krwPerUsd = (await getUsdKrwQuote()).rate

  const rows: { ticker: string; cap: number }[] = []
  for (const co of COMPANIES) {
    const cap = stats[co.ticker]
    if (cap) rows.push({ ticker: co.ticker, cap })
  }
  // KR 주입(삼성·SK하이닉스): KRX 시총을 USD로 환산해 US 시총과 같은 축에서 정렬.
  for (const kr of KOREAN_STOCKS) {
    const code = kr.ticker.replace(/\.(KS|KQ)$/, '')
    const capKRW = ds.byCode.get(code)?.marketCapKRW
    if (capKRW) rows.push({ ticker: kr.ticker, cap: krwCapToUsdT(capKRW, krwPerUsd) })
  }
  return { date, rank: rankByCap(rows, ALL_FEED.rankLimit) }
}

async function rankNasdaq(limit: number): Promise<FeedRanking | null> {
  const date = await usTradingDate()
  if (!date) return null
  const stats = await getUsStats()
  const rows: { ticker: string; cap: number }[] = []
  for (const co of NASDAQ_COMPANIES) {
    const cap = stats[co.ticker]
    if (cap) rows.push({ ticker: co.ticker, cap })
  }
  // SK Hynix 주입(TD에 US 심볼이 없어 KRX 시총을 USD 환산해 주입) — 라우트와 동일.
  const ds = await getKrxDataset()
  const capKRW = ds.byCode.get(SKHYNIX_KRX.ticker.replace(/\.(KS|KQ)$/, ''))?.marketCapKRW
  if (capKRW) {
    const krwPerUsd = (await getUsdKrwQuote()).rate
    rows.push({ ticker: SKHYNIX_KRX.ticker, cap: krwCapToUsdT(capKRW, krwPerUsd) })
  }
  return { date, rank: rankByCap(rows, limit) }
}

async function rankNyse(limit: number): Promise<FeedRanking | null> {
  const date = await usTradingDate()
  if (!date) return null
  const stats = await getUsStats()
  const rows = NYSE_COMPANIES
    .map(co => ({ ticker: co.ticker, cap: stats[co.ticker] ?? 0 }))
  return { date, rank: rankByCap(rows, limit) }
}

async function rankKrx(suffix: 'KS' | 'KQ', limit: number): Promise<FeedRanking | null> {
  const ds   = await getKrxDataset()
  if (!ds.basDt) return null
  const list = suffix === 'KS' ? ds.kospi : ds.kosdaq   // 이미 시총 내림차순
  const rank: Record<string, number> = {}
  list.slice(0, limit).forEach((row, i) => { rank[`${row.code}.${suffix}`] = i + 1 })
  return { date: dashDate(ds.basDt), rank }
}

async function rankJpx(limit: number): Promise<FeedRanking | null> {
  const asOf = await getJpxAsOfDate()
  if (!asOf) return null
  const ds = await getJpxDataset()
  const rows = ds.map(r => ({ ticker: r.ticker, cap: r.capJPY }))
  return { date: asOf, rank: rankByCap(rows, limit) }
}

async function rankEu(limit: number): Promise<FeedRanking | null> {
  const { cap, asOfDate } = await getEuStats()
  if (!asOfDate) return null
  const rows = EU_COMPANIES.map(co => ({ ticker: co.symbol, cap: cap[co.symbol]?.capEUR ?? 0 }))
  return { date: asOfDate, rank: rankByCap(rows, limit) }
}

async function rankCn(mic: 'XSHG' | 'XSHE', limit: number): Promise<FeedRanking | null> {
  const { cap, asOfDate } = await getCnStats()
  if (!asOfDate) return null
  const rows = CN_COMPANIES
    .filter(co => co.mic === mic)
    .map(co => ({ ticker: co.symbol, cap: cap[co.symbol]?.capCNY ?? 0 }))
  return { date: asOfDate, rank: rankByCap(rows, limit) }
}

async function rankNse(limit: number): Promise<FeedRanking | null> {
  const { cap, asOfDate } = await getNseStats()
  if (!asOfDate) return null
  const rows = NSE_COMPANIES.map(co => ({ ticker: co.symbol, cap: cap[co.symbol]?.capINR ?? 0 }))
  return { date: asOfDate, rank: rankByCap(rows, limit) }
}

async function rankDe(limit: number): Promise<FeedRanking | null> {
  const { cap, asOfDate } = await getDeStats()
  if (!asOfDate) return null
  const rows = DE_COMPANIES.map(co => ({ ticker: co.symbol, cap: cap[co.symbol]?.capEUR ?? 0 }))
  return { date: asOfDate, rank: rankByCap(rows, limit) }
}

// 피드 param → EOD 순위 계산기. EXCHANGES(config)와 ALL을 단일 소스로 순회한다.
function rankerFor(param: string, capModel: { kind: string; suffix?: string; mic?: string }, limit: number): () => Promise<FeedRanking | null> {
  switch (capModel.kind) {
    case 'krx': return () => rankKrx(capModel.suffix as 'KS' | 'KQ', limit)
    case 'jpx': return () => rankJpx(limit)
    case 'eu':  return () => rankEu(limit)
    case 'cn':  return () => rankCn(capModel.mic as 'XSHG' | 'XSHE', limit)
    case 'nse': return () => rankNse(limit)
    case 'de':  return () => rankDe(limit)
    case 'td':  return param === 'nasdaq' ? () => rankNasdaq(limit) : () => rankNyse(limit)
    default:    return async () => null
  }
}

// param → 계산기 테이블(ALL + 전 거래소).
const RANKERS: Record<string, () => Promise<FeedRanking | null>> = {
  all: rankAll,
  ...Object.fromEntries(
    EXCHANGES.map(e => [e.param, rankerFor(e.param, e.capModel, e.rankLimit)]),
  ),
}

// ─── 저장소 + 적재 ──────────────────────────────────────────────────────────────

// 한 피드의 순위를 히스토리에 append(멱등·링버퍼 trim). 결과 상태를 돌려준다.
async function appendFeed(feed: string, ranking: FeedRanking): Promise<'appended' | 'skipped-dup' | 'skipped-empty'> {
  if (Object.keys(ranking.rank).length === 0) return 'skipped-empty'

  const store   = createSnapshotStore<RankHistoryEntry[]>(key(feed))
  const history = (await store.load()) ?? []
  const last    = history[history.length - 1]
  if (last && last.date === ranking.date) return 'skipped-dup'  // 이미 이 거래일 적재됨

  history.push({ date: ranking.date, rank: ranking.rank })
  const trimmed = history.slice(-HISTORY_DAYS)
  await store.save(trimmed)
  return 'appended'
}

export interface CaptureResult {
  feed:   string
  status: 'appended' | 'skipped-dup' | 'skipped-empty' | 'error'
  date?:  string
  count?: number
  error?: string
}

// 전 피드(ALL + 10거래소)의 EOD 순위를 계산해 히스토리에 적재한다. 피드별 독립 — 하나가
// 실패(스냅샷 결손 등)해도 나머지는 계속 진행한다. 스크립트/크론이 이 함수만 호출한다.
export async function captureAllRankHistory(): Promise<CaptureResult[]> {
  const results: CaptureResult[] = []
  for (const [feed, ranker] of Object.entries(RANKERS)) {
    try {
      const ranking = await ranker()
      if (!ranking) { results.push({ feed, status: 'error', error: '스냅샷 없음/거래일 미상' }); continue }
      const status = await appendFeed(feed, ranking)
      results.push({ feed, status, date: ranking.date, count: Object.keys(ranking.rank).length })
    } catch (err) {
      results.push({ feed, status: 'error', error: err instanceof Error ? err.message : String(err) })
    }
  }
  return results
}

// ─── 읽기 API (소비 경로 — Phase 2에서 서사 계산에 사용) ─────────────────────────

// 한 피드의 순위 히스토리(오래된→최신)를 그대로 반환. 없으면 빈 배열.
export async function getRankHistory(feed: string): Promise<RankHistoryEntry[]> {
  const store = createSnapshotStore<RankHistoryEntry[]>(key(feed))
  return (await store.load()) ?? []
}
