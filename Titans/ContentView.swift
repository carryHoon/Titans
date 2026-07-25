//
//  ContentView.swift
//  Titans
//
//  Created by MacH on 7/21/26.
//

import SwiftUI
import Combine   // ObservableObject / @Published

// MARK: - Currency

enum Currency { case usd, krw }

// MARK: - Market (거래소 필터)

/// 거래소 카테고리 필터. 새 거래소는 case만 추가하면 칩이 자동 확장됨.
///
/// 섹션 = "EODHD 거래소코드 필터 + 통화" 로 정의한다(선언적). 데이터 소스를 EODHD 상업
/// 플랜으로 전환하면 각 섹션은 아래 eodhdCode 매핑만으로 동작한다(스크래핑 로직 불필요).
/// 확장 시장(HKEX/TWSE/NSE)은 구조만 정의해 두고 실데이터는 EODHD 전환 시 활성화한다
/// (그전까지 comingSoon = true → "출시 시 제공" 플레이스홀더).
enum Market: String, CaseIterable, Identifiable {
    case all, nasdaq, nyse, kospi, kosdaq, jpx, sse, szse, euronext, hkex, twse, nse

    var id: String { rawValue }

    /// 칩에 표시되는 라벨
    var title: String {
        switch self {
        case .all:      return "ALL"
        case .nasdaq:   return "NASDAQ"
        case .nyse:     return "NYSE"
        case .kospi:    return "KOSPI"
        case .kosdaq:   return "KOSDAQ"
        case .jpx:      return "JPX"
        case .sse:      return "SSE"
        case .szse:     return "SZSE"
        case .euronext: return "EURONEXT"
        case .hkex:     return "HKEX"
        case .twse:     return "TWSE"
        case .nse:      return "NSE"
        }
    }

    /// EODHD 거래소 코드(접미사). 전환 후 유니버스/시세 조회의 단일 기준.
    /// US는 `.US` 하나로 오고 종목별 상장거래소 필드로 NASDAQ/NYSE를 분리한다.
    /// Euronext는 도시별 코드(PA·AS·MI)를 백엔드에서 한 섹션으로 합친다.
    var eodhdCode: [String] {
        switch self {
        case .all:      return []                       // 전 섹션 통합
        case .nasdaq:   return ["US"]                   // + 상장거래소=NASDAQ 필터
        case .nyse:     return ["US"]                   // + 상장거래소=NYSE 필터
        case .kospi:    return ["KO"]
        case .kosdaq:   return ["KQ"]
        case .jpx:      return ["TSE"]
        case .sse:      return ["SHG"]
        case .szse:     return ["SHE"]
        case .euronext: return ["PA", "AS", "MI"]
        case .hkex:     return ["HK"]
        case .twse:     return ["TW"]
        case .nse:      return ["NSE"]
        }
    }

    /// 1차 출시(v1) 범위 = US(NASDAQ/NYSE) + 한국(KOSPI/KOSDAQ)만. 나머지 섹션은
    /// "준비 중" 플레이스홀더(ComingSoonView)로 표시하고 데이터 조회를 하지 않는다.
    /// 상업용 데이터 소스 연동 시 해당 case를 false로 내리고 apiExchangeParam만 열어주면 됨.
    var comingSoon: Bool {
        switch self {
        case .all, .nasdaq, .nyse, .kospi, .kosdaq: return false
        default:                                    return true
        }
    }

    /// 거래소 소속 국가 국기 이미지명 (Assets.xcassets 기준)
    var flagImageName: String {
        switch self {
        case .all:              return "flag_global"
        case .nasdaq, .nyse:   return "flag_us"
        case .kospi, .kosdaq:  return "flag_kr"
        case .jpx:             return "flag_jp"
        case .sse, .szse:      return "flag_cn"
        case .euronext:        return "flag_eu"
        case .hkex:            return "flag_hk"
        case .twse:            return "flag_tw"
        case .nse:             return "flag_in"
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
        // jpx/sse/szse/euronext/hkex/twse/nse 는 1차 출시 범위 밖(comingSoon)이라
        // 백엔드 피드가 없다. 상업용 데이터 소스(EODHD) 전환 시 백엔드 핸들러와 함께
        // 여기서 "jpx"/"sse"/… 로 개방하면 별도 UI 변경 없이 활성화된다.
        default:      return nil
        }
    }
}

// MARK: - Sort State

enum SortField: Equatable { case rank, name, marketCap }
enum SortOrder: Equatable { case ascending, descending }

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
    "INTC": .nasdaq, "LRCX": .nasdaq, "ARM": .nasdaq, "KLAC": .nasdaq, "PANW": .nasdaq,
    "LIN": .nasdaq, "ASML": .nasdaq,
    // Walmart는 Finnhub·나스닥 공식 모두 NASDAQ으로 분류
    "WMT": .nasdaq,
    // NYSE
    "BRK.B": .nyse, "JPM": .nyse, "TSM": .nyse, "LLY": .nyse,
    "V": .nyse, "ORCL": .nyse, "XOM": .nyse, "MA": .nyse, "UNH": .nyse,
    "JNJ": .nyse, "HD": .nyse, "PG": .nyse, "ABBV": .nyse, "KO": .nyse,
    "BAC": .nyse, "CVX": .nyse, "CRM": .nyse, "WFC": .nyse, "MRK": .nyse,
    "ACN": .nyse, "MCD": .nyse,
    "CAT": .nyse, "GE": .nyse, "MS": .nyse, "GS": .nyse, "PM": .nyse,
    "RTX": .nyse, "AXP": .nyse, "C": .nyse, "HSBC": .nyse,
    // KOSPI (KRX)
    "005930.KS": .kospi, "000660.KS": .kospi, "005935.KS": .kospi,
]

// MARK: - Market Data

struct MarketIndex: Identifiable {
    let id: String
    let name: String
    var value: Double
    var change: Double
    var changePercent: Double
}

private let initialIndices: [MarketIndex] = [
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
    let previousRank: Int?     // nil = 첫 로드 (비교 대상 없음)
    let name: String
    let ticker: String
    let marketCapUSD: Double   // USD 조(trillion) 단위
    let change: Double         // changePercent (%) — API의 dp 값
    let color: Color

    /// Ticker 기반 상장 거래소. 미등록 종목은 필터에서 ALL에만 노출됨.
    var market: Market? { tickerMarket[ticker] }
}

// MARK: - API Response DTOs

struct APICompanyResult: Decodable {
    let rank: Int
    let ticker: String
    let name: String
    let color: String          // hex 문자열 e.g. "#78BB17"
    let changePercent: Double  // % change → Company.change 에 매핑
    let marketCapUSD: Double   // trillion USD
}

struct MarketCapResponse: Decodable {
    let exchangeRate: Double?
    let basDt: String?         // KRX 기준일("YYYYMMDD") — 코스피/코스닥만 내려옴(EOD/D-1)
    let data: [APICompanyResult]
    let stale: Bool?
    let error: String?
}

struct APIIndexData: Decodable {
    let id: String
    let name: String
    let value: Double
    let change: Double
    let changePercent: Double
}

struct MarketIndexResponse: Decodable {
    let data: [APIIndexData]
    let stale: Bool?
}

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
    // 추가 NASDAQ 종목 (시총 상위 유니버스 확장)
    "INTC":      "intel.com",
    "LRCX":      "lamresearch.com",
    "ARM":       "arm.com",
    "KLAC":      "kla.com",
    "PANW":      "paloaltonetworks.com",
    "LIN":       "linde.com",
    "ASML":      "asml.com",
    // 추가 NYSE 종목 (시총 상위 유니버스 확장)
    "CAT":       "caterpillar.com",
    "GE":        "geaerospace.com",
    "MS":        "morganstanley.com",
    "GS":        "goldmansachs.com",
    "PM":        "pmi.com",
    "RTX":       "rtx.com",
    "AXP":       "americanexpress.com",
    "C":         "citi.com",
    "HSBC":      "hsbc.com",
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
    "000250.KQ": "scd.co.kr",
    // KRX (Korea) — KOSDAQ
    "214450.KQ": "pharmaresearch.co.kr",
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
    "319660.KQ": "pskinc.com",
    "222800.KQ": "simmtech.com",
    "141080.KQ": "ligachembio.com",
    "108490.KQ": "robotis.com",
    "403870.KQ": "hpsp.co.kr",
    "440110.KQ": "fadu.io",
    "095340.KQ": "iscmfg.com",
    "095610.KQ": "tes.co.kr",
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

// MARK: - UIImage Background Removal

private extension UIImage {
    /// 어두운 무채색 픽셀(배경)을 투명하게 만든다.
    /// 채도(saturation) + 밝기(brightness) 기준으로 판별해
    /// 짙은 레드 그림자처럼 어두워도 채색된 픽셀은 보존한다.
    func removingDarkBackground() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for i in 0..<(w * h) {
            let r = CGFloat(buf[i*4]) / 255,
                g = CGFloat(buf[i*4+1]) / 255,
                b = CGFloat(buf[i*4+2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            let sat = hi == 0 ? 0.0 : (hi - lo) / hi
            if sat < 0.3 && hi < 0.3 { // 어둡고 무채색인 픽셀 → 투명 처리
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }
}

private enum LogoProcessingCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - App Theme (부드러운 다크/라이트 전환)

/// 시스템 시맨틱 컬러(`Color(.systemBackground)` 등)는 colorScheme가 바뀌면 즉시 스냅되어
/// 애니메이션이 걸리지 않는다. 대신 명시적인 `Color` 값을 테마로 주입하면
/// `withAnimation` 안에서 두 색상 사이를 부드럽게 보간(crossfade)할 수 있다.
struct AppTheme {
    var background: Color
    var label: Color           // 기본 텍스트 (primary)
    var secondaryLabel: Color  // secondary
    var tertiaryLabel: Color   // tertiary
    var fill: Color            // systemGray5 (스켈레톤, 토글 배경)
    var stroke: Color          // systemGray3 (테두리)

    static let light = AppTheme(
        background:     Color(red: 1.00, green: 1.00, blue: 1.00),
        label:          Color(red: 0.00, green: 0.00, blue: 0.00),
        secondaryLabel: Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.60),
        tertiaryLabel:  Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.30),
        fill:           Color(red: 0.898, green: 0.898, blue: 0.918),
        stroke:         Color(red: 0.780, green: 0.780, blue: 0.800)
    )

    static let dark = AppTheme(
        background:     Color(red: 0.00, green: 0.00, blue: 0.00),
        label:          Color(red: 1.00, green: 1.00, blue: 1.00),
        secondaryLabel: Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.60),
        tertiaryLabel:  Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.30),
        fill:           Color(red: 0.173, green: 0.173, blue: 0.180),
        stroke:         Color(red: 0.282, green: 0.282, blue: 0.290)
    )
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .light
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
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
    var basDt: String? = nil   // KRX 기준일("YYYYMMDD") — 코스피/코스닥 "종가 기준" 표기용
}

// MARK: - Daily Baseline (일별 기준 순위)

/// 당일 첫 fetch 시 확정되는 기준 순위. UserDefaults에 영속 저장되며 날짜가 바뀌면 자동 리셋.
/// ALL 피드와 거래소별 피드를 분리 저장해 서로 다른 rank 체계를 혼용하지 않는다.
private struct DailyBaseline: Codable {
    var date: String                           // "yyyy-MM-dd"
    var allRanks: [String: Int]                // ALL 피드 전역 순위
    var exchangeRanks: [String: [String: Int]] // apiExchangeParam → 거래소 내 순위
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

    // 일별 기준 순위 — 앱 재실행 후에도 당일이면 복원
    private var dailyBaseline = DailyBaseline(date: "", allRanks: [:], exchangeRanks: [:])

    // 시뮬레이터는 Mac의 localhost로, 실제 기기는 같은 Wi-Fi의 Mac LAN IP로 자동 연결
    #if targetEnvironment(simulator)
    static let host = "localhost"
    #else
    static let host = "172.30.1.21"
    #endif

    private let endpoint      = URL(string: "http://\(host):3000/api/market-cap")!
    private let indexEndpoint = URL(string: "http://\(host):3000/api/market-index")!

    init() {
        let today = Self.todayDateString()
        if let data = UserDefaults.standard.data(forKey: "dailyBaseline"),
           let saved = try? JSONDecoder().decode(DailyBaseline.self, from: data),
           saved.date == today {
            dailyBaseline = saved
        }
    }

    private static func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 당일 기준 순위가 아직 없을 때만 설정. 날짜가 바뀌면 전체 리셋 후 새로 설정.
    private func setBaselineIfNeeded(ranks: [String: Int], exchangeParam: String?) {
        let today = Self.todayDateString()
        if dailyBaseline.date != today {
            dailyBaseline = DailyBaseline(date: today, allRanks: [:], exchangeRanks: [:])
        }
        if let param = exchangeParam {
            guard dailyBaseline.exchangeRanks[param] == nil else { return }
            dailyBaseline.exchangeRanks[param] = ranks
        } else {
            guard dailyBaseline.allRanks.isEmpty else { return }
            dailyBaseline.allRanks = ranks
        }
        if let data = try? JSONEncoder().encode(dailyBaseline) {
            UserDefaults.standard.set(data, forKey: "dailyBaseline")
        }
    }

    /// market-cap 엔드포인트에서 데이터를 받아 Company 배열로 매핑하는 공통 로직.
    /// ALL 피드(exchangeParam == nil)와 거래소 전용 피드가 동일한 디코딩·기준순위 매핑을 공유한다.
    private func loadCompanies(from url: URL, exchangeParam: String?) async throws
        -> (companies: [Company], stale: Bool, rate: Double?, basDt: String?) {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(MarketCapResponse.self, from: data)
        if let apiError = decoded.error, decoded.data.isEmpty {
            throw NSError(domain: "API", code: 0, userInfo: [NSLocalizedDescriptionKey: apiError])
        }
        let todayRanks = Dictionary(uniqueKeysWithValues: decoded.data.map { ($0.ticker, $0.rank) })
        setBaselineIfNeeded(ranks: todayRanks, exchangeParam: exchangeParam)
        let baseline = exchangeParam.map { dailyBaseline.exchangeRanks[$0] ?? [:] } ?? dailyBaseline.allRanks
        let mapped: [Company] = decoded.data.map { api in
            Company(
                rank:         api.rank,
                previousRank: baseline[api.ticker],
                name:         api.name,
                ticker:       api.ticker,
                marketCapUSD: api.marketCapUSD,
                change:       api.changePercent,
                color:        Color(hex: api.color)
            )
        }
        return (mapped, decoded.stale ?? false, decoded.exchangeRate, decoded.basDt)
    }

    func fetch() async {
        do {
            let result = try await loadCompanies(from: endpoint, exchangeParam: nil)
            withAnimation(.easeInOut(duration: 0.3)) {
                companies = result.companies
                isStale   = result.stale
                isError   = false
                isLoading = false
            }
            if let rate = result.rate { exchangeRate = rate }
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
              let url = URL(string: "http://\(Self.host):3000/api/market-cap?exchange=\(param)")
        else { return }
        do {
            let result = try await loadCompanies(from: url, exchangeParam: param)
            withAnimation(.easeInOut(duration: 0.3)) {
                exchangeFeeds[market] = ExchangeFeed(
                    companies: result.companies,
                    isLoading: false,
                    isError:   false,
                    isStale:   result.stale,
                    basDt:     result.basDt
                )
            }
            if let rate = result.rate { exchangeRate = rate }
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

// MARK: - Proportional Scaled Layout (기기별 비례 축소)

/// 콘텐츠를 항상 `referenceWidth`(디자인 기준 기기 = iPhone 17 Pro)의 폭으로 먼저 배치한 뒤,
/// 실제 사용 가능한 폭에 맞춰 전체를 균일하게 축소한다.
/// 덕분에 어떤 기기에서도 기준 기기와 **동일한 레이아웃·비율**이 유지되고,
/// 화면이 좁으면 폰트와 간격이 함께 비례 축소되어 줄바꿈(2줄)이 발생하지 않는다.
/// (기준 폭보다 넓은 기기에서는 확대하지 않고 원본 크기를 유지)
struct ProportionalScaledLayout<Content: View>: View {
    var referenceWidth: CGFloat
    @ViewBuilder var content: Content

    @State private var availableWidth: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private var scale: CGFloat {
        guard availableWidth > 0 else { return 1 }
        return min(1, availableWidth / referenceWidth)
    }

    var body: some View {
        content
            // 항상 기준 기기 폭으로 배치 → 디자인 시점과 동일한 한 줄 레이아웃 보장
            .frame(width: referenceWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            // 실제 폭 비율만큼 전체(폰트·간격 포함)를 균일 축소
            .scaleEffect(scale, anchor: .topLeading)
            // scaleEffect는 레이아웃 크기를 바꾸지 않으므로, 축소된 실제 크기를 프레임으로 반영
            .frame(width: referenceWidth * scale, height: contentHeight * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
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
    @State private var sortField: SortField = .rank
    @State private var sortOrder: SortOrder = .ascending

    // 화면(윈도우) 전체 높이 — 헤더 세로 간격을 기기별 "동일 비율"로 스케일링하기 위한 기준값.
    // 기준: iPhone 17 Pro(874pt). 모든 기기에서 헤더가 화면의 동일한 세로 비율을 차지하도록 함.
    @State private var viewportHeight: CGFloat = 874

    // 화이트/다크 모드 선택 (앱 재실행 후에도 유지)
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    // 검색 / 메뉴 화면 표시 상태
    @State private var showSearch = false
    @State private var showMenu = false

    private var exchangeRate: Double { viewModel.exchangeRate }

    /// 검색 대상 유니버스 — ALL 피드 + 현재까지 로드된 거래소별 피드를 티커 기준으로 합침.
    /// (별도 API 없이 이미 라이브로 받고 있는 데이터를 그대로 검색에 재사용)
    private var searchableCompanies: [Company] {
        var seen = Set<String>()
        var merged: [Company] = []
        for c in viewModel.companies + viewModel.exchangeFeeds.values.flatMap(\.companies) {
            if seen.insert(c.ticker).inserted { merged.append(c) }
        }
        return merged
    }

    /// 현재 선택 모드에 대응하는 테마. isDarkMode 변경 시 색상이 보간되도록 명시적 Color 사용.
    private var theme: AppTheme { isDarkMode ? .dark : .light }

    /// 헤더(Live 바~탭 필터) 세로 여백에 곱해지는 높이 비례 계수.
    /// 화면이 낮은 기기일수록 여백이 함께 줄어들어, 헤더가 어떤 기기에서도 화면의 동일한 세로 비율을 차지한다.
    private var vScale: CGFloat { min(max(viewportHeight / 874, 0.85), 1.12) }

    private func selectMarket(_ market: Market) {
        guard market != selectedMarket else { return }
        selectedMarket = market
    }

    // MARK: 섹션별 데이터 헬퍼 — TabView 각 페이지가 자체 상태를 독립적으로 읽는다

    private func feed(for market: Market) -> ExchangeFeed? {
        guard market.apiExchangeParam != nil else { return nil }
        return viewModel.exchangeFeeds[market] ?? ExchangeFeed()
    }

    private func companies(for market: Market) -> [Company] {
        if let f = feed(for: market) { return f.companies }
        guard market != .all else { return viewModel.companies }
        return viewModel.companies.filter { $0.market == market }
    }

    private func sortedCompanies(for market: Market) -> [Company] {
        let list = companies(for: market)
        switch sortField {
        case .rank:
            return sortOrder == .ascending
                ? list.sorted { $0.rank < $1.rank }
                : list.sorted { $0.rank > $1.rank }
        case .name:
            return sortOrder == .ascending
                ? list.sorted { $0.name < $1.name }
                : list.sorted { $0.name > $1.name }
        case .marketCap:
            return sortOrder == .ascending
                ? list.sorted { $0.marketCapUSD < $1.marketCapUSD }
                : list.sorted { $0.marketCapUSD > $1.marketCapUSD }
        }
    }

    private func isLoading(for market: Market) -> Bool {
        if let f = feed(for: market) { return f.isLoading && f.companies.isEmpty }
        return viewModel.isLoading && viewModel.companies.isEmpty
    }

    private func isError(for market: Market) -> Bool {
        if let f = feed(for: market) { return f.isError && f.companies.isEmpty }
        return viewModel.isError && viewModel.companies.isEmpty
    }

    private func isStale(for market: Market) -> Bool {
        if let f = feed(for: market) { return f.isStale }
        return viewModel.isStale
    }

    private func basDt(for market: Market) -> String? { feed(for: market)?.basDt }

    // MARK: 섹션 페이지 — 각 거래소별 스크롤 가능한 기업 목록

    @ViewBuilder
    private func marketPage(for market: Market) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !isError(for: market) && !market.comingSoon {
                    ColumnHeader(sortField: $sortField, sortOrder: $sortOrder)
                }

                if market.comingSoon {
                    ComingSoonView(market: market)
                } else if isLoading(for: market) {
                    ForEach(1...20, id: \.self) { rank in
                        SkeletonCompanyRow(rank: rank)
                    }
                } else if isError(for: market) {
                    ErrorStateView()
                } else if companies(for: market).isEmpty {
                    EmptyMarketView(market: market)
                } else {
                    let list = sortedCompanies(for: market)
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, company in
                        CompanyRow(
                            company: company,
                            currency: selectedCurrency,
                            exchangeRate: exchangeRate
                        )
                        if (index + 1) % 20 == 0 && index + 1 < list.count {
                            AdBannerSlot()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 고정 헤더 — 섹션을 스와이프해도 항상 화면 상단에 유지
            LiveIndicatorBar(
                market: selectedMarket,
                currentTime: currentTime,
                basDt: basDt(for: selectedMarket),
                isDarkMode: $isDarkMode,
                vScale: vScale,
                onSearch: { showSearch = true },
                onMenu: { showMenu = true }
            )
            .padding(.top, 6 * vScale)

            ProportionalScaledLayout(referenceWidth: 402) {
                HStack(alignment: .center, spacing: 12) {
                    SingleMarketTicker(indices: indices, currentIndex: currentMarketIndex, vScale: vScale)
                    CurrencyToggle(selected: $selectedCurrency)
                }
                .padding(.leading, 6)
                .padding(.trailing, 16)
            }
            .padding(.top, -4 * vScale)
            .padding(.bottom, 2 * vScale)

            if isStale(for: selectedMarket) {
                StaleBanner()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            MarketFilterBar(selected: selectedMarket, onSelect: selectMarket)
                .padding(.bottom, 8 * vScale)

            // 섹션별 페이지 — TabView가 손가락 드래그에 비례한 이동과 스냅을 네이티브로 처리.
            // 모든 Market.allCases 섹션이 동일하게 좌우 스와이프로 전환된다.
            TabView(selection: $selectedMarket) {
                ForEach(Market.allCases) { market in
                    marketPage(for: market)
                        .tag(market)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(theme.label)
        .environment(\.appTheme, theme)
        .background(theme.background.ignoresSafeArea())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewportHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewportHeight = h }
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(
                companies: searchableCompanies,
                currency: selectedCurrency,
                exchangeRate: exchangeRate,
                isDarkMode: isDarkMode,
                onDismiss: { showSearch = false }
            )
        }
        .fullScreenCover(isPresented: $showMenu) {
            MenuView(
                isDarkMode: $isDarkMode,
                selectedCurrency: $selectedCurrency,
                onDismiss: { showMenu = false }
            )
        }
        .animation(.easeInOut(duration: 0.45), value: isDarkMode)
        .task {
            while !Task.isCancelled {
                await viewModel.fetch()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .task(id: selectedMarket) {
            guard selectedMarket.apiExchangeParam != nil else { return }
            while !Task.isCancelled {
                await viewModel.fetchExchange(selectedMarket)
                try? await Task.sleep(for: .seconds(15))
            }
        }
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                currentTime = Date()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentMarketIndex = (currentMarketIndex + 1) % indices.count
                }
            }
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

// MARK: - Ad Banner Slot (띠배너 광고 자리 — 출시 전 지면 확보용 플레이스홀더)

/// 기업 리스트 20개마다 삽입되는 띠배너(가로 스트립) 광고 자리.
///
/// 지금은 실제 광고를 붙이지 않고 "지면(자리)"만 확보한 플레이스홀더다.
/// App Store 출시 직전에 이 뷰의 내부만 실제 광고 SDK 배너(예: Google Mobile Ads)로
/// 교체하면 리스트 레이아웃 변경 없이 그대로 활성화된다.
/// - 표준 모바일 배너 높이(50~60pt)에 맞춰 리스트 흐름을 해치지 않도록 설계.
struct AdBannerSlot: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        // ▼▼▼ 광고 SDK 연동 지점 ▼▼▼
        // 출시 시 아래 HStack(플레이스홀더)을 실제 배너 뷰로 교체:
        //   AdBannerView(adUnitID: "ca-app-pub-…")  // 예: GADBannerView 래퍼
        // (동의/ATT·PrivacyManifest·Info.plist 광고ID 설정은 SDK 연동 시 함께 진행)
        // ▲▲▲ 광고 SDK 연동 지점 ▲▲▲
        HStack(spacing: 8) {
            Text("AD")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.secondaryLabel)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.fill, in: RoundedRectangle(cornerRadius: 4))
            Text("광고 자리")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .padding(.vertical, 2)
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(theme.secondaryLabel)
            Text("백엔드 서버에 연결할 수 없습니다")
                .font(.system(size: 16, weight: .semibold))
            Text("\(MarketCapViewModel.host):3000 이 실행 중인지 확인해주세요")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Skeleton Company Row

struct SkeletonCompanyRow: View {
    let rank: Int
    @Environment(\.appTheme) private var theme
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 20)

            RoundedRectangle(cornerRadius: 14)
                .fill(theme.fill)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 72, height: 14)
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 40, height: 11)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 68, height: 14)
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 48, height: 11)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
    @Environment(\.appTheme) private var theme

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
                .foregroundStyle(isSelected ? theme.label : theme.secondaryLabel)
                .frame(minWidth: 32)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.stroke, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Market Filter Bar (가로 스크롤 칩)

struct MarketFilterBar: View {
    let selected: Market
    let onSelect: (Market) -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Market.allCases) { market in
                        chip(market)
                            .id(market)
                    }
                }
                // CompanyRow / ColumnHeader의 좌우 패딩(16)과 시작점을 맞춤
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            // 양 끝을 옅게 페이드시켜 "가로 스크롤 가능"을 직관적으로 안내.
            // 배경색에 의존하지 않도록 콘텐츠 자체를 마스크로 흐리게 처리한다.
            .mask(edgeFadeMask)
            // 선택된 섹션이 바뀌면 해당 칩이 가운데로 스크롤됨 (Toss 스타일)
            .onChange(of: selected) { _, newValue in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// 좌우 끝 20pt 구간을 투명하게 페이드아웃하는 마스크.
    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private func chip(_ market: Market) -> some View {
        let isSelected = selected == market
        Button {
            onSelect(market)
        } label: {
            Text(market.title)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? theme.background : theme.label)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(theme.label)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Launch Vote (출시 투표 집계)

/// 기기 고유 식별자 — 서버가 SET으로 세어 한 기기가 여러 번 눌러도 1로 집계(중복 방지).
enum DeviceID {
    static let current: String = {
        let key = "titansDeviceID"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }()
}

/// titans-web `/api/launch-vote` 클라이언트.
enum LaunchVoteAPI {
    private static var base: URL {
        URL(string: "http://\(MarketCapViewModel.host):3000/api/launch-vote")!
    }

    /// 거래소별 하트 수. 실패 시 빈 딕셔너리.
    static func counts() async -> [String: Int] {
        do {
            let (data, _) = try await URLSession.shared.data(from: base)
            return try JSONDecoder().decode(CountsResponse.self, from: data).counts
        } catch {
            return [:]
        }
    }

    /// 하트 추가(wants=true)/취소(false). 성공 시 갱신된 총합, 실패 시 nil.
    static func vote(market: String, wants: Bool) async -> Int? {
        var req = URLRequest(url: base)
        req.httpMethod = wants ? "POST" : "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["market": market, "deviceId": DeviceID.current])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(VoteResponse.self, from: data).count
        } catch {
            return nil
        }
    }

    private struct CountsResponse: Decodable { let counts: [String: Int] }
    private struct VoteResponse: Decodable { let count: Int }
}

// MARK: - Coming Soon View (1차 출시 범위 밖 — 준비 중 + 출시 투표)

struct ComingSoonView: View {
    let market: Market
    @Environment(\.appTheme) private var theme

    /// 이 기기에서 하트를 눌렀는지(즉시 UI 반영 + 서버 확인 전 상태 유지).
    @AppStorage private var wantsLaunch: Bool
    @State private var count: Int = 0
    @State private var isBusy = false

    init(market: Market) {
        self.market = market
        _wantsLaunch = AppStorage(wrappedValue: false, "launchWish_\(market.rawValue)")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 38))
                .foregroundStyle(theme.tertiaryLabel)
            Text("\(market.title) 준비 중입니다")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            Text("하트가 많은 증권거래소부터 출시돼요")
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center)

            // 하트 토글 — 서버 집계와 연동. 누르면 총 인원 수가 동적으로 갱신됨
            VStack(spacing: 8) {
                Button {
                    Task { await toggleVote() }
                } label: {
                    Image(systemName: wantsLaunch ? "heart.fill" : "heart")
                        .font(.system(size: 34))
                        .foregroundStyle(wantsLaunch ? Color.pink : theme.tertiaryLabel)
                        .scaleEffect(wantsLaunch ? 1.0 : 0.92)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Text("\(count)명이 출시를 원해요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
                    .contentTransition(.numericText())
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .task(id: market) { await loadCount() }
    }

    private func loadCount() async {
        if let c = await LaunchVoteAPI.counts()[market.rawValue] {
            withAnimation(.snappy) { count = c }
        }
    }

    private func toggleVote() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let newValue = !wantsLaunch
        // 낙관적 UI — 서버 응답 전 즉시 반영
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            wantsLaunch = newValue
            count = max(0, count + (newValue ? 1 : -1))
        }

        if let serverCount = await LaunchVoteAPI.vote(market: market.rawValue, wants: newValue) {
            withAnimation(.snappy) { count = serverCount }
        } else {
            // 실패 → 롤백
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                wantsLaunch = !newValue
                count = max(0, count + (newValue ? -1 : 1))
            }
        }
    }
}

// MARK: - Empty Market View (필터 결과 없음)

struct EmptyMarketView: View {
    let market: Market
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(theme.tertiaryLabel)
            Text("\(market.title) 상장 종목이 없습니다")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Live Indicator Bar

struct LiveIndicatorBar: View {
    let market: Market                      // 현재 섹션 — 상태 문구(실시간/종가 기준)를 결정
    let currentTime: Date                   // 실시간 섹션 시계
    let basDt: String?                      // 코스피/코스닥 기준일("YYYYMMDD")
    @Binding var isDarkMode: Bool
    var vScale: CGFloat = 1                 // 헤더 세로 비례 계수 (기기별 동일 비율)
    var onSearch: () -> Void = {}           // 돋보기 → 검색 화면
    var onMenu: () -> Void = {}             // ≡ → 전체 메뉴
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            // market이 바뀌면 텍스트 내용이 교체되고, 그 너비 변화가 스프링으로 자연스럽게 애니메이션됨.
            // 왼쪽 시작점은 고정, 오른쪽만 텍스트 길이에 맞춰 늘었다 줄었다 함.
            MarketStatusView(market: market, currentTime: currentTime, basDt: basDt)

            Spacer()

            // 우측 상단 액션 버튼 — 토스 스타일 (다크/화이트 토글 · 검색 · 메뉴)
            HStack(spacing: 20) {
                Button {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        isDarkMode.toggle()
                    }
                } label: {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundStyle(isDarkMode ? Color.yellow : Color.orange)
                }
                .buttonStyle(.plain)

                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)

                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 20, weight: .medium))
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 6 * vScale)
        // market 변경 시 텍스트 너비 변화(레이아웃)를 스프링으로 애니메이션
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: market)
    }
}

// MARK: - Market Status View (섹션별 데이터 기준 표시)

/// 화면 좌측 상단의 데이터 기준 인디케이터. 초록 하이라이트 단어가 **선택된 거래소명**으로 바뀌어,
/// 옆의 날짜/시각이 어느 거래소 기준인지 한눈에 보이게 한다(섹션 전환 시 함께 동적으로 갱신).
///  · 실시간(ALL/NASDAQ/NYSE, Finnhub 15초 폴링): "● NASDAQ 실시간 HH:mm:ss" (1초마다 시각 갱신)
///  · EOD(KOSPI/KOSDAQ, 공공데이터포털 D-1): "● KOSPI 2026.07.23 종가 기준" (실제 기준일 basDt)
///  · 준비 중 섹션(데이터 없음): "● JPX 출시 준비 중" (초록 대신 흐린 색·정적 원으로 구분)
/// 초록 하이라이트 + 깜빡이는 원은 기존 Live 인디케이터의 시각 언어를 그대로 계승한다.
struct MarketStatusView: View {
    let market: Market
    let currentTime: Date
    let basDt: String?                      // "20260723" (코스피/코스닥만)
    @Environment(\.appTheme) private var theme

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var isEOD: Bool { market == .kospi || market == .kosdaq }

    /// "20260723" → "2026.07.23". 형식이 다르면 원본 그대로.
    private func formatBasDt(_ s: String) -> String {
        guard s.count == 8 else { return s }
        return "\(s.prefix(4)).\(s.dropFirst(4).prefix(2)).\(s.dropFirst(6).prefix(2))"
    }

    /// 거래소명 옆 부가 문구 — 섹션 성격에 따라 기준일/실시간 시각/준비 중.
    private var detail: String {
        if market.comingSoon { return "출시 준비 중" }
        if isEOD { return basDt.map { "\(formatBasDt($0)) 종가 기준" } ?? "불러오는 중" }
        return "실시간 \(Self.timeFormatter.string(from: currentTime))"
    }

    var body: some View {
        HStack(spacing: 6) {
            // 국가 국기 아이콘 — 원형 클리핑으로 일관된 모양 유지
            // 글로브 아이콘은 PNG 내부 여백이 있어 실제 시각 크기가 작으므로 프레임을 키워 보정
            let flagSize: CGFloat = market == .all ? 24 : 18
            Image(market.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: flagSize, height: flagSize)
                .clipShape(Circle())
                .opacity(market.comingSoon ? 0.35 : 1.0)

            // 초록 하이라이트 = 선택된 거래소명 (준비 중은 흐린 색)
            Text(market.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(market.comingSoon ? theme.secondaryLabel : Color.green)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()          // 실시간 시계 자릿수 흔들림 방지
                .foregroundStyle(theme.secondaryLabel)
        }
    }
}

// MARK: - Single Market Ticker (하나의 카드, 종목 순환)

struct SingleMarketTicker: View {
    let indices: [MarketIndex]
    let currentIndex: Int
    var vScale: CGFloat = 1                 // 헤더 세로 비례 계수 (기기별 동일 비율)

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<indices.count, id: \.self) { i in
                    if i == currentIndex {
                        MarketIndexRow(
                            index: indices[i],
                            changeTrailingPadding: {
                                switch indices[i].id {
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
            .frame(height: 50 * vScale)
            .clipped()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6 * vScale)
    }
}

// MARK: - Market Index Row (카드 내부 콘텐츠)

struct MarketIndexRow: View {
    let index: MarketIndex
    var changeTrailingPadding: CGFloat = 0
    @Environment(\.appTheme) private var theme

    private var isPositive: Bool { index.change >= 0 }
    // 토스증권 컨벤션: 상승=빨강, 하락=파랑
    private var trendColor: Color {
        isPositive
            ? Color(red: 0.95, green: 0.20, blue: 0.20)
            : Color(red: 0.10, green: 0.43, blue: 0.92)
    }

    private static let valueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private var formattedValue: String {
        Self.valueFormatter.string(from: NSNumber(value: index.value)) ?? "\(index.value)"
    }

    private var formattedChangePercent: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)\(String(format: "%.2f", index.changePercent))%"
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(index.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize()                       // 짧은 지수명은 항상 온전히 표시
                Text(formattedValue)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.label)
                    .contentTransition(.numericText())
                    .lineLimit(1)                      // 자릿수 많은 값도 절대 줄바꿈 금지
                    .minimumScaleFactor(0.5)           // 공간 부족 시 폰트만 축소
            }

            Spacer(minLength: 4)

            Text(formattedChangePercent)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)
                .fixedSize()                           // 퍼센트도 항상 온전히 표시
                .padding(.trailing, changeTrailingPadding)
        }
    }
}

// MARK: - Brand Logo Tile

/// 로컬 에셋 우선 표시 매핑. Assets.xcassets에 이미지 추가 후 여기에 등록하면
/// 해당 기업은 URL 대신 로컬 이미지를 우선 표시함.
/// 예: "TSLA": "logo_TSLA"
// 로고 파일을 Assets.xcassets에 추가한 뒤 여기에 "TICKER": "asset_name" 형태로 매핑
private let tickerLocalLogo: [String: String] = [
    "AVGO":       "logo_AVGO",
    "NVDA":       "logo_NVDA",
    "TSM":        "logo_TSM",
    "AMZN":       "logo_AMZN",
    "2222.SR":    "logo_2222SR",
    "LLY":        "logo_LLY",
    "BRK.B":      "logo_BRKB",
    "000660.KS":  "logo_000660KS",
    "AMD":        "logo_AMD",
    "V":          "logo_V",
    "WMT":        "logo_WMT",
    "005930.KS":  "logo_005930KS",
    "402340.KS":  "logo_402340KS",
    "006400.KS":  "logo_006400KS",
    "034020.KS":  "logo_034020KS",
    "034730.KS":  "logo_034730KS",
    "012330.KS":  "logo_012330KS",
    "000270.KS":  "logo_000270KS",
    "207940.KS":  "logo_207940KS",
    "105560.KS":  "logo_105560KS",
    "028260.KS":  "logo_028260KS",
    "329180.KS":  "logo_329180KS",
    "032830.KS":  "logo_032830KS",
    "373220.KS":  "logo_373220KS",
    "005380.KS":  "logo_005380KS",
    "009150.KS":  "logo_009150KS",
    "META":       "logo_META",
    "AAPL":       "logo_AAPL",
    "GOOGL":      "logo_GOOGL",
    "SPCX":       "logo_SPCX",
    "COST":       "logo_COST",
    "PLTR":       "logo_PLTR",
    "CSCO":       "logo_CSCO",
    "NFLX":       "logo_NFLX",
    "TMUS":       "logo_TMUS",
    "TXN":        "logo_TXN",
    "AMGN":       "logo_AMGN",
    "QCOM":       "logo_QCOM",
    "MSFT":       "logo_MSFT",
    "XOM":        "logo_XOM",
    "BAC":        "logo_BAC",
    "JNJ":        "logo_JNJ",
    "ABBV":       "logo_ABBV",
    "MA":         "logo_MA",
    "UNH":        "logo_UNH",
    "KO":         "logo_KO",
    "CVX":        "logo_CVX",
    "ORCL":       "logo_ORCL",
    "HD":         "logo_HD",
    "ARM":        "logo_ARM",
    "INTC":       "logo_INTC",
    "ASML":       "logo_ASML",
    "CAT":        "logo_CAT",
    "GE":         "logo_GE",
    "247540.KQ":  "logo_247540KQ",
    "086520.KQ":  "logo_086520KQ",
    "277810.KQ":  "logo_277810KQ",
    "036930.KQ":  "logo_036930KQ",
    "240810.KQ":  "logo_240810KQ",
    "058470.KQ":  "logo_058470KQ",
    "298380.KQ":  "logo_298380KQ",
    "039030.KQ":  "logo_039030KQ",
    "028300.KQ":  "logo_028300KQ",
    "319660.KQ":  "logo_319660KQ",
    "214450.KQ":  "logo_214450KQ",
    "000250.KQ":  "logo_000250KQ",
    "440110.KQ":  "logo_440110KQ",
    "222800.KQ":  "logo_222800KQ",
    "095340.KQ":  "logo_095340KQ",
    "403870.KQ":  "logo_403870KQ",
    "108490.KQ":  "logo_108490KQ",
    "095610.KQ":  "logo_095610KQ",
    "141080.KQ":  "logo_141080KQ",
    // KOSPI — 추가 종목
    "035420.KS":  "logo_035420KS",  // 네이버
    "010120.KS":  "logo_010120KS",  // LS Electric
    "267260.KS":  "logo_267260KS",  // HD현대일렉트릭
    "066570.KS":  "logo_066570KS",  // LG전자
    "000810.KS":  "logo_000810KS",  // 삼성화재
    "042660.KS":  "logo_042660KS",  // 한화오션
    "009540.KS":  "logo_009540KS",  // HD한국조선해양
    "005490.KS":  "logo_005490KS",  // POSCO홀딩스
    "015760.KS":  "logo_015760KS",  // 한국전력
    "316140.KS":  "logo_316140KS",  // 우리금융지주
    "096770.KS":  "logo_096770KS",  // SK이노베이션
    "006800.KS":  "logo_006800KS",  // 미래에셋증권
    "010130.KS":  "logo_010130KS",  // 고려아연
    "017670.KS":  "logo_017670KS",  // SK텔레콤
    "010140.KS":  "logo_010140KS",  // 삼성중공업
    "000150.KS":  "logo_000150KS",  // 두산
    "011200.KS":  "logo_011200KS",  // HMM
    "051910.KS":  "logo_051910KS",  // LG화학
    "267250.KS":  "logo_267250KS",  // HD현대
    "064350.KS":  "logo_064350KS",  // 현대로템
    "018260.KS":  "logo_018260KS",  // 삼성SDS
    "010950.KS":  "logo_010950KS",  // S-Oil
    "024110.KS":  "logo_024110KS",  // 기업은행
    "035720.KS":  "logo_035720KS",  // 카카오
    "377300.KS":  "logo_377300KS",  // 카카오페이
    "298040.KS":  "logo_298040KS",  // 효성중공업
    "005935.KS":  "logo_005935KS",  // 삼성전자우
]

/// 로컬 PNG에 검정 배경이 포함된 로고 — 표시 시 배경을 자동 제거.
private let tickersNeedDarkBgRemoval: Set<String> = [
    "000270.KS",   // Kia — dark navy background
    "207940.KS",   // Samsung Biologics — dark blue background
]

private struct LogoImage: View {
    let localAssetName: String?    // Xcode Assets 로컬 이미지 (우선)
    let clearbitURL: URL?
    let brandfetchURL: URL?
    let faviconURL: URL?
    let ticker: String
    let name: String
    let color: Color

    var body: some View {
        if let assetName = localAssetName, let raw = UIImage(named: assetName) {
            if tickersNeedDarkBgRemoval.contains(ticker) {
                let cacheKey = ticker as NSString
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingDarkBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else {
                styledLogo(Image(assetName))
            }
        } else {
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
        }
    }

    @ViewBuilder
    private func styledLogo(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .padding(tickerLogoPadding[ticker] ?? 8)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// SVG viewBox 편심으로 인해 시각적 중심이 어긋나는 로고 — (x, y) 오프셋으로 보정.
/// 양수 x = 오른쪽, 음수 x = 왼쪽 / 양수 y = 아래, 음수 y = 위
private let tickerLogoOffset: [String: CGPoint] = [
    "NVDA":       CGPoint(x: -3, y: 0),
    "AAPL":       CGPoint(x:  -1, y: -1),
    "MCD":        CGPoint(x:  1, y: 0),
    "TSLA":       CGPoint(x:  0, y: 3),
]

/// 기본 padding(8)과 다른 로고 — 작은 값일수록 로고가 더 크게 표시됨.
private let tickerLogoPadding: [String: CGFloat] = [
    "005930.KS": 3,
    "000660.KS": 4,
    "034020.KS": 2,
    "006400.KS": 2,
    "012330.KS": 2,
    "NFLX":      0,
    "SPCX":      2,
    "MA":        2,
]

/// 흰색 원 배경 대신 다른 색상을 사용할 티커 (예: 검정 배경 로고)
private let tickerCircleBackground: [String: Color] = [
    "NFLX": Color.black,
    "SPCX": Color.black,
    "CSCO": Color(red: 0.07, green: 0.18, blue: 0.36),
    "ABBV": Color(red: 0.07, green: 0.13, blue: 0.30),
]

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
        let offset = tickerLogoOffset[ticker] ?? .zero
        ZStack {
            Circle().fill(tickerCircleBackground[ticker] ?? .white)
            LogoImage(
                localAssetName: tickerLocalLogo[ticker],
                clearbitURL: clearbitURL,
                brandfetchURL: brandfetchURL,
                faviconURL: faviconURL,
                ticker: ticker,
                name: name,
                color: color
            )
            .offset(x: offset.x, y: offset.y)
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
    }
}

// MARK: - Column Header

struct ColumnHeader: View {
    @Binding var sortField: SortField
    @Binding var sortOrder: SortOrder
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            sortButton("순위", field: .rank)

            // CompanyRow의 로고(폭 50) 자리만큼 비워서 '기업'을 기업명 라인에 맞춤
            Color.clear.frame(width: 50, height: 0)

            sortButton("기업", field: .name)

            Spacer()

            sortButton("시가총액", field: .marketCap)
                .padding(.trailing, 8)
        }
        .font(.system(size: 12, weight: .semibold))
        // CompanyRow의 내부 좌우 패딩(16)과 정렬을 맞춤
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func sortButton(_ title: String, field: SortField) -> some View {
        let isActive = sortField == field
        HStack(spacing: 3) {
            // 제목 탭: 해당 컬럼 활성화(토글). 방향은 위/아래 화살표로 명시적으로 고른다.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isActive {
                        sortOrder = sortOrder == .ascending ? .descending : .ascending
                    } else {
                        sortField = field
                        sortOrder = .ascending
                    }
                }
            } label: {
                Text(title)
                    .foregroundStyle(isActive ? theme.label : theme.secondaryLabel)
            }
            .buttonStyle(.plain)

            // 위 화살표 = 오름차순, 아래 화살표 = 내림차순 (각각 개별 탭)
            VStack(spacing: 1) {
                chevron("chevron.up",   field: field, order: .ascending,  isActive: isActive)
                chevron("chevron.down", field: field, order: .descending, isActive: isActive)
            }
        }
    }

    /// 방향 화살표 한 개 — 탭하면 해당 컬럼을 그 방향으로 정렬한다.
    @ViewBuilder
    private func chevron(_ system: String, field: SortField, order: SortOrder, isActive: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                sortField = field
                sortOrder = order
            }
        } label: {
            Image(systemName: system)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isActive && sortOrder == order ? theme.label : theme.tertiaryLabel)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Market Cap Formatting

/// 원화 조(兆)/억(億) 단위 표기용 포매터 — 천 단위 구분(US 메가캡을 원화로 볼 때 6,380조원 등).
/// 소수 자릿수와 단위는 호출부에서 값 크기에 따라 동적으로 설정한다.
private let krwTrillionFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f
}()

/// 시총 표시 문자열 — 통화별 단위 동적 변환. 목록·검색 화면이 공유한다.
/// · KRW: 1조원 미만 → 억원 정수; 100조원 미만 → 조원 소수 2자리; 1000조원 미만 → 1자리; 이상 → 정수
/// · USD: 1T 이상은 T, 1T 미만이면 크기에 맞춰 B(십억)·M(백만)로 동적 전환
func formatMarketCap(_ marketCapUSD: Double, currency: Currency, exchangeRate: Double) -> String {
    switch currency {
    case .usd:
        let t = marketCapUSD                       // 조(兆) 달러(trillion USD) 단위
        if t >= 1 {
            return String(format: "$%.2fT", t)
        } else if t >= 0.001 {                     // 1B = 0.001T
            return String(format: "$%.2fB", t * 1_000)
        } else {
            return String(format: "$%.2fM", t * 1_000_000)
        }
    case .krw:
        let krwTrillion = marketCapUSD * exchangeRate   // 조원 단위
        if krwTrillion < 1 {
            // 1조원 미만: 억원 정수로 표시
            let eok = krwTrillion * 10_000
            krwTrillionFormatter.minimumFractionDigits = 0
            krwTrillionFormatter.maximumFractionDigits = 0
            let s = krwTrillionFormatter.string(from: NSNumber(value: eok))
                ?? "\(Int(eok.rounded()))"
            return "\(s)억원"
        } else {
            let digits: Int
            if krwTrillion < 100       { digits = 2 }
            else if krwTrillion < 1000 { digits = 1 }
            else                       { digits = 0 }
            krwTrillionFormatter.minimumFractionDigits = digits
            krwTrillionFormatter.maximumFractionDigits = digits
            let s = krwTrillionFormatter.string(from: NSNumber(value: krwTrillion))
                ?? String(format: "%.\(digits)f", krwTrillion)
            return "\(s)조원"
        }
    }
}

// MARK: - Company Row

struct CompanyRow: View {
    let company: Company
    let currency: Currency
    let exchangeRate: Double
    @Environment(\.appTheme) private var theme

    private var formattedMarketCap: String {
        formatMarketCap(company.marketCapUSD, currency: currency, exchangeRate: exchangeRate)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("\(company.rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.tertiaryLabel)
                    // 세 자리 순위(예: 100)가 컬럼 폭을 넘어 줄바꿈되지 않도록 한 줄 고정
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let prev = company.previousRank, prev != company.rank {
                    let delta = prev - company.rank  // 양수 = 순위 상승 (숫자 감소)
                    HStack(spacing: 1) {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 7, weight: .bold))
                        Text("\(abs(delta))")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(delta > 0
                        ? Color(red: 0.95, green: 0.20, blue: 0.20)
                        : Color(red: 0.10, green: 0.43, blue: 0.92))
                }
            }
            // 세 자리 순위(100)도 한 줄로 담기도록 폭을 24로. 중앙 정렬 유지.
            .frame(width: 24, alignment: .center)

            BrandLogoTile(ticker: company.ticker, name: company.name, color: company.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(company.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(company.ticker)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryLabel)
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
        .padding(.vertical, 10)
        // 섹션 전환/최초 로드 시 위에서 아래로 내려오며 나타나는 효과
        // (사용자 시선 방향과 일치: 위 → 아래)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal:   .opacity
        ))
    }
}

#Preview {
    ContentView()
}
