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

    /// 등락 통일색 — 지역 팔레트(AppRegion)를 따른다. + 상승 / − 하락.
    /// .global(해외)=초록↑·빨강↓, .korea(한국)=빨강↑·파랑↓. 하이라이트·시장지수·시총차트·행 공통.
    static var tickerUp: Color {
        AppRegion.current == .korea ? Color(red: 0.95, green: 0.20, blue: 0.20) : .green
    }
    static var tickerDown: Color {
        AppRegion.current == .korea ? Color(red: 0.10, green: 0.43, blue: 0.92) : .red
    }
}

// MARK: - 스토어 지역 팔레트 스위치

/// 앱스토어 지역별 등락 색·하이라이트 아이콘 팔레트. **스토어 빌드 시 아래 `current` 한 줄만 변경.**
///  · .global — 해외(미국·영국 등): 상승 초록 / 하락 빨강 / 하이라이트 = 새 커스텀 아이콘
///  · .korea  — 한국: 상승 빨강 / 하락 파랑 / 하이라이트 = 기존 이모지(색감 매칭)
///
/// ⚠️ 위젯은 별도 타깃이라 WidgetFormatting.swift의 `WidgetRegion.current`도 같은 값으로 맞출 것.
enum AppRegion {
    case global, korea

    /// 개발 빌드(DEBUG)는 한국 모드 고정, 스토어(Release)는 기기 지역으로 자동 판정한다.
    /// → 앱·위젯이 동일 로직으로 각자 판정하므로 수동 플립 없이 항상 일치. 스토어 빌드는 지역별 자동 적용.
    static var current: AppRegion {
        #if DEBUG
        return .korea            // 개발 중 한국 앱스토어 모드 고정 (해외 확인이 필요하면 .global 로)
        #else
        return autoDetected      // 스토어(Release): 기기 지역 자동감지
        #endif
    }

    /// 기기 지역이 한국이면 .korea, 그 외는 .global.
    private static var autoDetected: AppRegion {
        (Locale.current.region?.identifier == "KR") ? .korea : .global
    }
}

