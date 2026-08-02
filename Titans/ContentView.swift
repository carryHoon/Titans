//
//  ContentView.swift
//  Titans
//
//  Created by MacH on 7/21/26.
//

import SwiftUI
import Combine   // ObservableObject / @Published
import CryptoKit // 로고 디스크 캐시 파일명 해시(SHA256)
import UIKit

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


// MARK: - Market Data

struct MarketIndex: Identifiable {
    let id: String
    let name: String
    var value: Double
    var change: Double
    var changePercent: Double
}

private let initialIndices: [MarketIndex] = [
    MarketIndex(id: "usd",    name: "달러 환율", value: 1450.00, change:  0.00, changePercent:  0.00),
    MarketIndex(id: "kospi",  name: "코스피",   value: 2856.78, change: 12.34, changePercent:  0.43),
    MarketIndex(id: "kosdaq", name: "코스닥",   value:  854.23, change: -4.56, changePercent: -0.53),
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
    let domain: String?        // 백엔드(DART) 해석 홈페이지 도메인 — 큐레이션 미등록 종목 로고 폴백용

    /// Ticker 기반 상장 거래소. 미등록 종목은 필터에서 ALL에만 노출됨.
    var market: Market? { tickerMarket[ticker] }
}

// MARK: - API Response DTOs

struct APICompanyResult: Decodable {
    let rank: Int
    let previousRank: Int?     // 전일 종가 기준 순위 (US만 내려옴; KR은 basDt로 클라이언트가 계산)
    let ticker: String
    let name: String
    let color: String          // hex 문자열 e.g. "#78BB17"
    let changePercent: Double  // % change → Company.change 에 매핑
    let marketCapUSD: Double   // trillion USD
    let domain: String?        // 홈페이지 도메인(로고 폴백용) — KOSPI/KOSDAQ만 내려옴, 없으면 nil
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

// MARK: - Logo Source

// logo.dev publishable token — 도메인으로 공식 브랜드 로고를 받는다(Clearbit 후속 표준).
// publishable(pk_) 키라 클라이언트 노출용으로 안전. fallback=404로 미보유 시 404를 받아
// 앱의 다음 폴백(이니셜 타일)이 동작하게 한다.
private let logoDevToken = "pk_J8vaeyLSSxewXruh0z5O9g"


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

    /// 밝은 회색/흰색 배경 픽셀을 투명하게 만든다.
    /// 채도가 낮고(무채색) 밝기가 높은(회색·흰색) 픽셀만 제거해 채색된 로고 요소는 보존한다.
    func removingLightBackground() -> UIImage? {
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
            if sat < 0.12 && hi > 0.50 { // 밝고 무채색인 픽셀(회색·흰색) → 투명 처리
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    /// 네 귀퉁이 픽셀의 평균색을 배경색으로 간주하고, 그 색에 가까운 픽셀을 투명하게 만든다.
    /// 녹색(네이버)·노랑(KB금융) 같은 단색 컬러 배경 로고에 적용.
    func removingDominantBackground(tolerance: CGFloat = 0.22) -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 1, h > 1 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let corners = [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0
        for (cx, cy) in corners {
            let idx = cy * w + cx
            bgR += CGFloat(buf[idx*4])   / 255
            bgG += CGFloat(buf[idx*4+1]) / 255
            bgB += CGFloat(buf[idx*4+2]) / 255
        }
        bgR /= 4; bgG /= 4; bgB /= 4
        let tol2 = tolerance * tolerance
        for i in 0..<(w * h) {
            let r = CGFloat(buf[i*4])   / 255
            let g = CGFloat(buf[i*4+1]) / 255
            let b = CGFloat(buf[i*4+2]) / 255
            let d2 = (r-bgR)*(r-bgR) + (g-bgG)*(g-bgG) + (b-bgB)*(b-bgB)
            if d2 < tol2 {
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }
}

private enum LogoProcessingCache {
    static let shared = NSCache<NSString, UIImage>()
}

/// 원격 로고(logo.dev) 영구 캐시 — 메모리(NSCache) + 디스크(Caches/LogoCache).
///
/// logo.dev 응답은 `max-age=86400`(24h)이라 기본 URLCache로는 유저가 매일 재호출한다.
/// 로고는 거의 안 바뀌므로 이 캐시가 24h 만료를 무시하고 폰에 오래(기본 60일) 보관해
/// logo.dev 무료 플랜(월 50만) 호출을 최소화한다. device-side 캐싱이라 약관을 준수한다
/// (서버 캐싱/self-host는 logo.dev Pro 전용이라 여기선 절대 하지 않는다).
final class LogoStore {
    static let shared = LogoStore()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let ttl: TimeInterval = 60 * 24 * 60 * 60   // 60일

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("LogoCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// 메모리 → 디스크(TTL 이내) → 네트워크 순. 200이 아니면 nil을 반환해 다음 폴백을 유도한다.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }

        let file = fileURL(for: url)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl,
           let data = try? Data(contentsOf: file),
           let img = UIImage(data: data) {
            memory.setObject(img, forKey: key)
            return img
        }

        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        memory.setObject(img, forKey: key)
        return img
    }
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

// MARK: - KR Rank Baseline (basDt 기준)

/// KOSPI/KOSDAQ 전용. 공공데이터포털 EOD 스냅샷의 basDt(기준일)가 바뀔 때마다 롤오버.
/// previousRanks = 직전 basDt 스냅샷 순위 → 화살표 비교 기준으로 사용.
/// 언제 앱을 처음 열어도 "이전 종가 vs 현재 종가" 비교가 항상 성립한다.
private struct KRExchangeBaseline: Codable {
    var currentBasDt: String         // 가장 최근에 수신한 basDt ("YYYYMMDD")
    var currentRanks: [String: Int]  // currentBasDt 기준 순위
    var previousRanks: [String: Int] // 직전 basDt 기준 순위 (rank change 비교 대상)
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

    // KR 종목 basDt 기준 스냅샷 — 영속 저장, 만료 없음(basDt 변경 시 자동 롤오버)
    private var krBaselines: [String: KRExchangeBaseline] = [:]  // exchangeParam → baseline

    // 시뮬레이터는 Mac의 localhost로, 실제 기기는 같은 Wi-Fi의 Mac LAN IP로 자동 연결
    #if targetEnvironment(simulator)
    static let host = "localhost"
    #else
    static let host = "172.30.1.21"
    #endif

    private let endpoint      = URL(string: "http://\(host):3000/api/market-cap")!
    private let indexEndpoint = URL(string: "http://\(host):3000/api/market-index")!

    init() {
        if let data = UserDefaults.standard.data(forKey: "krRankBaselines"),
           let saved = try? JSONDecoder().decode([String: KRExchangeBaseline].self, from: data) {
            krBaselines = saved
        }
    }

    /// KR 전용. basDt가 변경될 때마다 currentRanks → previousRanks 롤오버 후 저장.
    /// 같은 basDt가 반복 수신되면 아무것도 하지 않는다.
    private func updateKRBaseline(param: String, newBasDt: String, newRanks: [String: Int]) {
        var bl = krBaselines[param] ?? KRExchangeBaseline(currentBasDt: "", currentRanks: [:], previousRanks: [:])
        guard bl.currentBasDt != newBasDt else { return }
        bl.previousRanks = bl.currentRanks
        bl.currentRanks  = newRanks
        bl.currentBasDt  = newBasDt
        krBaselines[param] = bl
        if let data = try? JSONEncoder().encode(krBaselines) {
            UserDefaults.standard.set(data, forKey: "krRankBaselines")
        }
    }

    /// market-cap 엔드포인트에서 데이터를 받아 Company 배열로 매핑하는 공통 로직.
    /// ALL 피드(exchangeParam == nil)와 거래소 전용 피드가 동일한 디코딩·기준순위 매핑을 공유한다.
    /// 순위변동 기준(previousRank)은 "전일 종가 순위 대비"로 통일: KR은 basDt 롤오버 baseline, 비KR은 서버 previousRank.
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
        // 순위변동 기준(previousRank) = "전일 종가 순위 대비"로 US/KR 통일.
        //  · KR(basDt 존재): 직전 basDt 스냅샷 순위와 비교 (클라이언트가 basDt 롤오버로 보관)
        //  · 비KR(US): 서버가 전일 종가 시총으로 계산해 내려준 previousRank를 그대로 사용
        var krBaseline: [String: Int] = [:]
        if let basDt = decoded.basDt, let param = exchangeParam {
            let todayRanks = Dictionary(uniqueKeysWithValues: decoded.data.map { ($0.ticker, $0.rank) })
            updateKRBaseline(param: param, newBasDt: basDt, newRanks: todayRanks)
            krBaseline = krBaselines[param]?.previousRanks ?? [:]
        }
        let isKR = decoded.basDt != nil
        let mapped: [Company] = decoded.data.map { api in
            Company(
                rank:         api.rank,
                previousRank: isKR ? krBaseline[api.ticker] : api.previousRank,
                name:         api.name,
                ticker:       api.ticker,
                marketCapUSD: api.marketCapUSD,
                change:       api.changePercent,
                color:        Color(hex: api.color),
                domain:       api.domain
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
    @Environment(AuthManager.self) private var auth

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

    // preferredColorScheme 대신 UIKit window 직접 설정.
    // preferredColorScheme은 UIKit snapshot 기반 crossfade를 유발해 withAnimation과 충돌함.
    // window.overrideUserInterfaceStyle은 부드러운 trait 업데이트만 수행하므로 충돌 없음.
    private func setWindowColorScheme(_ isDark: Bool) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = isDark ? .dark : .light }
    }

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
                    // v1은 ALL 섹션을 상위 20개만 노출. v2에서 100개로 확대 예정이라
                    // 마지막 종목 아래에 "확장 준비 중" 안내를 붙인다.
                    if market == .all {
                        ExpansionFooter()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // 고정 헤더 — 섹션을 스와이프해도 항상 화면 상단에 유지
            LiveIndicatorBar(
                market: selectedMarket,
                currentTime: currentTime,
                basDt: basDt(for: selectedMarket),
                isDarkMode: $isDarkMode,
                vScale: vScale,
                onSearch: { showSearch = true },
                onMenu: { withAnimation(.easeInOut(duration: 0.32)) { showMenu = true } }
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
        .onAppear { setWindowColorScheme(isDarkMode) }
        .onChange(of: isDarkMode) { _, value in setWindowColorScheme(value) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // 로그인 완료 시 어느 섹션에 있었든 홈의 ALL 섹션으로 되돌린다.
            if signedIn {
                showMenu = false
                selectedMarket = .all
            }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(
                companies: searchableCompanies,
                currency: selectedCurrency,
                exchangeRate: exchangeRate,
                isDarkMode: isDarkMode,
                onDismiss: { showSearch = false }
            )
        }
        .animation(.easeInOut(duration: 0.45), value: isDarkMode)
        .task {
            while !Task.isCancelled {
                await viewModel.fetch()
                // 서버 quote 캐시(20초)와 정렬. sleep이 fetch 뒤라 실제 간격은 항상 20초 초과 → 매 호출 신선.
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .task(id: selectedMarket) {
            guard selectedMarket.apiExchangeParam != nil else { return }
            while !Task.isCancelled {
                await viewModel.fetchExchange(selectedMarket)
                // 서버 quote 캐시(20초)와 정렬. sleep이 fetch 뒤라 실제 간격은 항상 20초 초과 → 매 호출 신선.
                try? await Task.sleep(for: .seconds(20))
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

        if showMenu {
            MenuView(
                isDarkMode: $isDarkMode,
                onDismiss: { withAnimation(.easeInOut(duration: 0.32)) { showMenu = false } }
            )
            .transition(.move(edge: .trailing))
            .zIndex(2)
        }
        } // ZStack
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
                .frame(width: logoTileSize, height: logoTileSize)

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
        HStack(spacing: 0) {
            pill("$", currency: .usd)
            pill("원", currency: .krw)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).stroke(theme.stroke, lineWidth: 1))
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
                .foregroundStyle(isSelected ? theme.background : theme.secondaryLabel)
                .frame(minWidth: 32)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(theme.label)
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
            Text("\(market.title) 준비 중")
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

// MARK: - Expansion Footer (ALL 섹션 하단 — v2 확대 예고)

/// ALL 섹션은 v1에서 상위 20개만 노출한다. 마지막 종목 아래에 붙어
/// "더 많은 기업이 곧 추가된다"는 것을 알려주는 안내 푸터. (v2에서 100개로 확대 예정)
struct ExpansionFooter: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 26))
                .foregroundStyle(theme.tertiaryLabel)
            Text("확장 준비 중이에요")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            Text("Coming Soon 2026.09.01")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
    var onMenu: () -> Void = {}             // ≡ → 메뉴
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
                    withAnimation(.easeInOut(duration: 0.3)) {
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
        return "\(Self.timeFormatter.string(from: currentTime))"
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

private struct LogoImage: View {
    let localAssetName: String?    // Xcode Assets 로컬 이미지 (우선)
    let logoDevURL: URL?           // logo.dev 공식 로고 (도메인 기반)
    let ticker: String
    let name: String
    let color: Color

    @State private var remoteImage: UIImage?
    @State private var remoteResolved = false

    var body: some View {
        if let assetName = localAssetName, let raw = UIImage(named: assetName) {
            let cacheKey = ticker as NSString
            if tickersNeedDarkBgRemoval.contains(ticker) {
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingDarkBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else if tickersNeedLightBgRemoval.contains(ticker) {
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingLightBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else if tickersNeedColoredBgRemoval.contains(ticker) {
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingDominantBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else {
                styledLogo(Image(assetName))
            }
        } else {
            remoteBody
        }
    }

    // 폴백 순서: logo.dev(공식 로고) → 이니셜 타일.
    // 로고 소스는 라이선스 근거가 있는 것만 사용한다(로컬 에셋 / logo.dev 정식 토큰).
    // AsyncImage 대신 LogoStore(영구 캐시)로 로드해 logo.dev 재호출을 최소화한다.
    @ViewBuilder private var remoteBody: some View {
        Group {
            if let img = remoteImage {
                styledLogo(Image(uiImage: img))
            } else if remoteResolved {
                textFallback
            } else {
                Color.clear
            }
        }
        // 행이 다른 종목으로 재사용되면(URL 변경) 다시 로드. 캐시 히트는 네트워크 없이 즉시.
        .task(id: remoteKey) { await loadRemote() }
    }

    private var remoteKey: String {
        logoDevURL?.absoluteString ?? ""
    }

    private func loadRemote() async {
        remoteImage = nil
        remoteResolved = false
        if let url = logoDevURL, let img = await LogoStore.shared.image(for: url) {
            remoteImage = img
        }
        remoteResolved = true
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


struct BrandLogoTile: View {
    let ticker: String
    let name: String
    let color: Color
    var domain: String? = nil   // 백엔드(DART) 해석 도메인 — 큐레이션(tickerDomain) 미등록 신규 종목 폴백

    // 큐레이션 도메인이 있으면 그대로 우선(기존 로고 표시 불변), 없을 때만 백엔드 도메인을 쓴다.
    private var resolvedDomain: String? { tickerDomain[ticker] ?? domain }

    // logo.dev 공식 로고. fallback=404로 미보유 시 404 → LogoImage가 이니셜 타일로 폴백.
    private var logoDevURL: URL? {
        resolvedDomain.flatMap {
            URL(string: "https://img.logo.dev/\($0)?token=\(logoDevToken)&size=200&format=png&retina=true&fallback=404")
        }
    }

    var body: some View {
        let offset = tickerLogoOffset[ticker] ?? .zero
        ZStack {
            Circle().fill(tickerCircleBackground[ticker] ?? .white)
            LogoImage(
                localAssetName: tickerLocalLogo[ticker],
                logoDevURL: logoDevURL,
                ticker: ticker,
                name: name,
                color: color
            )
            .offset(x: offset.x, y: offset.y)
        }
        .frame(width: logoTileSize, height: logoTileSize)
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
            Color.clear.frame(width: logoTileSize, height: 0)

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

            BrandLogoTile(ticker: company.ticker, name: company.name, color: company.color, domain: company.domain)

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
        .environment(AuthManager())
}
