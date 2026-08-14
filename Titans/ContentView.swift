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
import GoogleMobileAds // 적응형 배너 크기 계산(currentOrientationAnchoredAdaptiveBanner)

// MARK: - Currency

/// 표시 통화. USD는 항상 기준(anchor)이고, 나머지는 USD와 함께 볼 "보조 표시 통화".
/// rawValue = ISO 통화 코드(백엔드 exchangeRates 맵 키·user_prefs.display_currency 저장값과 일치).
enum Currency: String, CaseIterable, Codable {
    case usd = "USD"
    case krw = "KRW"
    case jpy = "JPY"
    case cny = "CNY"
    case eur = "EUR"

    /// 저장값 파싱 실패 시 기본 통화(USD 전용 = 순수 달러 경험).
    static func from(_ code: String?) -> Currency {
        guard let code, let c = Currency(rawValue: code.uppercased()) else { return .usd }
        return c
    }

    /// 헤더 통화 토글 pill에 표시되는 짧은 기호.
    var toggleSymbol: String {
        switch self {
        case .usd: return "$"
        case .krw: return "원"
        case .jpy: return "¥"
        case .cny: return "元"
        case .eur: return "€"
        }
    }

    /// 온보딩 통화 선택 카드의 제목(통화명 + 코드).
    var onboardingLabel: String {
        switch self {
        case .usd: return "달러"
        case .krw: return "원"
        case .jpy: return "엔"
        case .cny: return "위안"
        case .eur: return "유로"
        }
    }

    /// 온보딩 카드 우측 보조 표기(국가/설명).
    var onboardingSubtitle: String {
        switch self {
        case .usd: return "USD · 달러만 보기"
        case .krw: return "KRW · 대한민국"
        case .jpy: return "JPY · 일본"
        case .cny: return "CNY · 중국"
        case .eur: return "EUR · 유로존"
        }
    }

    /// 동아시아 만진법(1兆=10¹², 1億=10⁸) 표기를 쓰는 통화인지. false면 서구식 T/B/M.
    var usesEastAsianUnits: Bool {
        switch self {
        case .krw, .jpy, .cny: return true
        case .usd, .eur:       return false
        }
    }

    /// 동아시아 통화의 (조 단위 접미사, 억 단위 접미사). 비동아시아는 사용 안 함.
    var eastAsianUnitWords: (trillion: String, hundredMillion: String) {
        switch self {
        case .krw: return ("조원", "억원")
        case .jpy: return ("조엔", "억엔")
        case .cny: return ("조위안", "억위안")
        default:   return ("", "")
        }
    }

    /// 서구식 통화의 금액 앞 기호($/€). 동아시아는 사용 안 함.
    var westernSymbol: String {
        switch self {
        case .eur: return "€"
        default:   return "$"
        }
    }
}

// MARK: - Market (거래소 필터)

/// 거래소 카테고리 필터. 새 거래소는 case만 추가하면 칩이 자동 확장됨.
enum Market: String, CaseIterable, Identifiable {
    // 선언 순서 = 홈 화면 필터 칩·스와이프 페이지 순서(둘 다 allCases를 따름).
    // 활성 거래소를 앞에 모으고(…fwb → nse), 준비 중(comingSoon)인 거래소를 뒤로 몬다.
    case all, nasdaq, nyse, kospi, kosdaq, jpx, sse, szse, euronext, fwb, nse, hkex, twse, six, tsx

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
        case .fwb:      return "FWB"
        case .hkex:     return "HKEX"
        case .twse:     return "TWSE"
        case .six:      return "SIX"
        case .tsx:      return "TSX"
        case .nse:      return "NSE"
        }
    }

    /// 1차 출시(v1) 범위 = US(NASDAQ/NYSE) + 한국(KOSPI/KOSDAQ)만. 나머지 섹션은
    /// "준비 중" 플레이스홀더(ComingSoonView)로 표시하고 데이터 조회를 하지 않는다.
    /// 상업용 데이터 소스 연동 시 해당 case를 false로 내리고 apiExchangeParam만 열어주면 됨.
    var comingSoon: Bool {
        switch self {
        case .all, .nasdaq, .nyse, .kospi, .kosdaq, .jpx, .euronext, .fwb, .sse, .szse, .nse: return false
        default:                                                                              return true
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
        case .fwb:             return "flag_de"
        case .hkex:            return "flag_hk"
        case .twse:            return "flag_tw"
        case .six:             return "flag_ch"
        case .tsx:             return "flag_ca"
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
        case .jpx:      return "jpx"        // TD /statistics EOD 스냅샷. 시총만·라이브 아님.
        case .euronext: return "euronext"   // 파리/암스=라이브(quote), 밀라노=EOD. EUR→USD 환산.
        case .sse:      return "sse"        // 상하이 A주. TD /statistics(CNY) base + quote 스케일링. CNY→USD 환산.
        case .szse:     return "szse"       // 선전 A주. 위와 동일.
        case .nse:      return "nse"        // 인도 NSE. TD /statistics(INR) base + quote 스케일링. INR→USD 환산.
        case .fwb:      return "fwb"      // 독일 FWB. TD /statistics(EUR) base + quote 스케일링. EUR→USD 환산.
        // hkex/twse 는 아직 범위 밖(comingSoon)이라 백엔드 피드가 없다.
        // 상업용 데이터 소스 확장 시 백엔드 핸들러와 함께 여기서 개방하면 별도 UI 변경 없이 활성화된다.
        default:        return nil
        }
    }

    // MARK: 데이터 기준(as-of) 분류

    enum DataBasis {
        case realtime    // 발행주식수 × 실시간 주가 (US·EU 라이브 quote 스케일링)
        case eodDated    // 거래일 종가 기준 EOD — 기준일(basDt/asOf)을 함께 표기
        case comingSoon  // 데이터 미제공(준비 중)
    }

    /// 상단 기준 섹션 문구를 가르는 데이터 형태.
    ///  · realtime: 장중 실시간 시총(마감 후 기준값 갱신) — nasdaq/nyse/euronext/fwb.
    ///  · eodDated: 거래일 종가 기준 시총 — kospi/kosdaq(basDt) · jpx/sse/szse/nse(asOf).
    /// (ALL은 US 실시간 + KR 종가 혼합이라 MarketStatusView가 별도 문구로 직접 처리한다.)
    var dataBasis: DataBasis {
        if comingSoon { return .comingSoon }
        switch self {
        case .kospi, .kosdaq, .jpx, .sse, .szse, .nse: return .eodDated
        default:                                       return .realtime
        }
    }

    /// ⓘ 상세 시트에 표시할 거래소별 정적 설명. comingSoon(hkex/twse)은 nil → 버튼 미노출.
    var info: MarketInfo? {
        switch self {
        case .all:
            return MarketInfo(
                fullName: "전체 시장",
                basis: "미국(NASDAQ·NYSE) 실시간 시가총액과 한국(KOSPI·KOSDAQ) 종가 기준 시가총액을 함께 모아 시총 상위 기업을 보여줍니다.",
                schedule: "미국 종목은 실시간, 한국 종목은 영업일 종가 기준입니다.",
                officialName: nil, officialURLString: nil)
        case .nasdaq:
            return MarketInfo(
                fullName: "Nasdaq Stock Market",
                basis: "각 종목의 발행주식수에 실시간 주가를 곱해 산출한 실시간 시가총액입니다.",
                schedule: "미국 정규장 시간에는 실시간으로, 장 마감(한국시간 새벽) 후 기준값이 갱신됩니다.",
                officialName: "nasdaq.com", officialURLString: "https://www.nasdaq.com")
        case .nyse:
            return MarketInfo(
                fullName: "New York Stock Exchange",
                basis: "각 종목의 발행주식수에 실시간 주가를 곱해 산출한 실시간 시가총액입니다.",
                schedule: "미국 정규장 시간에는 실시간으로, 장 마감(한국시간 새벽) 후 기준값이 갱신됩니다.",
                officialName: "nyse.com", officialURLString: "https://www.nyse.com")
        case .kospi:
            return MarketInfo(
                fullName: "유가증권시장 (KRX)",
                basis: "한국거래소가 발표하는 공식 종가 기준 시가총액입니다.",
                schedule: "영업일 오후(한국시간 13시경)에 직전 거래일 종가 데이터가 갱신됩니다.",
                officialName: "data.krx.co.kr", officialURLString: "http://data.krx.co.kr")
        case .kosdaq:
            return MarketInfo(
                fullName: "코스닥시장 (KRX)",
                basis: "한국거래소가 발표하는 공식 종가 기준 시가총액입니다.",
                schedule: "영업일 오후(한국시간 13시경)에 직전 거래일 종가 데이터가 갱신됩니다.",
                officialName: "data.krx.co.kr", officialURLString: "http://data.krx.co.kr")
        case .jpx:
            return MarketInfo(
                fullName: "Japan Exchange Group (도쿄증권거래소)",
                basis: "도쿄증권거래소 종가 기준 시가총액입니다.",
                schedule: "도쿄 증시 마감 후 매 거래일(한국시간 오후) 갱신됩니다.",
                officialName: "jpx.co.jp", officialURLString: "https://www.jpx.co.jp")
        case .sse:
            return MarketInfo(
                fullName: "Shanghai Stock Exchange (상하이증권거래소)",
                basis: "상하이 A주 종가 기준 시가총액입니다.",
                schedule: "중국 A주 마감 후 매 거래일(한국시간 저녁) 갱신됩니다.",
                officialName: "english.sse.com.cn", officialURLString: "http://english.sse.com.cn")
        case .szse:
            return MarketInfo(
                fullName: "Shenzhen Stock Exchange (선전증권거래소)",
                basis: "선전 A주 종가 기준 시가총액입니다.",
                schedule: "중국 A주 마감 후 매 거래일(한국시간 저녁) 갱신됩니다.",
                officialName: "szse.cn", officialURLString: "https://www.szse.cn/English/")
        case .nse:
            return MarketInfo(
                fullName: "National Stock Exchange of India (인도 NSE)",
                basis: "인도 NSE 종가 기준 시가총액입니다.",
                schedule: "인도 증시 마감 후 매 거래일(한국시간 밤) 갱신됩니다.",
                officialName: "nseindia.com", officialURLString: "https://www.nseindia.com")
        case .euronext:
            return MarketInfo(
                fullName: "Euronext (유럽)",
                basis: "파리·암스테르담 상장 종목은 실시간, 밀라노 상장 종목은 종가 기준 시가총액입니다.",
                schedule: "유럽 정규장 시간에는 실시간으로, 장 마감 후 기준값이 갱신됩니다.",
                officialName: "euronext.com", officialURLString: "https://live.euronext.com")
        case .fwb:
            return MarketInfo(
                fullName: "Frankfurt Stock Exchange (Deutsche Börse)",
                basis: "Xetra 시스템 기준 실시간 시가총액입니다.",
                schedule: "유럽 정규장 시간에는 실시간으로, 장 마감 후 기준값이 갱신됩니다.",
                officialName: "boerse-frankfurt.de", officialURLString: "https://www.boerse-frankfurt.de/en")
        case .hkex, .twse, .six, .tsx:
            return nil   // comingSoon — ⓘ 미노출
        }
    }
}

// MARK: - Market Info (거래소 데이터 기준 상세)

/// ⓘ 상세 시트에 표시할 거래소별 정적 설명. 데이터 산출 기준·갱신 주기·공식 사이트 링크를 담는다.
struct MarketInfo {
    let fullName: String              // 거래소 정식명
    let basis: String                 // 시가총액 산출 기준 설명
    let schedule: String              // 갱신 주기(한국시간 안내)
    let officialName: String?         // 공식 사이트 표시명 (없으면 링크 미노출)
    let officialURLString: String?    // 공식 홈페이지 URL 문자열
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
    let exchangeRate: Double?              // KRW/USD 단일 (위젯·구버전 호환)
    let exchangeRates: [String: Double]?  // 다통화 rate 맵 {"KRW":..,"JPY":..} — 구버전 응답엔 없을 수 있어 옵셔널
    let basDt: String?         // KRX 기준일("YYYYMMDD") — 코스피/코스닥만 내려옴(EOD/D-1)
    let asOf: String?          // EOD 계열(JPX/SSE/SZSE/NSE 등) 스냅샷 거래일("YYYY-MM-DD"). 없으면 nil. basDt와 별개(표시 전용, KR 순위 baseline 무관)
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

    /// 원격(logo.dev) 로고가 불투명한 사각 배경을 갖는지 판별한다.
    /// 네 귀퉁이가 모두 불투명하면 배경이 있는 로고로 보고 원을 꽉 채우게 하고,
    /// 하나라도 투명하면 아이콘형 로고로 보고 기존 여백을 유지한다.
    func hasOpaqueBackground() -> Bool {
        guard let cg = cgImage else { return false }
        let w = cg.width, h = cg.height
        guard w > 1, h > 1 else { return false }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for (cx, cy) in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)] {
            if buf[(cy*w+cx)*4+3] < 230 { return false }  // 반투명·투명 귀퉁이 → 아이콘형
        }
        return true
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
    var asOf: String? = nil    // EOD 계열(JPX/SSE/SZSE/NSE) 스냅샷 거래일("YYYY-MM-DD") — "종가 기준" 표기용
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
    @Published var exchangeRate: Double = 1450.0            // KRW/USD (위젯·기존 로직 호환)
    @Published var exchangeRates: [String: Double] = [:]    // 다통화 rate 맵 (표시 통화 환산용)
    @Published var isLoading = true
    @Published var isError   = false
    @Published var isStale   = false

    // 거래소 전용 피드 (NASDAQ/NYSE …) — Market 키로 분리 저장
    @Published var exchangeFeeds: [Market: ExchangeFeed] = [:]

    // KR 종목 basDt 기준 스냅샷 — 영속 저장, 만료 없음(basDt 변경 시 자동 롤오버)
    private var krBaselines: [String: KRExchangeBaseline] = [:]  // exchangeParam → baseline

    // 데이터 API — Vercel 서버리스 상시가동 호스팅
    static let host    = "titans-sooty.vercel.app"
    static let apiBase = "https://\(host)"

    private let endpoint      = URL(string: "\(apiBase)/api/market-cap")!
    private let indexEndpoint = URL(string: "\(apiBase)/api/market-index")!

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
        -> (companies: [Company], stale: Bool, rate: Double?, rates: [String: Double]?, basDt: String?, asOf: String?) {
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
            let result = try await loadCompanies(from: endpoint, exchangeParam: nil)
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
            let result = try await loadCompanies(from: url, exchangeParam: param)
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
    // 온보딩에서 고른 표시 통화(=USD와 함께 볼 보조 통화). PrefsSync가 로그인 시 이 @AppStorage에 반영한다.
    // USD면 통화 토글을 숨기고 순수 달러로만 표시한다.
    @AppStorage("displayCurrency") private var displayCurrency: Currency = .usd
    // 현재 화면에 적용 중인 통화(토글로 $ ↔ displayCurrency 전환). displayCurrency가 USD면 항상 .usd.
    @State private var selectedCurrency: Currency = .usd
    @State private var selectedMarket: Market = .all
    @State private var sortField: SortField = .rank
    @State private var sortOrder: SortOrder = .ascending

    // 화면(윈도우) 전체 높이 — 헤더 세로 간격을 기기별 "동일 비율"로 스케일링하기 위한 기준값.
    // 기준: iPhone 17 Pro(874pt). 모든 기기에서 헤더가 화면의 동일한 세로 비율을 차지하도록 함.
    @State private var viewportHeight: CGFloat = 874

    // 라이트/다크 모드는 iOS 시스템 설정을 그대로 따른다.
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    // 검색 / 메뉴 화면 표시 상태
    @State private var showSearch = false
    @State private var showMenu = false

    /// 현재 표시 통화의 환산 rate(1 USD 당 금액). formatMarketCap에 전달된다.
    private var displayRate: Double { viewModel.rate(for: selectedCurrency) }

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
    private func asOf(for market: Market) -> String? { feed(for: market)?.asOf }

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
                            exchangeRate: displayRate
                        )
                        if (index + 1) % AdsConfig.bannerRowInterval == 0 && index + 1 < list.count {
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
                asOf: asOf(for: selectedMarket),
                vScale: vScale,
                onSearch: { showSearch = true },
                onMenu: { withAnimation(.easeInOut(duration: 0.32)) { showMenu = true } }
            )
            .padding(.top, 6 * vScale)

            // 통화 시세 + 통화 토글 행.
            // 상단 바(LiveIndicatorBar)와 동일한 좌우 여백(leading 28 / trailing 32)으로 화면 전체 폭을
            // 사용해, 어떤 기기 폭에서도 통화 토글 우측이 검색·메뉴 버튼 우측과 정확히 정렬되게 한다.
            // (기존 ProportionalScaledLayout은 고정 402pt 폭으로 배치 후 좌측 정렬해서, 402pt보다 넓은
            //  기기(예: 17 Pro Max 440pt)에서 통화 토글이 우측 끝에 못 붙고 안쪽으로 어긋났다.
            //  티커는 내부 lineLimit(1)+minimumScaleFactor로 좁은 기기에서도 줄바꿈 없이 축소된다.)
            HStack(alignment: .center, spacing: 12) {
                SingleMarketTicker(indices: indices, currentIndex: currentMarketIndex, vScale: vScale)
                // 표시 통화가 USD면 CurrencyToggle이 두 슬롯을 합친 단일 $ 버튼으로 그려 크기를 유지한다.
                // 그 외엔 $ ↔ 보조통화 2-pill 토글.
                CurrencyToggle(selected: $selectedCurrency, secondary: displayCurrency)
            }
            .padding(.leading, 10)    // + SingleMarketTicker 내부 18 = 콘텐츠 시작 28 (상단 바 국기와 정렬)
            // 통화 토글은 테두리 pill이라 메뉴 아이콘(글리프)보다 시각적으로 살짝 왼쪽에 보인다.
            // trailing을 검색/메뉴(32)보다 15pt 작게(17) 줘서 오른쪽으로 밀어 두 우측 끝을 시각적으로 맞춘다.
            // (우측 여백은 화면 끝 기준 고정 pt라 모든 아이폰 기기에서 동일하게 적용된다. 검색/메뉴와 함께 8pt씩 오른쪽으로 이동: 25→17.)
            .padding(.trailing, 17)
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
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // 로그인 완료 시 어느 섹션에 있었든 홈의 ALL 섹션으로 되돌린다.
            if signedIn {
                showMenu = false
                selectedMarket = .all
            }
        }
        .onChange(of: selectedMarket) { _, _ in
            // 섹션(거래소) 전환 N번째마다 전면 광고 노출.
            InterstitialAdManager.shared.handleSectionSwitch()
        }
        .onChange(of: displayCurrency, initial: true) { _, newValue in
            // 표시 통화 확정/변경(온보딩·로그인 동기화) 시 현재 선택을 그 통화로 맞춘다.
            // USD면 토글이 숨겨지므로 selectedCurrency도 .usd로 고정된다.
            selectedCurrency = newValue
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(
                companies: searchableCompanies,
                currency: selectedCurrency,
                exchangeRate: displayRate,
                onDismiss: { showSearch = false }
            )
        }
        .animation(.easeInOut(duration: 0.45), value: colorScheme)
        .task {
            while !Task.isCancelled {
                await viewModel.fetch()
                // 서버 quote 캐시(20초)와 정렬. sleep이 fetch 뒤라 실제 간격은 항상 20초 초과 → 매 호출 신선.
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .task {
            // 검색 유니버스 워밍업: 홈 기본 데이터(ALL)가 먼저 뜨도록 잠깐 양보한 뒤,
            // 백엔드 피드를 가진 모든 거래소를 1회 프리페치한다. 이후 거래소 탭 방문 없이도 검색이 전 종목을 커버한다.
            try? await Task.sleep(for: .seconds(1))
            await viewModel.prefetchExchangesForSearch()
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
        // 홈스크린/맥 위젯용 스냅샷 — 앱 활성 시 즉시 1회 + 5분마다 갱신.
        // 4개 거래소 Top5와 로고 PNG를 App Group에 써서 위젯이 오프라인으로 표시할 수 있게 한다.
        .task {
            while !Task.isCancelled {
                await WidgetSnapshotWriter.update()
                try? await Task.sleep(for: .seconds(300))
            }
        }

        if showMenu {
            MenuView(
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

// MARK: - Ad Banner Slot (띠배너 광고 — Google Mobile Ads 적응형 배너)

/// 기업 리스트 `AdsConfig.bannerRowInterval`개마다 삽입되는 띠배너(가로 스트립) 광고.
///
/// 리스트 좌우 패딩(16pt)을 제외한 폭에 맞춘 앵커드 적응형 배너를 로드한다.
/// 광고가 아직 로드되지 않았을 때도 리스트 흐름이 튀지 않도록, 배너와 동일한 크기의
/// 지면(자리)을 항상 확보한다.
struct AdBannerSlot: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        // 리스트 콘텐츠 폭 = 화면 폭 - 좌우 패딩(16*2). 이 폭에 맞춘 적응형 배너 크기 계산.
        // iOS 26에서 UIScreen.main이 deprecated → Apple 권장대로 활성 window scene의
        // screen에서 폭을 얻는다. (렌더링 중인 뷰는 항상 scene을 가지므로 폴백 상수는 사실상 미사용)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let width = (scene?.screen.bounds.width ?? 393) - 32
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)

        BannerAdView(adUnitID: AdsConfig.bannerUnitID, adSize: adSize)
            .frame(width: adSize.size.width, height: adSize.size.height)
            .frame(maxWidth: .infinity)
            // 광고 로딩 전에도 지면이 비어 보이지 않도록 옅은 배경을 깔아 둔다.
            .background(theme.fill.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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
            Text("네트워크 상태를 확인한 뒤 다시 시도해주세요")
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
    /// USD와 함께 토글할 보조 통화(온보딩에서 고른 표시 통화).
    /// USD면 토글을 숨기지 않고, 두 슬롯 폭을 합친 "단일 $ 버튼"으로 그려 크기를 그대로 유지한다.
    let secondary: Currency
    @Environment(\.appTheme) private var theme

    // 한 슬롯(pill)의 기준 치수. 단일 $ 버튼이 2슬롯과 동일한 크기를 갖도록 아래 계산에 재사용한다.
    private let pillMinWidth: CGFloat = 32
    private let pillHPad:     CGFloat = 10
    private let pillVPad:     CGFloat = 5

    var body: some View {
        HStack(spacing: 0) {
            if secondary == .usd {
                // USD 전용: 보조 슬롯까지 USD로 확장 → 2슬롯 폭(2×(minWidth+2×hPad))의 단일 $ 버튼.
                usdOnlyPill
            } else {
                pill("$", currency: .usd)
                pill(secondary.toggleSymbol, currency: secondary)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).stroke(theme.stroke, lineWidth: 1))
    }

    /// USD 전용 단일 버튼. 2-pill 토글과 동일한 외곽 크기를 유지하도록 폭을 두 슬롯 합으로 고정.
    /// 항상 선택 상태(채워짐)이고 전환 대상이 없어 탭 액션은 두지 않는다.
    private var usdOnlyPill: some View {
        Text("$")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.background)
            .frame(minWidth: pillMinWidth * 2 + pillHPad * 2)   // 두 슬롯 콘텐츠 폭 합
            .padding(.horizontal, pillHPad)
            .padding(.vertical, pillVPad)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.label))
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
                .frame(minWidth: pillMinWidth)
                .padding(.horizontal, pillHPad)
                .padding(.vertical, pillVPad)
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
    @Namespace private var chipNamespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Market.allCases) { market in
                        chip(market)
                            .id(market)
                    }
                }
                // 선택 캡슐이 칩 사이를 미끄러지듯 이동하도록 선택값 변화를 스프링으로 애니메이션.
                // (ALL은 맨 왼쪽 끝이라 스크롤 재정렬 모션이 없어, 애니메이션이 없으면 캡슐이
                //  툭 튀어 보였다. matchedGeometryEffect + 이 애니메이션으로 모든 칩이 균일하게 미끄러진다.)
                .animation(.spring(response: 0.22, dampingFraction: 0.9), value: selected)
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
                        Capsule()
                            .fill(theme.label)
                            // 선택 칩이 바뀔 때 캡슐 프레임이 이전 칩→새 칩으로 보간되어 미끄러진다.
                            .matchedGeometryEffect(id: "selectedChip", in: chipNamespace)
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
        URL(string: "\(MarketCapViewModel.apiBase)/api/launch-vote")!
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
            Text("Coming Soon 2026.10.01")
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
    var asOf: String? = nil                 // JPX/SSE/SZSE/NSE 스냅샷 거래일("YYYY-MM-DD")
    var vScale: CGFloat = 1                 // 헤더 세로 비례 계수 (기기별 동일 비율)
    var onSearch: () -> Void = {}           // 돋보기 → 검색 화면
    var onMenu: () -> Void = {}             // ≡ → 메뉴
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            // market이 바뀌면 텍스트 내용이 교체되고, 그 너비 변화가 스프링으로 자연스럽게 애니메이션됨.
            // 왼쪽 시작점은 고정, 오른쪽만 텍스트 길이에 맞춰 늘었다 줄었다 함.
            MarketStatusView(market: market, currentTime: currentTime, basDt: basDt, asOf: asOf)

            Spacer()

            // 우측 상단 액션 버튼 — 토스 스타일 (검색 · 메뉴)
            HStack(spacing: 27) {
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
        .padding(.leading, 28)
        .padding(.trailing, 32)   // 검색·메뉴 버튼을 우측 끝에서 조금 안쪽으로. 통화 토글(테두리 pill)은 글리프보다 시각적으로 왼쪽에 보여, trailing을 더 작게(17) 줘 우측을 시각적으로 맞춘다. (통화 토글과 함께 8pt씩 오른쪽으로 이동: 40→32.)
        .padding(.vertical, 6 * vScale)
        // market 변경 시 텍스트 너비 변화(레이아웃)를 스프링으로 애니메이션
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: market)
    }
}

// MARK: - Market Status View (섹션별 데이터 기준 표시)

/// 화면 좌측 상단의 데이터 기준 인디케이터. 초록 하이라이트 단어가 **선택된 거래소명**으로 바뀌어,
/// 옆의 날짜/시각이 어느 거래소 기준인지 한눈에 보이게 한다(섹션 전환 시 함께 동적으로 갱신).
///  · realtime(NASDAQ/NYSE/EURONEXT/FWB, 60초 폴링): "NASDAQ HH:mm 기준" / ALL은 "HH:mm 기준 · 일부 종가"
///  · eodDated(KOSPI/KOSDAQ=basDt, JPX/SSE/SZSE/NSE=asOf): "KOSPI 2026.07.23 종가 기준" (갱신된 실제 거래일)
///  · comingSoon(데이터 없음): "HKEX 출시 준비 중" (초록 대신 흐린 색으로 구분)
/// 우측 ⓘ 버튼으로 거래소별 데이터 기준·갱신 주기·공식 사이트 링크(MarketInfoSheet)를 연다.
struct MarketStatusView: View {
    let market: Market
    let currentTime: Date
    let basDt: String?                      // "20260723" (코스피/코스닥만)
    var asOf: String? = nil                 // "2026-07-23" (JPX/SSE/SZSE/NSE EOD 스냅샷 거래일)
    @Environment(\.appTheme) private var theme
    @State private var showInfo = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// basDt("YYYYMMDD")·asOf("YYYY-MM-DD") 둘 다 "YY.MM.DD"로 정규화(연도 2자리 — ⓘ 버튼 공간 확보용,
    /// 모든 EOD 거래소 공통). 형식이 다르면 원본 그대로.
    private func formatDate(_ s: String) -> String {
        let digits = s.filter { $0.isNumber }
        guard digits.count == 8 else { return s }
        return "\(digits.dropFirst(2).prefix(2)).\(digits.dropFirst(4).prefix(2)).\(digits.dropFirst(6).prefix(2))"
    }

    /// EOD 섹션의 기준일 원본 — KR은 basDt, 그 외(JPX/CN/NSE)는 asOf.
    private var eodDate: String? { basDt ?? asOf }

    /// 거래소명 옆 부가 문구 — 데이터 형태(dataBasis)에 따라 기준일/실시간 시각/준비 중.
    private var detail: String {
        switch market.dataBasis {
        case .comingSoon:
            return "출시 준비 중"
        case .eodDated:
            // KR·JPX·중국·인도: "YYYY.MM.DD 종가 기준". 날짜는 갱신된 거래일이라 주말/공휴일 오해가 없다.
            return eodDate.map { "\(formatDate($0)) 종가 기준" } ?? "불러오는 중"
        case .realtime:
            let time = Self.timeFormatter.string(from: currentTime)
            // ALL은 KR(종가) + US(실시간)를 섞어 보여주므로 단서를 덧붙인다.
            if market == .all { return "\(time) 기준 · 일부 종가" }
            return "\(time) 기준"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // 국가 국기 아이콘 — 원형 클리핑으로 일관된 모양 유지.
            // 레이아웃 프레임은 모든 섹션에서 18로 고정한다. (ALL만 프레임을 키우면
            // 진입/이탈 시 국기 크기 변화가 텍스트 너비 스프링과 경쟁하는 두 번째 레이아웃
            // 애니메이션이 되어 헤더가 툭 끊겨 보인다.)
            // 글로브 PNG는 내부 여백이 커 작아 보이므로, 레이아웃은 그대로 두고 시각적으로만
            // scaleEffect로 키운다 — 가로 레이아웃에 영향을 주지 않아 텍스트 스프링이 균일해진다.
            Image(market.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .scaleEffect(market == .all ? 1.33 : 1.0)
                .opacity(market.comingSoon ? 0.35 : 1.0)

            // 초록 하이라이트 = 선택된 거래소명 (준비 중은 흐린 색)
            Text(market.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(market.comingSoon ? theme.secondaryLabel : Color.green)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()          // 실시간 시계 자릿수 흔들림 방지
                .foregroundStyle(theme.secondaryLabel)

            // ⓘ 데이터 기준 상세 — 무엇을 기준으로 어떻게 갱신되는지 + 공식 사이트 링크.
            // 배치: 국기 → 거래소명 → 기준일 → ⓘ (맨 오른쪽이라 탭하기 쉬움). comingSoon(정보 없음)은 숨긴다.
            if let info = market.info {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(market.title) 데이터 기준 안내")
                .sheet(isPresented: $showInfo) {
                    MarketInfoSheet(market: market, info: info)
                }
            }
        }
    }
}

// MARK: - Market Info Sheet (거래소 데이터 기준 상세 + 공식 사이트 링크)

/// ⓘ 버튼으로 열리는 상세 시트. "이 시가총액이 무엇을 기준으로 어떻게 갱신되는지"를 명확히 밝혀
/// 유저가 공식 거래소 사이트와 직접 대조할 수 있게 한다(리텐션·신뢰 목적).
struct MarketInfoSheet: View {
    let market: Market
    let info: MarketInfo
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 — 국기 + 거래소 정식명 + 닫기
            HStack(spacing: 10) {
                Image(market.flagImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(market.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.label)
                    Text(info.fullName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }
            .padding(.bottom, 20)

            // 데이터 기준 · 갱신 주기
            infoRow(icon: "chart.bar.doc.horizontal", title: "시가총액 기준", body: info.basis)
            Divider().overlay(theme.stroke).padding(.vertical, 14)
            infoRow(icon: "clock.arrow.circlepath", title: "갱신 주기", body: info.schedule)

            // USD 환산 안내 — 공식 사이트 수치와의 소폭 차이 이유를 미리 밝혀 신뢰 확보.
            Text("시가총액은 미국 달러(USD)로 환산해 순위를 매깁니다. 환율 변동 및 발행주식수 반영 시점 차이로 공식 사이트 수치와 소폭 다를 수 있습니다.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 20)

            // 공식 사이트 링크 — 유저가 직접 대조. 대표 도메인으로 오픈(Safari).
            if let name = info.officialName,
               let urlString = info.officialURLString,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("공식 사이트에서 확인  ·  \(name)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(theme.label)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func infoRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.label)
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                        MarketIndexRow(index: indices[i])
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
        // name · value · percent 를 균일한 8pt 간격으로 묶어 좌측 정렬한다(토스식 tight 그룹).
        // 값과 % 사이에 확장되는 Spacer를 두지 않으므로 둘이 양 끝으로 벌어지지 않는다.
        // 남는 폭은 맨 뒤 Spacer(minLength: 0)가 흡수 → 어떤 기기 폭에서도 간격은 8pt로 동일.
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(index.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize()                       // 짧은 지수명은 항상 온전히 표시
            Text(formattedValue)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .contentTransition(.numericText())
                .lineLimit(1)                      // 자릿수 많은 값도 절대 줄바꿈 금지
                .minimumScaleFactor(0.5)           // 공간 부족 시 값 폰트만 축소해 한 줄 유지
            Text(formattedChangePercent)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)
                .fixedSize()                       // 퍼센트도 항상 온전히 표시
            Spacer(minLength: 0)                   // 그룹 좌측 정렬 (여분 폭 흡수)
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
    @State private var remoteFillsCircle = false   // 배경 있는 원격 로고는 원을 꽉 채움

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
                // 배경이 있는(불투명) 원격 로고는 여백 없이 원을 꽉 채운다.
                styledLogo(Image(uiImage: img), paddingOverride: remoteFillsCircle ? 0 : nil)
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
        remoteFillsCircle = false
        if let url = logoDevURL, let img = await LogoStore.shared.image(for: url) {
            remoteImage = img
            remoteFillsCircle = img.hasOpaqueBackground()
        }
        remoteResolved = true
    }

    @ViewBuilder
    private func styledLogo(_ image: Image, paddingOverride: CGFloat? = nil) -> some View {
        image
            .resizable()
            .scaledToFit()
            .padding(paddingOverride ?? tickerLogoPadding[ticker] ?? 8)
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

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
        // 라이트 모드에서는 흰 로고 원이 흰 배경에 묻혀 경계가 사라진다.
        // 다크 모드의 원과 동일한 크기(logoTileSize)로 얇은 테두리를 둘러 원 프레임을 살린다.
        .overlay {
            if colorScheme == .light {
                Circle().strokeBorder(theme.stroke, lineWidth: 1)
            }
        }
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
                // 헤더 "시가총액" 라벨만 오른쪽으로 조금 이동 — trailing 8→4로 4pt 우측 이동.
                // 화면 끝 기준 고정 pt라 모든 기기에서 동일하게 적용된다.
                .padding(.trailing, -3)
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
/// `exchangeRate` = "1 USD 당 해당 통화 금액"(USD면 1.0). marketCapUSD 는 trillion USD 단위.
/// · 서구식(USD·EUR): 1T 이상 T, 1T 미만이면 크기에 맞춰 B(십억)·M(백만)로 동적 전환, 통화기호 접두.
/// · 동아시아(KRW·JPY·CNY): 만진법. 1조 미만 → 억 단위 정수; 100조 미만 → 조 소수 2자리; 1000조 미만 → 1자리; 이상 → 정수.
func formatMarketCap(_ marketCapUSD: Double, currency: Currency, exchangeRate: Double) -> String {
    let converted = marketCapUSD * exchangeRate   // 해당 통화의 trillion(兆) 단위 금액

    if currency.usesEastAsianUnits {
        let words = currency.eastAsianUnitWords
        if converted < 1 {
            // 1조 미만: 억 단위 정수로 표시 (1조 = 1만 억)
            let eok = converted * 10_000
            krwTrillionFormatter.minimumFractionDigits = 0
            krwTrillionFormatter.maximumFractionDigits = 0
            let s = krwTrillionFormatter.string(from: NSNumber(value: eok))
                ?? "\(Int(eok.rounded()))"
            return "\(s)\(words.hundredMillion)"
        } else {
            let digits: Int
            if converted < 100       { digits = 2 }
            else if converted < 1000 { digits = 1 }
            else                     { digits = 0 }
            krwTrillionFormatter.minimumFractionDigits = digits
            krwTrillionFormatter.maximumFractionDigits = digits
            let s = krwTrillionFormatter.string(from: NSNumber(value: converted))
                ?? String(format: "%.\(digits)f", converted)
            return "\(s)\(words.trillion)"
        }
    } else {
        // 서구식(USD·EUR): T/B/M
        let symbol = currency.westernSymbol
        let t = converted
        if t >= 1 {
            return String(format: "\(symbol)%.2fT", t)
        } else if t >= 0.001 {                     // 1B = 0.001T
            return String(format: "\(symbol)%.2fB", t * 1_000)
        } else {
            return String(format: "\(symbol)%.2fM", t * 1_000_000)
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
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
