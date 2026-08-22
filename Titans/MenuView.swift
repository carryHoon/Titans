//
//  MenuView.swift
//  Titans
//

import SwiftUI
import UIKit

struct MenuView: View {
    let onDismiss: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("displayCurrency") private var displayCurrencyRaw: String = Currency.usd.rawValue

    @State private var showLogin = false
    @State private var showLoginRequiredAlert = false
    @State private var showMailUnavailableAlert = false

    /// 고객센터 문의 수신 주소.
    private let supportEmail = "marcap.official@gmail.com"

    /// 개인정보처리방침 URL (GitHub Pages 호스팅).
    private let privacyPolicyURL = URL(string: "https://carryhoon.github.io/Titans/privacy.html")!

    private var isDarkMode: Bool { colorScheme == .dark }
    private var theme: AppTheme { isDarkMode ? .dark : .light }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: 계정
                    sectionCard {
                        accountCard
                    }
                    .padding(.top, 16)

                    // MARK: 표시 (로그인 시에만) — 닉네임 변경은 계정(AccountView)으로 이동됨
                    if auth.isSignedIn {
                        sectionLabel("표시")
                        sectionCard {
                            NavigationLink {
                                DisplayCurrencyEditView()
                                    .environment(\.appTheme, theme)
                            } label: {
                                valueRow(icon: "wonsign.circle.fill",
                                         iconColor: Color(red: 0.20, green: 0.60, blue: 1.00),
                                         title: "통화 단위",
                                         value: Currency.from(displayCurrencyRaw).onboardingLabel)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // MARK: 알림
                    sectionLabel("알림")
                    sectionCard {
                        HStack(spacing: 14) {
                            iconBadge("bell.fill", Color(red: 1.0, green: 0.23, blue: 0.19))
                            Text("앱 알림")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(theme.label)
                            Spacer()
                            SlideToggle(isOn: $notificationsEnabled, theme: theme)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }

                    // MARK: 기능
                    sectionLabel("기능")
                    sectionCard {
                        NavigationLink {
                            DividendCalendarView(companies: [])
                                .environment(\.appTheme, theme)
                        } label: {
                            menuRow(icon: "calendar", iconColor: Color(red: 0.20, green: 0.78, blue: 0.35),
                                    title: "배당 캘린더", subtitle: "관심 기업의 배당 일정을 한눈에 확인하세요")
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: 고객센터
                    sectionLabel("고객센터")
                    sectionCard {
                        Button(action: sendFeedback) {
                            menuRow(icon: "envelope.fill",
                                    iconColor: Color(red: 0.35, green: 0.78, blue: 0.98),
                                    title: "의견 보내기", subtitle: "오류 신고 및 개선 사항을 남겨주세요")
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: 정보
                    sectionLabel("정보")
                    sectionCard {
                        Link(destination: privacyPolicyURL) {
                            menuRow(icon: "lock.shield.fill",
                                    iconColor: Color(red: 0.20, green: 0.60, blue: 0.45),
                                    title: "개인정보처리방침",
                                    subtitle: "수집 항목과 이용 목적을 확인하세요")
                        }
                        .buttonStyle(.plain)
                        rowDivider
                        NavigationLink {
                            SourcesDetailView()
                                .environment(\.appTheme, theme)
                        } label: {
                            menuRow(icon: "chart.bar.doc.horizontal",
                                    iconColor: Color(red: 0.18, green: 0.69, blue: 0.78),
                                    title: "데이터 출처",
                                    subtitle: "공공데이터포털 · 한국수출입은행 · DART 외")
                        }
                        .buttonStyle(.plain)
                        rowDivider
                        HStack(spacing: 14) {
                            iconBadge("info.circle.fill", Color(.systemGray))
                            Text("앱 버전")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(theme.label)
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 15))
                                .foregroundStyle(theme.secondaryLabel)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.label)
                            .frame(width: 52, height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("메뉴")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(theme.label)

                    Spacer()

                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 8)
                .background(Color(.systemGroupedBackground))
            }
        }
        .environment(\.appTheme, theme)
        .foregroundStyle(theme.label)
        .fullScreenCover(isPresented: $showLogin) {
            LoginView(onContinueAnonymously: { showLogin = false })
                .environment(auth)
        }
        .alert("로그인이 필요해요", isPresented: $showLoginRequiredAlert) {
            Button("로그인") { showLogin = true }
            Button("취소", role: .cancel) { }
        } message: {
            Text("의견 보내기는 로그인 후 이용할 수 있어요.")
        }
        .alert("메일을 보낼 수 없어요", isPresented: $showMailUnavailableAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("이 기기에 메일 계정이 설정되어 있지 않아요.\n메일 앱에서 계정을 추가한 뒤 다시 시도하거나, \(supportEmail) 으로 직접 보내주세요.")
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // 로그인 성공 시 로그인 시트를 닫고, 메뉴도 함께 닫아 홈(ContentView)으로 돌아간다.
            // (ContentView가 로그인 전환을 감지해 ALL 섹션으로 리셋한다.)
            if signedIn {
                showLogin = false
                onDismiss()
            }
        }
    }

    // MARK: - 고객센터 · 의견 보내기

    /// 의견 보내기 진입점.
    /// 로그인한 사용자만 문의를 보낼 수 있고(계정 식별을 위해), 둘러보기(비로그인) 사용자는
    /// 로그인 안내로 막는다. 로그인 사용자는 계정 이메일과 최소한의 진단 정보(앱 버전·기기)를
    /// 미리 채운 메일 작성 화면으로 이동한다. 이 정보는 본인이 발송 전 확인·수정할 수 있다.
    private func sendFeedback() {
        guard auth.isSignedIn else {
            showLoginRequiredAlert = true
            return
        }
        guard let url = feedbackMailURL() else { return }
        openURL(url) { accepted in
            // 기기에 메일 처리 앱/계정이 없어 mailto를 열 수 없는 경우 안내.
            if !accepted { showMailUnavailableAlert = true }
        }
    }

    /// 계정 이메일과 진단 정보를 본문에 미리 채운 mailto URL을 만든다.
    private func feedbackMailURL() -> URL? {
        let account = auth.userEmail ?? "(이메일 미확인)"
        let device = deviceModelIdentifier()
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"

        let subject = "MarCap 의견 보내기"
        let body = """
        ── 아래 정보는 문의 처리를 위해 함께 전송됨을 미리 알려드립니다.(발송 전 수정·삭제 가능) ──
        • 계정: \(account)
        • 앱 버전: \(appVersion)
        • 기기: \(device)
        • OS: \(os)
        """

        // query 값에 특수 의미를 갖는 문자까지 인코딩되도록 허용 집합을 좁힌다.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?/#")
        let s = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "mailto:\(supportEmail)?subject=\(s)&body=\(b)")
    }

    /// 하드웨어 식별자(예: iPhone16,2). 지원 문의 재현용 비개인정보.
    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    // MARK: - Account Card

    @ViewBuilder
    private var accountCard: some View {
        if auth.isSignedIn {
            NavigationLink {
                AccountView()
                    .environment(auth)
            } label: {
                // 닉네임을 설정했으면 이메일 대신 닉네임을 보여준다(없으면 이메일 폴백).
                accountRow(title: PrefsSync.shared.nickname ?? auth.userEmail ?? "내 계정",
                           subtitle: "내 정보 · 프로필 수정하기",
                           active: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showLogin = true
            } label: {
                accountRow(title: "로그인",
                           subtitle: "관심 기업·설정을 기기 간 동기화",
                           active: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func accountRow(title: String, subtitle: String, active: Bool) -> some View {
        HStack(spacing: 16) {
            Circle()
                .fill(active
                      ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.20, green: 0.50, blue: 1.00),
                                     Color(red: 0.55, green: 0.20, blue: 0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(theme.fill))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(active ? .white : theme.secondaryLabel)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.tertiaryLabel)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func menuRow(icon: String, iconColor: Color,
                          title: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.label)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryLabel)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// 우측에 현재 값을 보여주는 행(프로필: 닉네임·표시 통화). 값 뒤에 chevron.
    @ViewBuilder
    private func valueRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.label)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(theme.secondaryLabel)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func iconBadge(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
    }

    // 카드 내 행 사이 구분선 — leading은 아이콘 이후, trailing은 화살표 끝점에 맞춤
    private var rowDivider: some View {
        Divider()
            .padding(.leading, 62)
            .padding(.trailing, 16)
    }
}

