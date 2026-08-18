//
//  RankSnapshotStore.swift
//  Titans
//
//  "나만의 거래소"의 주간/월간 하이라이트를 위한 일별 시가총액 히스토리 저장소.
//
//  왜 필요한가:
//   · 어제 대비(day-over-day) 순위변동은 당일 등락률로 역산할 수 있어 저장이 필요 없다.
//     (highlights(for:)의 prevCap = cap/(1+change/100) 로직 참고.)
//   · 그러나 주간/월간 변동은 7~30일 전 실제 시가총액이 있어야 하므로 "지금부터" 매일 적재해야 한다.
//   · 커스텀 거래소는 임의 종목 집합이라, 백엔드의 글로벌 순위 히스토리로는 서브셋 순위를 복원할 수 없다.
//     → 종목별 "시총" 값을 저장해두면 어떤 부분집합이든 과거 시점의 순위를 클라이언트가 재계산할 수 있다.
//
//  안전성: 순수 추가(additive) 컴포넌트. 읽기/쓰기 실패는 조용히 무시하며(try?), 기존 UI/데이터 흐름과
//         완전히 분리돼 있다. App Group 컨테이너에 별도 파일로 저장해 위젯 스냅샷(widget_snapshot.json)을
//         건드리지 않는다.
//

import Foundation

/// 하루치 유니버스 스냅샷 — 기준일(KST) 하나에 대한 종목별 시가총액(USD 조 단위) 맵.
struct UniverseDailySnapshot: Codable {
    let date: String            // 기준일 "YYYY-MM-DD" (Asia/Seoul 달력일)
    let caps: [String: Double]  // ticker → marketCapUSD (조 단위, USD 기준 — 통화 무관 공통값)
}

/// 일별 유니버스 시가총액 히스토리 저장소(App Group 파일 기반).
/// 하루 1개 엔트리를 upsert하며 최대 `maxDays`일만 보관한다.
enum RankSnapshotStore {

    /// 보관 상한(일). 약 3개월(월간 창) + 여유. 초과분은 오래된 것부터 정리한다.
    static let maxDays = 95

    private static let fileName = "universe_history.json"

    private static var fileURL: URL? {
        WidgetStore.containerURL?.appendingPathComponent(fileName)
    }

    // MARK: - 기준일 (KST)

    /// 오늘의 기준일 문자열("YYYY-MM-DD", Asia/Seoul). 모든 거래소가 하나의 기준일로 통일된다.
    static func todayKST() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? cal.timeZone
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - 적재

    /// 오늘 기준일 엔트리에 시가총액 맵을 upsert한다.
    ///  · 같은 날 재호출: 기존 caps에 병합(최신값 우선, 티커 합집합) — 부분 로드로 시작해도 완전성이 커진다.
    ///  · 날짜가 바뀌면 이전 날짜 엔트리는 그대로 동결되어 과거 기준선이 된다.
    /// caps가 비어 있으면 아무것도 하지 않는다(잘못된 빈 스냅샷 방지).
    static func record(caps: [String: Double], date: String = todayKST()) {
        guard !caps.isEmpty else { return }
        var history = load()

        if let idx = history.firstIndex(where: { $0.date == date }) {
            // 오늘 엔트리 병합: 새 값 우선, 기존 티커는 유지(완전성 보존).
            var merged = history[idx].caps
            for (ticker, cap) in caps { merged[ticker] = cap }
            history[idx] = UniverseDailySnapshot(date: date, caps: merged)
        } else {
            history.append(UniverseDailySnapshot(date: date, caps: caps))
        }

        // 날짜 오름차순 정렬 후 오래된 것부터 상한까지 정리.
        history.sort { $0.date < $1.date }
        if history.count > maxDays {
            history.removeFirst(history.count - maxDays)
        }
        save(history)
    }

    // MARK: - 조회

    /// 전체 히스토리(오래된→최신).
    static func load() -> [UniverseDailySnapshot] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([UniverseDailySnapshot].self, from: data)) ?? []
    }

    /// 오늘 기준으로 대략 `daysAgo`일 전의 기준선. 정확히 그 날짜가 없으면
    /// 목표일(오늘−daysAgo) *이하* 중 가장 최근 스냅샷을 사용한다(주말/미접속일 갭 흡수).
    /// 반환값은 요청한 티커 집합에 존재하는 항목만 담은 [ticker: 과거 시총].
    /// 사용 가능한 과거 스냅샷이 없으면 nil.
    static func baseline(daysAgo: Int, tickers: Set<String>, today: String = todayKST()) -> [String: Double]? {
        let history = load()
        guard !history.isEmpty else { return nil }
        guard let target = date(byAdding: -daysAgo, to: today) else { return nil }

        // 목표일 이하 중 가장 최근(날짜 문자열은 "YYYY-MM-DD"라 사전식 비교 = 시간순 비교).
        guard let snap = history.last(where: { $0.date <= target }) else { return nil }

        var result: [String: Double] = [:]
        for t in tickers {
            if let cap = snap.caps[t] { result[t] = cap }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - 내부 유틸

    private static func save(_ history: [UniverseDailySnapshot]) {
        guard let url = fileURL else { return }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// "YYYY-MM-DD"에 `days`일을 더한(음수면 뺀) 날짜 문자열. KST 달력 기준.
    private static func date(byAdding days: Int, to dateString: String) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? cal.timeZone
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comp = DateComponents()
        comp.year = parts[0]; comp.month = parts[1]; comp.day = parts[2]
        guard let base = cal.date(from: comp),
              let shifted = cal.date(byAdding: .day, value: days, to: base) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
