//
//  WidgetSharedModel.swift
//  Titans  +  surFinWidget  (동일 내용 복제본)
//
//  앱과 위젯 익스텐션이 App Group 컨테이너를 통해 데이터를 주고받기 위한 공유 계약.
//  ⚠️ 이 파일은 `Titans/`와 `surFinWidget/` 두 폴더에 **동일한 내용으로** 존재한다.
//     (Xcode 동기화 폴더 구조상 한 파일을 두 타깃에 넣기가 번거로워, 서로 다른 모듈에
//      같은 내용을 복제한다.) 한쪽을 고치면 반드시 다른 쪽도 같이 고칠 것.
//

import Foundation

// MARK: - App Group 상수

enum WidgetSharedConstants {
    /// 앱·위젯이 공유하는 App Group. (양 타깃 엔타이틀먼트에 동일하게 등록되어야 함)
    static let appGroupID = "group.com.carryHoon.Titans"
    static let snapshotFileName = "widget_snapshot.json"
    static let logosDirName = "widget_logos"
}

// MARK: - 스냅샷 모델 (앱이 쓰고, 위젯이 읽는다)

/// 위젯 한 행에 필요한 최소 종목 정보. 앱의 `Company`에서 위젯 표시에 필요한 필드만 추린 것.
struct WidgetCompany: Codable, Identifiable {
    var id: String { ticker }
    let rank: Int
    let previousRank: Int?
    let name: String
    let ticker: String
    let marketCapUSD: Double   // trillion USD (앱과 동일 단위)
    let changePercent: Double
    let colorHex: String       // 이니셜 폴백 타일 색상
    let domain: String?        // 백엔드(DART) 해석 도메인 — 로컬 에셋 없는 종목 로고 폴백용
}

/// 한 거래소의 스냅샷. companies는 Top5까지 담고, 위젯이 크기별로 3/5로 슬라이스한다.
struct WidgetExchangeData: Codable {
    let exchangeRate: Double    // 원화 환산용 (조원 = marketCapUSD * exchangeRate)
    let basDt: String?          // KRX 기준일("YYYYMMDD") — 코스피/코스닥만
    let companies: [WidgetCompany]
}

/// 전체 스냅샷 — 거래소 키(nasdaq/nyse/kospi/kosdaq) → 데이터.
struct WidgetSnapshot: Codable {
    var exchanges: [String: WidgetExchangeData]
    var updatedAt: Date
}

// MARK: - App Group 읽기/쓰기

enum WidgetStore {
    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSharedConstants.appGroupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(WidgetSharedConstants.snapshotFileName)
    }

    static var logosDirURL: URL? {
        containerURL?.appendingPathComponent(WidgetSharedConstants.logosDirName, isDirectory: true)
    }

    /// 티커별 로고 PNG 경로. 앱이 최종 렌더링해 저장하고, 위젯이 그대로 읽는다.
    static func logoURL(ticker: String) -> URL? {
        let safe = ticker.replacingOccurrences(of: "/", with: "_")
        return logosDirURL?.appendingPathComponent("\(safe).png")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL else { return }
        if let dir = logosDirURL {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
