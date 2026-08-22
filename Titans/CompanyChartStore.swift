//
//  CompanyChartStore.swift
//  Titans
//
//  종목 상세 화면(CompanyDetailView)의 시가총액 히스토리 로더.
//  · 미래 백엔드 `GET /api/company-chart?ticker=&range=` 호출 자리를 확보한다.
//  · 백엔드가 아직 없으므로, 네트워크 실패 시 결정론적 시드 곡선으로 폴백해 UI가 즉시 동작한다.
//    (SeedCharts / ChartCache 패턴과 동일 철학 — 실데이터가 오면 그대로 덮어쓴다.)
//  · 티커+기간 단위로 로컬(UserDefaults) 캐시해 재진입/기간 전환을 즉시 표시한다.
//
//  안전성: 순수 추가 컴포넌트. 기존 데이터 흐름과 분리돼 있고, 모든 실패는 시드로 흡수한다.
//

import SwiftUI
import Combine

@MainActor
final class CompanyChartStore: ObservableObject {
    /// 현재 표시 중인 차트(선택된 기간 기준). nil = 아직 첫 로드 전.
    @Published var chart: CompanyChart?
    /// 비교용 거래소 지수 시드(오래된→최신, chart.points와 인덱스 정렬). base 미적용 원값이며 뷰에서 100으로 리베이스한다.
    /// Phase 1: 결정론적 시드. 실데이터(백엔드 지수 시계열)가 오면 동일 자리(같은 길이)로 대체된다.
    @Published var indexSeries: [Double] = []
    /// 실데이터 지수명(백엔드 제공 시). nil이면 뷰가 거래소 기반 폴백 라벨을 쓴다.
    @Published var indexName: String? = nil
    @Published var isLoading = true

    private let ticker: String
    private let name: String
    private let exchangeParam: String? // 백엔드 지수 매핑용(?exchange=). company.market 기반.
    private let anchorCapUSD: Double   // 시드 곡선의 최신값 앵커(= 현재 시가총액, trillion USD)

    // 기간별 세션 캐시 — 한 번 만든 기간은 즉시 재사용(기간 왕복 시 깜빡임 방지).
    private var bySeg: [ChartRange: CompanyChart] = [:]
    private var fetched: Set<ChartRange> = []

    private var endpointBase: String { "\(MarketCapViewModel.apiBase)/api/company-chart" }

    init(company: Company) {
        self.ticker = company.ticker
        self.name = company.name
        self.exchangeParam = company.market?.chartParam
        self.anchorCapUSD = company.marketCapUSD

        // 첫 프레임 즉시 그래프(토스식): 기본기간(.m3)을 디스크 캐시(있으면 실데이터) → 없으면 시드로 미리 채운다.
        // 이후 .task의 load(.m3)가 세션 캐시/네트워크로 자연스럽게 최신화한다(중복 표시 없음).
        let initial: ChartRange = .m3
        if let disk = ChartDiskCache.load(ticker: ticker, range: initial) {
            bySeg[initial] = disk
            chart = disk
        } else {
            chart = Self.seed(ticker: ticker, name: name, anchorCapUSD: anchorCapUSD, range: initial)
        }
        isLoading = false
        applyIndex()
    }

    /// 선택 기간의 차트를 로드한다.
    ///  1) 세션 캐시 → 2) 로컬(UserDefaults) 캐시 → 즉시 표시
    ///  3) 백엔드 fetch 성공 시 최신값으로 갱신·캐시
    ///  4) 백엔드가 없거나 실패하면 결정론적 시드로 폴백(에러 상태를 사용자에게 노출하지 않음)
    func load(_ range: ChartRange) async {
        // 1) 세션 캐시 즉시 표시
        if let cached = bySeg[range] {
            chart = cached
            isLoading = false
        } else if let disk = ChartDiskCache.load(ticker: ticker, range: range) {
            // 2) 로컬 캐시 즉시 표시
            bySeg[range] = disk
            chart = disk
            isLoading = false
        } else {
            // 3) 첫 노출: 시드로 즉시 채워 빈 화면을 없앤다(곧 네트워크 결과로 대체 시도).
            let seeded = Self.seed(ticker: ticker, name: name, anchorCapUSD: anchorCapUSD, range: range)
            chart = seeded
            isLoading = false
        }

        // 지수 비교선 — 실데이터(백엔드 index)만 반영. 없으면 비움(가짜 시드 미표시).
        applyIndex()

        // 세션당 기간별 1회는 네트워크 갱신 시도(캐시가 있어도 최신화). 실패해도 조용히 시드/캐시 유지.
        guard !fetched.contains(range) else { return }
        if let fresh = await fetchRemote(range) {
            bySeg[range] = fresh
            chart = fresh
            fetched.insert(range)
            ChartDiskCache.save(fresh, ticker: ticker, range: range)
            applyIndex()   // 실데이터 지수 반영(없으면 비움).
        }
    }

    /// 비교 지수 시리즈를 확정한다. 백엔드가 종목 points와 정렬된 **실제 시장지수**를 주면 그걸 쓰고,
    /// 부재/불일치면 비운다(가짜 시드 지수는 절대 표시하지 않는다 — "지수 대비"엔 실 지수만).
    /// 실 지수가 아직 없으면 indexSeries=[] → 뷰는 비교 차트를 스켈레톤으로 두고 네트워크 결과를 기다린다.
    private func applyIndex() {
        let count = chart?.points.count ?? 0
        if let ip = chart?.indexPoints, ip.count == count, count >= 2 {
            indexSeries = ip
            indexName = chart?.indexName
        } else {
            indexName = nil
            indexSeries = []
        }
    }

    // MARK: - 네트워크 (미래 백엔드 계약)

    /// `GET /api/company-chart?ticker=&range=&exchange=` → CompanyChart. 실패/부재 시 nil.
    /// exchange는 비교 지수 매핑용(백엔드가 거래소 지수를 선택). 없으면 백엔드가 티커로 폴백.
    private func fetchRemote(_ range: ChartRange) async -> CompanyChart? {
        guard let encoded = ticker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        var urlString = "\(endpointBase)?ticker=\(encoded)&range=\(range.rawValue)"
        if let ex = exchangeParam { urlString += "&exchange=\(ex)" }
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanyChartResponse.self, from: data),
              decoded.error == nil, decoded.points.count >= 2
        else { return nil }
        // 지수는 종목 points와 길이가 같을 때만 채택(정렬 보장). 아니면 nil → 시드 폴백.
        let idx = decoded.index
        let indexPoints = (idx?.points.count == decoded.points.count) ? idx?.points : nil
        return CompanyChart(ticker: decoded.ticker, name: decoded.name, points: decoded.points,
                            indexName: indexPoints != nil ? idx?.name : nil,
                            indexPoints: indexPoints)
    }

    // MARK: - 시드 생성기 (백엔드 부재 동안 플레이스홀더)

    /// 티커·기간에 대해 결정론적(같은 입력 → 같은 곡선)인 시가총액 곡선을 만든다.
    /// 마지막 포인트는 현재 시총(anchor)에 고정하고, 과거로 갈수록 완만히 낮아지는 성장 곡선 + 미세 노이즈.
    /// 실데이터가 아니므로 값 자체에 의미는 없고, UI·인터랙션 개발/검증용 형태만 제공한다.
    static func seed(ticker: String, name: String, anchorCapUSD: Double, range: ChartRange) -> CompanyChart {
        let count = pointCount(for: range)
        let spacingDays = spacing(for: range, count: count)

        var rng = SeededRNG(seed: stableHash(ticker) &+ UInt64(range.rawValue.count) &* 2654435761)

        // 과거 시작값: 기간이 길수록 더 낮은 지점에서 시작(장기 성장 서사).
        let startFactor: Double
        switch range {
        case .w1:  startFactor = 0.97
        case .m1:  startFactor = 0.90
        case .m3:  startFactor = 0.80
        case .y1:  startFactor = 0.60
        case .y5:  startFactor = 0.28
        case .all: startFactor = 0.15
        }
        let anchor = max(anchorCapUSD, 0.0001)
        let start = anchor * startFactor

        // 오래된→최신. 지수 보간 위에 소폭 노이즈. 마지막 값은 정확히 anchor로 고정.
        var caps: [Double] = []
        caps.reserveCapacity(count)
        for i in 0..<count {
            let t = count > 1 ? Double(i) / Double(count - 1) : 1.0
            let base = start * pow(anchor / start, t)              // 지수 성장 보간
            let noise = 1.0 + (rng.nextUnit() - 0.5) * 0.06        // ±3% 흔들림
            caps.append(base * noise)
        }
        if !caps.isEmpty { caps[caps.count - 1] = anchor }

        // 날짜: 오늘(KST)에서 spacingDays 간격으로 과거로.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? cal.timeZone
        let today = Date()
        var points: [CompanyChartPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let daysBack = Double(count - 1 - i) * spacingDays
            let date = cal.date(byAdding: .day, value: -Int(daysBack.rounded()), to: today) ?? today
            points.append(CompanyChartPoint(date: ymd(date, cal: cal), capUSD: caps[i]))
        }
        return CompanyChart(ticker: ticker, name: name, points: points)
    }

    /// 기간별 시드 포인트 개수(그래프 매끄러움 vs 비용 균형).
    private static func pointCount(for range: ChartRange) -> Int {
        switch range {
        case .w1:  return 7
        case .m1:  return 30
        case .m3:  return 60
        case .y1:  return 120
        case .y5:  return 180
        case .all: return 240
        }
    }

    /// 포인트 간 날짜 간격(일). 전체 기간 / 포인트 수.
    /// all = 상장 이후를 흉내 내는 장기 서사(약 20년) — 사용자가 기대하는 거시적 성장 곡선.
    /// (실제 상장일·정확 값은 백엔드가 담당; 시드는 형태 프리뷰용 플레이스홀더.)
    private static func spacing(for range: ChartRange, count: Int) -> Double {
        let totalDays = Double(range.days ?? 365 * 20)
        return count > 1 ? totalDays / Double(count - 1) : 1
    }

    private static func ymd(_ date: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 런치 간 안정적인 문자열 해시(Swift String.hashValue는 실행마다 달라짐 → 시드용으로 부적합).
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603   // FNV-1a offset
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}

// MARK: - 결정론적 난수 (시드 곡선 노이즈용)

/// 작은 선형 합동 생성기(LCG). 같은 seed → 같은 수열이라 곡선이 재진입마다 흔들리지 않는다.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    /// [0,1) 실수.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}

// MARK: - 종목 차트 로컬 캐시

/// 종목별·기간별 차트의 마지막 성공 데이터를 로컬(UserDefaults)에 보관한다.
/// EOD(하루 1회 변동) 특성상, 재진입 시 캐시를 즉시 표시해 네트워크 지연을 감춘다.
private enum ChartDiskCache {
    private static func key(ticker: String, range: ChartRange) -> String {
        "companyChart.\(ticker).\(range.rawValue)"
    }

    static func load(ticker: String, range: ChartRange) -> CompanyChart? {
        guard let data = UserDefaults.standard.data(forKey: key(ticker: ticker, range: range)) else { return nil }
        return try? JSONDecoder().decode(CompanyChart.self, from: data)
    }

    static func save(_ chart: CompanyChart, ticker: String, range: ChartRange) {
        if let data = try? JSONEncoder().encode(chart) {
            UserDefaults.standard.set(data, forKey: key(ticker: ticker, range: range))
        }
    }
}
