//
//  CustomExchangeStore.swift
//  Titans
//
//  "나만의 거래소"(커스텀 종목 집합) 목록의 로컬 저장/관리.
//
//  저장 위치: App Group UserDefaults(JSON). 위젯도 같은 App Group을 공유하므로 후속에 위젯이
//            "내 거래소"를 읽는 확장이 자연스럽다. (로그인 사용자는 후속에 Supabase user_prefs 동기화 예정.)
//  안전성: 순수 로컬 데이터. 실패는 조용히 무시하며 기존 데이터 흐름과 분리돼 있다.
//

import Foundation
import Observation

// MARK: - 탭 식별자

/// 홈 거래소 페이징의 탭 식별자. 기존 거래소(builtin) + 커스텀 거래소 + "만들기" 페이지를 하나의
/// TabView selection으로 통합한다. (기존 selectedMarket: Market은 builtin에서 유도되는 computed로 유지.)
enum MarketTab: Hashable {
    case builtin(Market)
    case custom(UUID)
    case addNew
}

// MARK: - 모델

/// 사용자가 만든 커스텀 거래소 하나. tickers는 로드된 유니버스에 존재하는 티커만 담는다(클라이언트 서브셋).
struct CustomExchange: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var tickers: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, tickers: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tickers = tickers
        self.createdAt = createdAt
    }
}

// MARK: - 스토어

/// 커스텀 거래소 목록의 단일 소스. ContentView에 @State로 주입해 페이징/필터바가 관찰한다.
@Observable
final class CustomExchangeStore {
    private(set) var exchanges: [CustomExchange]

    private let defaultsKey = "customExchanges"
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSharedConstants.appGroupID)
    }

    init() {
        exchanges = Self.load(from: UserDefaults(suiteName: WidgetSharedConstants.appGroupID),
                              key: "customExchanges")
    }

    // MARK: CRUD

    /// 새 거래소 추가(맨 뒤). 저장 후 반환.
    @discardableResult
    func add(name: String, tickers: [String]) -> CustomExchange {
        let ex = CustomExchange(name: name, tickers: tickers)
        exchanges.append(ex)
        persist()
        return ex
    }

    /// 이름/종목 수정. id가 없으면 무시.
    func update(_ exchange: CustomExchange) {
        guard let idx = exchanges.firstIndex(where: { $0.id == exchange.id }) else { return }
        exchanges[idx] = exchange
        persist()
    }

    func remove(id: UUID) {
        exchanges.removeAll { $0.id == id }
        persist()
    }

    /// 거래소 칩 순서 변경(토스식 드래그 재정렬). fromID를 toID 자리로 옮긴다.
    func moveExchange(fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let from = exchanges.firstIndex(where: { $0.id == fromID }),
              let to = exchanges.firstIndex(where: { $0.id == toID }) else { return }
        let item = exchanges.remove(at: from)
        exchanges.insert(item, at: to)
        persist()
    }

    /// 이름만 변경(연필 → 이름 편집). 종목 구성은 건드리지 않는다.
    func rename(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let idx = exchanges.firstIndex(where: { $0.id == id }) else { return }
        exchanges[idx].name = trimmed
        persist()
    }

    func exchange(id: UUID) -> CustomExchange? {
        exchanges.first { $0.id == id }
    }

    // MARK: 영속화

    private func persist() {
        guard let data = try? JSONEncoder().encode(exchanges) else { return }
        defaults?.set(data, forKey: defaultsKey)
    }

    private static func load(from defaults: UserDefaults?, key: String) -> [CustomExchange] {
        guard let data = defaults?.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomExchange].self, from: data)
        else { return [] }
        return decoded
    }
}
