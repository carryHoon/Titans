//
//  ContentView.swift
//  Titans
//
//  Created by MacH on 7/21/26.
//

import SwiftUI
import Combine

// MARK: - Currency

enum Currency { case usd, krw }

// MARK: - Market (거래소 필터)

/// 거래소 카테고리 필터. 새 거래소는 case만 추가하면 칩이 자동 확장됨.
enum Market: String, CaseIterable, Identifiable {
    case all, nasdaq, nyse, kospi, jpx

    var id: String { rawValue }

    /// 칩에 표시되는 라벨
    var title: String {
        switch self {
        case .all:    return "ALL"
        case .nasdaq: return "NASDAQ"
        case .nyse:   return "NYSE"
        case .kospi:  return "KOSPI"
        case .jpx:    return "JPX"
        }
    }
}

/// Ticker → 상장 거래소 매핑. 신규 종목 추가 시 여기에 등록.
private let tickerMarket: [String: Market] = [
    // NASDAQ
    "NVDA": .nasdaq, "AAPL": .nasdaq, "MSFT": .nasdaq, "GOOGL": .nasdaq,
    "AMZN": .nasdaq, "META": .nasdaq, "TSLA": .nasdaq, "AVGO": .nasdaq,
    "COST": .nasdaq, "NFLX": .nasdaq, "PLTR": .nasdaq, "AMD": .nasdaq, "MU": .nasdaq,
    // NYSE
    "BRK.B": .nyse, "JPM": .nyse, "TSM": .nyse, "LLY": .nyse, "WMT": .nyse,
    "V": .nyse, "ORCL": .nyse, "XOM": .nyse, "MA": .nyse, "UNH": .nyse,
    // KOSPI (KRX)
    "005930.KS": .kospi, "000660.KS": .kospi,
]

// MARK: - Market Data

struct MarketIndex: Identifiable {
    let id: String
    let name: String
    var value: Double
    var change: Double
    var changePercent: Double
}

private var initialIndices: [MarketIndex] = [
    MarketIndex(id: "usd",    name: "달러 환율", value: 1450.00,  change:   0.00,   changePercent:  0.00),
    MarketIndex(id: "nasdaq", name: "나스닥",   value: 19854.32, change: -123.45,  changePercent: -0.62),
    MarketIndex(id: "kospi",  name: "코스피",   value: 2856.78,  change:   12.34,  changePercent:  0.43),
    MarketIndex(id: "kosdaq", name: "코스닥",   value:  854.23,  change:   -4.56,  changePercent: -0.53),
]

// MARK: - Company Data

struct Company: Identifiable {
    // ticker를 ID로 사용해 ForEach가 안정적으로 뷰를 재사용할 수 있게 함
    var id: String { ticker }
    let rank: Int
    let name: String
    let ticker: String
    let marketCapUSD: Double   // USD 조(trillion) 단위
    let change: Double         // changePercent (%) — API의 dp 값
    let color: Color
    let symbol: String

    /// Ticker 기반 상장 거래소. 미등록 종목은 필터에서 ALL에만 노출됨.
    var market: Market? { tickerMarket[ticker] }
}

// MARK: - API Response DTOs

struct APICompanyResult: Decodable {
    let rank: Int
    let ticker: String
    let name: String
    let color: String          // hex 문자열 e.g. "#78BB17"
    let currentPrice: Double
    let change: Double         // dollar change (사용하지 않음)
    let changePercent: Double  // % change → Company.change 에 매핑
    let marketCapUSD: Double   // trillion USD
}

struct MarketCapResponse: Decodable {
    let exchangeRate: Double?
    let data: [APICompanyResult]
    let updatedAt: Double
    let stale: Bool?
    let error: String?
}

struct APIIndexData: Decodable {
    let id: String
    let name: String
    let value: Double
    let change: Double
    let changePercent: Double
    let updatedAt: Double
}

struct MarketIndexResponse: Decodable {
    let data: [APIIndexData]
    let stale: Bool?
}

// MARK: - Ticker → SF Symbol 매핑

private let tickerSymbols: [String: String] = [
    "NVDA":  "cpu.fill",
    "AAPL":  "apple.logo",
    "MSFT":  "square.grid.2x2.fill",
    "GOOGL": "magnifyingglass",
    "AMZN":  "bag.fill",
    "META":  "bubble.left.and.bubble.right.fill",
    "TSLA":  "bolt.car",
    "BRK.B": "chart.bar.fill",
    "AVGO":  "cpu.fill",
    "JPM":   "building.columns.fill",
    "TSM":   "memorychip.fill",
    // 11–20위
    "LLY":   "pills.fill",
    "WMT":   "cart.fill",
    "V":     "creditcard.fill",
    "ORCL":  "server.rack",
    "XOM":   "fuelpump.fill",
    "MA":    "creditcard",
    "COST":  "basket.fill",
    "NFLX":  "play.rectangle.fill",
    "UNH":   "heart.fill",
    "PLTR":  "waveform.path.ecg",
    "SPCX":  "airplane.departure",
    "AMD":   "cpu",
    "MU":    "memorychip",
    // Tadawul (Saudi Arabia)
    "2222.SR":   "drop.fill",
    // KRX (Korea)
    "005930.KS": "memorychip.fill",
    "000660.KS": "memorychip",
]

// MARK: - Brandfetch

private let brandfetchClientId = "1idj1IMRGO60qnHErBy"

private let tickerDomain: [String: String] = [
    "NVDA":    "nvidia.com",
    "AAPL":    "apple.com",
    "MSFT":    "microsoft.com",
    "GOOGL":   "google.com",
    "AMZN":    "amazon.com",
    "META":    "meta.com",
    "TSLA":    "tesla.com",
    "BRK.B":   "berkshirehathaway.com",
    "AVGO":    "broadcom.com",
    "JPM":     "jpmorganchase.com",
    "TSM":     "tsmc.com",
    "LLY":     "lilly.com",
    "WMT":     "walmart.com",
    "V":       "visa.com",
    "ORCL":    "oracle.com",
    "XOM":     "exxonmobil.com",
    "MA":      "mastercard.com",
    "COST":    "costco.com",
    "NFLX":    "netflix.com",
    "UNH":     "unitedhealthgroup.com",
    "PLTR":      "palantir.com",
    "SPCX":      "spacex.com",
    "AMD":       "amd.com",
    "MU":        "micron.com",
    "2222.SR":   "aramco.com",
    // KRX (Korea)
    "005930.KS": "samsung.com",
    "000660.KS": "skhynix.com",
]

// MARK: - Color(hex:) Extension

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - ViewModel

@MainActor
final class MarketCapViewModel: ObservableObject {
    @Published var companies: [Company] = []
    @Published var exchangeRate: Double = 1450.0
    @Published var isLoading = true
    @Published var isError   = false
    @Published var isStale   = false

    // 시뮬레이터는 Mac의 localhost로, 실제 기기는 같은 Wi-Fi의 Mac LAN IP로 자동 연결
    #if targetEnvironment(simulator)
    static let host = "localhost"
    #else
    static let host = "172.30.1.21"
    #endif

    private let endpoint      = URL(string: "http://\(host):3000/api/market-cap")!
    private let indexEndpoint = URL(string: "http://\(host):3000/api/market-index")!

    func fetch() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
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
                    name:         api.name,
                    ticker:       api.ticker,
                    marketCapUSD: api.marketCapUSD,
                    change:       api.changePercent,
                    color:        Color(hex: api.color),
                    symbol:       tickerSymbols[api.ticker] ?? "chart.line.uptrend.xyaxis"
                )
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                companies = mapped
                isStale   = decoded.stale ?? false
                isError   = false
                isLoading = false
            }
            if let rate = decoded.exchangeRate {
                exchangeRate = rate
            }
        } catch {
            isError = true
            // 기존 데이터가 있으면 Stale fallback으로 유지, 없으면 skeleton 유지
            if companies.isEmpty { isLoading = true }
        }
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
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var viewModel = MarketCapViewModel()

    @State private var indices: [MarketIndex] = initialIndices
    @State private var currentMarketIndex: Int = 0
    @State private var currentTime: Date = Date()
    @State private var selectedCurrency: Currency = .usd
    @State private var selectedMarket: Market = .all

    private static let switchTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private static let liveTimer   = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var exchangeRate: Double { viewModel.exchangeRate }

    /// 선택된 거래소로 필터링된 기업 리스트 (ALL이면 전체)
    private var filteredCompanies: [Company] {
        guard selectedMarket != .all else { return viewModel.companies }
        return viewModel.companies.filter { $0.market == selectedMarket }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LiveIndicatorBar(currentTime: currentTime)
                    .padding(.top, 12)

                HStack(alignment: .center, spacing: 12) {
                    SingleMarketTicker(indices: indices, currentIndex: currentMarketIndex)
                    CurrencyToggle(selected: $selectedCurrency)
                }
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .padding(.top, -10)
                .padding(.bottom, 12)

                // Stale 배너 (API 장애 시 캐시 데이터 사용 중 알림)
                if viewModel.isStale {
                    StaleBanner()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // 거래소 카테고리 필터 (가로 스크롤 칩) — 에러 상태가 아닐 때만 표시
                if !(viewModel.isError && viewModel.companies.isEmpty) {
                    MarketFilterBar(selected: $selectedMarket)
                        .padding(.bottom, 12)
                }

                LazyVStack(spacing: 10) {
                    // 컬럼 헤더 (순위 / 기업 / 시가총액) — 에러 상태가 아닐 때만 표시
                    if !(viewModel.isError && viewModel.companies.isEmpty) {
                        ColumnHeader()
                    }

                    if viewModel.isLoading && viewModel.companies.isEmpty {
                        // Skeleton UI — 첫 로드 중
                        ForEach(1...20, id: \.self) { rank in
                            SkeletonCompanyRow(rank: rank)
                        }
                    } else if viewModel.isError && viewModel.companies.isEmpty {
                        // 에러 UI — fallback 캐시도 없음
                        ErrorStateView()
                    } else if filteredCompanies.isEmpty {
                        // 선택한 거래소에 해당하는 종목이 없을 때
                        EmptyMarketView(market: selectedMarket)
                    } else {
                        // 실제 데이터 바인딩 (선택된 거래소로 필터링)
                        ForEach(filteredCompanies) { company in
                            CompanyRow(
                                company: company,
                                currency: selectedCurrency,
                                exchangeRate: exchangeRate
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        // 15초 폴링 — 백엔드 quote 캐시(21초)와 sync, Finnhub rate limit 안전
        .task {
            while !Task.isCancelled {
                await viewModel.fetch()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        // 30초 폴링 — Yahoo Finance 지수 (서버 15초 캐시)
        .task(id: "market-index") {
            while !Task.isCancelled {
                if let newIndices = await viewModel.fetchIndices() {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        indices = newIndices
                    }
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onReceive(Self.switchTimer) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                currentMarketIndex = (currentMarketIndex + 1) % indices.count
            }
        }
        .onReceive(Self.liveTimer) { time in
            currentTime = time
        }
    }
}

// MARK: - Stale Banner

struct StaleBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text("API 일시 오류 — 마지막 캐시 데이터 표시 중")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("백엔드 서버에 연결할 수 없습니다")
                .font(.system(size: 16, weight: .semibold))
            Text("\(MarketCapViewModel.host):3000 이 실행 중인지 확인해주세요")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Skeleton Company Row

struct SkeletonCompanyRow: View {
    let rank: Int
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 20)

            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5))
                    .frame(width: 72, height: 14)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 11)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5))
                    .frame(width: 68, height: 14)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5))
                    .frame(width: 48, height: 11)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .opacity(shimmer ? 0.45 : 1.0)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.85)
                .repeatForever(autoreverses: true)
                .delay(Double(rank) * 0.06)
            ) {
                shimmer = true
            }
        }
    }
}

// MARK: - Currency Toggle

struct CurrencyToggle: View {
    @Binding var selected: Currency

    var body: some View {
        HStack(spacing: 2) {
            pill("$", currency: .usd)
            pill("원", currency: .krw)
        }
        .padding(3)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func pill(_ title: String, currency: Currency) -> some View {
        let isSelected = selected == currency
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                selected = currency
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color(.label) : Color(.secondaryLabel))
                .frame(minWidth: 32)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 0.5)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Market Filter Bar (가로 스크롤 칩)

struct MarketFilterBar: View {
    @Binding var selected: Market

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Market.allCases) { market in
                    chip(market)
                }
            }
            // CompanyRow / ColumnHeader의 좌우 패딩(16)과 시작점을 맞춤
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(_ market: Market) -> some View {
        let isSelected = selected == market
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selected = market
            }
        } label: {
            Text(market.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color(.label))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? Color(.label) : Color(.systemGray5))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty Market View (필터 결과 없음)

struct EmptyMarketView: View {
    let market: Market

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("\(market.title) 상장 종목이 없습니다")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Live Indicator Bar

struct LiveIndicatorBar: View {
    let currentTime: Date
    @State private var blinkOpacity: Double = 1.0

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var dateString: String { Self.dateFormatter.string(from: currentTime) }
    private var timeString: String { Self.timeFormatter.string(from: currentTime) }

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .opacity(blinkOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        blinkOpacity = 0.15
                    }
                }

            Text("Live")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.green)

            Text("\(dateString)  \(timeString)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - Single Market Ticker (하나의 카드, 종목 순환)

struct SingleMarketTicker: View {
    let indices: [MarketIndex]
    let currentIndex: Int

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<indices.count, id: \.self) { i in
                    if i == currentIndex {
                        MarketIndexRow(
                            index: indices[i],
                            nameValueSpacing: {
                                switch indices[i].id {
                                case "usd":    return 8
                                case "nasdaq": return 8
                                case "kospi":  return 8
                                case "kosdaq": return 8
                                default:       return 8
                                }
                            }(),
                            changeTrailingPadding: {
                                switch indices[i].id {
                                case "usd":    return 0
                                case "nasdaq": return 0
                                case "kospi":  return 12
                                case "kosdaq": return 15
                                default:       return 0
                                }
                            }()
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .clipped()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Market Index Row (카드 내부 콘텐츠)

struct MarketIndexRow: View {
    let index: MarketIndex
    var nameValueSpacing: CGFloat = 8
    var changeTrailingPadding: CGFloat = 0

    private var isPositive: Bool { index.change >= 0 }
    // 토스증권 컨벤션: 상승=빨강, 하락=파랑
    private var trendColor: Color {
        isPositive
            ? Color(red: 0.95, green: 0.20, blue: 0.20)
            : Color(red: 0.10, green: 0.43, blue: 0.92)
    }

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: index.value)) ?? "\(index.value)"
    }

    private var formattedChangePercent: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)\(String(format: "%.2f", index.changePercent))%"
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: nameValueSpacing) {
                Text(index.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(formattedValue)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Text(formattedChangePercent)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(trendColor)
                .padding(.trailing, changeTrailingPadding)
        }
    }
}

// MARK: - Brand Logo Tile

private struct LogoImage: View {
    let clearbitURL: URL?
    let brandfetchURL: URL?
    let faviconURL: URL?
    let ticker: String
    let color: Color

    var body: some View {
        AsyncImage(url: clearbitURL) { phase in
            switch phase {
            case .success(let image):
                styledLogo(image)
            case .failure:
                AsyncImage(url: brandfetchURL) { phase2 in
                    switch phase2 {
                    case .success(let image):
                        styledLogo(image)
                    case .failure:
                        AsyncImage(url: faviconURL) { phase3 in
                            if case .success(let img) = phase3 {
                                styledLogo(img)
                            } else {
                                textFallback
                            }
                        }
                    default:
                        Color.clear
                    }
                }
            default:
                Color.clear
            }
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private func styledLogo(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 1)
    }

    private var textFallback: some View {
        Text(String(ticker.prefix(2)))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BrandLogoTile: View {
    let ticker: String
    let color: Color

    private var domain: String? { tickerDomain[ticker] }

    private var clearbitURL: URL? {
        domain.flatMap { URL(string: "https://logo.clearbit.com/\($0)?size=200") }
    }

    private var brandfetchURL: URL? {
        domain.flatMap { URL(string: "https://asset.brandfetch.io/\($0)?c=\(brandfetchClientId)") }
    }

    private var faviconURL: URL? {
        domain.flatMap { URL(string: "https://www.google.com/s2/favicons?domain=\($0)&sz=128") }
    }

    var body: some View {
        LogoImage(
            clearbitURL: clearbitURL,
            brandfetchURL: brandfetchURL,
            faviconURL: faviconURL,
            ticker: ticker,
            color: color
        )
        .frame(width: 50, height: 50)
    }
}

// MARK: - Column Header

struct ColumnHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("순위")
                .fixedSize()                            // 세로 줄바꿈 방지 → 가로 한 줄
                .frame(width: 20, alignment: .center)

            // CompanyRow의 로고(폭 50) 자리만큼 비워서 '기업'을 기업명 라인에 맞춤
            Color.clear.frame(width: 50, height: 0)

            Text("기업")

            Spacer()

            Text("시가총액")
                .padding(.trailing, 8)                  // 시가총액을 왼쪽으로 살짝 이동
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        // CompanyRow의 내부 좌우 패딩(16)과 정렬을 맞춤
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Company Row

struct CompanyRow: View {
    let company: Company
    let currency: Currency
    let exchangeRate: Double

    private var formattedMarketCap: String {
        switch currency {
        case .usd:
            return String(format: "$%.2fT", company.marketCapUSD)
        case .krw:
            let krwTrillion = company.marketCapUSD * exchangeRate
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
            let formatted = formatter.string(from: NSNumber(value: krwTrillion)) ?? String(format: "%d", krwTrillion)
            return "\(formatted)조원"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(company.rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)

            BrandLogoTile(ticker: company.ticker, color: company.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(company.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(company.ticker)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedMarketCap)
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.numericText())

                HStack(spacing: 2) {
                    Image(systemName: company.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.2f%%", abs(company.change)))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(company.change >= 0 ? .green : .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
