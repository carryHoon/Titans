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
    // 순서 = 앱 홈 화면 거래소 칩 순서(ContentView Market enum과 동일). rawValue는 백엔드
    // `?exchange=` 파라미터와 1:1로 일치해야 한다(불일치 시 무증상 US 폴백).
    case nasdaq, nyse, kospi, kosdaq, jpx, sse, szse, euronext, fwb, nse

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "증권거래소" }
    static var caseDisplayRepresentations: [WidgetExchangeChoice: DisplayRepresentation] {
        [
            .nasdaq:   "NASDAQ",
            .nyse:     "NYSE",
            .kospi:    "KOSPI",
            .kosdaq:   "KOSDAQ",
            .jpx:      "JPX",
            .sse:      "SSE",
            .szse:     "SZSE",
            .euronext: "EURONEXT",
            .fwb:      "FWB",
            .nse:      "NSE",
        ]
    }

    /// 스냅샷 딕셔너리 키(백엔드 exchange 파라미터와 동일).
    var apiKey: String { rawValue }

    /// 위젯 헤더에 중앙정렬로 표시되는 거래소 이름.
    var title: String {
        switch self {
        case .nasdaq:   return "NASDAQ"
        case .nyse:     return "NYSE"
        case .kospi:    return "KOSPI"
        case .kosdaq:   return "KOSDAQ"
        case .jpx:      return "JPX"
        case .sse:      return "SSE"
        case .szse:     return "SZSE"
        case .euronext: return "EURONEXT"
        case .fwb:      return "FWB"
        case .nse:      return "NSE"
        }
    }
}

// MARK: - 데이터 기준(as-of) 분류

/// 헤더 기준시간 라벨을 가르는 데이터 형태. 앱 `Market.dataBasis`를 위젯용으로 미러한 것.
/// (위젯은 exchangeKey 문자열만 들고 있어 enum이 아닌 키로 분기한다.)
enum WidgetDataBasis {
    case realtime    // 실시간 quote 스케일링 — NASDAQ/NYSE/EURONEXT/FWB → 시각 표시
    case eodDated    // 거래일 종가 기준 — KOSPI/KOSDAQ(basDt)·SSE/SZSE/NSE(asOf) → "종가"
    case reportedCap // 제공사 보고 시가총액(일별 주가 미반영) — JPX → "기준"(종가 미표기)

    static func of(_ exchangeKey: String) -> WidgetDataBasis {
        switch exchangeKey {
        case "jpx":                                      return .reportedCap
        case "kospi", "kosdaq", "sse", "szse", "nse":    return .eodDated
        default:                                         return .realtime
        }
    }
}

// MARK: - 통화 단위 선택

enum WidgetCurrencyChoice: String, AppEnum {
    case usd, krw, jpy, cny, eur

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "통화 단위" }
    static var caseDisplayRepresentations: [WidgetCurrencyChoice: DisplayRepresentation] {
        [
            .usd: "$ 달러",
            .krw: "₩ 원",
            .jpy: "¥ 엔",
            .cny: "元 위안",
            .eur: "€ 유로",
        ]
    }

    var currency: Currency {
        switch self {
        case .usd: return .usd
        case .krw: return .krw
        case .jpy: return .jpy
        case .cny: return .cny
        case .eur: return .eur
        }
    }
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
