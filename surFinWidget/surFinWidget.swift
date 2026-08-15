//
//  surFinWidget.swift
//  surFinWidget
//
//  증권거래소별 상위 시가총액 위젯. 앱이 App Group에 써 둔 스냅샷/로고 PNG만 읽어
//  오프라인으로도 앱과 동일하게 표시한다.
//  · Small(정사각) → 로고 + 시총 + 등락% (Top3, 세로 균등 배치)
//  · Medium(가로 배너) → 순위·로고·이름·시총·등락% (Top3)
//  · Large(달력형)     → 위와 동일 (Top8, 세로 중앙 배치)
//  헤더: 거래소명 + 기준시간("… 기준") + 토스식 원형 새로고침 버튼.
//  화이트/다크는 colorScheme에 따라 전환.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        .preview(exchange: .nasdaq, currency: .usd)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let e = entry(for: configuration)
        // 데이터는 앱/새로고침 버튼이 App Group에 push하지만, 안전망으로 30분마다 재로드한다.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1800)
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for config: ConfigurationAppIntent) -> SimpleEntry {
        let snapshot = WidgetStore.load()
        let data = snapshot?.exchanges[config.exchange.apiKey]
        return SimpleEntry(
            date: Date(),
            exchangeKey: config.exchange.apiKey,
            exchangeTitle: config.exchange.title,
            currency: config.currency.currency,
            exchangeRate: data?.exchangeRate ?? 1450,
            companies: data?.companies ?? [],
            basDt: data?.basDt,
            updatedAt: snapshot?.updatedAt ?? Date()
        )
    }
}

// MARK: - Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let exchangeKey: String
    let exchangeTitle: String
    let currency: Currency
    let exchangeRate: Double
    let companies: [WidgetCompany]
    let basDt: String?
    let updatedAt: Date

    /// 프리뷰/플레이스홀더용 더미 데이터.
    static func preview(exchange: WidgetExchangeChoice, currency: Currency) -> SimpleEntry {
        let sample: [WidgetCompany] = [
            WidgetCompany(rank: 1, previousRank: 1, name: "Nvidia",   ticker: "NVDA", marketCapUSD: 3.42, changePercent: 1.24, colorHex: "#76B900", domain: nil),
            WidgetCompany(rank: 2, previousRank: 3, name: "Apple",    ticker: "AAPL", marketCapUSD: 3.31, changePercent: -0.42, colorHex: "#555555", domain: nil),
            WidgetCompany(rank: 3, previousRank: 2, name: "Microsoft",ticker: "MSFT", marketCapUSD: 3.18, changePercent: 0.87, colorHex: "#00A4EF", domain: nil),
            WidgetCompany(rank: 4, previousRank: 4, name: "Amazon",   ticker: "AMZN", marketCapUSD: 2.10, changePercent: 0.15, colorHex: "#FF9900", domain: nil),
            WidgetCompany(rank: 5, previousRank: 6, name: "Alphabet", ticker: "GOOGL",marketCapUSD: 2.05, changePercent: -0.31, colorHex: "#4285F4", domain: nil),
            WidgetCompany(rank: 6, previousRank: 5, name: "Meta",     ticker: "META", marketCapUSD: 1.48, changePercent: 0.62, colorHex: "#0668E1", domain: nil),
            WidgetCompany(rank: 7, previousRank: 8, name: "Broadcom", ticker: "AVGO", marketCapUSD: 1.12, changePercent: 2.03, colorHex: "#CC0000", domain: nil),
            WidgetCompany(rank: 8, previousRank: 7, name: "Tesla",    ticker: "TSLA", marketCapUSD: 0.98, changePercent: -1.17, colorHex: "#E82127", domain: nil),
        ]
        return SimpleEntry(date: Date(), exchangeKey: exchange.apiKey, exchangeTitle: exchange.title,
                           currency: currency, exchangeRate: 1450, companies: sample,
                           basDt: nil, updatedAt: Date())
    }
}

// MARK: - 크기별 밀도 지표

private struct RowMetrics {
    var logo: CGFloat
    var name: CGFloat
    var ticker: CGFloat
    var value: CGFloat
    var change: CGFloat
    var rank: CGFloat
    var rowSpacing: CGFloat

    static let medium = RowMetrics(logo: 26, name: 14, ticker: 11, value: 13, change: 11,
                                   rank: 11, rowSpacing: 8)
    // Top6 — 남은 여백을 채우도록 텍스트를 조금 더 키움
    static let large = RowMetrics(logo: 30, name: 16.5, ticker: 12.5, value: 16, change: 12.5,
                                  rank: 14, rowSpacing: 12)
}

// MARK: - 순위 변동 화살표

/// 순위 열 아래 붙는 전일 종가 대비 순위 변동. 앱 CompanyRow와 동일 규약(상승=빨강 ▲ / 하락=파랑 ▼).
/// previousRank 가 없거나(첫 로드·KR 스냅샷 미확장) 변동이 없으면 아무것도 그리지 않는다.
private struct WidgetRankDelta: View {
    let rank: Int
    let previousRank: Int?
    var arrowSize:  CGFloat = 6
    var numberSize: CGFloat = 7

    var body: some View {
        if let prev = previousRank, prev != rank {
            let delta = prev - rank  // 양수 = 순위 상승(숫자 감소)
            HStack(spacing: 1) {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: arrowSize, weight: .bold))
                Text("\(abs(delta))")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
            }
            .foregroundStyle(delta > 0
                ? Color(red: 0.95, green: 0.20, blue: 0.20)
                : Color(red: 0.10, green: 0.43, blue: 0.92))
        }
    }
}

// MARK: - Entry View

struct surFinWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var theme: AppTheme { AppTheme.forScheme(scheme) }

    private var isSmall: Bool { family == .systemSmall }
    private var rowCount: Int { family == .systemLarge ? 6 : 3 }
    private var metrics: RowMetrics { family == .systemLarge ? .large : .medium }
    private var visibleCompanies: [WidgetCompany] { Array(entry.companies.prefix(rowCount)) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .containerBackground(theme.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if visibleCompanies.isEmpty {
            VStack(spacing: isSmall ? 6 : metrics.rowSpacing) {
                header
                emptyState
            }
        } else if family == .systemLarge {
            // 헤더+목록을 한 블록으로 세로 중앙 배치 → 상단에 붙어 있던 헤더가
            // NVIDIA와의 여백을 활용해 아래로 내려오며 작게/중간과 통일감을 준다.
            VStack(spacing: metrics.rowSpacing) {
                // 상단 Spacer 비중을 늘려(top:middle:bottom = 2:1:2) 헤더를 조금 내린다.
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                header
                Spacer(minLength: 0)
                // 헤더는 그대로 두고 목록만 아주 조금 위로(오프셋).
                rowsStack
                    .offset(y: -6)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
        } else if family == .systemMedium {
            VStack(spacing: metrics.rowSpacing) {
                header
                rowsStack
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            // Small: 헤더는 상단, 목록은 남은 공간에서 살짝 아래로(상단 여백을 조금 더 줌)
            VStack(spacing: 6) {
                header
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                rowsStack
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 헤더 (거래소명 + 기준시간 + 새로고침)

    @ViewBuilder
    private var header: some View {
        if isSmall {
            HStack(spacing: 6) {
                Text(entry.exchangeTitle)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                Spacer(minLength: 2)
                referenceLabel
                refreshButton
            }
        } else {
            // 거래소명은 중앙정렬, 기준시간·버튼은 우측에 오버레이
            ZStack {
                Text(entry.exchangeTitle)
                    .font(.system(size: family == .systemLarge ? 18.5 : 15, weight: .bold))
                    .foregroundStyle(theme.label)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    referenceLabel
                    refreshButton
                }
                // 거래소명이 커진 large에서 기준시간·새로고침을 살짝 내려 세로 정렬을 맞춘다.
                .padding(.top, family == .systemLarge ? 3 : 0)
            }
        }
    }

    /// US(나스닥/나이스): 시각만 "17:36". KR(코스피/코스닥): "08.04 종가".
    /// '종가'는 시각·새로고침 버튼과 색상·굵기를 통일한다(secondary + semibold).
    private var referenceLabel: some View {
        let (time, suffix) = referenceParts
        return HStack(spacing: 3) {
            Text(time)
                .font(.system(size: isSmall ? 9.5 : 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryLabel)
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: isSmall ? 9.5 : 11.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .lineLimit(1)
    }

    /// KR은 basDt로 "MM.DD" + "종가", US는 시각만(접미사 없음).
    private var referenceParts: (time: String, suffix: String) {
        if let bas = entry.basDt, bas.count == 8 {
            return ("\(bas.dropFirst(4).prefix(2)).\(bas.dropFirst(6).prefix(2))", "종가")
        }
        return (Self.hhmm.string(from: entry.updatedAt), "")
    }
    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// 새로고침 버튼 (아이콘만 — 기존 디자인).
    private var refreshButton: some View {
        Button(intent: RefreshWidgetIntent(exchangeKey: entry.exchangeKey)) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: isSmall ? 10.5 : 12.5, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
        }
        .buttonStyle(.plain)
    }

    // MARK: 행 목록

    private var rowsStack: some View {
        VStack(spacing: isSmall ? 10 : metrics.rowSpacing) {
            ForEach(visibleCompanies) { company in
                if isSmall {
                    WidgetSmallRow(company: company, currency: entry.currency,
                                   exchangeRate: entry.exchangeRate, theme: theme)
                } else {
                    WidgetCompanyRow(company: company, currency: entry.currency,
                                     exchangeRate: entry.exchangeRate, metrics: metrics, theme: theme)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22))
                .foregroundStyle(theme.tertiaryLabel)
            Text("앱을 한 번 실행해 주세요")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small Row (로고 + 시가총액 수치만)

private struct WidgetSmallRow: View {
    let company: WidgetCompany
    let currency: Currency
    let exchangeRate: Double
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 8) {
            // 다른 크기 위젯처럼 왼쪽에 순위 숫자 열 — 로고가 오른쪽으로 밀리며 열이 정렬됨
            VStack(spacing: 1) {
                Text("\(company.rank)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.tertiaryLabel)
                    .lineLimit(1)
                WidgetRankDelta(rank: company.rank, previousRank: company.previousRank)
            }
            .frame(width: 16, alignment: .center)
            WidgetLogo(company: company, size: 26, theme: theme)
            Spacer(minLength: 4)
            Text(formatMarketCap(company.marketCapUSD, currency: currency, exchangeRate: exchangeRate))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Company Row (Medium/Large — 앱 CompanyRow 축약 재현)

private struct WidgetCompanyRow: View {
    let company: WidgetCompany
    let currency: Currency
    let exchangeRate: Double
    let metrics: RowMetrics
    let theme: AppTheme

    private var isUp: Bool { company.changePercent >= 0 }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 1) {
                Text("\(company.rank)")
                    .font(.system(size: metrics.rank, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.tertiaryLabel)
                    .lineLimit(1)
                WidgetRankDelta(rank: company.rank, previousRank: company.previousRank,
                                arrowSize: 6.5, numberSize: 7.5)
            }
            .frame(width: 18, alignment: .center)

            WidgetLogo(company: company, size: metrics.logo, theme: theme)

            VStack(alignment: .leading, spacing: 1) {
                Text(company.name)
                    .font(.system(size: metrics.name, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                Text(company.ticker)
                    .font(.system(size: metrics.ticker))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(formatMarketCap(company.marketCapUSD, currency: currency, exchangeRate: exchangeRate))
                    .font(.system(size: metrics.value, weight: .bold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                HStack(spacing: 1) {
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: metrics.change - 1, weight: .bold))
                    Text(String(format: "%.2f%%", abs(company.changePercent)))
                        .font(.system(size: metrics.change, weight: .semibold))
                }
                .foregroundStyle(isUp ? .green : .red)
                .lineLimit(1)
            }
        }
    }
}

// MARK: - Logo (App Group PNG → 이니셜 폴백)

private struct WidgetLogo: View {
    let company: WidgetCompany
    let size: CGFloat
    let theme: AppTheme

    private var pngImage: UIImage? {
        guard let url = WidgetStore.logoURL(ticker: company.ticker),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 앱 LogoImage.fallbackInitials와 동일 규칙.
    private var initials: String {
        if company.ticker.first?.isLetter == true {
            return String(company.ticker.prefix(2)).uppercased()
        }
        return String(company.name.prefix(2)).uppercased()
    }

    var body: some View {
        if let ui = pngImage {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let color = Color(hex: company.colorHex)
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.12), in: Circle())
        }
    }
}

// MARK: - 갤러리 표시 문구 (크기별로 직접 수정하세요)

/// 위젯 추가 갤러리에 뜨는 이름/상세설명. 작게·중간·크게 각각 따로 편집할 수 있다.
enum WidgetCopy {
    // 작게(Small)
    static let smallName        = "시가총액 순위 · 작게"
    static let smallDescription = "관심 있는 거래소의 시가총액 상위 기업을 로고와 함께 한눈에 보세요."

    // 중간(Medium)
    static let mediumName        = "시가총액 순위 · 중간"
    static let mediumDescription = "거래소 상위 3개 기업의 시가총액과 등락률을 가로 배너로 보세요."

    // 크게(Large)
    static let largeName        = "시가총액 순위 · 크게"
    static let largeDescription = "거래소 상위 6개 기업을 넉넉한 화면으로 보세요."
}

// MARK: - Widgets (크기별 분리 — 갤러리에서 각각 다른 설명을 노출)

struct surFinWidgetSmall: Widget {
    let kind = "surFinWidgetSmall"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            surFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.smallName)
        .description(WidgetCopy.smallDescription)
        .supportedFamilies([.systemSmall])
    }
}

struct surFinWidgetMedium: Widget {
    let kind = "surFinWidgetMedium"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            surFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.mediumName)
        .description(WidgetCopy.mediumDescription)
        .supportedFamilies([.systemMedium])
    }
}

struct surFinWidgetLarge: Widget {
    let kind = "surFinWidgetLarge"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            surFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.largeName)
        .description(WidgetCopy.largeDescription)
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    surFinWidgetSmall()
} timeline: {
    SimpleEntry.preview(exchange: .nasdaq, currency: .usd)
}

#Preview(as: .systemMedium) {
    surFinWidgetMedium()
} timeline: {
    SimpleEntry.preview(exchange: .kospi, currency: .krw)
}

#Preview(as: .systemLarge) {
    surFinWidgetLarge()
} timeline: {
    SimpleEntry.preview(exchange: .nyse, currency: .usd)
}
