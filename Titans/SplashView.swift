//
//  SplashView.swift
//  Titans
//
//  앱 실행 시 아이콘(TiT 투구 마크)을 2~3초 보여준 뒤 메인 화면으로 전환하는
//  스플래시(런치) 화면. 토스·당근·유튜브의 오프닝을 오마주한 구성이다.
//

import SwiftUI

// MARK: - Root (스플래시 → 메인 전환)

/// 앱 최상단 컨테이너. 스플래시 → (비로그인·최초 진입 시) 로그인 → 메인으로 전환한다.
/// 로그인은 선택이므로, 한 번 "둘러보기"를 고르면 이후에는 곧장 메인으로 진입한다.
struct RootView: View {
    @State private var auth = AuthManager()
    @State private var splashDone = false

    /// 로그인 화면을 한 번이라도 건너뛰었는지(익명 진입 완료). true면 다음부터 바로 메인.
    @AppStorage("hasSkippedLogin") private var hasSkippedLogin = false

    private enum Screen: Equatable { case splash, login, main }

    private var screen: Screen {
        // 스플래시가 끝나기 전 or 세션 복원 중이면 스플래시 유지.
        if !splashDone || auth.isLoading { return .splash }
        if auth.isSignedIn { return .main }
        return hasSkippedLogin ? .main : .login
    }

    var body: some View {
        ZStack {
            switch screen {
            case .splash:
                SplashView().transition(.opacity)
            case .login:
                LoginView(onContinueAnonymously: { hasSkippedLogin = true })
                    .transition(.opacity)
            case .main:
                ContentView().transition(.opacity)
            }
        }
        .environment(auth)
        .animation(.easeInOut(duration: 0.5), value: screen)
        .task {
            // 투구 마크 노출 시간 (약 2.5초)
            try? await Task.sleep(for: .seconds(2.5))
            splashDone = true
        }
        .onChange(of: auth.userId) { _, newId in
            // 로그인/로그아웃에 따라 환경설정 동기화를 시작/중단한다.
            PrefsSync.shared.update(userId: newId)
        }
    }
}

// MARK: - Splash

struct SplashView: View {
    // 메인 화면과 동일한 테마 설정을 공유해 라이트/다크가 일관되게 보이도록 함.
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @State private var markAppear = false
    @State private var wordmarkAppear = false

    private var background: LinearGradient {
        isDarkMode
            ? LinearGradient(
                colors: [Color(red: 0.04, green: 0.08, blue: 0.16),
                         Color(red: 0.01, green: 0.02, blue: 0.05)],
                startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [Color(red: 0.96, green: 0.97, blue: 0.99),
                         Color(red: 0.89, green: 0.91, blue: 0.95)],
                startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                TitansMark(isDark: isDarkMode)
                    .frame(width: 168, height: 150)
                    // 토스식 팝인: 살짝 작게 시작해 스프링으로 자리잡음
                    .scaleEffect(markAppear ? 1.0 : 0.62)
                    .opacity(markAppear ? 1 : 0)

                Text("Titans")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(isDarkMode
                        ? Color(red: 0.95, green: 0.96, blue: 0.98)
                        : Color(red: 0.06, green: 0.11, blue: 0.24))
                    .opacity(wordmarkAppear ? 1 : 0)
                    .offset(y: wordmarkAppear ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                markAppear = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
                wordmarkAppear = true
            }
        }
    }
}

// MARK: - Titans Mark (TiT 투구 마크 · 벡터)

/// 앱 아이콘과 동일한 "TiT" 투구 실루엣을 벡터로 재현한 마크.
/// 좌우 두 개의 T를 바깥쪽으로 기울여 투구의 뿔/측면을,
/// 가운데 'i'(빨강 점 + 기둥)로 볏(crest)을 표현한다.
struct TitansMark: View {
    var isDark: Bool

    private var glyphColor: Color {
        isDark ? Color(red: 0.95, green: 0.96, blue: 0.98)
               : Color(red: 0.06, green: 0.11, blue: 0.24)
    }
    private let dotColor = Color(red: 0.93, green: 0.16, blue: 0.14)

    // 획 두께 및 크기 파라미터
    private let thickness: CGFloat = 22
    private let barWidth: CGFloat = 74
    private let stemHeight: CGFloat = 150
    private let tilt: Double = 16

    var body: some View {
        HStack(alignment: .center, spacing: -4) {
            letterT
                .rotationEffect(.degrees(-tilt))
            middleI
                .padding(.horizontal, -2)
            letterT
                .rotationEffect(.degrees(tilt))
        }
    }

    /// 대문자 T — 상단 가로 바 + 세로 기둥 (둥근 끝 처리)
    private var letterT: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(glyphColor)
                .frame(width: thickness, height: stemHeight)
            Capsule()
                .fill(glyphColor)
                .frame(width: barWidth, height: thickness)
        }
        .frame(width: barWidth, height: stemHeight, alignment: .top)
    }

    /// 소문자 i — 빨강 점(볏) + 짧은 기둥
    private var middleI: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(dotColor)
                .frame(width: 42, height: 42)
            Capsule()
                .fill(glyphColor)
                .frame(width: thickness, height: 78)
        }
        // 세 글자의 세로 중심을 맞추기 위해 살짝 위로 올림
        .offset(y: -8)
    }
}

#Preview("Splash – Light") {
    SplashView()
}
