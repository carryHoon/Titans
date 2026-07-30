//
//  SettingsView.swift
//  Titans
//
//  ⚙ 버튼에서 진입하는 설정 화면.
//  계정 · 알림 · 화면 설정 · 고객센터 · 정보를 담는다.
//

import SwiftUI

// MARK: - Slide Toggle (ON/OFF pill — matchedGeometryEffect로 부드럽게 슬라이드)

struct SlideToggle: View {
    @Binding var isOn: Bool
    let theme: AppTheme
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            pill("ON",  value: true)
            pill("OFF", value: false)
        }
        .padding(3)
        .background(Capsule().fill(theme.fill))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { val in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isOn = val.translation.width > 0
                    }
                }
        )
    }

    private func pill(_ label: String, value: Bool) -> some View {
        let selected = isOn == value
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isOn = value }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? theme.background : theme.secondaryLabel)
                .frame(minWidth: 40)
                .padding(.vertical, 6)
                .background {
                    if selected {
                        Capsule()
                            .fill(theme.label)
                            .matchedGeometryEffect(id: "pill", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data Source Model

private struct DataSource: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let urlString: String?

    var url: URL? { urlString.flatMap(URL.init) }
}

// MARK: - Sources Detail View

struct SourcesDetailView: View {
    @Environment(\.appTheme) private var theme

    private let sources: [DataSource] = [
        DataSource(icon: "building.columns.fill", iconColor: .blue,
                   title: "공공데이터포털", detail: "KRX 주식·지수 시세 (EOD)",
                   urlString: "https://www.data.go.kr"),
        DataSource(icon: "globe.asia.australia.fill", iconColor: .green,
                   title: "한국수출입은행", detail: "USD/KRW 환율 데이터",
                   urlString: "https://www.koreaexim.go.kr"),
        DataSource(icon: "chart.line.uptrend.xyaxis", iconColor: .purple,
                   title: "Twelve Data", detail: "해외 주식·지수 시세 (Data by Twelve Data)",
                   urlString: "https://twelvedata.com"),
        DataSource(icon: "flag.fill", iconColor: .orange,
                   title: "Flaticon", detail: "국기 아이콘 (www.flaticon.com)",
                   urlString: "https://www.flaticon.com"),
        DataSource(icon: "doc.text.magnifyingglass", iconColor: .teal,
                   title: "DART", detail: "기업 홈페이지 도메인 해석",
                   urlString: "https://dart.fss.or.kr"),
        DataSource(icon: "photo.fill", iconColor: .indigo,
                   title: "Logo.dev", detail: "기업 로고 이미지",
                   urlString: "https://logo.dev"),
        DataSource(icon: "sparkle", iconColor: .pink,
                   title: "Brandfetch", detail: "기업 로고 (Logos provided by Brandfetch)",
                   urlString: "https://brandfetch.com"),
        DataSource(icon: "safari.fill", iconColor: Color(.systemGray),
                   title: "Google Favicon", detail: "파비콘 이미지 서비스",
                   urlString: nil),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Group {
                        if let url = source.url {
                            Link(destination: url) { sourceRow(source: source) }
                                .buttonStyle(.plain)
                        } else {
                            sourceRow(source: source)
                        }
                    }
                    if index < sources.count - 1 {
                        Rectangle()
                            .fill(theme.stroke.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 10) {
                Text("각 서비스의 이용약관 및 라이선스 정책을 준수하여 활용합니다.")

                Text("본 앱에 표시되는 기업 로고 및 명칭은 각 상표권자의 자산이며, 종목 식별 목적으로만 사용됩니다. 본 앱은 해당 기업과 제휴·후원 관계가 없습니다.")
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.tertiaryLabel)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("데이터 출처")
        .navigationBarTitleDisplayMode(.large)
    }

    private func sourceRow(source: DataSource) -> some View {
        HStack(spacing: 14) {
            Image(systemName: source.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(source.iconColor)
                .frame(width: 28, height: 28)
                .background(source.iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.label)
                Text(source.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            if source.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiaryLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - SettingsView

struct SettingsView: View {
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
                VStack(spacing: 20) {
                    accountCard.padding(.top, 8)

                    section(title: "알림") {
                        settingRow(icon: "bell.fill", iconColor: .red, title: "앱 알림") {
                            SlideToggle(isOn: $notificationsEnabled, theme: theme)
                        }
                    }

                    section(title: "고객센터") {
                        Link(destination: URL(string: "mailto:feedback@titans.app?subject=Titans%20피드백")!) {
                            linkRow(icon: "envelope.fill", iconColor: .blue,
                                    title: "피드백 보내기",
                                    subtitle: "불편한 점이나 요청 사항을 알려주세요")
                        }
                        .buttonStyle(.plain)
                    }

                    section(title: "정보") {
                        NavigationLink {
                            SourcesDetailView()
                                .environment(\.appTheme, theme)
                                .preferredColorScheme(isDarkMode ? .dark : .light)
                        } label: {
                            linkRow(icon: "chart.bar.doc.horizontal", iconColor: .indigo,
                                    title: "데이터 출처",
                                    subtitle: "공공데이터포털 · 수출입은행 · DART 외")
                        }
                        .buttonStyle(.plain)
                        divider
                        infoRow(icon: "info.circle.fill", iconColor: Color(.systemGray),
                                title: "앱 버전", value: appVersion)
                    }

                    Text("Titans · 전 세계 시가총액 거인들")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryLabel)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.label)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("설정")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.label)

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .frame(height: 44)
                .padding(.horizontal, 8)
                .background(theme.background)
            }
        }
        .environment(\.appTheme, theme)
        .foregroundStyle(theme.label)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    // MARK: - Account Card

    private var accountCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.20, green: 0.50, blue: 1.00),
                                 Color(red: 0.55, green: 0.20, blue: 0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 60, height: 60)
                Image(systemName: "person.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("내 계정")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.label)
                Text("계정 관리 및 개인정보")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(18)
        .background(theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .opacity(0.55)
    }

    // MARK: - Helpers

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

    private func settingRow<T: View>(icon: String, iconColor: Color, title: String,
                                     @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, iconColor)
            Text(title).font(.system(size: 15, weight: .medium))
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
                    .foregroundStyle(theme.label)
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
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
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

}
