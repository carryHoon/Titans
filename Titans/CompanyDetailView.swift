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
    @State private var mode: ChartMode = .marketCap
    @State private var metrics: CompanyMetricsResponse? = nil
    @State private var metricsLoaded = false
    @State private var showDividendCalendar = false

    private let haptics = UISelectionFeedbackGenerator()

    /// 상세 차트 표시 모드 — 헤더 우측 pill로 전환한다.
    ///  · marketCap: 기존 시가총액 절대값 곡선(토스 오마주).
    ///  · vsIndex: 거래소 지수(=base 100) 대비 종목 시총 성장률 비교(2라인).
    enum ChartMode: String, CaseIterable, Identifiable {
        case marketCap, vsIndex
        var id: String { rawValue }
        /// pill에 표시할 짧은 라벨.
        var pillLabel: String {
            switch self {
            case .marketCap: return "시가총액"
            case .vsIndex:   return "지수 대비"
            }
        }
        /// 메뉴 항목 라벨(조금 더 설명적).
        var menuLabel: String {
            switch self {
            case .marketCap: return "시가총액 그래프"
            case .vsIndex:   return "지수 대비 성장률"
            }
        }
    }

    init(company: Company, currency: Currency, exchangeRate: Double,
         allRank: Int? = nil, exchangeRank: Int? = nil, exchangeTitle: String? = nil) {
        self.company = company
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.allRank = allRank
        self.exchangeRank = exchangeRank
        self.exchangeTitle = exchangeTitle
        _store = StateObject(wrappedValue: CompanyChartStore(company: company))
        // 캐시된 지표가 있으면 첫 프레임부터 즉시 표시(토스식 즉각 반영). 없으면 스켈레톤 후 로드.
        _metrics = State(initialValue: CompanyMetricsCache.cached(ticker: company.ticker))
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
                    if mode == .vsIndex {
                        comparisonLegend
                            .padding(.top, 20)
                    }
                    chartSection
                        .frame(height: 320)
                        .padding(.top, mode == .vsIndex ? 12 : 22)
                    rangeSelector
                        .padding(.top, 20)
                    infoCard
                        .padding(.top, 28)
                    investmentSection
                        .padding(.top, 28)
                    attribution
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            bottomBar
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.appTheme, theme)   // 하위 뷰(로고 타일 등)도 동일 다크/라이트 적용
        .task(id: range) { await store.load(range) }
        .task { await loadMetrics() }
        .onChange(of: mode) { _, _ in selectedIndex = nil }
        .sheet(isPresented: $showDividendCalendar) {
            NavigationStack { DividendCalendarView(companies: [company]) }
        }
    }

    /// 투자지표/배당 최신화. 캐시가 이미 표시돼 있어도 세션당 1회 백그라운드 갱신한다(실패 시 캐시 유지).
    private func loadMetrics() async {
        guard !metricsLoaded else { return }
        metricsLoaded = true
        if let fresh = await CompanyMetricsCache.fetch(ticker: company.ticker,
                                                       exchangeParam: company.market?.chartParam) {
            metrics = fresh
        }
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

            // 2행: 큰 시가총액 (현재/최신) + 모드 전환 pill(시총 숫자 행에 맞춤).
            //      스크러빙 값은 그래프 말풍선이 담당.
            HStack(alignment: .center, spacing: 8) {
                Text(formatMarketCap(company.marketCapUSD, currency: currency, exchangeRate: exchangeRate))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.label)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                modePill
            }

            // 3행: 기간 전보다 등락
            periodDelta
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 헤더 우측 모드 전환 pill(캡슐 + chevron). 탭하면 시가총액/지수 대비 메뉴가 뜬다.
    private var modePill: some View {
        Menu {
            Picker("차트 모드", selection: $mode) {
                ForEach(ChartMode.allCases) { m in
                    Text(m.menuLabel).tag(m)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(mode.pillLabel)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(theme.label)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.fill, in: Capsule())
        }
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
            switch mode {
            case .marketCap:
                if points.count >= 2 { marketCapChart } else { chartSkeleton }
            case .vsIndex:
                if comparisonSeries != nil { comparisonChart } else { chartSkeleton }
            }
        }
    }

    /// 데이터 부재(시드 실패 등) 시 옅은 스켈레톤.
    private var chartSkeleton: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(theme.fill)
            .overlay(ProgressView())
    }

    // MARK: 시가총액 그래프(절대값 + 토스식 기준 점선)

    private var marketCapChart: some View {
        let caps = points.map(\.capUSD)
        let minCap = caps.min() ?? 0
        let maxCap = caps.max() ?? 1
        let pad = max((maxCap - minCap) * 0.12, maxCap * 0.02)
        let lower = max(minCap - pad, 0)
        let upper = maxCap + pad
        let baseline = points.first?.capUSD ?? caps.first ?? 0   // 기준선 = 기간 시작값

        return Chart {
            // 토스식 기준 점선(기간 시작 시총). 이 선 위/아래로 등락을 직관적으로 읽는다.
            RuleMark(y: .value("base", baseline))
                .foregroundStyle(theme.secondaryLabel.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

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
            scrubOverlay(proxy)
        }
    }

    // MARK: 지수 대비 성장률 그래프(base 100, 2라인)

    /// 종목·지수 시드를 각각 base 100으로 리베이스한 비교 시리즈. 데이터 미비 시 nil.
    private var comparisonSeries: (company: [Double], index: [Double])? {
        let caps = points.map(\.capUSD)
        let idx = store.indexSeries
        guard caps.count >= 2, idx.count == caps.count,
              let c0 = caps.first, c0 > 0, let i0 = idx.first, i0 > 0 else { return nil }
        return (caps.map { $0 / c0 * 100 }, idx.map { $0 / i0 * 100 })
    }

    private var comparisonChart: some View {
        let series = comparisonSeries ?? (company: [], index: [])
        let all = series.company + series.index
        let minV = all.min() ?? 90
        let maxV = all.max() ?? 110
        let pad = max((maxV - minV) * 0.12, 2)
        let lower = minV - pad
        let upper = maxV + pad

        return Chart {
            // 기준선 = 100(비교 시작 시점). 이 선 대비 두 곡선의 상대 성과를 읽는다.
            RuleMark(y: .value("base", 100.0))
                .foregroundStyle(theme.secondaryLabel.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // 지수선(회색) — 먼저 그려 종목선이 위로 오게.
            ForEach(Array(series.index.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v), series: .value("s", "지수"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(theme.secondaryLabel)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            // 종목선(추세색)
            ForEach(Array(series.company.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v), series: .value("s", "종목"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let sel = selectedIndex, series.company.indices.contains(sel) {
                RuleMark(x: .value("i", sel))
                    .foregroundStyle(theme.stroke)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        comparisonBubble(at: sel, series: series)
                    }
                PointMark(x: .value("i", sel), y: .value("v", series.index[sel]))
                    .symbolSize(70)
                    .foregroundStyle(theme.secondaryLabel)
                PointMark(x: .value("i", sel), y: .value("v", series.company[sel]))
                    .symbolSize(90)
                    .foregroundStyle(trendColor)
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            scrubOverlay(proxy)
        }
    }

    /// 스크러빙 제스처 오버레이(두 차트 공용). x좌표 → 최근접 인덱스.
    private func scrubOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in updateSelection(at: value.location.x, proxy: proxy, geo: geo) }
                        .onEnded { _ in selectedIndex = nil }
                )
        }
    }

    /// 비교 모드 범례 — 종목/지수 각각의 기간 성장률(base 100 대비)과 초과성과.
    private var comparisonLegend: some View {
        let series = comparisonSeries
        let companyPct = (series?.company.last ?? 100) - 100
        let indexPct = (series?.index.last ?? 100) - 100
        let excess = companyPct - indexPct   // 지수 대비 초과성과(%p)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                legendItem(color: trendColor, name: company.name, pct: companyPct)
                legendItem(color: theme.secondaryLabel, name: indexName, pct: indexPct)
            }
            Text(excessText(excess))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(color: Color, name: String, pct: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.label)
                .lineLimit(1)
            Text(String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(pct >= 0 ? Color.tickerUp : Color.tickerDown)
        }
    }

    /// 초과성과 문구. 양수면 지수를 앞섰다는 서사, 음수면 뒤처졌다는 서사.
    private func excessText(_ excess: Double) -> String {
        let mag = String(format: "%.1f%%p", abs(excess))
        if excess >= 0.05 {
            return "\(deltaPrefix.replacingOccurrences(of: " 전보다", with: "")) \(indexName)보다 \(mag) 앞섰어요"
        } else if excess <= -0.05 {
            return "\(deltaPrefix.replacingOccurrences(of: " 전보다", with: "")) \(indexName)보다 \(mag) 뒤처졌어요"
        } else {
            return "\(indexName)와 비슷한 흐름이에요"
        }
    }

    /// 비교선에 표기할 지수명. 백엔드 실데이터 지수명이 있으면 그걸, 없으면 거래소 기반 폴백.
    private var indexName: String {
        if let n = store.indexName, !n.isEmpty { return n }
        switch company.market {
        case .all:      return "S&P 500"
        case .nasdaq:   return "나스닥 100"
        case .nyse:     return "다우존스"
        case .kospi:    return "코스피"
        case .kosdaq:   return "코스닥"
        case .jpx:      return "MSCI 일본"
        case .euronext: return "유로 스톡스 50"
        case .sse:      return "CSI 300"
        case .szse:     return "차이넥스트"
        case .nse:      return "니프티 50"
        case .fwb:      return "DAX"
        default:        return "시장 지수"
        }
    }

    /// 비교 모드 크로스헤어 말풍선 — 날짜 + 종목/지수 각각의 base 100 대비 성장률.
    private func comparisonBubble(at idx: Int, series: (company: [Double], index: [Double])) -> some View {
        let dateStr = points.indices.contains(idx) ? displayDate(points[idx].date) : ""
        let cPct = series.company[idx] - 100
        let iPct = series.index[idx] - 100
        return VStack(alignment: .leading, spacing: 3) {
            Text(dateStr)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
            bubbleRow(color: trendColor, name: company.name, pct: cPct)
            bubbleRow(color: theme.secondaryLabel, name: indexName, pct: iPct)
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

    private func bubbleRow(color: Color, name: String, pct: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .lineLimit(1)
            Text(String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.label)
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

    // MARK: - 투자 지표 + 배당 소식 (토스 오마주)

    /// 정보 카드 아래에 투자지표 그리드 + 배당 소식을 노출. US/글로벌=실데이터, KR/미지원=준비 안내.
    /// 로딩 전(metrics==nil)엔 아무것도 그리지 않아 레이아웃 흔들림을 줄인다.
    @ViewBuilder
    private var investmentSection: some View {
        if let m = metrics, m.supported {
            let hasMetric = hasAnyMetric(m.metrics)
            let hasDiv = hasAnyDividend(m.dividend)
            VStack(alignment: .leading, spacing: 24) {
                if hasMetric { valuationCard(m.metrics!) }
                if hasDiv { dividendCard(m.dividend!, currencyCode: m.currency ?? "USD") }
                if !hasMetric && !hasDiv { comingSoonCard }
            }
        } else if metrics != nil {
            comingSoonCard   // supported=false (KR 등)
        } else {
            metricsSkeleton  // 캐시 없음(첫 조회) → 로딩 스켈레톤(가짜 수치 없이 즉각 반응)
        }
    }

    /// 지표 로딩 스켈레톤 — 실제 카드와 같은 레이아웃의 회색 블록(값이 뜨면 자연스럽게 대체).
    private var metricsSkeleton: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 6).fill(theme.fill).frame(width: 88, height: 20)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14).fill(theme.fill.opacity(0.6))
                        .frame(height: 64)
                }
            }
        }
        .redacted(reason: .placeholder)
        .transition(.opacity)
    }

    private func hasAnyMetric(_ m: CompanyMetricsData?) -> Bool {
        guard let m else { return false }
        return [m.per, m.pbr, m.psr, m.roePct, m.divYieldPct].contains { $0 != nil }
    }
    private func hasAnyDividend(_ d: CompanyDividendData?) -> Bool {
        guard let d else { return false }
        return d.perShare != nil || d.yieldPct != nil || d.freqCount != nil || d.exDate != nil
    }

    /// 투자 지표 그리드(토스 "투자 지표" 오마주). 값 있는 지표만 3열 타일로.
    private func valuationCard(_ m: CompanyMetricsData) -> some View {
        var tiles: [(String, String)] = []
        if let v = m.per { tiles.append(("PER", String(format: "%.2f배", v))) }
        if let v = m.pbr { tiles.append(("PBR", String(format: "%.2f배", v))) }
        if let v = m.psr { tiles.append(("PSR", String(format: "%.2f배", v))) }
        if let v = m.roePct { tiles.append(("ROE", String(format: "%.1f%%", v))) }
        if let v = m.divYieldPct { tiles.append(("배당수익률", String(format: "%.2f%%", v))) }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return VStack(alignment: .leading, spacing: 14) {
            Text("투자 지표").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.label)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(tiles, id: \.0) { t in metricTile(label: t.0, value: t.1) }
            }
        }
    }

    private func metricTile(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(theme.label)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.fill.opacity(0.6)))
    }

    /// 배당 소식(토스 "배당 소식" 오마주 — 아래로 따로 뺀 섹션). 값 있는 항목만 행으로.
    private func dividendCard(_ d: CompanyDividendData, currencyCode: String) -> some View {
        var rows: [(String, String)] = []
        if let n = d.freqCount { rows.append(("지급 횟수", "연 \(n)회")) }
        if let v = d.perShare { rows.append(("1주당 배당금", "연 \(formatDividendAmount(v, currencyCode: currencyCode))")) }
        if let v = d.yieldPct { rows.append(("배당수익률", String(format: "연 %.2f%%", v))) }
        if let ex = d.exDate { rows.append(("배당락일", displayDate(ex))) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("배당 소식").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.label)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { divider }
                    infoRow(row.0, row.1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.fill.opacity(0.6)))
        }
    }

    /// 데이터 미연동(KR 등) 안내 카드 — 가짜 값 대신 정직한 준비 중 표기.
    private var comingSoonCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            Text("투자지표·배당 정보는 곧 제공될 예정이에요.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.fill.opacity(0.6)))
    }

    /// 배당금 표기: 통화별 기호. 원/엔은 정수(천단위 콤마), 그 외 소수 2자리.
    private func formatDividendAmount(_ v: Double, currencyCode: String) -> String {
        switch currencyCode {
        case "USD": return String(format: "$%.2f", v)
        case "KRW": return "\(groupedInt(v))원"
        case "JPY": return "¥\(groupedInt(v))"
        case "EUR": return String(format: "€%.2f", v)
        case "CNY": return String(format: "CN¥%.2f", v)
        case "INR": return String(format: "₹%.2f", v)
        default:    return String(format: "%.2f %@", v, currencyCode)
        }
    }

    /// 정수 천단위 콤마 표기(4344 → "4,344").
    private func groupedInt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
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

    /// 토스증권 딥링크/웹에 쓰는 종목 경로 세그먼트.
    ///  · 🇰🇷 KOSPI/KOSDAQ = "A"+6자리코드(예: 삼성전자 → A005930). 로컬에서 즉시 도출(티커 접미사 우선).
    ///  · 🇺🇸/글로벌 = 토스 US 상품코드(US{IPO일}001, 예: NVDA → US19990122001). 백엔드가 토스 검색으로
    ///    해석한 값(metrics.tossCode)만 사용한다. ⚠️토스 앱은 티커 딥링크를 "지원하지 않는 주식"으로
    ///    거부하므로 티커를 경로로 쓰면 안 된다. 코드 미해석(로딩 전/실패)이면 nil → 버튼 미노출.
    private var tossPath: String? {
        let upper = company.ticker.uppercased()
        let isKR = upper.hasSuffix(".KS") || upper.hasSuffix(".KQ")
            || company.market == .kospi || company.market == .kosdaq
        if isKR {
            let base = company.ticker.split(separator: ".").first.map(String.init) ?? company.ticker
            let digits = base.filter(\.isNumber)
            return digits.count == 6 ? "A\(digits)" : nil
        }
        // US/글로벌: 백엔드가 해석한 토스 상품코드만 신뢰(티커 딥링크는 토스가 거부).
        if let code = metrics?.tossCode, !code.isEmpty { return code }
        return nil
    }

    /// 하단 고정 바(토스 오마주 2버튼): [바로가기(토스증권)] + [배당 캘린더].
    /// KR·US 종목에 토스 바로가기가 붙고(자본시장법: 앱은 정보 안내만·주문 미관여), 그 외는 배당 캘린더만 전폭.
    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if tossPath != nil { brokerButton }
                dividendCalendarButton
            }
            if tossPath != nil {
                Text("정보 제공 목적이며 투자 권유가 아니에요. 토스증권 미설치 시 웹으로 이동해요.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(theme.background)
    }

    /// 토스증권 바로가기 버튼(파란 CTA). KR·US 종목에서 노출.
    private var brokerButton: some View {
        Button { openInToss() } label: {
            HStack(spacing: 8) {
                // 토스 로고(브랜드 심볼)를 흰 원형 칩에 담아 파란 버튼 위에서도 또렷하게.
                Image("TossLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .padding(5)
                    .background(Circle().fill(.white))
                Text("바로가기")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)   // 토스 하단 CTA 표준 높이 오마주
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#3182F6")))
        }
        .buttonStyle(.plain)
    }

    /// 배당 캘린더 버튼(중립 CTA). 탭 시 배당락일 캘린더 시트를 연다.
    private var dividendCalendarButton: some View {
        Button { showDividendCalendar = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .semibold))
                Text("배당 캘린더")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(theme.label)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.fill))
        }
        .buttonStyle(.plain)
    }

    /// 토스증권의 해당 종목 상세 화면을 연다. 경로 세그먼트는 KR="A"+6자리(예: A005930), US=티커(예: AAPL).
    /// 딥링크는 토스 공유링크(OneLink)를 리다이렉트 추적해 확보한 실제 앱 스킴이며, 랜딩 URL만 종목별로 바꾼다.
    ///   supertoss://securities?url=<service.tossinvest.com?nextLandingUrl=/stocks/{path}>&…
    /// 앱이 설치돼 있으면(openURL 수락) 앱의 해당 종목 화면으로, 없으면(미수락) 웹 랜딩으로 폴백한다.
    private func openInToss() {
        guard let path = tossPath else { return }
        // 웹 폴백: 토스 종목 콘텐츠 페이지(KR=A+코드, US=상품코드) — 토스 자체 web_dp와 동일 호스트.
        guard let web = URL(string: "https://contents.tossinvest.com/stocks/\(path)") else { return }
        // 딥링크: nextLandingUrl(/stocks/{path})을 1차 인코딩 → 전체 url 파라미터를 2차 인코딩(기존 KR 링크와 동일 규약).
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_~"))
        let landingEnc = "/stocks/\(path)".addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let inner = "https://service.tossinvest.com?nextLandingUrl=\(landingEnc)"
        let innerEnc = inner.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let deepLink = URL(string: "supertoss://securities?url=\(innerEnc)&clearHistory=true&swipeRefresh=true")
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

// MARK: - 종목 지표 캐시 + 프리페치 (토스식 즉시 표시)

/// 종목 상세의 투자지표/배당(`/api/company-metrics`)을 즉시 보여주기 위한 공용 캐시.
///  · 메모리(세션) + UserDefaults(디스크) 2단 캐시 → 재방문 시 네트워크 없이 첫 프레임에 표시.
///  · 리스트 행이 화면에 들어올 때 `prefetch`로 백그라운드 워밍 → 탭 시점엔 이미 로드됨(토스 오마주).
///  · 안전장치: 티커 단위 중복 제거 + 세션 프리페치 상한(콜드 스타트 시 업스트림/크레딧 과호출 방지).
///    서버가 24h 캐시하므로 정상 상태에선 프리페치 비용이 사실상 0이다.
@MainActor
enum CompanyMetricsCache {
    private static var memory: [String: CompanyMetricsResponse] = [:]
    private static var inFlight: Set<String> = []
    private static var prefetchCount = 0
    private static let prefetchCap = 60   // 세션당 프리페치 상한(콜드 스타트 비용 하드 바운드)

    private static func diskKey(_ ticker: String) -> String { "companyMetrics.\(ticker)" }

    /// 캐시된 지표(메모리 → 디스크). 없으면 nil. (View init/onAppear에서 즉시 호출용)
    static func cached(ticker: String) -> CompanyMetricsResponse? {
        if let m = memory[ticker] { return m }
        guard let data = UserDefaults.standard.data(forKey: diskKey(ticker)),
              let decoded = try? JSONDecoder().decode(CompanyMetricsResponse.self, from: data)
        else { return nil }
        memory[ticker] = decoded
        return decoded
    }

    private static func store(_ m: CompanyMetricsResponse) {
        memory[m.ticker] = m
        if let data = try? JSONEncoder().encode(m) {
            UserDefaults.standard.set(data, forKey: diskKey(m.ticker))
        }
    }

    /// 네트워크로 최신 지표를 받아 캐시에 저장하고 반환. 실패 시 nil(호출부는 캐시/스켈레톤 유지).
    @discardableResult
    static func fetch(ticker: String, exchangeParam: String?) async -> CompanyMetricsResponse? {
        guard let encoded = ticker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        var urlString = "\(MarketCapViewModel.apiBase)/api/company-metrics?ticker=\(encoded)"
        if let ex = exchangeParam { urlString += "&exchange=\(ex)" }
        guard let url = URL(string: urlString),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanyMetricsResponse.self, from: data)
        else { return nil }
        store(decoded)
        return decoded
    }

    /// 리스트 행이 보일 때 백그라운드 워밍. 이미 캐시/진행중이거나 상한 초과면 아무 것도 안 한다.
    static func prefetch(_ company: Company) {
        let t = company.ticker
        if memory[t] != nil || inFlight.contains(t) { return }
        if cached(ticker: t) != nil { return }             // 디스크 캐시 존재 → 네트워크 생략(서버 24h 캐시 존중)
        guard prefetchCount < prefetchCap else { return }   // 세션 상한(콜드 과호출 방지)
        prefetchCount += 1
        inFlight.insert(t)
        let ex = company.market?.chartParam
        Task {
            _ = await fetch(ticker: t, exchangeParam: ex)
            inFlight.remove(t)
        }
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
