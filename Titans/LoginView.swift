//
//  LoginView.swift
//  surFin
//
//  스플래시 이후 (비로그인·최초 진입 시) 보여지는 로그인 화면.
//  브랜드 무드: "surFin — Ride the Market".
//
//  구성(위 → 아래):
//    1) 브랜드 텍스트("RIDE THE MARKET" / "surFin") — 상단에 크게 배치, 진입 시 페이드인.
//    2) 소셜 로그인(메인) — Apple · Google · Kakao 원형 버튼.
//    3) 하단(서브)         — 로그인 없이 둘러보기.
//
//  이메일/비밀번호 가입은 안전한 메일 전달성(커스텀 SMTP)·딥링크 인증이 갖춰지기 전까지
//  제공하지 않는다(소셜 로그인만 노출). 관련 진입점(회원가입 버튼·EmailAuthSheet)은 제거됨.
//
//  로그인은 선택이다. 실제 세션 전환은 AuthManager가 authStateChanges로 감지해
//  RootView가 자동으로 ContentView로 넘어간다. 이 화면은 "요청"만 하고 상태는 소유하지 않는다.
//

import SwiftUI
import AuthenticationServices
import UIKit

// MARK: - LoginView

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthManager.self) private var auth

    private var isDarkMode: Bool { colorScheme == .dark }

    /// "로그인 없이 둘러보기" 선택 시 호출(익명으로 앱 진입).
    let onContinueAnonymously: () -> Void

    // 인트로가 끝난 뒤 순차적으로 드러나는 요소들.
    @State private var revealBrand = false
    @State private var revealControls = false

    // 소셜/이메일 진행 상태
    @State private var appleCoordinator = AppleSignInCoordinator()
    @State private var isBusy = false
    @State private var alertMessage: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 브랜드 텍스트 — 화면 상단(약 22% 지점)에 크게 배치.
                    Spacer(minLength: 0).frame(height: geo.size.height * 0.22)
                    brand

                    Spacer(minLength: 0)

                    // 소셜 로그인 + 하단 링크 — 화면 하단에 모아 배치.
                    VStack(spacing: 24) {
                        socialSection
                        bottomLinks
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 0).frame(height: geo.size.height * 0.12)
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 12)

                if isBusy {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView().controlSize(.large).tint(theme.label)
                }
            }
        }
        .task {
            // 진입과 동시에 브랜드 텍스트, 이어서 소셜/하단이 페이드인.
            withAnimation(.easeOut(duration: 0.7)) { revealBrand = true }
            try? await Task.sleep(for: .seconds(0.28))
            withAnimation(.easeOut(duration: 0.7)) { revealControls = true }
        }
        .alert("알림", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// 라이트/다크 모드에 대응하는 테마(배경·텍스트 색).
    private var theme: AppTheme { isDarkMode ? .dark : .light }
    private var background: Color { theme.background }

    // MARK: 브랜드 텍스트

    private var brand: some View {
        VStack(spacing: 20) {
            // 앱 아이콘과 통일된 브랜드 마크. 라이트=검정, 다크=흰색으로 유동 전환된다.
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .offset(x: -5)

            VStack(spacing: 6) {
                Text("RIDE THE MARKET")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))

                Text("MarCap")
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.label)
            }
        }
        .opacity(revealBrand ? 1 : 0)
        .offset(y: revealBrand ? 0 : 14)
    }

    // MARK: 메인 — 소셜 로그인 (원형)

    private var socialSection: some View {
        HStack(spacing: 26) {
            SocialCircleButton(kind: .apple)  { signInWithApple() }
            SocialCircleButton(kind: .google) { signInWithGoogle() }
            SocialCircleButton(kind: .kakao)  { signInWithKakao() }
        }
        .opacity(revealControls ? 1 : 0)
        .offset(y: revealControls ? 0 : 14)
    }

    // MARK: 서브 — 둘러보기

    private var bottomLinks: some View {
        Button("로그인 없이 둘러보기") { onContinueAnonymously() }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.secondaryLabel)
            .opacity(revealControls ? 1 : 0)
    }

    // MARK: 액션

    private func signInWithApple() {
        appleCoordinator.start(configure: { auth.prepareAppleRequest($0) }) { result in
            Task { await handleApple(result) }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.handleAppleCompletion(result)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // 사용자가 취소한 경우는 오류로 표시하지 않는다.
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            alertMessage = error.localizedDescription
        }
    }

    private func signInWithKakao() {
        Task { await handleKakao() }
    }

    private func handleKakao() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signInWithKakao()
        } catch {
            // 사용자가 웹 로그인 창을 닫은(취소한) 경우는 오류로 표시하지 않는다.
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return }
            alertMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() {
        Task { await handleGoogle() }
    }

    private func handleGoogle() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signInWithGoogle()
        } catch {
            // 사용자가 웹 로그인 창을 닫은(취소한) 경우는 오류로 표시하지 않는다.
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return }
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - SocialCircleButton (원형 소셜 로그인 버튼)

private struct SocialCircleButton: View {
    enum Kind { case apple, google, kakao }

    let kind: Kind
    let action: () -> Void

    private let diameter: CGFloat = 62

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(background)
                symbol
            }
            .frame(width: diameter, height: diameter)
            // 배경색과 겹쳐 구획이 안 되는 경우를 대비해 원 테두리로 구획한다.
            .overlay(Circle().stroke(ring, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var background: Color {
        switch kind {
        case .apple:  return .black
        case .google: return .white
        case .kakao:  return Color(red: 0.996, green: 0.898, blue: 0.0) // Kakao Yellow #FEE500
        }
    }

    /// 흰 배경(구글)은 검정 계열 테두리로, 나머지는 은은한 흰 테두리로 구획.
    private var ring: Color {
        kind == .google ? Color.black.opacity(0.14) : Color.white.opacity(0.18)
    }

    @ViewBuilder
    private var symbol: some View {
        switch kind {
        case .apple:
            Image(systemName: "applelogo")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .offset(y: -1)
        case .google:
            Image("SocialGoogle")
                .resizable()
                .scaledToFit()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        case .kakao:
            // 카카오 공식 말풍선 심볼(투명 배경) — 노랑 배경 위에 얹는다.
            Image("KakaoLoginSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
    }

    private var accessibilityLabelText: String {
        switch kind {
        case .apple:  return "Apple로 로그인"
        case .google: return "Google로 로그인"
        case .kakao:  return "카카오로 로그인"
        }
    }
}

// MARK: - AppleSignInCoordinator (커스텀 원형 버튼용 네이티브 Apple 로그인)

/// `SignInWithAppleButton`(정형 버튼) 대신 원형 아이콘 버튼을 쓰기 위해
/// `ASAuthorizationController`를 직접 구동한다. nonce/스코프 설정은 AuthManager가 담당.
@MainActor
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var onResult: ((Result<ASAuthorization, Error>) -> Void)?

    func start(configure: (ASAuthorizationAppleIDRequest) -> Void,
               onResult: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.onResult = onResult
        let request = ASAuthorizationAppleIDProvider().createRequest()
        configure(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            onResult?(.success(authorization)); onResult = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            onResult?(.failure(error)); onResult = nil
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let key = scene?.keyWindow { return key }
        if let scene { return UIWindow(windowScene: scene) }
        return UIWindow(frame: .zero)
    }
}

#Preview("Login") {
    LoginView(onContinueAnonymously: {})
        .environment(AuthManager())
}
