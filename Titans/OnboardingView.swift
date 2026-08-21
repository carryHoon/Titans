//
//  OnboardingView.swift
//  surFin
//
//  로그인 직후(닉네임 미설정 계정)에 1회 표시되는 온보딩.
//  흐름(아하 모먼트 = "보고 싶은 거래소의 순위 변동을 빠르게 확인"을 첫 경험으로):
//    0) 소개(지원 거래소·확장 로드맵 + 국기 마퀴) →
//    1) 닉네임 설정 → 2) 표시 통화 선택 → (설정 중 로딩) →
//    3) 환영 인사 → 4) 보고 싶은 거래소 선택 → (동향 분석 중 로딩) →
//    5) 그 거래소의 순위 동향(문장형 "비트"를 한 번에 하나씩 천천히 등장) →
//    6) 환영·투자 여정 응원 → 홈(ContentView).
//
//  · 앞 두 폼 단계(닉네임·통화)만 진행바를 노출하고, 나머지는 안내형 경험이라
//    진행바 없이 스테이지드 페이드(멘트 먼저 → 목록/카드 순차 등장)로 여유 있게 연출한다.
//  · 모든 단계 콘텐츠는 서브뷰로 분리해 진입/전환마다 부드럽게 등장한다(툭 끊김 방지).
//  · 5단계 동향은 홈의 하이라이트 로직을 축약해 선택 거래소의 "오늘의 순위 사건"을 비트로 보여준다.
//  · 완료(응원 화면 끝)에서 PrefsSync.completeOnboarding 이 로컬(@AppStorage)·원격(user_prefs)에
//    반영하고, RootView가 nickname 변화를 관찰해 자동으로 홈으로 전환한다.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthManager.self) private var auth

    /// 온보딩 완료 후 호출(RootView가 홈으로 전환).
    let onComplete: () -> Void

    private enum Step: Int {
        case intro, nickname, currency, settingUp, welcome, exchange, analyzing, preview, cheer
    }

    @State private var step: Step = .intro
    @State private var nickname: String = ""
    @State private var selectedCurrency: Currency?
    @State private var selectedMarket: Market?
    /// 동향 미리보기 재생이 마무리에 도달하면 true — 그때 하단 "시작하기" 버튼을 노출한다.
    @State private var previewFinished = false

    /// 미리보기 단계에서 선택한 거래소 동향을 불러오는 전용 뷰모델(홈과 분리).
    @StateObject private var previewVM = MarketCapViewModel()

    private let maxNicknameLength = 20
    private let accent = Color(red: 0.2, green: 0.8, blue: 0.4)

    private var theme: AppTheme { colorScheme == .dark ? .dark : .light }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 온보딩에서 고를 수 있는 거래소 = 현재 데이터가 제공되는(준비 중 아님) 거래소 10개(ALL 제외).
    private var selectableMarkets: [Market] {
        Market.allCases.filter { !$0.comingSoon && $0 != .all }
    }

    /// 진행바는 "설정 폼"인 두 단계에서만 노출(나머지는 안내형 경험이라 부담을 줄임).
    private var showsProgress: Bool { step == .nickname || step == .currency }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            switch step {
            case .settingUp:
                // 폼 → 경험 전환 사이의 짧은 "설정 중" 호흡.
                OnboardingSettingUpView(theme: theme, accent: accent) {
                    go(to: .welcome)
                }
                .transition(.opacity)

            case .analyzing:
                // 거래소 선택 → 동향 결과 사이의 "분석 중" 호흡(설정 중 로딩과 동일한 느낌).
                // 이 동안 실제 데이터를 미리 받아와 결과뷰에서 곧바로 카드가 등장하게 한다.
                OnboardingAnalyzingView(
                    market: selectedMarket,
                    vm: previewVM,
                    theme: theme,
                    accent: accent
                ) {
                    go(to: .preview)
                }
                .transition(.opacity)

            case .cheer:
                // 마지막 환영·응원 문구가 여운을 남긴 뒤 홈으로.
                OnboardingCheerView(nickname: trimmedNickname, theme: theme, accent: accent) {
                    completeAndFinish()
                }
                .transition(.opacity)

            default:
                VStack(spacing: 0) {
                    header
                        .padding(.top, 24)

                    stepBody
                        .id(step)                       // 단계 교체마다 재생성 → 스테이지드 등장 + 크로스페이드
                        .transition(.opacity)

                    primaryButton
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                }
                .transition(.opacity)
            }
        }
        .environment(\.appTheme, theme)
        // 키보드로 레이아웃이 밀려 올라갔다가 내려오며 화면이 "툭" 끊기는 것을 방지
        // (닉네임 입력 → 통화 단계 전환 시 크로스페이드가 매끄럽게 유지된다).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.5), value: step)
    }

    // MARK: - 단계별 본문

    /// 짧은 단계(소개/닉네임/통화/환영)는 하단 Spacer로 버튼을 아래로 밀고,
    /// 거래소 선택은 스크롤 영역, 미리보기는 화면 중앙 히어로 스테이지로 처리한다.
    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .intro:
            OnboardingIntroStep(theme: theme, accent: accent)
        case .nickname:
            OnboardingNicknameStep(
                nickname: $nickname,
                maxLength: maxNicknameLength,
                theme: theme,
                onNext: { if !trimmedNickname.isEmpty { go(to: .currency) } }
            )
            Spacer(minLength: 0)
        case .currency:
            OnboardingCurrencyStep(selection: $selectedCurrency, accent: accent, theme: theme)
            Spacer(minLength: 0)
        case .welcome:
            OnboardingWelcomeView(nickname: trimmedNickname, theme: theme)
        case .exchange:
            ScrollView {
                OnboardingExchangeStep(
                    markets: selectableMarkets,
                    selection: $selectedMarket,
                    theme: theme,
                    accent: accent
                )
            }
        case .preview:
            // 한 번에 하나씩 크게 보여주는 히어로 스테이지 — 스크롤 없이 화면 중앙에서 순환.
            OnboardingPreviewStep(
                market: selectedMarket,
                currency: selectedCurrency ?? .usd,
                vm: previewVM,
                theme: theme,
                onFinished: { withAnimation(.easeOut(duration: 0.5)) { previewFinished = true } }
            )
        case .settingUp, .analyzing, .cheer:
            EmptyView()   // 별도 브랜치에서 전체 화면으로 처리됨(도달하지 않음)
        }
    }

    // MARK: 헤더 (진행 표시 + 로고)

    private var header: some View {
        VStack(spacing: 18) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            // 2단계(닉네임·통화)에서만 진행바 노출.
            if showsProgress {
                HStack(spacing: 6) {
                    Capsule().fill(accent).frame(width: 22, height: 4)
                    Capsule().fill(step == .currency ? accent : theme.stroke).frame(width: 22, height: 4)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: 하단 버튼

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .intro:
            actionButton(title: "시작할게요", enabled: true) { go(to: .nickname) }
        case .nickname:
            actionButton(title: "다음", enabled: !trimmedNickname.isEmpty) { go(to: .currency) }
        case .currency:
            actionButton(title: "다음", enabled: selectedCurrency != nil) { go(to: .settingUp) }
        case .welcome:
            actionButton(title: "좋아요", enabled: true) { go(to: .exchange) }
        case .exchange:
            actionButton(title: "다음", enabled: selectedMarket != nil) {
                previewFinished = false
                go(to: .analyzing)
            }
        case .preview:
            // 동향을 온전히 감상하는 동안에는 버튼을 숨겨 몰입을 유지, 마무리에서만 노출.
            if previewFinished {
                actionButton(title: "시작하기", enabled: true) { go(to: .cheer) }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        case .settingUp, .analyzing, .cheer:
            EmptyView()
        }
    }

    private func actionButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(RoundedRectangle(cornerRadius: 14).fill(accent))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 액션

    private func go(to next: Step) {
        withAnimation { step = next }
    }

    /// 응원 화면 종료 시 호출 — 온보딩 결과를 반영하면 RootView가 홈으로 전환한다.
    private func completeAndFinish() {
        guard let currency = selectedCurrency, !trimmedNickname.isEmpty else { return }
        Task {
            await PrefsSync.shared.completeOnboarding(nickname: trimmedNickname, currency: currency)
            onComplete()
        }
    }
}

// MARK: - Step 0 — 소개 (지원 거래소 + 확장 로드맵 + 국기 마퀴)

private struct OnboardingIntroStep: View {
    let theme: AppTheme
    let accent: Color

    @State private var appeared = false

    // 현재 지원(미국·한국·일본·중국·유럽·독일·인도) + 확장 예정(홍콩·대만·스위스·캐나다)까지
    // 한 줄에 모아 끊김 없이 흐르게 해 "넓혀간다"는 인상을 준다.
    private let flags = ["flag_us", "flag_kr", "flag_jp", "flag_cn", "flag_eu", "flag_de", "flag_in", "flag_hk", "flag_tw", "flag_ch", "flag_ca"]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            // 히어로 문구 — 국기 위 빈 공간을 채우는 핵심가치.
            Text("시가총액 순위를\n간편하게 확인해보세요")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .padding(.horizontal, 32)
                .onboardingStaged(appeared, delay: 0.1)

            // 국기 마퀴 — 한 줄로 오른쪽→왼쪽, 천천히 끊김 없이 무한 순환(엣지까지 꽉 차게).
            OnboardingFlagMarquee(flags: flags, itemSize: 68, speed: 22)
                .onboardingStaged(appeared, delay: 0.4)

            VStack(alignment: .leading, spacing: 16) {
                Text("주요 7개국\n10개 거래소를 지원해요")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)
                    .onboardingStaged(appeared, delay: 0.8)

                Text("앞으로 50개 거래소까지\n시장을 계속 넓혀갈 거예요.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)
                    .onboardingStaged(appeared, delay: 1.35)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }
}

private struct OnboardingFlagMarquee: View {
    let flags: [String]
    var itemSize: CGFloat = 56
    var speed: Double = 50   // 작을수록 천천히

    private let spacing: CGFloat = 18

    private var singleWidth: CGFloat { CGFloat(flags.count) * (itemSize + spacing) }

    var body: some View {
        // 화면 폭에 고정된 컨테이너(Color.clear) 위에 흐르는 HStack을 오버레이로 얹는다.
        // (HStack 자체는 화면보다 훨씬 넓어, frame(maxWidth:)만으로는 레이아웃 폭이 부풀어
        //  형제 텍스트가 화면 밖으로 밀려나므로 반드시 컨테이너 크기로 가둔다.)
        // 이동은 TimelineView로 매 프레임 시간 기반 offset을 계산해 상위 애니메이션 수정자와
        // 무관하게 항상 부드럽게 흐르게 한다(오른쪽→왼쪽, seamless 루프).
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: itemSize)
            .overlay(alignment: .leading) {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let offset = CGFloat((elapsed * speed).truncatingRemainder(dividingBy: Double(singleWidth)))
                    HStack(spacing: spacing) {
                        ForEach(0..<(flags.count * 2), id: \.self) { i in
                            Image(flags[i % flags.count])
                                .resizable()
                                .scaledToFill()
                                .frame(width: itemSize, height: itemSize)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .fixedSize()          // 컨테이너 폭에 압축되지 않고 고유 폭 유지
                    .offset(x: -offset)   // 오른쪽→왼쪽. 첫 복사본이 한 칸 흐르면 둘째 복사본이 이어받아 seamless
                }
            }
            .clipped()
    }
}

// MARK: - Step 1 — 닉네임 (레이아웃 유지 + 진입 스테이지드)

private struct OnboardingNicknameStep: View {
    @Binding var nickname: String
    let maxLength: Int
    let theme: AppTheme
    let onNext: () -> Void

    @State private var appeared = false

    private var trimmed: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("닉네임을 입력해주세요")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .onboardingStaged(appeared, delay: 0.05)

            Text("앱에서 사용할 이름이에요. 언제든 설정에서 바꿀 수 있어요.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .onboardingStaged(appeared, delay: 0.2)

            TextField("닉네임", text: $nickname)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { if !trimmed.isEmpty { onNext() } }
                .onChange(of: nickname) { _, newValue in
                    if newValue.count > maxLength {
                        nickname = String(newValue.prefix(maxLength))
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))
                .padding(.top, 12)
                .onboardingStaged(appeared, delay: 0.35)

            Text("\(trimmed.count)/\(maxLength)")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .onboardingStaged(appeared, delay: 0.35)
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .onAppear { appeared = true }
    }
}

// MARK: - Step 2 — 표시 통화 (레이아웃 유지 + 진입 스테이지드)

private struct OnboardingCurrencyStep: View {
    @Binding var selection: Currency?
    let accent: Color
    let theme: AppTheme

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("시가총액을 볼 통화를 선택해주세요")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .onboardingStaged(appeared, delay: 0.05)

            Text("시가총액을 이 통화로 표시해요.\n메뉴에서 언제든 바꿀 수 있어요.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingStaged(appeared, delay: 0.2)

            VStack(spacing: 10) {
                ForEach(Array(Currency.allCases.enumerated()), id: \.element) { i, currency in
                    row(currency)
                        .onboardingStaged(appeared, delay: 0.32 + Double(i) * 0.06)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 32)
        .onAppear { appeared = true }
    }

    private func row(_ currency: Currency) -> some View {
        let isSelected = selection == currency
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selection = currency
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
            .background(onboardingSelectionBackground(isSelected, accent: accent, theme: theme))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - "설정 중" 로딩 (폼 → 경험 전환 호흡)

private struct OnboardingSettingUpView: View {
    let theme: AppTheme
    let accent: Color
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
                .tint(accent)
            Text("소중한 정보 감사해요. 안전하게 저장할게요")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.easeOut(duration: 0.55), value: appeared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appeared = true
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                onDone()
            }
        }
    }
}

// MARK: - "동향 분석 중" 로딩 (거래소 선택 → 결과 전환 호흡)

/// 거래소를 고른 뒤 결과를 보여주기 전, "정성껏 분석하는 중"이라는 인상을 주는 호흡 화면.
/// "설정 중" 로딩과 동일한 룩앤필(중앙 스피너 + 안내 문구)로 통일하고,
/// 이 사이에 선택 거래소 데이터를 실제로 미리 받아와 다음 결과뷰에서 곧바로 카드가 등장하게 한다.
private struct OnboardingAnalyzingView: View {
    let market: Market?
    @ObservedObject var vm: MarketCapViewModel
    let theme: AppTheme
    let accent: Color
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
                .tint(accent)
            Text("\(market?.title ?? "거래소")의 동향을\n꼼꼼히 분석하는 중이에요")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.easeOut(duration: 0.55), value: appeared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .onAppear {
            appeared = true
            Task {
                // 순위 + 대표지수(첫 비트용)를 함께 미리 받고, 최소 호흡(약 2.2s)도 확보.
                if let market {
                    async let ranks: Void = vm.fetchExchange(market)
                    async let chart: Void = vm.fetchChart(market)
                    try? await Task.sleep(for: .seconds(2.2))
                    _ = await (ranks, chart)
                } else {
                    try? await Task.sleep(for: .seconds(2.2))
                }
                onDone()
            }
        }
    }
}

// MARK: - Step 3 — 환영 인사

private struct OnboardingWelcomeView: View {
    let nickname: String
    let theme: AppTheme

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)

            Text("\(nickname)님,\n환영해요 🎉")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .onboardingStaged(appeared, delay: 0.2)

            Text("MarCap을 사용하면\n보고 싶은 거래소의 순위 변동을\n빠르게 확인할 수 있어요.")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .onboardingStaged(appeared, delay: 0.95)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .onAppear { appeared = true }
    }
}

// MARK: - Step 4 — 보고 싶은 거래소 선택

private struct OnboardingExchangeStep: View {
    let markets: [Market]
    @Binding var selection: Market?
    let theme: AppTheme
    let accent: Color

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("보고 싶은 거래소를\n선택해주세요")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
                .onboardingStaged(appeared, delay: 0.15)

            Text("선택한 거래소의 동향을 보여드릴게요.\n홈에서 모든 거래소를 확인할 수 있어요.")
                .font(.system(size: 16))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .onboardingStaged(appeared, delay: 0.5)

            VStack(spacing: 12) {
                ForEach(Array(markets.enumerated()), id: \.element.id) { i, market in
                    row(market)
                        .onboardingStaged(appeared, delay: 0.85 + Double(i) * 0.07)
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .onAppear { appeared = true }
    }

    private func row(_ market: Market) -> some View {
        let isSelected = selection == market
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selection = market
            }
        } label: {
            HStack(spacing: 16) {
                Image(market.flagImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(market.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.label)
                    if let fullName = market.info?.fullName {
                        Text(fullName)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(onboardingSelectionBackground(isSelected, accent: accent, theme: theme))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5 — 선택한 거래소 순위 동향 미리보기

private struct OnboardingPreviewStep: View {
    let market: Market?
    let currency: Currency
    @ObservedObject var vm: MarketCapViewModel
    let theme: AppTheme
    /// 모든 동향(비트)을 다 보여주고 마무리 메시지에 도달하면 호출 — 하단 "시작하기" 버튼을 그때 노출한다.
    let onFinished: () -> Void

    // first happy experience: 한 번에 하나씩(비트) 화면 정중앙에서 크게 보여주고,
    // 부드럽게 사라지면 다음 비트가 그 자리를 이어받는다. 각 비트 자체가 주인공이 되게 한다.
    @State private var beats: [PreviewBeat] = []
    @State private var index = 0
    @State private var beatVisible = false   // 현재 비트 페이드 인/아웃
    @State private var started = false       // 재생 1회만 시작
    @State private var advanceTask: Task<Void, Never>?   // 다음 비트 자동 예약(탭 스킵 시 취소·재예약)

    private var feed: ExchangeFeed? { market.flatMap { vm.exchangeFeeds[$0] } }
    private var companies: [Company] { feed?.companies ?? [] }

    var body: some View {
        ZStack {
            if beats.indices.contains(index) {
                let beat = beats[index]
                beatView(beat)
                    .id(beat.id)   // 비트 교체마다 확실히 재구성
                    .opacity(beatVisible ? 1 : 0)
                    .scaleEffect(beatVisible ? 1 : 0.94)
                    .offset(y: beatVisible ? 0 : 16)
            } else {
                // 데이터 대기 — 회색 프레임 없이 조용한 스피너만.
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // 정중앙 기준, 살짝 위로 올려 시선 균형
        .offset(y: -40)
        .padding(.horizontal, 36)
        .contentShape(Rectangle())          // 빈 영역까지 탭 인식(결과 화면 어디를 눌러도 스킵)
        .onTapGesture { skip() }            // 탭 → 다음 결과로 즉시 건너뛰기
        .onAppear { startIfReady() }
        .onChange(of: companies.count) { _, _ in startIfReady() }
    }

    /// 비트 한 장 — 하이라이트 asset 이미지(있으면) + 크게 감싼 문장. 배경 프레임 없이 텍스트 중심.
    @ViewBuilder
    private func beatView(_ beat: PreviewBeat) -> some View {
        VStack(spacing: 30) {
            if let asset = beat.imageAsset {
                if beat.circularImage {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                } else {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                }
            }
            VStack(spacing: 10) {
                Text(LocalizedStringKey(beat.text))
                    .font(.system(size: beat.isFinale ? 30 : 27, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(8)

                // 기준일 등 표기용 곁다리 — 작고 흐릿하게(강조 아님).
                if let caption = beat.caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.tertiaryLabel)
                }
            }
        }
    }

    /// 데이터가 준비되면(프리페치 완료) 비트를 구성하고 1회 재생한다.
    private func startIfReady() {
        guard !started else { return }
        let highlights = previewHighlights(companies)
        guard !highlights.isEmpty else { return }   // 아직 데이터 없음 → onChange에서 재시도
        started = true
        beats = buildBeats(highlights)
        scheduleBeat(0)
    }

    /// 대표지수 → 동향 비트(최대 3개, 첫 비트에 순위 기준일을 작게 곁들임) → 마무리(끝맺음)로 구성.
    /// (기준일은 강조하지 않고 첫 하이라이트 하단에 작게만 표기 — 거래소별 형태에 맞춰 정확히.)
    private func buildBeats(_ highlights: [Highlight]) -> [PreviewBeat] {
        var list: [PreviewBeat] = []
        if let idx = indexBeat() { list.append(idx) }   // 대표지수 + 지수 갱신일(있으면)

        var highlightBeats = highlights.prefix(3).map(beat(for:))
        if !highlightBeats.isEmpty {
            highlightBeats[0].caption = asOfCaption()   // 첫 하이라이트 하단에 기준일 작게
        }
        list.append(contentsOf: highlightBeats)

        list.append(PreviewBeat(id: "closing", imageAsset: nil,
            text: "더 많은 변동정보와 다양한 거래소\nMarCap은 모두 있어요\n간편하게 시작해 보세요", isFinale: true))
        return list
    }

    /// 대표지수(대표 ETF/지수 일별) 동향 비트 — 데이터가 있을 때만. 거래소 국기(원형)와 함께.
    /// 지수 갱신 시점은 거래소 데이터 형태를 따른다(realtime=오늘, EOD=갱신된 거래일).
    private func indexBeat() -> PreviewBeat? {
        guard let chart = market.flatMap({ vm.charts[$0] }) else { return nil }
        let title = market?.title ?? ""
        let flag = market?.flagImageName
        let p = chart.changePercent
        let sign = p > 0 ? "+" : ""
        let verb = p > 0 ? "올랐어요" : (p < 0 ? "내렸어요" : "보합이에요")
        let pct = p == 0 ? "0.00%" : "\(sign)\(String(format: "%.2f", p))%"

        let whenPrefix: String
        switch market?.dataBasis {
        case .realtime?:
            whenPrefix = "오늘 "
        case .eodDated?, .reportedCap?:
            whenPrefix = referenceDateText().map { "\($0) 기준 " } ?? ""
        default:
            whenPrefix = ""
        }
        return PreviewBeat(id: "index", imageAsset: flag,
            text: "**\(title)** 대표지수 **\(chart.name)**,\n\(whenPrefix)**\(pct)** \(verb)",
            isFinale: false, circularImage: true)
    }

    /// 순위/시총 기준일 — 강조 없이 첫 하이라이트 하단에 작게 곁들일 캡션(오해 방지·표기 목적).
    ///  · realtime(US·EU): "실시간 기준"
    ///  · eodDated(KR·중국·인도): "{거래일} 종가 기준"
    ///  · reportedCap(JPX): "{기준일} 기준" (종가 미표기)
    private func asOfCaption() -> String? {
        switch market?.dataBasis {
        case .realtime?:
            return "실시간 기준"
        case .eodDated?:
            return referenceDateText().map { "\($0) 종가 기준" }
        case .reportedCap?:
            return referenceDateText().map { "\($0) 기준" }
        default:
            return nil
        }
    }

    /// 기준일 문자열 — basDt("YYYYMMDD") 또는 asOf("YYYY-MM-DD")를 "YYYY.MM.DD"로 정규화.
    private func referenceDateText() -> String? {
        if let b = feed?.basDt, b.count == 8 {
            let y = b.prefix(4), m = b.dropFirst(4).prefix(2), d = b.suffix(2)
            return "\(y).\(m).\(d)"
        }
        if let a = feed?.asOf, !a.isEmpty {
            return a.replacingOccurrences(of: "-", with: ".")
        }
        return nil
    }

    /// 비트 체류 시간 — 적으면 오래(강조), 많으면 조금 짧게.
    private var beatHold: Double {
        let nonFinal = max(1, beats.count - 1)
        return nonFinal <= 3 ? 3.0 : 2.2
    }

    /// i번째 비트를 등장시키고, 마무리가 아니면 체류 후 다음 비트를 자동 예약한다.
    /// 예약(advanceTask)은 취소 가능해서, 사용자가 화면을 탭하면 즉시 다음 비트로 건너뛸 수 있다(skip).
    /// 마지막(마무리) 비트는 사라지지 않고 머물며 하단 "시작하기" 버튼을 노출한다.
    private func scheduleBeat(_ i: Int) {
        advanceTask?.cancel()
        guard beats.indices.contains(i) else { return }
        index = i
        beatVisible = false
        advanceTask = Task { @MainActor in
            // 새 비트를 '숨김'으로 먼저 렌더한 뒤 등장(팝인 방지).
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 1.0)) { beatVisible = true }

            if i == beats.count - 1 {
                onFinished()   // 마무리 도달 → "시작하기" 노출
                return
            }
            try? await Task.sleep(for: .seconds(beatHold))   // 충분한 강조 체류
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.8)) { beatVisible = false }
            try? await Task.sleep(for: .seconds(1.0))         // 페이드아웃 + 여백
            if Task.isCancelled { return }
            scheduleBeat(i + 1)
        }
    }

    /// 결과 화면 탭 — 현재 비트를 건너뛰고 다음 결과로 즉시 전환. 마무리 비트에선 무시.
    private func skip() {
        guard !beats.isEmpty, index < beats.count - 1 else { return }
        scheduleBeat(index + 1)
    }

    /// 선택한 거래소의 "오늘의 순위 사건"을 축약해 만든다(홈 하이라이트 로직의 미리보기용 축약판).
    /// 현재 1위 → 최대 상승 → 최대 하락 → 시총 급등락 순으로, 중복 종목은 제외한다.
    private func previewHighlights(_ list: [Company]) -> [Highlight] {
        guard !list.isEmpty else { return [] }
        let rate = vm.rate(for: currency)
        var result: [Highlight] = []
        var used = Set<String>()

        // 1) 현재 1위 — 서열의 정점(항상 채워 절대 비지 않게).
        if let leader = list.first(where: { $0.rank == 1 }) ?? list.min(by: { $0.rank < $1.rank }) {
            let cap = formatMarketCap(leader.marketCapUSD, currency: currency, exchangeRate: rate)
            result.append(Highlight(kind: .leader, company: leader,
                title: "현재 1위", detail: "\(leader.name) · \(cap)", rankDelta: nil))
            used.insert(leader.ticker)
        }

        // 2) 최대 상승 — (previousRank - rank)가 가장 큰 종목.
        if let riser = list.compactMap({ c -> (Company, Int)? in
            guard let p = c.previousRank else { return nil }
            let d = p - c.rank
            return d > 0 ? (c, d) : nil
        }).max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rank > $1.0.rank }), !used.contains(riser.0.ticker) {
            let c = riser.0
            result.append(Highlight(kind: .topGainer, company: c,
                title: "최대 상승", detail: "\(c.name) \(c.previousRank!)위 → \(c.rank)위", rankDelta: riser.1))
            used.insert(c.ticker)
        }

        // 3) 최대 하락 — (previousRank - rank)가 가장 작은(가장 많이 내린) 종목.
        if let faller = list.compactMap({ c -> (Company, Int)? in
            guard let p = c.previousRank else { return nil }
            let d = p - c.rank
            return d < 0 ? (c, d) : nil
        }).min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rank < $1.0.rank }), !used.contains(faller.0.ticker) {
            let c = faller.0
            result.append(Highlight(kind: .topLoser, company: c,
                title: "최대 하락", detail: "\(c.name) \(c.previousRank!)위 → \(c.rank)위", rankDelta: faller.1))
            used.insert(c.ticker)
        }

        // 4) 시총 급등락 — |당일 등락률|이 가장 큰 종목(3% 이상). 순위가 안 변한 날도 살아있게.
        if let mover = list.filter({ abs($0.change) >= 3.0 && !used.contains($0.ticker) })
            .max(by: { abs($0.change) < abs($1.change) }) {
            let up = mover.change >= 0
            result.append(Highlight(kind: .bigMove, company: mover,
                title: up ? "시총 급등" : "시총 급락", detail: "\(mover.name) \(mover.rank)위",
                rankDelta: nil, percentMove: mover.change))
            used.insert(mover.ticker)
        }

        return result
    }

    /// 하이라이트 하나를 "정성껏 짚어주는" 문장 비트로 만든다(값만 툭 보여주지 않도록).
    /// 아이콘은 이모지 대신 하이라이트 asset(cat_*)을 사용하고, **굵게**는 마크다운으로 강조된다.
    private func beat(for h: Highlight) -> PreviewBeat {
        let name = h.company.name
        let id = h.company.ticker
        // categoryAsset이 nil인 종류만 하락 아이콘(cat_loser)으로 폴백(현재 preview 대상엔 없음).
        let asset = h.categoryAsset ?? "cat_loser"
        switch h.kind {
        case .leader:
            let cap = formatMarketCap(h.company.marketCapUSD, currency: currency, exchangeRate: vm.rate(for: currency))
            return PreviewBeat(id: id, imageAsset: asset,
                text: "**\(name)**, 시가총액 **\(cap)** 규모로\n지금 당당히 **1위**를 지키고 있어요!", isFinale: false)
        case .topGainer:
            let d = h.rankDelta ?? 0
            let prev = h.company.previousRank ?? h.company.rank
            return PreviewBeat(id: id, imageAsset: asset,
                text: "**\(name)**, \(prev)위에서 \(h.company.rank)위로\n무려 **\(d)계단**이나 껑충 뛰어올랐네요!", isFinale: false)
        case .topLoser:
            let d = abs(h.rankDelta ?? 0)
            let prev = h.company.previousRank ?? h.company.rank
            return PreviewBeat(id: id, imageAsset: asset,
                text: "**\(name)**, \(prev)위에서 \(h.company.rank)위로\n\(d)계단 내려오며 오늘은 조금 부진했어요.", isFinale: false)
        case .bigMove:
            let p = h.percentMove ?? 0
            if p >= 0 {
                return PreviewBeat(id: id, imageAsset: asset,
                    text: "**\(name)**, 하루 만에 시가총액이\n**+\(String(format: "%.2f", p))%**나 훌쩍 올랐네요!", isFinale: false)
            } else {
                return PreviewBeat(id: id, imageAsset: asset,
                    text: "**\(name)**, 하루 만에 시가총액이\n**\(String(format: "%.2f", p))%** 빠지며 잠시 숨을 고르고 있어요.", isFinale: false)
            }
        default:
            return PreviewBeat(id: id, imageAsset: asset,
                text: "**\(name)**, \(h.company.rank)위로 오늘도 순위를 지키고 있어요.", isFinale: false)
        }
    }
}

// MARK: - 온보딩 순위 동향 "비트" (한 번에 하나씩 크게 보여주는 단위)

/// 결과뷰에서 한 화면에 하나씩 등장/퇴장하는 단위. 인트로·마무리는 이미지 없이 텍스트만.
private struct PreviewBeat: Identifiable {
    let id: String
    /// 하이라이트 asset명(cat_*) 또는 거래소 국기명. nil이면 텍스트만 크게(마무리).
    let imageAsset: String?
    /// 마크다운(**굵게**)으로 핵심 값이 강조된 문장.
    let text: String
    /// 마지막(마무리) 비트 여부 — 페이드아웃 없이 머문다.
    let isFinale: Bool
    /// 국기처럼 원형으로 클립할지(첫 비트의 거래소 국기 전용).
    var circularImage: Bool = false
    /// 본문 아래 작게 곁들이는 표기(예: 순위 기준일) — 강조 아님.
    var caption: String? = nil
}

// MARK: - Step 6 — 응원 (환영 + 핵심가치 재전달 + 투자 여정 응원)

/// 마지막 화면. 🚀 → "이제 준비가 모두 끝났어요" → 핵심가치 재전달 → "{닉네임}님의 투자 여정을
/// MarCap이 함께 응원할게요"(accent)를 아주 부드럽고 천천히 순차로 띄워 환영·응원의 여운을 남긴 뒤,
/// 충분히 머물다 onDone으로 홈에 진입한다.
private struct OnboardingCheerView: View {
    let nickname: String
    let theme: AppTheme
    let accent: Color

    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer(minLength: 0)

            Text("🚀")
                .font(.system(size: 64))
                .onboardingStaged(appeared, delay: 0.3, duration: 0.9)

            Text("이제 준비가\n모두 끝났어요")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .onboardingStaged(appeared, delay: 1.1, duration: 0.9)

            Text("보고 싶은 거래소의 순위 변동을\n이제 홈에서 매일 만나보세요")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .onboardingStaged(appeared, delay: 2.2, duration: 0.9)

            Text("\(nickname)님의 투자 여정을\nMarCap이 함께 응원할게요")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .onboardingStaged(appeared, delay: 3.4, duration: 1.0)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .onAppear {
            appeared = true
            Task {
                // 마지막 문장이 다 등장하고(약 4.4s) 충분히 머물러 여운을 남긴 뒤 홈으로.
                try? await Task.sleep(for: .seconds(6.5))
                onDone()
            }
        }
    }
}

// MARK: - 공통 헬퍼

/// 선택 카드 배경(통화·거래소 행 공용).
private func onboardingSelectionBackground(_ isSelected: Bool, accent: Color, theme: AppTheme) -> some View {
    RoundedRectangle(cornerRadius: 12)
        .fill(theme.fill)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? accent : Color.clear, lineWidth: 1.5)
        )
}

private extension View {
    /// 스테이지드 등장 — appeared가 true가 되면 delay 후 아래에서 위로 여유 있게 페이드인.
    /// (각 요소에 서로 다른 delay를 주면 순차 등장 캐스케이드가 된다.)
    func onboardingStaged(_ appeared: Bool, delay: Double, duration: Double = 0.65) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .animation(.easeOut(duration: duration).delay(delay), value: appeared)
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
        .environment(AuthManager())
}
