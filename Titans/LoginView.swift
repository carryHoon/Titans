//
//  LoginView.swift
//  Titans
//
//  스플래시 이후 (비로그인·최초 진입 시) 보여지는 로그인 화면.
//  구성: 상단 브랜드 마크 → 메인(플랫폼 계정 연동) → 서브(이메일 직접 가입/로그인)
//        → 하단("로그인 없이 둘러보기", 익명 사용 허용).
//
//  로그인은 선택이다. 실제 세션 전환은 AuthManager가 authStateChanges로 감지해
//  RootView가 자동으로 ContentView로 넘어간다. 이 화면은 "요청"만 하고 상태는 소유하지 않는다.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @Environment(AuthManager.self) private var auth

    /// "로그인 없이 둘러보기" 선택 시 호출(익명으로 앱 진입).
    let onContinueAnonymously: () -> Void

    // 이메일 폼 상태
    @State private var isSignUpMode = false
    @State private var email = ""
    @State private var password = ""

    @State private var isBusy = false
    @State private var alertMessage: String?
    @State private var infoMessage: String?

    private var theme: AppTheme { isDarkMode ? .dark : .light }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    brand
                    socialSection
                    divider
                    emailSection
                    skipButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 48)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)

            if isBusy {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.label)
            }
        }
        .alert("알림", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("안내", isPresented: .init(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
    }

    // MARK: - 브랜드

    private var brand: some View {
        VStack(spacing: 16) {
            TitansMark(isDark: isDarkMode)
                .frame(width: 96, height: 86)
            Text("Titans")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(theme.label)
            Text("로그인하고 관심 종목·설정을 기기 간에 동기화하세요")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 메인: 플랫폼 계정 연동

    private var socialSection: some View {
        VStack(spacing: 12) {
            // Sign in with Apple (App Store 가이드라인 4.8 준수: 소셜 로그인 최상단 배치)
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(isDarkMode ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 카카오 로그인 (웹 OAuth) — 브랜드 컬러 #FEE500 / 검정 라벨
            kakaoButton

            // Google 버튼은 다음 단계에서 provider 연동과 함께 추가된다.
        }
    }

    /// 카카오 브랜드 가이드에 맞춘 로그인 버튼(노란 배경 + 말풍선 심볼 + 검정 라벨).
    private var kakaoButton: some View {
        Button {
            Task { await handleKakao() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "message.fill")
                    .font(.system(size: 17, weight: .bold))
                Text("카카오로 계속하기")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.11).opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 1.0, green: 0.898, blue: 0.0)))
        }
        .disabled(isBusy)
    }

    // MARK: - 구분선

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(theme.stroke).frame(height: 1)
            Text("또는 이메일로")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize()
            Rectangle().fill(theme.stroke).frame(height: 1)
        }
    }

    // MARK: - 서브: 이메일 직접 가입/로그인

    private var emailSection: some View {
        VStack(spacing: 12) {
            themedField("이메일", text: $email, isSecure: false)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            themedField("비밀번호", text: $password, isSecure: true)
                .textContentType(isSignUpMode ? .newPassword : .password)

            Button {
                Task { await submitEmail() }
            } label: {
                Text(isSignUpMode ? "회원가입" : "로그인")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.label))
            }
            .disabled(!isEmailFormValid || isBusy)
            .opacity(isEmailFormValid ? 1 : 0.5)

            HStack {
                Button(isSignUpMode ? "이미 계정이 있어요" : "계정 만들기") {
                    withAnimation { isSignUpMode.toggle() }
                }
                Spacer()
                Button("비밀번호를 잊으셨나요?") {
                    Task { await sendReset() }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(theme.secondaryLabel)
        }
    }

    // MARK: - 하단: 익명 진입

    private var skipButton: some View {
        Button("로그인 없이 둘러보기") {
            onContinueAnonymously()
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(theme.secondaryLabel)
        .padding(.top, 4)
    }

    // MARK: - 공용 텍스트필드

    @ViewBuilder
    private func themedField(_ placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(theme.label)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.stroke, lineWidth: 1))
    }

    private var isEmailFormValid: Bool {
        email.contains("@") && password.count >= 6
    }

    // MARK: - 액션

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.handleAppleCompletion(result)
        } catch {
            // 사용자가 취소한 경우는 오류로 표시하지 않는다.
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            alertMessage = error.localizedDescription
        }
    }

    private func handleKakao() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signInWithKakao()
        } catch {
            // 사용자가 로그인 시트를 닫은 경우는 오류로 표시하지 않는다.
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return }
            alertMessage = error.localizedDescription
        }
    }

    private func submitEmail() async {
        isBusy = true
        defer { isBusy = false }
        do {
            if isSignUpMode {
                try await auth.signUpEmail(email: email, password: password)
                // 이메일 확인이 켜져 있으면 세션이 바로 열리지 않을 수 있다.
                if auth.currentUser == nil {
                    infoMessage = "확인 메일을 보냈어요. 메일의 링크로 인증을 완료한 뒤 로그인해 주세요."
                }
            } else {
                try await auth.signInEmail(email: email, password: password)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func sendReset() async {
        guard email.contains("@") else {
            alertMessage = "비밀번호를 재설정할 이메일 주소를 먼저 입력해 주세요."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.resetPassword(email: email)
            infoMessage = "비밀번호 재설정 메일을 보냈어요."
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
