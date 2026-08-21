//
//  CompanyDetailView.swift
//  Titans
//
//  종목 시가총액 상세 차트(토스 오마주). 리스트에서 종목을 탭하면 시트로 표시된다.
//   · 헤더: 종목명·티커 + 현재(최신) 시가총액 + 선택 기간 등락
//   · 차트: Swift Charts area/line + 그라데이션 (토스처럼 축을 최소화)
//   · 크로스헤어: 그래프 위 드래그 → 세로 점선 기준바 + 말풍선(날짜·시총) + 라인 위 점 + 미세 햅틱
//   · 기간: 1주 / 1달 / 3달 / 1년 / 5년 / 전체
//
//  데이터는 CompanyChartStore가 소유한다(미래 백엔드 /api/company-chart, 현재는 시드 폴백).
//  값 자체는 시드 단계에선 플레이스홀더이며, 백엔드 연결 시 UI 변경 없이 실데이터로 대체된다.
//

import SwiftUI
import Charts

struct CompanyDetailView: View {
    let company: Company
    let currency: Currency
    let exchangeRate: Double
    // 순위 배지: ALL 섹션 순위(top20에 있으면 non-nil) + 상장 거래소 순위/명.
    let allRank: Int?
    let exchangeRank: Int?
    let exchangeTitle: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 다크/라이트를 시스템 colorScheme에서 직접 도출한다.
    /// (fullScreenCover는 상위의 appTheme 주입이 끊길 수 있어, 자체 계산 후 하위에 재주입한다.)
    private var theme: AppTheme { colorScheme == .dark ? .dark : .light }

    @StateObject private var store: CompanyChartStore
    @State private var range: ChartRange = .m3
    @State private var selectedIndex: Int? = nil

    private let haptics = UISelectionFeedbackGenerator()

    init(company: Company, currency: Currency, exchangeRate: Double,
         allRank: Int? = nil, exchangeRank: Int? = nil, exchangeTitle: String? = nil) {
        self.company = company
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.allRank = allRank
        self.exchangeRank = exchangeRank
        self.exchangeTitle = exchangeTitle
        _store = StateObject(wrappedValue: CompanyChartStore(company: company))
    }

    // 오래된→최신 포인트. 시드/실데이터 공통.
    private var points: [CompanyChartPoint] { store.chart?.points ?? [] }

    /// 상승/하락 색 — 앱 전역(CompanyRow) 규칙과 통일(초록=상승·빨강=하락).
    private var trendColor: Color {
        (store.chart?.changePercent ?? company.change) >= 0 ? .tickerUp : .tickerDown
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 10)
                    chartSection
                        .frame(height: 280)
                        .padding(.top, 22)
                    rangeSelector
                        .padding(.top, 20)
                    infoCard
                        .padding(.top, 28)
                    attribution
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            if tossStockCode != nil {
                brokerLinkBar
            }
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.appTheme, theme)   // 하위 뷰(로고 타일 등)도 동일 다크/라이트 적용
        .task(id: range) { await store.load(range) }
    }

    // MARK: - 상단 바

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - 헤더(시총 + 등락)

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1행: 로고 + (이름 · 거래소 순위) + 티커
            HStack(spacing: 12) {
                BrandLogoTile(ticker: company.ticker, name: company.name,
                              color: company.color, domain: company.domain)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(company.name)
                            .font(.system(size: 19, weight: .bold))
                            .lineLimit(1)
                            .layoutPriority(1)
                        ForEach(rankBadges) { badgeView($0) }
                    }
                    Text(company.ticker)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                }
                Spacer(minLength: 0)
            }

            // 2행: 큰 시가총액 (현재/최신). 스크러빙 값은 그래프 말풍선이 담당.
            Text(formatMarketCap(company.marketCapUSD, currency: currency, exchangeRate: exchangeRate))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.label)
                .contentTransition(.numericText())

            // 3행: 기간 전보다 등락
            periodDelta
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 이름 오른편 순위 배지. ALL top20에 있으면 "ALL N위"를 먼저, 이어서 상장 거래소 순위(동일 디자인).
    private struct RankBadge: Identifiable {
        var id: String { text }   // 텍스트 기반 안정 id — 매 렌더 새 id로 인한 깜빡임(재삽입) 방지
        let text: String
    }

    private var rankBadges: [RankBadge] {
        var out: [RankBadge] = []
        if let allRank {
            out.append(RankBadge(text: "ALL \(allRank)위"))
        }
        if let exchangeTitle {
            if let exRank = exchangeRank {
                out.append(RankBadge(text: "\(exchangeTitle) \(exRank)위"))
            } else if allRank == nil {
                // ALL에 없고 거래소 랭크도 못 구한 경우: 넘어온 순위를 거래소 순위로 간주(거래소 페이지 진입).
                out.append(RankBadge(text: "\(exchangeTitle) \(company.rank)위"))
            }
        }
        return out
    }

    /// 모든 순위 배지는 동일한 중립 스타일(회색 캡슐) — 강조·애니메이션 없음.
    private func badgeView(_ b: RankBadge) -> some View {
        Text(b.text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.secondaryLabel)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(theme.fill, in: Capsule())
    }

    /// 선택 기간 첫→최신 시총 변화(“{기간} 전보다 +X (n%)”). 색은 추세색.
    private var periodDelta: some View {
        let pct = store.chart?.changePercent ?? 0
        let first = points.first?.capUSD ?? company.marketCapUSD
        let last = points.last?.capUSD ?? company.marketCapUSD
        let deltaAbs = abs(last - first)
        let up = pct >= 0
        return HStack(spacing: 6) {
            Text(deltaPrefix)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .bold))
            Text(formatMarketCap(deltaAbs, currency: currency, exchangeRate: exchangeRate))
                .font(.system(size: 15, weight: .bold))
            Text(String(format: "(%.2f%%)", abs(pct)))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(up ? Color.tickerUp : Color.tickerDown)
    }

    /// 등락 앞에 붙는 기간 문구. 전체는 “상장 이후”, 나머지는 “{기간} 전보다”.
    private var deltaPrefix: String {
        range == .all ? "상장 이후" : "\(range.label) 전보다"
    }

    // MARK: - 차트

    private var chartSection: some View {
        Group {
            if points.count >= 2 {
                chart
            } else {
                // 데이터 부재(시드 실패 등) 시 옅은 스켈레톤.
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.fill)
                    .overlay(ProgressView())
            }
        }
    }

    private var chart: some View {
        let caps = points.map(\.capUSD)
        let minCap = caps.min() ?? 0
        let maxCap = caps.max() ?? 1
        let pad = max((maxCap - minCap) * 0.12, maxCap * 0.02)
        let lower = max(minCap - pad, 0)
        let upper = maxCap + pad

        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { idx, p in
                // 토스 오마주: 그라데이션 채움 없이 라인만.
                LineMark(x: .value("i", idx), y: .value("cap", p.capUSD))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let sel = selectedIndex, points.indices.contains(sel) {
                let p = points[sel]
                RuleMark(x: .value("i", sel))
                    .foregroundStyle(theme.stroke)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        scrubBubble(p)
                    }
                PointMark(x: .value("i", sel), y: .value("cap", p.capUSD))
                    .symbolSize(90)
                    .foregroundStyle(trendColor)
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in updateSelection(at: value.location.x, proxy: proxy, geo: geo) }
                            .onEnded { _ in selectedIndex = nil }
                    )
            }
        }
    }

    /// 크로스헤어 말풍선 — 날짜 + 해당일 시가총액.
    private func scrubBubble(_ p: CompanyChartPoint) -> some View {
        VStack(spacing: 2) {
            Text(displayDate(p.date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
            Text(formatMarketCap(p.capUSD, currency: currency, exchangeRate: exchangeRate))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.background)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.stroke.opacity(0.5), lineWidth: 0.5))
    }

    /// 드래그 x좌표 → 최근접 포인트 인덱스. 변경 시에만 햅틱.
    private func updateSelection(at locationX: CGFloat, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let originX = geo[plotFrame].origin.x
        let x = locationX - originX
        guard let raw: Double = proxy.value(atX: x) else { return }
        let idx = min(max(Int(raw.rounded()), 0), points.count - 1)
        if idx != selectedIndex {
            selectedIndex = idx
            haptics.selectionChanged()
        }
    }

    // MARK: - 기간 선택(알약)

    private var rangeSelector: some View {
        HStack(spacing: 6) {
            ForEach(ChartRange.allCases) { r in
                let isSel = r == range
                Button {
                    guard r != range else { return }
                    selectedIndex = nil
                    withAnimation(.easeInOut(duration: 0.25)) { range = r }
                } label: {
                    Text(r.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSel ? theme.background : theme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSel ? theme.label : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.fill))
    }

    // MARK: - 종목 정보 카드

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("거래소", exchangeTitle ?? company.market?.title ?? "—")
            divider
            infoRow("거래소 순위", "\(exchangeRank ?? company.rank)위")
            divider
            infoRowColored("당일 등락", String(format: "%@%.2f%%", company.change >= 0 ? "+" : "-", abs(company.change)),
                           color: company.change >= 0 ? .tickerUp : .tickerDown)
            divider
            infoRow("표시 통화", currency.rawValue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.fill.opacity(0.6)))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.label)
        }
        .padding(.vertical, 13)
    }

    private func infoRowColored(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(theme.stroke.opacity(0.35)).frame(height: 0.5)
    }

    // MARK: - 출처 표기(라이선스)

    private var attribution: some View {
        VStack(spacing: 4) {
            if let note = coverageNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            Text(attributionText)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 거래소에 맞는 데이터 출처. 상업 배포 라이선스 표기 요건 대응.
    private var attributionText: String {
        switch company.market {
        case .kospi, .kosdaq:
            return "데이터 · 공공데이터포털(금융위원회)"
        default:
            return "데이터 · Twelve Data"
        }
    }

    /// 데이터 특성 안내(정보 정확성).
    ///  · KR: 공공데이터포털은 2020년부터의 공식 시총만 제공.
    ///  · US/글로벌: 종가×현재 발행주식수로 계산한 추정치(과거 주식수 미반영) → '추정치' 명시.
    private var coverageNote: String? {
        switch company.market {
        case .kospi, .kosdaq:
            return "한국 종목은 2020년부터의 공식 시가총액이에요."
        default:
            return "해외 종목 시가총액은 종가 × 현재 발행주식수 기준 추정치예요."
        }
    }

    // MARK: - 증권앱 바로가기(토스증권)

    /// 토스증권 딥링크에 쓰는 6자리 종목 코드. 한국(KOSPI·KOSDAQ) 종목에서만 값을 낸다.
    /// 판별은 티커 접미사(".KS"/".KQ") 우선 — ALL·검색 등 일부 진입 경로에선 company.market이
    /// nil로 들어와(거래소 "—"·통화 USD로 표시) market만 보면 버튼이 누락되기 때문.
    /// 티커는 "005930.KS" / "035720.KQ" 형태라 접미사를 떼고 숫자 6자리만 취한다.
    private var tossStockCode: String? {
        let upper = company.ticker.uppercased()
        let isKR = upper.hasSuffix(".KS") || upper.hasSuffix(".KQ")
            || company.market == .kospi || company.market == .kosdaq
        guard isKR else { return nil }
        let base = company.ticker.split(separator: ".").first.map(String.init) ?? company.ticker
        let digits = base.filter(\.isNumber)
        return digits.count == 6 ? digits : nil
    }

    /// 하단 고정 바로가기 바. 앱은 "정보 안내"만 하며 주문·투자권유에는 관여하지 않는다(자본시장법 대응).
    private var brokerLinkBar: some View {
        VStack(spacing: 6) {
            Button { openInToss() } label: {
                HStack(spacing: 8) {
                    // 토스 로고(브랜드 심볼)를 흰 원형 칩에 담아 파란 버튼 위에서도 또렷하게.
                    Image("TossLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .padding(5)
                        .background(Circle().fill(.white))
                    Text("토스증권 바로가기")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)   // 토스 하단 CTA 표준 높이 오마주
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#3182F6")))
            }
            .buttonStyle(.plain)

            Text("정보 제공 목적이며 투자 권유가 아니에요. 토스증권 미설치 시 웹으로 이동해요.")
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(theme.background)
    }

    /// 토스증권의 해당 종목 상세 화면을 연다. KR 종목 코드는 "A" 접두사 + 6자리(예: 삼성전자 A005930).
    /// 딥링크는 토스 공유링크(OneLink)를 리다이렉트 추적해 확보한 실제 앱 스킴이다.
    ///   supertoss://securities?url=<service.tossinvest.com?nextLandingUrl=/stocks/A{code}>&…
    /// 앱이 설치돼 있으면(openURL 수락) 앱의 해당 종목 화면으로, 없으면(미수락) 웹 랜딩으로 폴백한다.
    private func openInToss() {
        guard let code = tossStockCode else { return }
        let web = URL(string: "https://contents.tossinvest.com/stocks/A\(code)")!
        let deepLink = URL(string: "supertoss://securities?url=https%3A%2F%2Fservice.tossinvest.com%3FnextLandingUrl%3D%252Fstocks%252FA\(code)&clearHistory=true&swipeRefresh=true")
        if let deepLink {
            openURL(deepLink) { accepted in
                if !accepted { openURL(web) }
            }
        } else {
            openURL(web)
        }
    }

    /// "YYYY-MM-DD" → "YYYY.MM.DD".
    private func displayDate(_ ymd: String) -> String {
        ymd.replacingOccurrences(of: "-", with: ".")
    }
}

#Preview {
    CompanyDetailView(
        company: Company(rank: 1, previousRank: 2, name: "NVIDIA", ticker: "NVDA",
                         marketCapUSD: 5.249, change: 1.84,
                         color: Color(hex: "#76B900"), domain: "nvidia.com"),
        currency: .usd,
        exchangeRate: 1.0
    )
    .environment(\.appTheme, .light)
}
