//
//  SplashView.swift
//  surFin
//
//  앱 최상단 컨테이너(RootView).
//
//  앱을 실행하면 먼저 로딩뷰(LoadingView)가 앱 아이콘을 화면 중앙에 잠깐 보여준 뒤
//  (토스·당근 스타일 스플래시), 로그인 화면(LoginView) 또는 메인(ContentView)으로 넘어간다.
//  세션이 복원되어 이미 로그인돼 있거나, 한 번 "둘러보기"를 고른 사용자는 곧장 메인으로 간다.
//

import SwiftUI

/// 로딩뷰가 화면에 머무는 시간. 이 동안 세션 복원·초기화가 자연스럽게 가려진다.
private let kLoadingDuration: Double = 1.3

struct RootView: View {
    @State private var auth = AuthManager()

    /// 로딩뷰를 지나 실제 화면으로 넘어갔는지. 앱 실행 직후 한 번만 로딩을 보여준다.
    @State private var isLoading = true

    /// 로그인 화면을 한 번이라도 건너뛰었는지(익명 진입 완료). true면 다음부터 바로 메인.
    @AppStorage("hasSkippedLogin") private var hasSkippedLogin = false

    private enum Screen: Equatable { case login, main }

    private var screen: Screen {
        // 로그인돼 있거나 이미 둘러보기를 고른 사용자는 메인으로. 그 외(신규·비로그인)는 로그인.
        if auth.isSignedIn { return .main }
        return hasSkippedLogin ? .main : .login
    }

    var body: some View {
        ZStack {
            if isLoading {
                LoadingView().transition(.opacity)
            } else {
                switch screen {
                case .login:
                    LoginView(onContinueAnonymously: { hasSkippedLogin = true })
                        .transition(.opacity)
                case .main:
                    ContentView().transition(.opacity)
                }
            }
        }
        .environment(auth)
        .animation(.easeInOut(duration: 0.5), value: screen)
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .task {
            // 로딩뷰를 잠깐 보여준 뒤 실제 화면으로 전환한다.
            try? await Task.sleep(for: .seconds(kLoadingDuration))
            isLoading = false
        }
        .onChange(of: auth.userId) { _, newId in
            // 로그인/로그아웃에 따라 환경설정 동기화를 시작/중단한다.
            PrefsSync.shared.update(userId: newId)
        }
    }
}

// MARK: - LoadingView (토스·당근 스타일 스플래시)

/// 앱 아이콘을 화면 중앙에 적당한 크기로 보여주는 로딩 화면. 진입 시 살짝 팝인한다.
/// 배경·로고는 라이트/다크 모드에 따라 흰/검정으로 유동적으로 바뀐다.
private struct LoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appear = false

    private var isDarkMode: Bool { colorScheme == .dark }
    private var theme: AppTheme { isDarkMode ? .dark : .light }

    /// 로고 아래 은은한 음영. 라이트는 옅은 회색 그림자, 다크는 옅은 흰 헤일로.
    private var logoShadow: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.12)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            // LaunchLogo 에셋(MarCap "MC" 모노그램)은 다크 외형 변형을 포함해,
            // iOS 시스템 라이트/다크에 따라 배경(흰/검정)과 로고 색이 함께 맞물려 전환된다.
            // 은은한 그림자로 담백한 입체감만 살짝 준다(라이트=옅은 그림자, 다크=옅은 헤일로).
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .shadow(color: logoShadow, radius: 14, y: 6)
                .scaleEffect(appear ? 1.0 : 0.88)
                .opacity(appear ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appear = true }
        }
    }
}
