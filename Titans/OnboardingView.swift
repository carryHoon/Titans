//
//  OnboardingView.swift
//  surFin
//
//  로그인 직후(닉네임 미설정 계정)에 1회 표시되는 온보딩.
//  흐름(아하 모먼트 = "보고 싶은 거래소의 순위 변동을 빠르게 확인"을 첫 경험으로):
//    0) 소개(지원 거래소·확장 로드맵 + 국기 마퀴) →
//    1) 닉네임 설정 → 2) 표시 통화 선택 → (설정 중 로딩) →
//    3) 환영 인사 → 4) 보고 싶은 거래소 선택 → 5) 그 거래소의 순위 동향 →
//    6) "RIDE THE MARKET" 응원 → 홈(ContentView).
//
//  · 앞 두 폼 단계(닉네임·통화)만 진행바를 노출하고, 나머지는 안내형 경험이라
//    진행바 없이 스테이지드 페이드(멘트 먼저 → 목록/카드 순차 등장)로 여유 있게 연출한다.
//  · 모든 단계 콘텐츠는 서브뷰로 분리해 진입/전환마다 부드럽게 등장한다(툭 끊김 방지).
//  · 5단계 동향은 홈의 하이라이트 로직을 축약해 선택 거래소의 "오늘의 순위 사건"을 카드로 보여준다.
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
        case intro, nickname, currency, settingUp, welcome, exchange, preview, cheer
    }

    @State private var step: Step = .intro
    @State private var nickname: String = ""
    @State private var selectedCurrency: Currency?
    @State private var selectedMarket: Market?

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

            case .cheer:
                // 마지막 응원 → "RIDE THE MARKET" 후 홈으로.
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
        .animation(.easeInOut(duration: 0.5), value: step)
    }

    // MARK: - 단계별 본문

    /// 짧은 단계(소개/닉네임/통화/환영)는 하단 Spacer로 버튼을 아래로 밀고,
    /// 긴 단계(거래소 선택/미리보기)는 스크롤 영역으로 감싼다.
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
            ScrollView {
                OnboardingPreviewStep(
                    market: selectedMarket,
                    currency: selectedCurrency ?? .usd,
                    vm: previewVM,
                    theme: theme
                )
            }
        case .settingUp, .cheer:
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
            actionButton(title: "다음", enabled: selectedMarket != nil) { go(to: .preview) }
        case .preview:
            actionButton(title: "시작하기", enabled: true) { go(to: .cheer) }
        case .settingUp, .cheer:
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

    // 헤더(제목·기준일)는 진입 즉시, 카드는 데이터 도착 후 순차 등장(비동기 로드 대응).
    @State private var headerAppeared = false
    @State private var dataArrived = false
    @State private var cardsAppeared = false

    private var feed: ExchangeFeed? { market.flatMap { vm.exchangeFeeds[$0] } }
    private var companies: [Company] { feed?.companies ?? [] }

    var body: some View {
        let highlights = previewHighlights(companies)

        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(market?.title ?? "")\n순위 동향이에요")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
                Text("지금 이 거래소에서 벌어지는 순위 변동이에요.")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.secondaryLabel)
            }
            .onboardingStaged(headerAppeared, delay: 0.15)

            // 최상단 — 데이터 기준일/시각(홈과 동일한 표기 재사용).
            if let market {
                MarketStatusView(
                    market: market,
                    currentTime: Date(),
                    basDt: feed?.basDt,
                    asOf: feed?.asOf
                )
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.fill))
                .onboardingStaged(headerAppeared, delay: 0.55)
            }

            if !dataArrived {
                // 로딩 — 하이라이트 카드 자리를 스켈레톤으로 채움.
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.fill)
                            .frame(height: 74)
                    }
                }
                .redacted(reason: .placeholder)
                .onboardingStaged(headerAppeared, delay: 0.85)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(highlights.enumerated()), id: \.element.id) { i, highlight in
                        OnboardingHighlightCard(highlight: highlight, theme: theme)
                            .onboardingStaged(cardsAppeared, delay: Double(i) * 0.14)
                    }
                }

                Text("이게 바로 MarCap이 보여주는 순위 변동이에요.\n홈에서 전체 순위를 확인해보세요.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .onboardingStaged(cardsAppeared, delay: Double(highlights.count) * 0.14)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .onAppear {
            headerAppeared = true
            if let market { Task { await vm.fetchExchange(market) } }
        }
        .onChange(of: companies.count) { _, count in
            // 데이터 도착 → 카드 렌더 후 다음 런루프에 등장 트리거(값 변화로 스테이지드 애니메이션 발동).
            guard count > 0, !dataArrived else { return }
            dataArrived = true
            DispatchQueue.main.async {
                cardsAppeared = true
            }
        }
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
}

// MARK: - 온보딩 하이라이트 카드 (홈보다 큰 글씨로 화면을 알차게)

/// 홈의 HighlightRow를 온보딩용으로 확대 재구성.
private struct OnboardingHighlightCard: View {
    let highlight: Highlight
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 14) {
            Text(highlight.emoji)
                .font(.system(size: 30))

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(highlight.accent)
                Text(highlight.detail)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 0)

            trailingBadge
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.fill))
    }

    /// 순위 델타(상승=빨강 ▲ / 하락=파랑 ▼) 또는 대형 등락률(%).
    @ViewBuilder
    private var trailingBadge: some View {
        if let d = highlight.rankDelta, d != 0 {
            let up = d > 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 14, weight: .bold))
                Text("\(abs(d))")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
            }
            .foregroundStyle(up ? Highlight.increaseColor : Highlight.decreaseColor)
            .fixedSize()
        } else if let p = highlight.percentMove {
            let up = p >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 14, weight: .bold))
                Text(String(format: "%.2f%%", abs(p)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundStyle(up ? Highlight.increaseColor : Highlight.decreaseColor)
            .fixedSize()
        }
    }
}

// MARK: - Step 6 — 응원 ("RIDE THE MARKET")

/// 마지막 화면. 짧은 응원 인사와 브랜드 태그라인 "RIDE THE MARKET"만 남겨 여운을 준 뒤,
/// 여유 있게 등장이 끝나면 onDone으로 홈에 진입한다.
private struct OnboardingCheerView: View {
    let nickname: String
    let theme: AppTheme
    let accent: Color

    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            Text("🚀")
                .font(.system(size: 64))
                .onboardingStaged(appeared, delay: 0.15)

            Text("\(nickname)님,\n이제 준비가 모두 끝났어요")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)
                .onboardingStaged(appeared, delay: 0.7)

            Text("RIDE THE MARKET")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingStaged(appeared, delay: 1.4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .onAppear {
            appeared = true
            Task {
                // 문장이 다 등장하고(약 2.1s) 잠시 머문 뒤 홈으로.
                try? await Task.sleep(for: .seconds(3.2))
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
