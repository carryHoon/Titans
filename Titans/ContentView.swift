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
    case all, nasdaq, nyse, kospi, kosdaq, jpx, sse, szse

    var id: String { rawValue }

    /// 칩에 표시되는 라벨
    var title: String {
        switch self {
        case .all:    return "ALL"
        case .nasdaq: return "NASDAQ"
        case .nyse:   return "NYSE"
        case .kospi:  return "KOSPI"
        case .kosdaq: return "KOSDAQ"
        case .jpx:    return "JPX"
        case .sse:    return "SSE"
        case .szse:   return "SZSE"
        }
    }

    /// 백엔드 전용 피드(`?exchange=`)를 가진 거래소만 값을 반환.
    /// nil이면 ALL 통합 피드를 클라이언트에서 필터링해 사용.
    var apiExchangeParam: String? {
        switch self {
        case .nasdaq: return "nasdaq"
        case .nyse:   return "nyse"
        case .kospi:  return "kospi"
        case .kosdaq: return "kosdaq"
        case .jpx:    return "jpx"
        case .sse:    return "sse"
        case .szse:   return "szse"
        default:      return nil
        }
    }
}

/// Ticker → 상장 거래소 매핑. 신규 종목 추가 시 여기에 등록.
private let tickerMarket: [String: Market] = [
    // NASDAQ
    "NVDA": .nasdaq, "AAPL": .nasdaq, "MSFT": .nasdaq, "GOOGL": .nasdaq,
    "AMZN": .nasdaq, "META": .nasdaq, "TSLA": .nasdaq, "AVGO": .nasdaq,
    "COST": .nasdaq, "NFLX": .nasdaq, "PLTR": .nasdaq, "AMD": .nasdaq, "MU": .nasdaq,
    "SPCX": .nasdaq,
    "CSCO": .nasdaq, "ADBE": .nasdaq, "TMUS": .nasdaq, "INTU": .nasdaq, "QCOM": .nasdaq,
    "AMAT": .nasdaq, "TXN": .nasdaq, "AMGN": .nasdaq, "ISRG": .nasdaq, "BKNG": .nasdaq,
    "GILD": .nasdaq,
    // NYSE
    "BRK.B": .nyse, "JPM": .nyse, "TSM": .nyse, "LLY": .nyse, "WMT": .nyse,
    "V": .nyse, "ORCL": .nyse, "XOM": .nyse, "MA": .nyse, "UNH": .nyse,
    "JNJ": .nyse, "HD": .nyse, "PG": .nyse, "ABBV": .nyse, "KO": .nyse,
    "BAC": .nyse, "CVX": .nyse, "CRM": .nyse, "WFC": .nyse, "MRK": .nyse,
    "ACN": .nyse, "MCD": .nyse,
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
    // 추가 NASDAQ 종목
    "CSCO":  "network",
    "ADBE":  "paintbrush.pointed.fill",
    "TMUS":  "antenna.radiowaves.left.and.right",
    "INTU":  "chart.pie.fill",
    "QCOM":  "dot.radiowaves.right",
    "AMAT":  "gearshape.2.fill",
    "TXN":   "function",
    "AMGN":  "cross.case.fill",
    "ISRG":  "stethoscope",
    "BKNG":  "bed.double.fill",
    "GILD":  "cross.vial.fill",
    // 추가 NYSE 종목
    "JNJ":   "bandage.fill",
    "HD":    "hammer.fill",
    "PG":    "shippingbox.fill",
    "ABBV":  "pill.fill",
    "KO":    "cup.and.saucer.fill",
    "BAC":   "banknote.fill",
    "CVX":   "flame.fill",
    "CRM":   "cloud.fill",
    "WFC":   "banknote",
    "MRK":   "cross.fill",
    "ACN":   "briefcase.fill",
    "MCD":   "fork.knife",
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
    // 추가 NASDAQ 종목
    "CSCO":      "cisco.com",
    "ADBE":      "adobe.com",
    "TMUS":      "t-mobile.com",
    "INTU":      "intuit.com",
    "QCOM":      "qualcomm.com",
    "AMAT":      "appliedmaterials.com",
    "TXN":       "ti.com",
    "AMGN":      "amgen.com",
    "ISRG":      "intuitive.com",
    "BKNG":      "bookingholdings.com",
    "GILD":      "gilead.com",
    // 추가 NYSE 종목
    "JNJ":       "jnj.com",
    "HD":        "homedepot.com",
    "PG":        "pg.com",
    "ABBV":      "abbvie.com",
    "KO":        "coca-cola.com",
    "BAC":       "bankofamerica.com",
    "CVX":       "chevron.com",
    "CRM":       "salesforce.com",
    "WFC":       "wellsfargo.com",
    "MRK":       "merck.com",
    "ACN":       "accenture.com",
    "MCD":       "mcdonalds.com",
    "2222.SR":   "aramco.com",
    // KRX (Korea) — KOSPI
    "005930.KS": "samsung.com",
    "000660.KS": "skhynix.com",
    "402340.KS": "sksquare.com",
    "009150.KS": "samsungsem.com",
    "005380.KS": "hyundai.com",
    "373220.KS": "lgensol.com",
    "032830.KS": "samsunglife.com",
    "207940.KS": "samsungbiologics.com",
    "105560.KS": "kbfg.com",
    "028260.KS": "samsungcnt.com",
    "000270.KS": "kia.com",
    "055550.KS": "shinhangroup.com",
    "012330.KS": "mobis.co.kr",
    "012450.KS": "hanwhaaerospace.com",
    "034730.KS": "sk.com",
    "034020.KS": "doosanenerbility.com",
    "068270.KS": "celltrion.com",
    "086790.KS": "hanafn.com",
    "006400.KS": "samsungsdi.com",
    // KRX (Korea) — KOSDAQ
    "196170.KQ": "alteogen.com",
    "247540.KQ": "ecoprobm.co.kr",
    "086520.KQ": "ecopro.co.kr",
    "277810.KQ": "rainbow-robotics.com",
    "036930.KQ": "jseng.com",
    "240810.KQ": "wonikips.com",
    "058470.KQ": "leeno.co.kr",
    "298380.KQ": "ablbio.com",
    "039030.KQ": "eotechnics.com",
    "028300.KQ": "hlb.co.kr",
    "222800.KQ": "simmtech.com",
    "141080.KQ": "ligachembio.com",
    "108490.KQ": "robotis.com",
    "403870.KQ": "hpsp.co.kr",
    // JPX (Japan) — Yahoo `.T` 심볼
    "7203.T": "toyota-global.com",
    "8306.T": "mufg.jp",
    "6758.T": "sony.com",
    "6861.T": "keyence.com",
    "9984.T": "group.softbank",
    "9983.T": "fastretailing.com",
    "6098.T": "recruit.co.jp",
    "8035.T": "tel.com",
    "4063.T": "shinetsu.co.jp",
    "9432.T": "group.ntt",
    "6501.T": "hitachi.com",
    "7974.T": "nintendo.com",
    "8058.T": "mitsubishicorp.com",
    "8001.T": "itochu.co.jp",
    "6902.T": "denso.com",
    "4519.T": "chugai-pharm.co.jp",
    "6367.T": "daikin.com",
    "8316.T": "smfg.co.jp",
    "7267.T": "global.honda",
    "6594.T": "nidec.com",
    // SSE (Shanghai) — Yahoo `.SS` 심볼
    "600519.SS": "moutaichina.com",
    "601398.SS": "icbc.com.cn",
    "600941.SS": "chinamobileltd.com",
    "601288.SS": "abchina.com",
    "601857.SS": "petrochina.com.cn",
    "601988.SS": "boc.cn",
    "600036.SS": "cmbchina.com",
    "601318.SS": "pingan.cn",
    "601628.SS": "e-chinalife.com",
    "600900.SS": "ctg.com.cn",
    "600028.SS": "sinopec.com",
    "601088.SS": "chnenergy.com.cn",
    "600030.SS": "citics.com",
    "603288.SS": "haitian-food.com",
    "600276.SS": "hengrui.com",
    "601668.SS": "cscec.com",
    "688981.SS": "smics.com",
    "601166.SS": "cib.com.cn",
    "600887.SS": "yili.com",
    "600809.SS": "fenjiu.com.cn",
    // SZSE (Shenzhen) — Yahoo `.SZ` 심볼
    "300750.SZ": "catl.com",
    "000858.SZ": "wuliangye.com.cn",
    "002594.SZ": "byd.com",
    "000333.SZ": "midea.com",
    "000651.SZ": "gree.com",
    "002415.SZ": "hikvision.com",
    "300760.SZ": "mindray.com",
    "000001.SZ": "bank.pingan.com",
    "002714.SZ": "muyuanfoods.com",
    "300059.SZ": "eastmoney.com",
    "002475.SZ": "luxshare-ict.com",
    "000568.SZ": "lzlj.com",
    "002304.SZ": "chinayanghe.com",
    "300124.SZ": "inovance.com",
    "002352.SZ": "sf-express.com",
    "300015.SZ": "aierchina.com",
    "000725.SZ": "boe.com",
    "002230.SZ": "iflytek.com",
    "300274.SZ": "sungrowpower.com",
    "002460.SZ": "ganfenglithium.com",
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

// MARK: - Exchange Feed (거래소 전용 피드 상태)

/// NASDAQ·NYSE처럼 백엔드 전용 엔드포인트를 가진 거래소의 로드 상태.
/// ALL(companies)과 완전히 분리해 서로 상태를 덮어쓰지 않도록 함.
struct ExchangeFeed {
    var companies: [Company] = []
    var isLoading = true
    var isError   = false
    var isStale   = false
}

// MARK: - ViewModel

@MainActor
final class MarketCapViewModel: ObservableObject {
    @Published var companies: [Company] = []
    @Published var exchangeRate: Double = 1450.0
    @Published var isLoading = true
    @Published var isError   = false
    @Published var isStale   = false

    // 거래소 전용 피드 (NASDAQ/NYSE …) — Market 키로 분리 저장
    @Published var exchangeFeeds: [Market: ExchangeFeed] = [:]

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

    /// 거래소 전용 피드 로드 (NASDAQ/NYSE …). fetch()와 동일한 매핑 로직이지만
    /// 해당 Market의 exchangeFeeds 항목에만 반영해 ALL 피드와 간섭하지 않음.
    func fetchExchange(_ market: Market) async {
        guard let param = market.apiExchangeParam,
              let url = URL(string: "http://\(Self.host):3000/api/market-cap?exchange=\(param)")
        else { return }
        do {
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
                    name:         api.name,
                    ticker:       api.ticker,
                    marketCapUSD: api.marketCapUSD,
                    change:       api.changePercent,
                    color:        Color(hex: api.color),
                    symbol:       tickerSymbols[api.ticker] ?? "chart.line.uptrend.xyaxis"
                )
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                exchangeFeeds[market] = ExchangeFeed(
                    companies: mapped,
                    isLoading: false,
                    isError:   false,
                    isStale:   decoded.stale ?? false
                )
            }
            if let rate = decoded.exchangeRate {
                exchangeRate = rate
            }
        } catch {
            // 기존 데이터가 있으면 Stale fallback으로 유지, 없으면 skeleton 유지
            var feed = exchangeFeeds[market] ?? ExchangeFeed()
            feed.isError = true
            if feed.companies.isEmpty { feed.isLoading = true }
            exchangeFeeds[market] = feed
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

    // 화이트/다크 모드 선택 (앱 재실행 후에도 유지)
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    private static let switchTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private static let liveTimer   = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var exchangeRate: Double { viewModel.exchangeRate }

    /// 전용 피드(NASDAQ/NYSE …)를 가진 거래소가 선택된 경우 그 피드를 반환. 아니면 nil.
    /// 아직 fetch 전이면 기본값(로딩 상태, 빈 리스트)을 돌려 skeleton이 뜨도록 함.
    private var dedicatedFeed: ExchangeFeed? {
        guard selectedMarket.apiExchangeParam != nil else { return nil }
        return viewModel.exchangeFeeds[selectedMarket] ?? ExchangeFeed()
    }

    /// 선택된 거래소로 필터링된 기업 리스트.
    /// ALL/기타 거래소는 통합 피드(companies)를 클라이언트에서 필터링,
    /// NASDAQ·NYSE는 전용 피드(상위 20개)를 그대로 사용.
    private var filteredCompanies: [Company] {
        if let feed = dedicatedFeed { return feed.companies }
        guard selectedMarket != .all else { return viewModel.companies }
        return viewModel.companies.filter { $0.market == selectedMarket }
    }

    /// 현재 선택된 섹션 기준 로딩/에러/Stale 상태 (전용 피드는 자체 상태를 사용)
    private var isDisplayLoading: Bool {
        if let feed = dedicatedFeed { return feed.isLoading && feed.companies.isEmpty }
        return viewModel.isLoading && viewModel.companies.isEmpty
    }
    private var isDisplayError: Bool {
        if let feed = dedicatedFeed { return feed.isError && feed.companies.isEmpty }
        return viewModel.isError && viewModel.companies.isEmpty
    }
    private var isDisplayStale: Bool {
        if let feed = dedicatedFeed { return feed.isStale }
        return viewModel.isStale
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LiveIndicatorBar(currentTime: currentTime, isDarkMode: $isDarkMode)
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
                if isDisplayStale {
                    StaleBanner()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // 거래소 카테고리 필터 (가로 스크롤 칩) — 에러 상태가 아닐 때만 표시
                if !isDisplayError {
                    MarketFilterBar(selected: $selectedMarket)
                        .padding(.bottom, 12)
                }

                LazyVStack(spacing: 10) {
                    // 컬럼 헤더 (순위 / 기업 / 시가총액) — 에러 상태가 아닐 때만 표시
                    if !isDisplayError {
                        ColumnHeader()
                    }

                    if isDisplayLoading {
                        // Skeleton UI — 첫 로드 중
                        ForEach(1...20, id: \.self) { rank in
                            SkeletonCompanyRow(rank: rank)
                        }
                    } else if isDisplayError {
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
        .background(Color(.systemBackground))
        // 상단 토글 버튼 선택값에 따라 라이트/다크 모드 적용
        .preferredColorScheme(isDarkMode ? .dark : .light)
        // 15초 폴링 — 백엔드 quote 캐시(21초)와 sync, Finnhub rate limit 안전
        .task {
            while !Task.isCancelled {
                await viewModel.fetch()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        // 거래소 전용 피드(NASDAQ/NYSE …) 폴링 — 해당 탭 선택 중에만 15초 주기로 동작.
        // selectedMarket 변경 시 task가 취소/재시작되므로 다른 탭에서는 호출되지 않아
        // 기존 ALL 폴링 및 Finnhub rate limit에 영향을 최소화한다.
        .task(id: selectedMarket) {
            guard selectedMarket.apiExchangeParam != nil else { return }
            while !Task.isCancelled {
                await viewModel.fetchExchange(selectedMarket)
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
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color(.label) : Color(.secondaryLabel))
                .frame(minWidth: 32)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray3), lineWidth: 1)
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
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color(.label))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(Color(.label))
                    }
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
    @Binding var isDarkMode: Bool
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
            // 좌측 상단 화이트/다크 모드 토글
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDarkMode.toggle()
                }
            } label: {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDarkMode ? Color.yellow : Color.orange)
                    .frame(width: 34, height: 34)
                    .background(Color(.systemGray5), in: Circle())
            }
            .buttonStyle(.plain)

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
    let name: String
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

    /// 숫자 티커(예: KRX "005930.KS")는 이니셜이 무의미하므로, 알파벳 티커면 티커,
    /// 아니면 회사명의 첫 글자로 폴백 이니셜을 만든다.
    private var fallbackInitials: String {
        if ticker.first?.isLetter == true {
            return String(ticker.prefix(2)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var textFallback: some View {
        Text(fallbackInitials)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BrandLogoTile: View {
    let ticker: String
    let name: String
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
            name: name,
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

            BrandLogoTile(ticker: company.ticker, name: company.name, color: company.color)

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
    }
}

#Preview {
    ContentView()
}
