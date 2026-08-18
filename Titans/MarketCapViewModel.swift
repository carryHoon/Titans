//
//  MarketCapViewModel.swift
//  Titans
//
//  ContentView.swift에서 분리한 거래소 피드 상태(ExchangeFeed) + 메인 ViewModel. 동작 동일.
//

import SwiftUI
import Combine

// MARK: - Exchange Feed (거래소 전용 피드 상태)

/// NASDAQ·NYSE처럼 백엔드 전용 엔드포인트를 가진 거래소의 로드 상태.
/// ALL(companies)과 완전히 분리해 서로 상태를 덮어쓰지 않도록 함.
struct ExchangeFeed {
    var companies: [Company] = []
    var isLoading = true
    var isError   = false
    var isStale   = false
    var basDt: String? = nil   // KRX 기준일("YYYYMMDD") — 코스피/코스닥 "종가 기준" 표기용
    var asOf: String? = nil    // EOD 계열(JPX/SSE/SZSE/NSE) 스냅샷 거래일("YYYY-MM-DD") — "종가 기준" 표기용
}

// MARK: - ViewModel

@MainActor
final class MarketCapViewModel: ObservableObject {
    @Published var companies: [Company] = []
    @Published var exchangeRate: Double = 1450.0            // KRW/USD (위젯·기존 로직 호환)
    @Published var exchangeRates: [String: Double] = [:]    // 다통화 rate 맵 (표시 통화 환산용)
    @Published var isLoading = true
    @Published var isError   = false
    @Published var isStale   = false

    // 거래소 전용 피드 (NASDAQ/NYSE …) — Market 키로 분리 저장
    @Published var exchangeFeeds: [Market: ExchangeFeed] = [:]

    // 거래소별 지수 스파크라인 (ALL/US/KR) — Market 키로 분리 저장. 하루 단위 데이터라 1회 로드.
    @Published var charts: [Market: MarketChart] = [:]

    // 이번 세션에서 이미 네트워크로 갱신한 차트(중복 요청 방지). 캐시된 값이 있어도 세션당 1회는 새로 받는다.
    private var chartsFetched: Set<Market> = []

    // 데이터 API — Vercel 서버리스 상시가동 호스팅
    static let host    = "titans-sooty.vercel.app"
    static let apiBase = "https://\(host)"

    private let endpoint      = URL(string: "\(apiBase)/api/market-cap")!
    private let indexEndpoint = URL(string: "\(apiBase)/api/market-index")!
    private let chartEndpoint = "\(apiBase)/api/market-chart"

    init() {
        // 지수 그래프는 EOD(하루 1회 변동)라, 지난 세션 그래프를 즉시 표시해 콜드 로드 지연을 없앤다.
        // (24h 캐시 백엔드의 첫 히트가 느려도 사용자는 캐시 그래프를 바로 보고, 곧 최신값으로 갱신된다.)
        charts = ChartCache.load()
    }

    /// market-cap 엔드포인트에서 데이터를 받아 Company 배열로 매핑하는 공통 로직.
    /// ALL 피드와 거래소 전용 피드가 동일한 디코딩·기준순위 매핑을 공유한다.
    /// 순위변동(previousRank)은 전 거래소 서버 제공값을 그대로 사용한다.
    /// (KR도 백엔드가 직전 basDt 스냅샷 대비로 계산해 내려주므로 클라이언트 baseline이 불필요.)
    private func loadCompanies(from url: URL) async throws
        -> (companies: [Company], stale: Bool, rate: Double?, rates: [String: Double]?, basDt: String?, asOf: String?) {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(MarketCapResponse.self, from: data)
        if let apiError = decoded.error, decoded.data.isEmpty {
            throw NSError(domain: "API", code: 0, userInfo: [NSLocalizedDescriptionKey: apiError])
        }
        let mapped: [Company] = decoded.data.map { api in
            Company(
                rank:         api.rank,
                previousRank: api.previousRank,
                name:         api.name,
                ticker:       api.ticker,
                marketCapUSD: api.marketCapUSD,
                change:       api.changePercent,
                color:        Color(hex: api.color),
                domain:       api.domain
            )
        }
        return (mapped, decoded.stale ?? false, decoded.exchangeRate, decoded.exchangeRates, decoded.basDt, decoded.asOf)
    }

    /// 표시 통화의 "1 USD 당 금액" rate. USD는 기준 통화라 1.0.
    /// 백엔드 다통화 맵을 우선 사용하고, 없으면(구버전 응답) KRW는 exchangeRate로, 그 외는 상수로 방어한다.
    func rate(for currency: Currency) -> Double {
        switch currency {
        case .usd: return 1.0
        case .krw: return exchangeRates["KRW"] ?? exchangeRate
        default:
            let fallback: [String: Double] = ["JPY": 155, "CNY": 7.2, "EUR": 0.92]
            return exchangeRates[currency.rawValue] ?? fallback[currency.rawValue] ?? 1.0
        }
    }

    func fetch() async {
        do {
            let result = try await loadCompanies(from: endpoint)
            // 주기적 시세 갱신은 애니메이션 없이 즉시 반영한다. (withAnimation은 전역 트랜잭션이라
            // 좌우 스와이프 전환과 겹치면 리스트 리플로우가 드래그와 충돌해 끊김을 유발함)
            companies = result.companies
            isStale   = result.stale
            isError   = false
            isLoading = false
            if let rate = result.rate { exchangeRate = rate }
            if let rates = result.rates { exchangeRates = rates }
        } catch {
            isError = true
            // 기존 데이터가 있으면 Stale fallback으로 유지, 없으면 skeleton 유지
            if companies.isEmpty { isLoading = true }
        }
    }

    /// 거래소 전용 피드 로드 (NASDAQ/NYSE …). 해당 Market의 exchangeFeeds 항목에만
    /// 반영해 ALL 피드와 간섭하지 않음.
    func fetchExchange(_ market: Market) async {
        guard let param = market.apiExchangeParam,
              let url = URL(string: "\(Self.apiBase)/api/market-cap?exchange=\(param)")
        else { return }
        do {
            let result = try await loadCompanies(from: url)
            // 섹션 도착 시 재fetch 결과도 애니메이션 없이 즉시 반영. (스와이프 착지와 겹치는
            // withAnimation 리플로우가 ALL↔NASDAQ 전환 끊김의 원인)
            exchangeFeeds[market] = ExchangeFeed(
                companies: result.companies,
                isLoading: false,
                isError:   false,
                isStale:   result.stale,
                basDt:     result.basDt,
                asOf:      result.asOf
            )
            if let rate = result.rate { exchangeRate = rate }
            if let rates = result.rates { exchangeRates = rates }
        } catch {
            // 기존 데이터가 있으면 Stale fallback으로 유지, 없으면 skeleton 유지
            var feed = exchangeFeeds[market] ?? ExchangeFeed()
            feed.isError = true
            if feed.companies.isEmpty { feed.isLoading = true }
            exchangeFeeds[market] = feed
        }
    }

    /// 검색 유니버스 워밍업 — 백엔드 전용 피드를 가진 모든 거래소를 실행 직후 1회 프리페치해,
    /// 사용자가 해당 거래소 탭을 방문하지 않아도 검색에 전 종목이 잡히게 한다.
    /// (탭 진입 시 .task(id:) 루프가 라이브 갱신을 이어받으므로 여기서는 1회성 로드로 충분)
    /// 이미 종목이 채워진 피드는 건너뛴다. 백엔드가 스냅샷을 캐시 서빙하므로 추가 벤더 크레딧 소모는 없다.
    func prefetchExchangesForSearch() async {
        let markets = Market.allCases.filter {
            $0.apiExchangeParam != nil && (exchangeFeeds[$0]?.companies.isEmpty ?? true)
        }
        await withTaskGroup(of: Void.self) { group in
            for market in markets {
                group.addTask { await self.fetchExchange(market) }
            }
        }
    }

    /// 현재 로드된 전 거래소 유니버스(ALL + 거래소별 피드)의 종목별 시가총액을
    /// 오늘 기준일(KST) 스냅샷으로 적재한다. "나만의 거래소"의 주간/월간 하이라이트 기준선용.
    /// 순수 추가 로직 — 하루 1개 엔트리로 upsert되며, 실패해도 앱 동작에 영향 없다.
    func captureUniverseSnapshot() {
        var caps: [String: Double] = [:]
        for c in companies where caps[c.ticker] == nil {
            caps[c.ticker] = c.marketCapUSD
        }
        for feed in exchangeFeeds.values {
            for c in feed.companies where caps[c.ticker] == nil {
                caps[c.ticker] = c.marketCapUSD
            }
        }
        RankSnapshotStore.record(caps: caps)
    }

    func fetchIndices() async -> [MarketIndex]? {
        guard let (data, response) = try? await URLSession.shared.data(from: indexEndpoint),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MarketIndexResponse.self, from: data)
        else { return nil }
        return decoded.data.map { api in
            MarketIndex(id: api.id, name: api.name, value: api.value, change: api.change, changePercent: api.changePercent)
        }
    }

    /// 거래소 지수 스파크라인 로드. 그래프는 일별(EOD) 데이터라 값이 하루에 한 번만 바뀌므로
    /// 이미 로드된 거래소는 다시 받지 않는다(백엔드도 24h 캐시). 실패해도 조용히 건너뛴다(그래프만 빔).
    func fetchChart(_ market: Market) async {
        // 세션당 1회만 갱신(캐시된 값이 있어도 최신화). 실패 시 fetched에 넣지 않아 재시도가 가능하다.
        guard let param = market.chartParam, !chartsFetched.contains(market),
              let url = URL(string: "\(chartEndpoint)?exchange=\(param)")
        else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MarketChartResponse.self, from: data),
              decoded.points.count >= 2
        else { return }
        charts[market] = MarketChart(name: decoded.name, points: decoded.points, changePercent: decoded.changePercent)
        chartsFetched.insert(market)
        ChartCache.save(charts)   // 다음 세션 즉시 표시용 로컬 캐시 갱신
    }
}

// MARK: - Chart 로컬 캐시

/// 지수 스파크라인의 마지막 성공 데이터를 로컬(UserDefaults)에 보관한다.
/// EOD(하루 1회 변동) 데이터라, 다음 실행 시 캐시를 즉시 표시해 서버 콜드 로드 지연을 감춘다.
/// Market 키는 rawValue(String)로 직렬화. (위젯은 스파크라인을 쓰지 않아 App Group 불필요.)
private enum ChartCache {
    private static let key = "marketChartCache"

    static func load() -> [Market: MarketChart] {
        // 1) 지난 세션 로컬 캐시(최신 실데이터) 우선.
        if let data = UserDefaults.standard.data(forKey: key),
           let raw = try? JSONDecoder().decode([String: MarketChart].self, from: data), !raw.isEmpty {
            return mapped(raw)
        }
        // 2) 없으면(앱 삭제 후 첫 실행) Swift 임베드 시드로 첫 프레임에 즉시 그래프를 깐다.
        //    곧바로 fetchChart가 라이브 값으로 덮어쓰므로 시드는 최초 1회 플레이스홀더로만 쓰인다.
        let seed = SeedCharts.load()
        if !seed.isEmpty { return mapped(seed) }
        return [:]
    }

    /// exchange 문자열 키(= Market.rawValue) → Market 매핑.
    private static func mapped(_ raw: [String: MarketChart]) -> [Market: MarketChart] {
        var result: [Market: MarketChart] = [:]
        for (k, v) in raw { if let m = Market(rawValue: k) { result[m] = v } }
        return result
    }

    static func save(_ charts: [Market: MarketChart]) {
        let raw = Dictionary(uniqueKeysWithValues: charts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

