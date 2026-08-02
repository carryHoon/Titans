//
//  MenuView.swift
//  Titans
//

import SwiftUI

struct MenuView: View {
    @Binding var isDarkMode: Bool
    let onDismiss: () -> Void

    @Environment(AuthManager.self) private var auth
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false

    @State private var showLogin = false

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
                            WatchlistPlaceholderView()
                                .environment(\.appTheme, theme)
                                .preferredColorScheme(isDarkMode ? .dark : .light)
                        } label: {
                            menuRow(icon: "heart.fill", iconColor: .pink,
                                    title: "관심 기업", subtitle: "배당 일정이 궁금한 기업을 추가")
                        }
                        .buttonStyle(.plain)
                        rowDivider
                        NavigationLink {
                            DividendCalendarView(companies: [], isDarkMode: isDarkMode)
                                .environment(\.appTheme, theme)
                        } label: {
                            menuRow(icon: "calendar", iconColor: Color(red: 0.20, green: 0.78, blue: 0.35),
                                    title: "배당 캘린더", subtitle: "관심 기업의 배당 일정을 한눈에 확인")
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: 고객센터
                    sectionLabel("고객센터")
                    sectionCard {
                        Link(destination: URL(string: "mailto:seunghoon003@gmail.com?subject=Titans%20피드백")!) {
                            menuRow(icon: "envelope.fill",
                                    iconColor: Color(red: 0.35, green: 0.78, blue: 0.98),
                                    title: "의견 보내기", subtitle: "오류 신고 및 개선 요청")
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: 정보
                    sectionLabel("정보")
                    sectionCard {
                        NavigationLink {
                            DeveloperNoteView()
                                .environment(\.appTheme, theme)
                                .preferredColorScheme(isDarkMode ? .dark : .light)
                        } label: {
                            menuRow(icon: "quote.bubble.fill",
                                    iconColor: Color(red: 0.345, green: 0.337, blue: 0.839),
                                    title: "개발자 노트", subtitle: "Titans를 만든 이야기")
                        }
                        .buttonStyle(.plain)
                        rowDivider
                        NavigationLink {
                            SourcesDetailView()
                                .environment(\.appTheme, theme)
                                .preferredColorScheme(isDarkMode ? .dark : .light)
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
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .fullScreenCover(isPresented: $showLogin) {
            LoginView(onContinueAnonymously: { showLogin = false })
                .environment(auth)
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

    // MARK: - Account Card

    @ViewBuilder
    private var accountCard: some View {
        if auth.isSignedIn {
            NavigationLink {
                AccountView()
                    .environment(auth)
                    .preferredColorScheme(isDarkMode ? .dark : .light)
            } label: {
                accountRow(title: auth.userEmail ?? "내 계정",
                           subtitle: "계정 관리 · 로그아웃",
                           active: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showLogin = true
            } label: {
                accountRow(title: "로그인",
                           subtitle: "관심 종목·설정을 기기 간 동기화",
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

// MARK: - 관심기업 준비 중 플레이스홀더

private struct WatchlistPlaceholderView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)
            Text("관심 기업")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.label)
            Text("곧 업데이트될 예정이에요")
                .font(.system(size: 15))
                .foregroundStyle(theme.secondaryLabel)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("관심 기업")
        .navigationBarTitleDisplayMode(.inline)
    }
}
