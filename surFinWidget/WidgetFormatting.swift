//
//  WidgetFormatting.swift
//  surFinWidget
//
//  위젯이 앱과 픽셀 단위로 동일한 표기를 내도록, 앱(ContentView.swift)의 수치 포맷·색상·
//  테마 정의를 위젯 모듈에 복제한 것. 앱 쪽 정의가 바뀌면 여기도 맞춰줄 것.
//

import SwiftUI

// MARK: - Currency (앱과 동일)

enum Currency { case usd, krw }

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

/// 앱 `formatMarketCap`과 동일. 통화별 단위 동적 변환.
func formatMarketCap(_ marketCapUSD: Double, currency: Currency, exchangeRate: Double) -> String {
    switch currency {
    case .usd:
        let t = marketCapUSD
        if t >= 1 {
            return String(format: "$%.2fT", t)
        } else if t >= 0.001 {
            return String(format: "$%.2fB", t * 1_000)
        } else {
            return String(format: "$%.2fM", t * 1_000_000)
        }
    case .krw:
        let krwTrillion = marketCapUSD * exchangeRate
        if krwTrillion < 1 {
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
