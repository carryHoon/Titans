//
//  SearchView.swift
//  Titans
//
//  돋보기 버튼으로 진입하는 검색 화면. 토스 증권의 검색 흐름을 오마주했다.
//  (상단 뒤로가기 + 둥근 검색바 + 최근 검색 칩 + 인기/급등 섹션)
//
//  데이터는 별도 API를 추가하지 않고, 이미 라이브로 받고 있는 시가총액 유니버스를
//  그대로 검색·정렬해 재사용한다(가짜 데이터 없이 실제 값만 노출).
//

import SwiftUI

// MARK: - 최근 검색 저장소 (로컬 영속)

/// 최근 검색어를 UserDefaults에 개행 구분 문자열로 보관하는 경량 저장소.
/// 별도 모델/DB 없이 @AppStorage 하나로 최신 항목이 앞에 오도록 관리한다.
private enum RecentSearchStore {
    static let key = "recentSearches"
    static let maxCount = 12

    static func load() -> [String] {
        (UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: "\n")
            .map(String.init)
    }

    static func save(_ items: [String]) {
        UserDefaults.standard.set(items.joined(separator: "\n"), forKey: key)
    }

    /// 이미 있으면 최상단으로 끌어올리고, 최대 개수를 넘으면 오래된 항목을 버린다.
    static func add(_ term: String, to items: [String]) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        var next = items.filter { $0 != trimmed }
        next.insert(trimmed, at: 0)
        return Array(next.prefix(maxCount))
    }
}

// MARK: - Search View

struct SearchView: View {
    /// 검색 대상 유니버스 — ContentView에서 현재 로드된 전 거래소 종목을 합쳐 전달.
    let companies: [Company]
    let currency: Currency
    let exchangeRate: Double
    let isDarkMode: Bool
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var recents: [String] = RecentSearchStore.load()
    @State private var placeholderIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var theme: AppTheme { isDarkMode ? .dark : .light }

    // 회전 placeholder — 토스처럼 검색 예시를 순환해 보여준다.
    private let placeholders = [
        "‘배당주’를 검색해보세요",
        "‘엔비디아’를 검색해보세요",
        "‘삼성전자’를 검색해보세요",
        "‘반도체’를 검색해보세요",
        "‘테슬라’를 검색해보세요",
    ]

    // MARK: 검색/추천 결과 (모두 실데이터 기반)

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// 이름·티커·한글 별칭에 검색어가 포함된 종목. 시가총액 큰 순으로.
    private var results: [Company] {
        guard !query.isEmpty else { return [] }
        return companies
            .filter { matches($0, query) }
            .sorted { $0.marketCapUSD > $1.marketCapUSD }
    }

    /// 영문명·티커 + 한글 별칭(엔비디아·삼전 등)까지 부분일치로 매칭.
    private func matches(_ company: Company, _ q: String) -> Bool {
        if company.name.localizedCaseInsensitiveContains(q) { return true }
        if company.ticker.localizedCaseInsensitiveContains(q) { return true }
        if let aliases = tickerKoreanAliases[company.ticker] {
            return aliases.contains { $0.localizedCaseInsensitiveContains(q) }
        }
        return false
    }

    /// 인기 주식 — 시가총액 상위(우리 유니버스의 '거인들').
    private var popular: [Company] {
        Array(companies.sorted { $0.marketCapUSD > $1.marketCapUSD }.prefix(5))
    }

    /// 오늘의 급등 — 당일 등락률 상위. (실시간 이슈 대신 실제 값으로 구성)
    private var topGainers: [Company] {
        Array(companies.sorted { $0.change > $1.change }.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        recentSection
                        rankSection(title: "인기 주식", timeLabel: nowLabel, items: popular, showChange: false)
                        rankSection(title: "오늘의 급등", timeLabel: nowLabel, items: topGainers, showChange: true)
                    } else if results.isEmpty {
                        emptyResults
                    } else {
                        resultsList
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.label)
        .environment(\.appTheme, theme)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear { isFieldFocused = true }
        // 회전 placeholder 2.5초 주기
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeInOut(duration: 0.35)) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                }
            }
        }
    }

    // MARK: - 상단 검색바

    private var searchBar: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)

                ZStack(alignment: .leading) {
                    // 회전 placeholder (검색어가 없을 때만)
                    if searchText.isEmpty {
                        Text(placeholders[placeholderIndex])
                            .font(.system(size: 15))
                            .foregroundStyle(theme.tertiaryLabel)
                            .id(placeholderIndex)
                            .transition(.push(from: .bottom).combined(with: .opacity))
                    }
                    TextField("", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.label)
                        .tint(theme.label)
                        .focused($isFieldFocused)
                        .submitLabel(.search)
                        .onSubmit { commitSearch(query) }
                }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.fill, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - 최근 검색

    @ViewBuilder
    private var recentSection: some View {
        if !recents.isEmpty {
            HStack {
                Text("최근 검색")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("전체 삭제") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        recents = []
                        RecentSearchStore.save(recents)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recents, id: \.self) { term in
                        recentChip(term)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .padding(.bottom, 18)
        }
    }

    private func recentChip(_ term: String) -> some View {
        HStack(spacing: 6) {
            Text(term)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    recents.removeAll { $0 == term }
                    RecentSearchStore.save(recents)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(
            Capsule().stroke(theme.stroke, lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture { searchText = term }
    }

    // MARK: - 순위 섹션 (인기 주식 / 오늘의 급등)

    private func rankSection(title: String, timeLabel: String, items: [Company], showChange: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.tertiaryLabel)
                }
                Spacer()
                Text(timeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            if items.isEmpty {
                Text("데이터를 불러오는 중이에요")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.tertiaryLabel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, company in
                    rankRow(rank: idx + 1, company: company, showChange: showChange)
                }
            }
        }
        .padding(.bottom, 22)
    }

    private func rankRow(rank: Int, company: Company, showChange: Bool) -> some View {
        Button {
            commitSearch(company.name)
        } label: {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? theme.label : theme.tertiaryLabel)
                    .frame(width: 18)

                Text(company.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                Spacer()

                changeLabel(company.change)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 검색 결과

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(results) { company in
                Button {
                    commitSearch(company.name)
                } label: {
                    HStack(spacing: 12) {
                        BrandLogoTile(ticker: company.ticker, name: company.name, color: company.color)
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(company.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(company.ticker)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryLabel)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(marketCapText(company))
                                .font(.system(size: 14, weight: .bold))
                            changeLabel(company.change)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(theme.tertiaryLabel)
            Text("‘\(query)’ 검색 결과가 없어요")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
            Text("종목명(영문) 또는 티커로 검색해보세요")
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    /// 상승=빨강 / 하락=파랑 (토스 증권 컨벤션 — 스크린샷과 일치)
    private func changeLabel(_ change: Double) -> some View {
        let up = change >= 0
        let color = up
            ? Color(red: 0.95, green: 0.20, blue: 0.20)
            : Color(red: 0.10, green: 0.43, blue: 0.92)
        return Text("\(up ? "+" : "")\(String(format: "%.1f", change))%")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(color)
    }

    private func marketCapText(_ c: Company) -> String {
        formatMarketCap(c.marketCapUSD, currency: currency, exchangeRate: exchangeRate)
    }

    private var nowLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "오늘 HH:mm 기준"
        return f.string(from: Date())
    }

    private func commitSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recents = RecentSearchStore.add(trimmed, to: recents)
        RecentSearchStore.save(recents)
        searchText = trimmed
    }
}
