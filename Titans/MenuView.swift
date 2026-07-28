//
//  MenuView.swift
//  Titans
//

import SwiftUI

struct MenuView: View {
    @Binding var isDarkMode: Bool
    let onDismiss: () -> Void

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false

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
                    sectionLabel("계정")
                    accountCard
                    sectionDivider

                    // MARK: 알림
                    sectionLabel("알림")
                    HStack(spacing: 14) {
                        iconBadge("bell.fill", .red)
                        Text("앱 알림")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(theme.label)
                        Spacer()
                        SlideToggle(isOn: $notificationsEnabled, theme: theme)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    sectionDivider

                    // MARK: 기능
                    sectionLabel("기능")
                    menuRow(icon: "star.fill", iconColor: .yellow,
                            title: "관심 기업", subtitle: "준비 중", disabled: true)
                    rowDivider
                    NavigationLink {
                        DividendCalendarView(companies: [], isDarkMode: isDarkMode)
                            .environment(\.appTheme, theme)
                    } label: {
                        menuRow(icon: "calendar", iconColor: .pink,
                                title: "배당 캘린더", subtitle: "관심 기업의 배당 일정")
                    }
                    .buttonStyle(.plain)
                    sectionDivider

                    // MARK: 고객센터
                    sectionLabel("고객센터")
                    Link(destination: URL(string: "mailto:seunghoon003@gmail.com?subject=Titans%20피드백")!) {
                        menuRow(icon: "envelope.fill", iconColor: .blue, title: "피드백 보내기")
                    }
                    .buttonStyle(.plain)
                    sectionDivider

                    // MARK: 정보
                    sectionLabel("정보")
                    NavigationLink {
                        SourcesDetailView()
                            .environment(\.appTheme, theme)
                            .preferredColorScheme(isDarkMode ? .dark : .light)
                    } label: {
                        menuRow(icon: "chart.bar.doc.horizontal", iconColor: .teal,
                                title: "데이터 출처",
                                subtitle: "공공데이터포털 · 수출입은행 · DART 외")
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .padding(.bottom, 48)
            }
            .background(theme.background.ignoresSafeArea())
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.label)

                    Spacer()

                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 8)
                .background(theme.background)
            }
        }
        .environment(\.appTheme, theme)
        .foregroundStyle(theme.label)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    // MARK: - Account Card (Apple Settings 스타일)

    private var accountCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(theme.fill)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("내 계정")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                Text("출시 예정")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.tertiaryLabel)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .opacity(0.55)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private func menuRow(icon: String, iconColor: Color,
                          title: String, subtitle: String? = nil,
                          disabled: Bool = false) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(disabled ? theme.secondaryLabel : theme.label)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryLabel)
                }
            }
            Spacer()
            if !disabled {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.tertiaryLabel)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func iconBadge(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // 아이템 사이 얇은 구분선 (아이콘 너비만큼 indent)
    private var rowDivider: some View {
        Rectangle()
            .fill(theme.stroke.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 66)
    }

    // 섹션 사이 전체 너비 구분선
    private var sectionDivider: some View {
        Rectangle()
            .fill(theme.stroke.opacity(0.5))
            .frame(height: 0.5)
    }
}
