//
//  SplashView.swift
//  surFin
//
//  앱 최상단 컨테이너(RootView).
//
//  기존 Titans 로딩(스플래시) 화면은 제거했다. 앱을 실행하면 곧바로 로그인 화면(LoginView)이
//  뜨고, 그 자체의 파도-형성 인트로가 "브랜드 로딩" 역할을 겸한다. 세션이 복원되어 이미
//  로그인돼 있거나, 한 번 "둘러보기"를 고른 사용자는 자동으로 메인(ContentView)으로 넘어간다.
//

import SwiftUI

struct RootView: View {
    @State private var auth = AuthManager()

    /// 로그인 화면을 한 번이라도 건너뛰었는지(익명 진입 완료). true면 다음부터 바로 메인.
    @AppStorage("hasSkippedLogin") private var hasSkippedLogin = false

    private enum Screen: Equatable { case login, main }

    private var screen: Screen {
        // 로그인돼 있거나 이미 둘러보기를 고른 사용자는 메인으로. 그 외(신규·비로그인)는 로그인.
        // 세션 복원 중에는 로그인 화면의 파도 인트로가 그대로 로딩 연출을 겸한다.
        if auth.isSignedIn { return .main }
        return hasSkippedLogin ? .main : .login
    }

    var body: some View {
        ZStack {
            switch screen {
            case .login:
                LoginView(onContinueAnonymously: { hasSkippedLogin = true })
                    .transition(.opacity)
            case .main:
                ContentView().transition(.opacity)
            }
        }
        .environment(auth)
        .animation(.easeInOut(duration: 0.5), value: screen)
        .onChange(of: auth.userId) { _, newId in
            // 로그인/로그아웃에 따라 환경설정 동기화를 시작/중단한다.
            PrefsSync.shared.update(userId: newId)
        }
    }
}
