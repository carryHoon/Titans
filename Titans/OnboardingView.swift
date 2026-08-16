//
//  OnboardingView.swift
//  surFin
//
//  로그인 직후(닉네임 미설정 계정)에 1회 표시되는 온보딩.
//  흐름: 1) 닉네임 설정 → 2) 시가총액 표시 통화 선택 → 홈(ContentView).
//
//  · 닉네임은 유니크 제약 없이 표시용으로만 저장한다(공백 트림 + 길이 제한).
//  · 표시 통화는 시가총액을 표시할 단일 통화(USD 포함 전 통화가 동등한 선택지). 메뉴에서 변경 가능.
//  · 완료 시 PrefsSync.completeOnboarding 이 로컬(@AppStorage)·원격(user_prefs)에 반영하고,
//    RootView가 nickname 변화를 관찰해 자동으로 홈으로 전환한다.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthManager.self) private var auth

    /// 온보딩 완료 후 호출(RootView가 홈으로 전환).
    let onComplete: () -> Void

    private enum Step { case nickname, currency }

    @State private var step: Step = .nickname
    @State private var nickname: String = ""
    @State private var selectedCurrency: Currency?
    @State private var isBusy = false

    private let maxNicknameLength = 20
    private let accent = Color(red: 0.2, green: 0.8, blue: 0.4)

    private var theme: AppTheme { colorScheme == .dark ? .dark : .light }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 24)

                Group {
                    switch step {
                    case .nickname: nicknameStep
                    case .currency: currencyStep
                    }
                }
                .transition(.opacity)

                Spacer(minLength: 0)

                primaryButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }

            if isBusy {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView().controlSize(.large).tint(theme.label)
            }
        }
        .environment(\.appTheme, theme)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: 헤더 (진행 표시 + 로고)

    private var header: some View {
        VStack(spacing: 18) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            // 2스텝 진행 인디케이터
            HStack(spacing: 6) {
                Capsule().fill(accent).frame(width: 22, height: 4)
                Capsule().fill(step == .currency ? accent : theme.stroke).frame(width: 22, height: 4)
            }
        }
    }

    // MARK: Step 1 — 닉네임

    private var nicknameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("닉네임을 정해주세요")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
            Text("앱에서 사용할 이름이에요. 언제든 설정에서 바꿀 수 있어요.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)

            TextField("닉네임", text: $nickname)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { if !trimmedNickname.isEmpty { goToCurrency() } }
                .onChange(of: nickname) { _, newValue in
                    // 길이 제한(초과 입력 즉시 잘라냄).
                    if newValue.count > maxNicknameLength {
                        nickname = String(newValue.prefix(maxNicknameLength))
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))
                .padding(.top, 12)

            Text("\(trimmedNickname.count)/\(maxNicknameLength)")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    // MARK: Step 2 — 표시 통화

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("시가총액을 볼 통화를 선택해주세요")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
            Text("시가총액을 이 통화로 표시해요.\n메뉴에서 언제든 바꿀 수 있어요.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    currencyRow(currency)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 32)
    }

    private func currencyRow(_ currency: Currency) -> some View {
        let isSelected = selectedCurrency == currency
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedCurrency = currency
            }
        } label: {
            HStack(spacing: 14) {
                Text(currency.toggleSymbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? accent : theme.label)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.onboardingLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Text(currency.onboardingSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accent)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 하단 버튼

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .nickname:
            actionButton(title: "다음", enabled: !trimmedNickname.isEmpty) { goToCurrency() }
        case .currency:
            actionButton(title: "시작하기", enabled: selectedCurrency != nil) { finish() }
        }
    }

    private func actionButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(accent))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 액션

    private func goToCurrency() {
        withAnimation { step = .currency }
    }

    private func finish() {
        guard let currency = selectedCurrency, !trimmedNickname.isEmpty else { return }
        isBusy = true
        Task {
            await PrefsSync.shared.completeOnboarding(nickname: trimmedNickname, currency: currency)
            isBusy = false
            onComplete()
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
        .environment(AuthManager())
}
