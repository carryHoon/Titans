//
//  AppIntent.swift
//  surFinWidget
//
//  위젯 편집(길게 눌러 "편집")에서 고를 수 있는 설정: 증권거래소 + 통화 단위.
//

import WidgetKit
import AppIntents

// MARK: - 거래소 선택

enum WidgetExchangeChoice: String, AppEnum {
    case nasdaq, nyse, kospi, kosdaq

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "증권거래소" }
    static var caseDisplayRepresentations: [WidgetExchangeChoice: DisplayRepresentation] {
        [
            .nasdaq: "NASDAQ",
            .nyse:   "NYSE",
            .kospi:  "KOSPI",
            .kosdaq: "KOSDAQ",
        ]
    }

    /// 스냅샷 딕셔너리 키(백엔드 exchange 파라미터와 동일).
    var apiKey: String { rawValue }

    /// 위젯 헤더에 중앙정렬로 표시되는 거래소 이름.
    var title: String {
        switch self {
        case .nasdaq: return "NASDAQ"
        case .nyse:   return "NYSE"
        case .kospi:  return "KOSPI"
        case .kosdaq: return "KOSDAQ"
        }
    }
}

// MARK: - 통화 단위 선택

enum WidgetCurrencyChoice: String, AppEnum {
    case usd, krw

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "통화 단위" }
    static var caseDisplayRepresentations: [WidgetCurrencyChoice: DisplayRepresentation] {
        [
            .usd: "$ 달러",
            .krw: "₩ 원",
        ]
    }

    var currency: Currency { self == .usd ? .usd : .krw }
}

// MARK: - 위젯 설정 인텐트

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "시가총액 순위" }
    
    static var description: IntentDescription {
            IntentDescription("증권거래소별 상위 시가총액 종목을 보여줍니다.")
        }

    @Parameter(title: "증권거래소", default: .nasdaq)
    var exchange: WidgetExchangeChoice

    @Parameter(title: "통화 단위", default: .usd)
    var currency: WidgetCurrencyChoice
}
