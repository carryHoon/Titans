//
//  WidgetRefresh.swift
//  surFinWidget
//
//  위젯 헤더의 새로고침 버튼이 실행하는 AppIntent. 위젯 익스텐션이 선택된 거래소를
//  백엔드에서 직접 받아 App Group 스냅샷의 해당 거래소 슬라이스만 갱신한다.
//  (로고 PNG는 앱이 렌더링한 캐시를 그대로 재사용 — 새 종목만 이니셜 폴백)
//

import WidgetKit
import AppIntents
import Foundation

// MARK: - 백엔드 호스트 (앱과 동일 규칙)

enum WidgetBackend {
    // 시뮬레이터는 Mac localhost(ATS 예외), 실기기는 같은 Wi-Fi의 Mac LAN IP.
    #if targetEnvironment(simulator)
    static let host = "localhost"
    #else
    static let host = "172.30.1.21"
    #endif

    static func marketCapURL(exchange: String) -> URL? {
        URL(string: "http://\(host):3000/api/market-cap?exchange=\(exchange)")
    }
}

// MARK: - 응답 DTO (앱 MarketCapResponse의 위젯용 최소 복제)

private struct WGCompanyResult: Decodable {
    let rank: Int
    let previousRank: Int?
    let ticker: String
    let name: String
    let color: String
    let changePercent: Double
    let marketCapUSD: Double
    let domain: String?
}

private struct WGMarketCapResponse: Decodable {
    let exchangeRate: Double?
    let basDt: String?
    let data: [WGCompanyResult]
}

// MARK: - 선택 거래소 새로고침

enum WidgetDataRefresher {
    static func refresh(exchangeKey: String) async {
        guard let url = WidgetBackend.marketCapURL(exchange: exchangeKey),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(WGMarketCapResponse.self, from: data),
              !decoded.data.isEmpty
        else { return }  // 실패 시 기존 스냅샷 유지

        let companies = decoded.data.sorted { $0.rank < $1.rank }.prefix(8).map { api in
            WidgetCompany(
                rank: api.rank, previousRank: api.previousRank, name: api.name,
                ticker: api.ticker, marketCapUSD: api.marketCapUSD,
                changePercent: api.changePercent, colorHex: api.color, domain: api.domain
            )
        }

        var snapshot = WidgetStore.load() ?? WidgetSnapshot(exchanges: [:], updatedAt: .distantPast)
        let rate = decoded.exchangeRate ?? snapshot.exchanges[exchangeKey]?.exchangeRate ?? 1450
        snapshot.exchanges[exchangeKey] = WidgetExchangeData(
            exchangeRate: rate, basDt: decoded.basDt, companies: Array(companies)
        )
        snapshot.updatedAt = Date()
        WidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - 새로고침 인텐트 (위젯 버튼 전용)

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { "새로고침" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Exchange")
    var exchangeKey: String

    init() {}
    init(exchangeKey: String) { self.exchangeKey = exchangeKey }

    func perform() async throws -> some IntentResult {
        await WidgetDataRefresher.refresh(exchangeKey: exchangeKey)
        return .result()
    }
}
