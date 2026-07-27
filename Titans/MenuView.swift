//
//  MenuView.swift
//  Titans
//
//  메뉴(≡) 버튼으로 진입하는 전체 메뉴 화면. 토스의 '전체' 시트를 오마주해
//  화면 설정 · 기능 · 정보를 카드형 리스트로 묶었다.
//
//  ContentView의 상태(다크모드·통화)를 @Binding으로 공유해, 여기서 바꾸면
//  메인 화면에도 즉시 반영된다. 배당 캘린더는 이 화면에서 push로 진입한다.
//

import SwiftUI

struct MenuView: View {
    @Binding var isDarkMode: Bool
    @Binding var selectedCurrency: Currency
    let onDismiss: () -> Void

    private var theme: AppTheme { isDarkMode ? .dark : .light }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    // 화면 설정
                    section(title: "화면 설정") {
                        settingRow(
                            icon: isDarkMode ? "moon.fill" : "sun.max.fill",
                            iconColor: isDarkMode ? .yellow : .orange,
                            title: "화면 모드"
                        ) {
                            segmented(
                                options: [("라이트", false), ("다크", true)],
                                selection: $isDarkMode
                            )
                        }
                        divider
                        settingRow(icon: "wonsign.circle.fill", iconColor: .green, title: "표시 통화") {
                            segmented(
                                options: [("$", Currency.usd), ("원", Currency.krw)],
                                selection: $selectedCurrency
                            )
                        }
                    }

                    // 기능
                    section(title: "기능") {
                        NavigationLink {
                            DividendCalendarView(companies: [], isDarkMode: isDarkMode)
                        } label: {
                            linkRow(icon: "calendar", iconColor: .pink,
                                    title: "배당락일 캘린더",
                                    subtitle: "관심 종목의 배당락일을 한눈에")
                        }
                        .buttonStyle(.plain)
                        divider
                        linkRow(icon: "star.fill", iconColor: .yellow,
                                title: "관심 종목",
                                subtitle: "출시 준비 중", disabled: true)
                        divider
                        linkRow(icon: "bell.fill", iconColor: .red,
                                title: "가격 알림",
                                subtitle: "출시 준비 중", disabled: true)
                    }

                    // 정보
                    section(title: "정보") {
                        infoRow(icon: "chart.bar.doc.horizontal", iconColor: .blue,
                                title: "데이터 출처",
                                value: "Finnhub · Naver")
                        divider
                        // logo.dev 무료 플랜 상업적 이용 요건: 눈에 보이는 링크백(어트리뷰션) 필수.
                        Link(destination: URL(string: "https://logo.dev")!) {
                            HStack(spacing: 14) {
                                iconBadge("checkmark.seal.fill", .indigo)
                                Text("로고 제공")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("Logo.dev")
                                        .font(.system(size: 14))
                                        .foregroundStyle(theme.secondaryLabel)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(theme.tertiaryLabel)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        divider
                        infoRow(icon: "info.circle.fill", iconColor: .gray,
                                title: "앱 버전", value: appVersion)
                    }

                    Text("Titans · 전 세계 시가총액 거인들")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryLabel)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("전체")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.label)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.label)
                    }
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
        }
        .environment(\.appTheme, theme)
        .foregroundStyle(theme.label)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            TitansMark(isDark: isDarkMode)
                .frame(width: 44, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Titans")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("실시간 시가총액 랭킹")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Section container (카드)

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.stroke.opacity(0.4))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    // MARK: - Rows

    private func settingRow<Trailing: View>(
        icon: String, iconColor: Color, title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func linkRow(icon: String, iconColor: Color, title: String,
                         subtitle: String, disabled: Bool = false) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(disabled ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    private func infoRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func iconBadge(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Segmented control (통화·모드 공용)

    private func segmented<T: Equatable>(options: [(String, T)], selection: Binding<T>) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSelected = selection.wrappedValue == opt.1
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection.wrappedValue = opt.1
                    }
                } label: {
                    Text(opt.0)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? theme.background : theme.secondaryLabel)
                        .frame(minWidth: 40)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected { Capsule().fill(theme.label) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.fill))
    }
}
