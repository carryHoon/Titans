//
//  Theme.swift
//  Titans
//
//  ContentView.swift에서 분리한 라이트/다크 테마(AppTheme) + Environment 주입. 동작 동일.
//

import SwiftUI

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

// MARK: - 브랜드 강조색 (MarCap 초록)

extension Color {
    /// MarCap 브랜드 강조색(초록). 로그인/프로필에서 쓰던 값과 동일 —
    /// "나만의 거래소" CTA·선택 요소 등 앱 전역 강조에 공용으로 쓴다.
    static let marcapAccent = Color(red: 0.2, green: 0.8, blue: 0.4)
}

