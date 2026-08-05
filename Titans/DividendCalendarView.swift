//
//  DividendCalendarView.swift
//  Titans
//
//  배당락일(ex-dividend date) 캘린더. 사용자가 원하는 기업의 배당락일을 월간 달력에서
//  한눈에 확인하는 화면이다.
//
//  ⚠️ 데이터 소스: 배당락일/배당금은 실시간 시세와 달리 '기업 액션(corporate action)' 데이터로,
//     무료 소스로는 안정적으로 얻기 어렵다. 출시 전 Finnhub 유료 플랜(`/stock/dividend`)을
//     연동하면 ex-date·record date·pay date·배당금·통화를 그대로 채울 수 있다.
//     이 화면은 그 연동을 그대로 끼우면 되도록 UI/모델을 미리 완성해 둔 '껍데기'이며,
//     지금은 가짜 배당일을 노출하지 않고 '연동 예정' 상태를 정직하게 보여준다.
//

import SwiftUI

// MARK: - Model (Finnhub /stock/dividend 응답에 1:1 대응)

/// 배당 이벤트 한 건. Finnhub `/stock/dividend` 의 필드명을 그대로 따 두어
/// 유료 연동 시 디코딩 → 매핑이 바로 되도록 했다.
struct DividendEvent: Identifiable {
    let id = UUID()
    let ticker: String
    let name: String
    let exDate: Date        // 배당락일 (ex-dividend date)
    let payDate: Date?      // 지급일
    let amount: Double      // 주당 배당금
    let currency: String    // "USD" / "KRW" …
}

// MARK: - Data Provider (연동 지점)

/// 배당 데이터 공급자. 지금은 항상 빈 배열을 돌려주는 플레이스홀더.
/// 유료 연동 시 이 구현만 Finnhub 호출로 교체하면 화면 코드는 그대로 동작한다.
///   GET https://finnhub.io/api/v1/stock/dividend?symbol=AAPL&from=YYYY-MM-DD&to=YYYY-MM-DD&token=...
protocol DividendProvider {
    func events(in month: Date, for tickers: [String]) async -> [DividendEvent]
}

struct PlaceholderDividendProvider: DividendProvider {
    func events(in month: Date, for tickers: [String]) async -> [DividendEvent] { [] }
}

// MARK: - Dividend Calendar View

struct DividendCalendarView: View {
    /// 배당락일을 추적할 관심 종목(현재는 미사용, 연동 시 필터로 사용).
    let companies: [Company]

    var provider: DividendProvider = PlaceholderDividendProvider()

    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var events: [DividendEvent] = []

    private var isDarkMode: Bool { colorScheme == .dark }
    private var theme: AppTheme { isDarkMode ? .dark : .light }
    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                infoBanner
                monthHeader
                weekdayHeader
                dayGrid
                Divider().overlay(theme.stroke.opacity(0.4))
                eventList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.label)
        .environment(\.appTheme, theme)
        .navigationTitle("배당락일 캘린더")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .task(id: visibleMonth) {
            events = await provider.events(in: visibleMonth, for: companies.map(\.ticker))
        }
    }

    // MARK: - 안내 배너

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.blue)
            Text("서비스를 준비 중이에요. 관심 기업의 배당락일·배당금·지급일을 이 달력에서 확인할 수 있어요.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 월 헤더 (이전/다음)

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.secondaryLabel)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle)
                .font(.system(size: 18, weight: .bold))
                .contentTransition(.numericText())

            Spacer()

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.secondaryLabel)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { idx, day in
                Text(day)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(idx == 0 ? Color.red.opacity(0.8)
                                     : idx == 6 ? Color.blue.opacity(0.8)
                                     : theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 날짜 그리드

    private var dayGrid: some View {
        let days = monthDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let hasEvent = events.contains { cal.isDate($0.exDate, inSameDayAs: day) }
        let weekday = cal.component(.weekday, from: day)   // 1=일, 7=토
        let dayColor: Color = weekday == 1 ? .red.opacity(0.85)
            : weekday == 7 ? .blue.opacity(0.85)
            : theme.label

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 15, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? theme.background : dayColor)
                Circle()
                    .fill(hasEvent ? Color.pink : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10).fill(theme.label)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10).stroke(theme.stroke, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 선택일 배당 목록

    private var eventList: some View {
        let dayEvents = events.filter { cal.isDate($0.exDate, inSameDayAs: selectedDay) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(selectedDayTitle)
                .font(.system(size: 15, weight: .bold))

            if dayEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 30))
                        .foregroundStyle(theme.tertiaryLabel)
                    Text("이 날 예정된 배당락 정보가 없어요")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(dayEvents) { ev in
                    eventRow(ev)
                }
            }
        }
    }

    private func eventRow(_ ev: DividendEvent) -> some View {
        HStack(spacing: 12) {
            BrandLogoTile(ticker: ev.ticker, name: ev.name, color: .pink)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.name).font(.system(size: 15, weight: .semibold))
                Text(ev.ticker).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            Text("\(ev.currency == "USD" ? "$" : "")\(String(format: "%.2f", ev.amount))")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func shiftMonth(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { visibleMonth = next }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f.string(from: visibleMonth)
    }

    private var selectedDayTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f.string(from: selectedDay)
    }

    /// 해당 월의 날짜 배열 — 첫 주 앞쪽은 nil로 채워 요일 정렬을 맞춘다.
    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstDay = interval.start
        let daysInMonth = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let leadingBlanks = cal.component(.weekday, from: firstDay) - 1   // 1=일요일 기준
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            if let d = cal.date(byAdding: .day, value: offset, to: firstDay) {
                cells.append(d)
            }
        }
        return cells
    }
}
