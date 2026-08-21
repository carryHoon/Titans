//
//  WidgetFormatting.swift
//  surFinWidget
//
//  위젯이 앱과 픽셀 단위로 동일한 표기를 내도록, 앱(ContentView.swift)의 수치 포맷·색상·
//  테마 정의를 위젯 모듈에 복제한 것. 앱 쪽 정의가 바뀌면 여기도 맞춰줄 것.
//

import SwiftUI

// MARK: - 지역 팔레트(앱 AppRegion 미러 — 스토어 빌드 시 같은 값으로 맞출 것)

/// 위젯 등락 색 팔레트. 앱의 `AppRegion.current`와 **항상 같은 값**으로 유지한다.
enum WidgetRegion {
    case global, korea

    /// 앱 `AppRegion`과 **동일 로직** — 개발(DEBUG)=한국 고정, 스토어(Release)=기기 지역 자동감지.
    /// 두 타깃이 같은 규칙으로 각자 판정하므로 수동 동기화 없이 항상 앱과 일치한다.
    static var current: WidgetRegion {
        #if DEBUG
        return .korea
        #else
        return (Locale.current.region?.identifier == "KR") ? .korea : .global
        #endif
    }
}

extension Color {
    /// + 상승색 — .global=초록 / .korea=빨강
    static var tickerUp: Color {
        WidgetRegion.current == .korea ? Color(red: 0.95, green: 0.20, blue: 0.20) : .green
    }
    /// − 하락색 — .global=빨강 / .korea=파랑
    static var tickerDown: Color {
        WidgetRegion.current == .korea ? Color(red: 0.10, green: 0.43, blue: 0.92) : .red
    }
}

// MARK: - Currency (앱과 동일 — rawValue = ISO 코드, exchangeRates 맵 키와 일치)

enum Currency: String {
    case usd = "USD"
    case krw = "KRW"
    case jpy = "JPY"
    case cny = "CNY"
    case eur = "EUR"

    /// 동아시아 만진법(1兆=10¹², 1億=10⁸) 표기를 쓰는 통화인지. false면 서구식 T/B/M.
    var usesEastAsianUnits: Bool {
        switch self {
        case .krw, .jpy, .cny: return true
        case .usd, .eur:       return false
        }
    }

    /// 동아시아 통화의 (조 단위 접미사, 억 단위 접미사).
    var eastAsianUnitWords: (trillion: String, hundredMillion: String) {
        switch self {
        case .krw: return ("조원", "억원")
        case .jpy: return ("조엔", "억엔")
        case .cny: return ("조위안", "억위안")
        default:   return ("", "")
        }
    }

    /// 서구식 통화의 금액 앞 기호($/€).
    var westernSymbol: String {
        switch self {
        case .eur: return "€"
        default:   return "$"
        }
    }
}

// MARK: - Color(hex:) (앱과 동일)

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

// MARK: - AppTheme (앱과 동일 — 라이트/다크 색상값)

struct AppTheme {
    var background: Color
    var label: Color
    var secondaryLabel: Color
    var tertiaryLabel: Color
    var fill: Color
    var stroke: Color

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

    static func forScheme(_ scheme: ColorScheme) -> AppTheme {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - 시가총액 포맷 (앱과 동일 로직)

private let krwTrillionFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f
}()

/// 앱 `formatMarketCap`과 동일. 통화별 단위 동적 변환(동아시아 조/억 · 서구식 T/B/M).
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
