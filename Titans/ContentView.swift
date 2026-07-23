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
    case all, nasdaq, nyse, kospi, kosdaq, jpx, sse, szse, euronext

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
        case .jpx:      return "jpx"
        case .sse:      return "sse"
        case .szse:     return "szse"
        case .euronext: return "euronext"
        default:        return nil
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
    let previousRank: Int?     // nil = 첫 로드 (비교 대상 없음)
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
    // 추가 NASDAQ 종목 (시총 상위 유니버스 확장)
    "INTC":  "cpu",
    "LRCX":  "gearshape.2.fill",
    "ARM":   "cpu.fill",
    "KLAC":  "wrench.and.screwdriver.fill",
    "PANW":  "lock.shield.fill",
    "LIN":   "wind",
    "ASML":  "camera.aperture",
    // 추가 NYSE 종목 (시총 상위 유니버스 확장)
    "CAT":   "truck.box.fill",
    "GE":    "airplane",
    "MS":    "building.columns.fill",
    "GS":    "building.columns.fill",
    "PM":    "smoke.fill",
    "RTX":   "airplane.circle.fill",
    "AXP":   "creditcard.fill",
    "C":     "building.columns.fill",
    "HSBC":  "building.columns.fill",
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
    // Euronext (범유럽) — 파리 `.PA` / 암스테르담 `.AS` / 밀라노 `.MI`
    "ASML.AS":  "asml.com",
    "MC.PA":    "lvmh.com",
    "RMS.PA":   "hermes.com",
    "OR.PA":    "loreal.com",
    "TTE.PA":   "totalenergies.com",
    "PRX.AS":   "prosus.com",
    "SAN.PA":   "sanofi.com",
    "SU.PA":    "se.com",
    "AI.PA":    "airliquide.com",
    "EL.PA":    "essilorluxottica.com",
    "RACE.MI":  "ferrari.com",
    "AIR.PA":   "airbus.com",
    "SAF.PA":   "safran-group.com",
    "CDI.PA":   "dior.com",
    "BNP.PA":   "bnpparibas.com",
    "ENEL.MI":  "enel.com",
    "ADYEN.AS": "adyen.com",
    "UCG.MI":   "unicreditgroup.eu",
    "ISP.MI":   "intesasanpaolo.com",
    "DG.PA":    "vinci.com",
    "INGA.AS":  "ing.com",
    "BN.PA":    "danone.com",
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
            let todayRanks = Dictionary(uniqueKeysWithValues: decoded.data.map { ($0.ticker, $0.rank) })
            setBaselineIfNeeded(ranks: todayRanks, exchangeParam: nil)
            let mapped: [Company] = decoded.data.map { api in
                Company(
                    rank:         api.rank,
                    previousRank: dailyBaseline.allRanks[api.ticker],
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
            let todayRanksEx = Dictionary(uniqueKeysWithValues: decoded.data.map { ($0.ticker, $0.rank) })
            setBaselineIfNeeded(ranks: todayRanksEx, exchangeParam: param)
            let mapped: [Company] = decoded.data.map { api in
                Company(
                    rank:         api.rank,
                    previousRank: dailyBaseline.exchangeRanks[param]?[api.ticker],
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

    // 섹션 전환 방향(+1: 다음/왼쪽 스와이프, -1: 이전/오른쪽 스와이프).
    // 기업 리스트가 스와이프 방향과 같은 방향으로 슬라이드되도록 트랜지션 계산에 사용.
    @State private var navigationDirection: Int = 1

    // 화면(윈도우) 전체 높이 — 헤더 세로 간격을 기기별 "동일 비율"로 스케일링하기 위한 기준값.
    // 기준: iPhone 17 Pro(874pt). 모든 기기에서 헤더가 화면의 동일한 세로 비율을 차지하도록 함.
    @State private var viewportHeight: CGFloat = 874

    // 화이트/다크 모드 선택 (앱 재실행 후에도 유지)
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    private static let switchTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private static let liveTimer   = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var exchangeRate: Double { viewModel.exchangeRate }

    /// 현재 선택 모드에 대응하는 테마. isDarkMode 변경 시 색상이 보간되도록 명시적 Color 사용.
    private var theme: AppTheme { isDarkMode ? .dark : .light }

    /// 헤더(Live 바~탭 필터) 세로 여백에 곱해지는 높이 비례 계수.
    /// 화면이 낮은 기기일수록 여백이 함께 줄어들어, 헤더가 어떤 기기에서도 화면의 동일한 세로 비율을 차지한다.
    private var vScale: CGFloat { min(max(viewportHeight / 874, 0.85), 1.12) }

    /// 섹션 선택을 한 곳으로 모은 진입점. 스와이프·칩 탭 모두 이 함수를 거쳐
    /// 이동 방향(navigationDirection)을 먼저 확정한 뒤 애니메이션과 함께 섹션을 바꾼다.
    private func selectMarket(_ market: Market) {
        let all = Market.allCases
        guard let from = all.firstIndex(of: selectedMarket),
              let to   = all.firstIndex(of: market),
              from != to else { return }
        navigationDirection = to > from ? 1 : -1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedMarket = market
        }
    }

    /// 좌우 스와이프로 인접한 거래소 섹션으로 이동. (왼쪽으로 쓸면 다음, 오른쪽으로 쓸면 이전)
    private func switchMarket(by offset: Int) {
        let all = Market.allCases
        guard let idx = all.firstIndex(of: selectedMarket) else { return }
        let newIndex = idx + offset
        guard all.indices.contains(newIndex) else { return }   // 양 끝에서는 멈춤(순환 없음)
        selectMarket(all[newIndex])
    }

    /// 기업 리스트가 스와이프 방향과 같은 방향으로 흐르도록 하는 트랜지션.
    /// 다음 섹션(왼쪽 스와이프)이면 새 리스트는 오른쪽에서 들어오고 이전 리스트는 왼쪽으로 빠진다.
    private var listTransition: AnyTransition {
        let insertionEdge: Edge = navigationDirection >= 0 ? .trailing : .leading
        let removalEdge:   Edge = navigationDirection >= 0 ? .leading  : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal:   .move(edge: removalEdge).combined(with: .opacity)
        )
    }

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

    private var sortedFilteredCompanies: [Company] {
        let list = filteredCompanies
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
                LiveIndicatorBar(currentTime: currentTime, isDarkMode: $isDarkMode, vScale: vScale)
                    .padding(.top, 6 * vScale)

                // 지수 섹션 — 기준 기기(iPhone 17 Pro, 폭 402pt) 레이아웃을 그대로 유지한 채
                // 좁은 기기에서는 전체를 비례 축소해 한 줄 UI가 깨지지 않도록 함.
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

                // Stale 배너 (API 장애 시 캐시 데이터 사용 중 알림)
                if isDisplayStale {
                    StaleBanner()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // 거래소 카테고리 필터 (가로 스크롤 칩) — 에러 상태가 아닐 때만 표시
                if !isDisplayError {
                    MarketFilterBar(selected: selectedMarket, onSelect: selectMarket)
                        .padding(.bottom, 8 * vScale)
                }

                LazyVStack(spacing: 8) {
                    // 컬럼 헤더 (순위 / 기업 / 시가총액) — 에러 상태가 아닐 때만 표시
                    if !isDisplayError {
                        ColumnHeader(sortField: $sortField, sortOrder: $sortOrder)
                    }

                    // 섹션(거래소)별 기업 리스트. selectedMarket을 id로 묶어 섹션이 바뀌면
                    // 리스트 전체가 스와이프 방향과 같은 방향으로 슬라이드된다.
                    VStack(spacing: 8) {
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
                            // 실제 데이터 바인딩 (선택된 거래소로 필터링 + 정렬)
                            ForEach(sortedFilteredCompanies) { company in
                                CompanyRow(
                                    company: company,
                                    currency: selectedCurrency,
                                    exchangeRate: exchangeRate
                                )
                            }
                        }
                    }
                    .id(selectedMarket)
                    .transition(listTransition)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                // 좌우 스와이프로 거래소 섹션 이동 — 기업 리스트 영역에서만 동작.
                // (거래소 필터바는 탭으로만 선택되도록 제외. 세로 스크롤과 공존하도록 simultaneousGesture 사용)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            // 가로 이동이 세로보다 우세하고 충분히 클 때만 섹션 전환
                            guard abs(dx) > abs(dy), abs(dx) > 50 else { return }
                            switchMarket(by: dx < 0 ? 1 : -1)
                        }
                )
            }
        }
        // 명시적 테마 컬러를 하위 뷰에 주입 → 다크/라이트 전환이 부드럽게 보간됨
        .foregroundStyle(theme.label)
        .environment(\.appTheme, theme)
        .background(theme.background.ignoresSafeArea())
        // 윈도우 전체 높이를 측정해 vScale(헤더 세로 비례 계수) 계산에 사용.
        // ignoresSafeArea로 기기 실제 화면 높이(예: iPhone 17 Pro 874pt)를 그대로 읽는다.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewportHeight = geo.size.height }
                    .onChange(of: geo.size.height) { viewportHeight = geo.size.height }
            }
            .ignoresSafeArea()
        )
        // 상단 토글 버튼 선택값에 따라 라이트/다크 모드 적용 (status bar 등 시스템 요소용)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        // isDarkMode 변경으로 인한 테마 색상 변화를 부드럽게 애니메이션
        .animation(.easeInOut(duration: 0.45), value: isDarkMode)
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
        // 양 끝을 옅게 페이드시켜 "가로 스크롤 가능"을 직관적으로 안내.
        // 배경색에 의존하지 않도록 콘텐츠 자체를 마스크로 흐리게 처리한다.
        .mask(edgeFadeMask)
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
    let currentTime: Date
    @Binding var isDarkMode: Bool
    var vScale: CGFloat = 1                 // 헤더 세로 비례 계수 (기기별 동일 비율)
    @Environment(\.appTheme) private var theme
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
            // 좌측 상단 Live 인디케이터 + 현재 날짜/시간
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
                .foregroundStyle(theme.secondaryLabel)

            Spacer()

            // 우측 상단 액션 버튼 — 토스 스타일 (다크/화이트 토글 · 검색 · 메뉴)
            HStack(spacing: 20) {
                // 토스의 AI 버튼 자리 → 다크/화이트 모드 토글
                Button {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        isDarkMode.toggle()
                    }
                } label: {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundStyle(isDarkMode ? Color.yellow : Color.orange)
                }
                .buttonStyle(.plain)

                // 검색 (기능은 다음 단계에서 연결)
                Button {
                    // TODO: 검색 화면 연결
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)

                // 메뉴 (기능은 다음 단계에서 연결)
                Button {
                    // TODO: 메뉴 연결
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 20, weight: .medium))
        }
        // Live 줄 시작점을 지수 섹션(leading 6 + 18 = 24)과 맞춤. 우측 버튼은 기존 20 유지.
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 6 * vScale)
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
    var nameValueSpacing: CGFloat = 8
    var changeTrailingPadding: CGFloat = 0
    @Environment(\.appTheme) private var theme

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
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(isActive ? theme.label : theme.secondaryLabel)
                VStack(spacing: 1) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(
                            isActive && sortOrder == .ascending ? theme.label : theme.tertiaryLabel
                        )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(
                            isActive && sortOrder == .descending ? theme.label : theme.tertiaryLabel
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Company Row

struct CompanyRow: View {
    let company: Company
    let currency: Currency
    let exchangeRate: Double
    @Environment(\.appTheme) private var theme

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
            VStack(spacing: 2) {
                Text("\(company.rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.tertiaryLabel)
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
            .frame(width: 20, alignment: .center)

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
