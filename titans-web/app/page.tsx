'use client'

import { useState, useEffect, useCallback } from 'react'
import type { CompanyResult } from './api/market-cap/route'
import type { IndexData } from './api/market-index/route'

// ─── Market Indices ───────────────────────────────────────────────────────────

type MarketIndex = IndexData

// 로딩 전 표시용 플레이스홀더 (즉시 실제 데이터로 교체됨)
const INITIAL_INDICES: MarketIndex[] = [
  { id: 'usd',    name: '달러 환율', value: 0, change: 0, changePercent: 0, updatedAt: 0 },
  { id: 'nasdaq', name: '나스닥',    value: 0, change: 0, changePercent: 0, updatedAt: 0 },
  { id: 'kospi',  name: '코스피',    value: 0, change: 0, changePercent: 0, updatedAt: 0 },
  { id: 'kosdaq', name: '코스닥',    value: 0, change: 0, changePercent: 0, updatedAt: 0 },
]

// Ticker → 브랜드 도메인 (Brandfetch / Favicon fallback용)
const TICKER_DOMAIN: Record<string, string> = {
  NVDA:    'nvidia.com',
  AAPL:    'apple.com',
  MSFT:    'microsoft.com',
  GOOGL:   'google.com',
  AMZN:    'amazon.com',
  META:    'meta.com',
  TSLA:    'tesla.com',
  'BRK.B': 'berkshirehathaway.com',
  AVGO:    'broadcom.com',
  JPM:     'jpmorganchase.com',
  TSM:     'tsmc.com',
  LLY:     'lilly.com',
  WMT:     'walmart.com',
  V:       'visa.com',
  ORCL:    'oracle.com',
  XOM:     'exxonmobil.com',
  MA:      'mastercard.com',
  COST:    'costco.com',
  NFLX:    'netflix.com',
  UNH:     'unitedhealthgroup.com',
  PLTR:    'palantir.com',
  '2222.SR':   'aramco.com',
  '005930.KS': 'samsung.com',
  '000660.KS': 'skhynix.com',
}

const BRANDFETCH_CLIENT_ID = process.env.NEXT_PUBLIC_BRANDFETCH_CLIENT_ID ?? ''

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatMarketCap(usdTrillions: number, currency: 'usd' | 'krw', rate: number): string {
  if (currency === 'usd') {
    return `$${usdTrillions.toFixed(2)}T`
  }
  const krwTrillions = usdTrillions * rate
  return `${Math.round(krwTrillions).toLocaleString('ko-KR')}조원`
}

function formatNumber(n: number, decimals = 2): string {
  return n.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  })
}

function formatTime(d: Date): string {
  return d.toLocaleTimeString('ko-KR', { hour12: false })
}
function formatDate(d: Date): string {
  return d.toLocaleDateString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit' })
    .replace(/\. /g, '-').replace('.', '')
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function LiveIndicatorBar({ time }: { time: Date }) {
  return (
    <div className="flex items-center justify-end gap-2 px-5 py-2.5 bg-white dark:bg-neutral-800">
      <span className="w-2 h-2 rounded-full bg-green-500 animate-blink" />
      <span className="text-sm font-bold text-green-500">Live</span>
      <span className="text-xs font-medium text-gray-400 font-mono tabular-nums">
        {formatDate(time)}&nbsp;&nbsp;{formatTime(time)}
      </span>
    </div>
  )
}

function MarketIndexCard({
  indices,
  currentIdx,
  currency,
  onCurrencyChange,
}: {
  indices: MarketIndex[]
  currentIdx: number
  currency: 'usd' | 'krw'
  onCurrencyChange: (c: 'usd' | 'krw') => void
}) {
  const idx = indices[currentIdx]
  const isPositive = idx.change >= 0
  // 토스증권 컨벤션: 상승=빨강, 하락=파랑
  const trendColor = isPositive ? 'text-red-500' : 'text-blue-500'
  const sign = isPositive ? '+' : ''

  return (
    <div className="flex items-center gap-3 mx-4 mt-3 mb-3">
      {/* 시세 카드 */}
      <div className="flex-1 px-4 py-3.5 bg-white dark:bg-neutral-800 rounded-[18px] shadow-sm overflow-hidden">
        <div key={idx.id} className="animate-slideUp flex items-baseline justify-between">
          <div className="flex items-baseline gap-2">
            <span className="text-xs font-medium text-gray-400">{idx.name}</span>
            <span className="text-[21px] font-bold tabular-nums">{formatNumber(idx.value)}</span>
          </div>
          <span className={`text-lg font-bold tabular-nums ${trendColor}`}>
            {sign}{idx.changePercent.toFixed(2)}%
          </span>
        </div>
      </div>

      {/* 통화 토글 */}
      <div className="flex p-[3px] bg-gray-200 dark:bg-neutral-700 rounded-[10px]">
        {(['usd', 'krw'] as const).map((c) => (
          <button
            key={c}
            onClick={() => onCurrencyChange(c)}
            className={`px-3 py-1 rounded-lg text-[13px] font-semibold transition-all duration-200 min-w-[36px]
              ${currency === c
                ? 'bg-white dark:bg-neutral-600 text-gray-900 dark:text-gray-100 shadow-sm'
                : 'text-gray-400 dark:text-gray-500'
              }`}
          >
            {c === 'usd' ? '$' : '원'}
          </button>
        ))}
      </div>
    </div>
  )
}

function BrandLogo({ ticker, color }: { ticker: string; color: string }) {
  const domain = TICKER_DOMAIN[ticker]
  const primarySrc = domain
    ? BRANDFETCH_CLIENT_ID
      ? `https://asset.brandfetch.io/${domain}?c=${BRANDFETCH_CLIENT_ID}`
      : `https://logo.brandfetch.io/${domain}`
    : null

  const [imgSrc, setImgSrc] = useState<string | null>(primarySrc)
  const [triedFavicon, setTriedFavicon] = useState(false)

  const handleError = () => {
    if (!triedFavicon && domain) {
      setTriedFavicon(true)
      setImgSrc(`https://www.google.com/s2/favicons?domain=${domain}&sz=128`)
    } else {
      setImgSrc(null)
    }
  }

  return (
    <div
      className="logo-tile flex-shrink-0"
      style={{
        background: `linear-gradient(145deg, ${color}28 0%, ${color}12 100%)`,
        borderColor: `${color}38`,
      }}
    >
      {imgSrc ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={imgSrc}
          alt={ticker}
          width={30}
          height={30}
          style={{ objectFit: 'contain' }}
          onError={handleError}
        />
      ) : (
        <span className="text-sm font-bold" style={{ color }}>
          {ticker.slice(0, 2)}
        </span>
      )}
    </div>
  )
}

function CompanyRow({
  company,
  currency,
  exchangeRate,
}: {
  company: CompanyResult
  currency: 'usd' | 'krw'
  exchangeRate: number
}) {
  const isPositive = company.changePercent >= 0
  const changeColor = isPositive ? 'text-green-500' : 'text-red-500'
  const arrow = isPositive ? '↗' : '↘'

  return (
    <div className="flex items-center gap-3.5 px-4 py-3 bg-white dark:bg-neutral-800 rounded-[18px] shadow-sm">
      {/* 순위 */}
      <span className="w-5 text-center text-[13px] font-bold text-gray-300 dark:text-gray-600 flex-shrink-0">
        {company.rank}
      </span>

      {/* 로고 */}
      <BrandLogo ticker={company.ticker} color={company.color} />

      {/* 이름 + 티커 */}
      <div className="flex flex-col gap-0.5 flex-1 min-w-0">
        <span className="text-base font-semibold truncate">{company.name}</span>
        <span className="text-[13px] text-gray-400">{company.ticker}</span>
      </div>

      {/* 시가총액 + 변동률 */}
      <div className="flex flex-col items-end gap-0.5 flex-shrink-0">
        <span className="text-base font-bold tabular-nums">
          {formatMarketCap(company.marketCapUSD, currency, exchangeRate)}
        </span>
        <span className={`flex items-center gap-0.5 text-[13px] font-semibold tabular-nums ${changeColor}`}>
          <span>{arrow}</span>
          <span>{Math.abs(company.changePercent).toFixed(2)}%</span>
        </span>
      </div>
    </div>
  )
}

function SkeletonRow({ rank }: { rank: number }) {
  return (
    <div className="flex items-center gap-3.5 px-4 py-3 bg-white dark:bg-neutral-800 rounded-[18px] shadow-sm animate-pulse">
      <span className="w-5 text-center text-[13px] font-bold text-gray-200 dark:text-gray-700">{rank}</span>
      <div className="w-[50px] h-[50px] rounded-[14px] bg-gray-100 dark:bg-neutral-700 flex-shrink-0" />
      <div className="flex flex-col gap-1.5 flex-1">
        <div className="h-4 bg-gray-100 dark:bg-neutral-700 rounded w-24" />
        <div className="h-3 bg-gray-100 dark:bg-neutral-700 rounded w-12" />
      </div>
      <div className="flex flex-col items-end gap-1.5">
        <div className="h-4 bg-gray-100 dark:bg-neutral-700 rounded w-20" />
        <div className="h-3 bg-gray-100 dark:bg-neutral-700 rounded w-14" />
      </div>
    </div>
  )
}

function ErrorBanner({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="mx-4 px-4 py-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-[14px] flex items-center justify-between gap-3">
      <div>
        <p className="text-sm font-semibold text-red-600 dark:text-red-400">데이터를 불러올 수 없습니다</p>
        <p className="text-xs text-red-400 mt-0.5">API 키를 확인하거나 잠시 후 다시 시도해주세요.</p>
      </div>
      <button
        onClick={onRetry}
        className="text-xs font-semibold text-red-500 bg-red-100 dark:bg-red-900/40 px-3 py-1.5 rounded-lg hover:bg-red-200 transition-colors"
      >
        재시도
      </button>
    </div>
  )
}

function StaleBanner() {
  return (
    <div className="mx-4 px-3 py-1.5 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-[10px]">
      <p className="text-xs text-yellow-600 dark:text-yellow-400 text-center">
        ⚠ API 일시 오류 — 마지막 캐시 데이터 표시 중
      </p>
    </div>
  )
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function TitansPage() {
  const [companies, setCompanies]       = useState<CompanyResult[] | null>(null)
  const [isLoading, setIsLoading]       = useState(true)
  const [isError, setIsError]           = useState(false)
  const [isStale, setIsStale]           = useState(false)
  const [currency, setCurrency]         = useState<'usd' | 'krw'>('usd')
  const [currentTime, setCurrentTime]   = useState(new Date())
  const [currentIdxIdx, setCurrentIdxIdx] = useState(0)
  const [indices, setIndices]           = useState<MarketIndex[]>(INITIAL_INDICES)

  // 환율 (인덱스에서 추출)
  const exchangeRate = indices.find(i => i.id === 'usd')?.value ?? 1382.5

  // ── 1초 폴링: /api/market-cap ──────────────────────────────────────────────
  const fetchMarketCap = useCallback(async () => {
    try {
      const res = await fetch('/api/market-cap')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const json = await res.json()
      if (json.error) throw new Error(json.error)
      setCompanies(json.data)
      setIsStale(json.stale ?? false)
      setIsError(false)
    } catch {
      setIsError(true)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchMarketCap()
    const id = setInterval(fetchMarketCap, 1000)
    return () => clearInterval(id)
  }, [fetchMarketCap])

  // ── 30초 폴링: /api/market-index (Yahoo Finance, 15초 서버 캐시) ──────────
  const fetchMarketIndex = useCallback(async () => {
    try {
      const res = await fetch('/api/market-index')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const json = await res.json()
      if (json.error) throw new Error(json.error)
      setIndices(json.data as MarketIndex[])
    } catch (err) {
      console.warn('[market-index] fetch failed, keeping last data:', err)
    }
  }, [])

  useEffect(() => {
    fetchMarketIndex()
    const id = setInterval(fetchMarketIndex, 30_000)
    return () => clearInterval(id)
  }, [fetchMarketIndex])

  // ── 1초마다 시각 업데이트 ──────────────────────────────────────────────────
  useEffect(() => {
    const id = setInterval(() => setCurrentTime(new Date()), 1000)
    return () => clearInterval(id)
  }, [])

  // ── 3초마다 시장지수 카드 전환 ────────────────────────────────────────────
  useEffect(() => {
    const id = setInterval(() => {
      setCurrentIdxIdx(i => (i + 1) % INITIAL_INDICES.length)
    }, 3000)
    return () => clearInterval(id)
  }, [])

  return (
    <div className="max-w-lg mx-auto min-h-screen">
      <LiveIndicatorBar time={currentTime} />

      <MarketIndexCard
        indices={indices}
        currentIdx={currentIdxIdx}
        currency={currency}
        onCurrencyChange={setCurrency}
      />

      {isStale && !isError && <StaleBanner />}

      <div className="flex flex-col gap-2.5 px-4 pb-8 mt-1">
        {isLoading ? (
          // Skeleton UI
          Array.from({ length: 10 }, (_, i) => (
            <SkeletonRow key={i} rank={i + 1} />
          ))
        ) : isError && !companies ? (
          // 완전 실패 (fallback 캐시도 없음)
          <ErrorBanner onRetry={fetchMarketCap} />
        ) : (
          companies?.map(company => (
            <CompanyRow
              key={company.ticker}
              company={company}
              currency={currency}
              exchangeRate={exchangeRate}
            />
          ))
        )}
      </div>
    </div>
  )
}
