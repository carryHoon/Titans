//
//  SurFinModels.swift
//  Titans
//
//  ContentView.swift에서 분리한 도메인/응답 DTO 모델. 동작 동일 — SourceKit 인덱싱 부담 분산용.
//

import SwiftUI

// MARK: - Currency

/// 표시 통화. 시가총액을 이 통화 하나로 표시한다(USD 포함 전 통화가 동등한 선택지).
/// rawValue = ISO 통화 코드(백엔드 exchangeRates 맵 키·user_prefs.display_currency 저장값과 일치).
enum Currency: String, CaseIterable, Codable {
    case usd = "USD"
    case krw = "KRW"
    case jpy = "JPY"
    case cny = "CNY"
    case eur = "EUR"

    /// 저장값 파싱 실패 시 기본 통화(USD 전용 = 순수 달러 경험).
    static func from(_ code: String?) -> Currency {
        guard let code, let c = Currency(rawValue: code.uppercased()) else { return .usd }
        return c
    }

    /// 통화 기호(온보딩·메뉴 카드 등에 표시되는 짧은 기호).
    var toggleSymbol: String {
        switch self {
        case .usd: return "$"
        case .krw: return "원"
        case .jpy: return "¥"
        case .cny: return "元"
        case .eur: return "€"
        }
    }

    /// 온보딩 통화 선택 카드의 제목(통화명 + 코드).
    var onboardingLabel: String {
        switch self {
        case .usd: return "달러"
        case .krw: return "원"
        case .jpy: return "엔"
        case .cny: return "위안"
        case .eur: return "유로"
        }
    }

    /// 온보딩 카드 우측 보조 표기(국가/설명).
    var onboardingSubtitle: String {
        switch self {
        case .usd: return "USD · 미국 달러"
        case .krw: return "KRW · 대한민국"
        case .jpy: return "JPY · 일본"
        case .cny: return "CNY · 중국"
        case .eur: return "EUR · 유로존"
        }
    }

    /// 동아시아 만진법(1兆=10¹², 1億=10⁸) 표기를 쓰는 통화인지. false면 서구식 T/B/M.
    var usesEastAsianUnits: Bool {
        switch self {
        case .krw, .jpy, .cny: return true
        case .usd, .eur:       return false
        }
    }

    /// 동아시아 통화의 (조 단위 접미사, 억 단위 접미사). 비동아시아는 사용 안 함.
    var eastAsianUnitWords: (trillion: String, hundredMillion: String) {
        switch self {
        case .krw: return ("조원", "억원")
        case .jpy: return ("조엔", "억엔")
        case .cny: return ("조위안", "억위안")
        default:   return ("", "")
        }
    }

    /// 서구식 통화의 금액 앞 기호($/€). 동아시아는 사용 안 함.
    var westernSymbol: String {
        switch self {
        case .eur: return "€"
        default:   return "$"
        }
    }
}

// MARK: - Market (거래소 필터)

/// 거래소 카테고리 필터. 새 거래소는 case만 추가하면 칩이 자동 확장됨.
enum Market: String, CaseIterable, Identifiable {
    // 선언 순서 = 홈 화면 필터 칩·스와이프 페이지 순서(둘 다 allCases를 따름).
    // 활성 거래소를 앞에 모으고(…fwb → nse), 준비 중(comingSoon)인 거래소를 뒤로 몬다.
    case all, nasdaq, nyse, kospi, kosdaq, jpx, sse, szse, euronext, fwb, nse, hkex, twse, six, tsx

    var id: String { rawValue }

    /// 칩에 표시되는 라벨
    var title: String {
        switch self {
        case .all:      return "ALL"
        case .nasdaq:   return "NASDAQ"
        case .nyse:     return "NYSE"
        case .kospi:    return "KOSPI"
        case .kosdaq:   return "KOSDAQ"
        case .jpx:      return "JPX"
        case .sse:      return "SSE"
        case .szse:     return "SZSE"
        case .euronext: return "EURONEXT"
        case .fwb:      return "FWB"
        case .hkex:     return "HKEX"
        case .twse:     return "TWSE"
        case .six:      return "SIX"
        case .tsx:      return "TSX"
        case .nse:      return "NSE"
        }
    }

    /// 1차 출시(v1) 범위 = US(NASDAQ/NYSE) + 한국(KOSPI/KOSDAQ)만. 나머지 섹션은
    /// "준비 중" 플레이스홀더(ComingSoonView)로 표시하고 데이터 조회를 하지 않는다.
    /// 상업용 데이터 소스 연동 시 해당 case를 false로 내리고 apiExchangeParam만 열어주면 됨.
    var comingSoon: Bool {
        switch self {
        case .all, .nasdaq, .nyse, .kospi, .kosdaq, .jpx, .euronext, .fwb, .sse, .szse, .nse: return false
        default:                                                                              return true
        }
    }

    /// 거래소 소속 국가 국기 이미지명 (Assets.xcassets 기준)
    var flagImageName: String {
        switch self {
        case .all:              return "flag_global"
        case .nasdaq, .nyse:   return "flag_us"
        case .kospi, .kosdaq:  return "flag_kr"
        case .jpx:             return "flag_jp"
        case .sse, .szse:      return "flag_cn"
        case .euronext:        return "flag_eu"
        case .fwb:             return "flag_de"
        case .hkex:            return "flag_hk"
        case .twse:            return "flag_tw"
        case .six:             return "flag_ch"
        case .tsx:             return "flag_ca"
        case .nse:             return "flag_in"
        }
    }

    /// 백엔드 전용 피드(`?exchange=`)를 가진 거래소만 값을 반환.
    /// nil이면 ALL 통합 피드를 클라이언트에서 필터링해 사용.
    var apiExchangeParam: String? {
        switch self {
        case .nasdaq: return "nasdaq"
        case .nyse:   return "nyse"
        case .kospi:  return "kospi"
        case .kosdaq: return "kosdaq"
        case .jpx:      return "jpx"        // TD /statistics EOD 스냅샷. 시총만·라이브 아님.
        case .euronext: return "euronext"   // 파리/암스=라이브(quote), 밀라노=EOD. EUR→USD 환산.
        case .sse:      return "sse"        // 상하이 A주. TD /statistics(CNY) base + quote 스케일링. CNY→USD 환산.
        case .szse:     return "szse"       // 선전 A주. 위와 동일.
        case .nse:      return "nse"        // 인도 NSE. TD /statistics(INR) base + quote 스케일링. INR→USD 환산.
        case .fwb:      return "fwb"      // 독일 FWB. TD /statistics(EUR) base + quote 스케일링. EUR→USD 환산.
        // hkex/twse 는 아직 범위 밖(comingSoon)이라 백엔드 피드가 없다.
        // 상업용 데이터 소스 확장 시 백엔드 핸들러와 함께 여기서 개방하면 별도 UI 변경 없이 활성화된다.
        default:        return nil
        }
    }

    /// 홈 상단 지수 스파크라인의 `?exchange=` 값. nil이면 해당 탭에 그래프를 노출하지 않는다.
    /// v1 범위 = ALL(S&P500) + US(나스닥100/다우) + KR(코스피/코스닥). 백엔드 MARKET_CHART와 대응.
    /// (후속 거래소는 백엔드 MARKET_CHART에 매핑을 추가하고 여기에 case만 열면 그래프가 확장된다.)
    var chartParam: String? {
        switch self {
        case .all:    return "all"
        case .nasdaq: return "nasdaq"
        case .nyse:   return "nyse"
        case .kospi:  return "kospi"
        case .kosdaq: return "kosdaq"
        // 해외 거래소 지수(대표 ETF 1일봉). 백엔드 MARKET_CHART와 1:1 대응.
        case .jpx:      return "jpx"        // MSCI 일본(EWJ)
        case .euronext: return "euronext"   // 유로 스톡스 50(EXW1)
        case .sse:      return "sse"        // CSI 300(ASHR)
        case .szse:     return "szse"       // 차이넥스트(CNXT)
        case .nse:      return "nse"        // 니프티 50(INDY)
        case .fwb:      return "fwb"        // DAX(EXS1)
        default:      return nil
        }
    }

    // MARK: 데이터 기준(as-of) 분류

    enum DataBasis {
        case realtime    // 발행주식수 × 실시간 주가 (US·EU 라이브 quote 스케일링)
        case eodDated    // 거래일 종가 기준 EOD — 기준일(basDt/asOf)을 함께 표기
        case reportedCap // 제공사 보고 시가총액(펀더멘털) — 일별 주가 미반영. JPX 전용.
        case comingSoon  // 데이터 미제공(준비 중)
    }

    /// 상단 기준 섹션 문구를 가르는 데이터 형태.
    ///  · realtime: 장중 실시간 시총(마감 후 기준값 갱신) — nasdaq/nyse/euronext/fwb.
    ///  · eodDated: 거래일 종가 기준 시총 — kospi/kosdaq(basDt) · sse/szse/nse(asOf, 지연 quote로 일별 변동 반영).
    ///  · reportedCap: JPX — TD가 가격 피드를 안 줘 /statistics 보고 시가총액만 사용. 일별 주가 변동이
    ///    반영되지 않으므로 "종가 기준"으로 표기하지 않는다(상업용 앱 정보 정확성).
    /// (ALL은 US 실시간 + KR 종가 혼합이라 MarketStatusView가 별도 문구로 직접 처리한다.)
    var dataBasis: DataBasis {
        if comingSoon { return .comingSoon }
        switch self {
        case .jpx:                              return .reportedCap
        case .kospi, .kosdaq, .sse, .szse, .nse: return .eodDated
        default:                                 return .realtime
        }
    }

    /// ⓘ 상세 시트에 표시할 거래소별 정적 설명. comingSoon(hkex/twse)은 nil → 버튼 미노출.
    var info: MarketInfo? {
        switch self {
        case .all:
            return MarketInfo(
                fullName: "전체 시장(Global Market)",
                basis: "전 세계 시가총액 상위 기업을 한눈에 볼 수 있어요. 현재 미국(NASDAQ·NYSE) 실시간 시가총액과 한국(KOSPI·KOSDAQ) 종가 시가총액을 함께 모으고, 여기에 사우디 아람코처럼 글로벌 시총 최상위권 종목을 더해 순위를 보여줘요. 지원 범위는 앞으로 거래소를 넓혀가며 계속 확장할 거예요.",
                schedule: "미국 종목은 실시간, 한국 종목은 영업일 종가 기준이에요. 사우디 아람코는 사우디 증시(Tadawul)의 영업일 종가 기준이에요.",
                officialName: nil, officialURLString: nil,
                chartNote: "미국 S&P 500 지수를 추종하는 대표 ETF(SPY)예요. 글로벌 증시 동향을 가장 잘 보여주는 지표로, 최근 30 거래일 종가 기준으로 업데이트돼요.")
        case .nasdaq:
            return MarketInfo(
                fullName: "나스닥(Nasdaq Stock Market)",
                basis: "각 종목의 발행주식수에 실시간 주가를 곱해 산출한 실시간 시가총액이에요.",
                schedule: "미국 정규장 시간에는 실시간으로, 장 마감(한국시간 새벽) 후 기준값이 갱신돼요.",
                officialName: "nasdaq.com", officialURLString: "https://www.nasdaq.com",
                chartNote: "나스닥 100 지수를 추종하는 대표 ETF(QQQ)예요. 나스닥 동향을 가장 잘 보여주는 지표로, 최근 30 거래일 종가 기준으로 업데이트돼요.")
        case .nyse:
            return MarketInfo(
                fullName: "뉴욕 증권거래소(New York Stock Exchange)",
                basis: "각 종목의 발행주식수에 실시간 주가를 곱해 산출한 실시간 시가총액이에요.",
                schedule: "미국 정규장 시간에는 실시간으로, 장 마감(한국시간 새벽) 후 기준값이 갱신돼요.",
                officialName: "nyse.com", officialURLString: "https://www.nyse.com",
                chartNote: "다우존스 산업평균지수(DJIA)를 추종하는 대표 ETF(DIA)예요. NYSE 동향을 가장 잘 보여주는 지표로, 최근 30 거래일 종가 기준으로 업데이트돼요.")
        case .kospi:
            return MarketInfo(
                fullName: "유가증권시장(Korea Composite Stock Price Index)",
                basis: "한국거래소가 발표하는 공식 종가 기준 시가총액이에요.",
                schedule: "영업일 오후(한국시간 13시경)에 직전 거래일 종가 데이터가 갱신돼요.",
                officialName: "data.krx.co.kr", officialURLString: "http://data.krx.co.kr",
                chartNote: "코스피 지수의 최근 30 거래일 종가 흐름이에요.")
        case .kosdaq:
            return MarketInfo(
                fullName: "코스닥시장(Korea Securities Dealers Automated Quotations)",
                basis: "한국거래소가 발표하는 공식 종가 기준 시가총액이에요.",
                schedule: "영업일 오후(한국시간 13시경)에 직전 거래일 종가 데이터가 갱신돼요.",
                officialName: "data.krx.co.kr", officialURLString: "http://data.krx.co.kr",
                chartNote: "코스닥 지수의 최근 30 거래일 종가(EOD) 흐름이에요.")
        case .jpx:
            return MarketInfo(
                fullName: "일본 거래소 그룹(Japan Exchange Group)",
                basis: "도쿄 증권거래소 상장 기업의 시가총액이에요. 데이터 제공사가 보고하는 발행주식수 기반 시가총액 값을 사용하며, 일간 주가 변동은 실시간으로 반영되지 않아요. 순위는 최신 기준 시가총액 크기로 정렬돼요.",
                schedule: "매 거래일(한국시간 오후) 데이터를 확인해 갱신하지만, 제공사 시가총액 지표 특성상 값이 매일 바뀌지 않을 수 있어요.",
                officialName: "jpx.co.jp", officialURLString: "https://www.jpx.co.jp",
                chartNote: "일본 증시를 대표하는 MSCI 일본 지수를 추종하는 대표 ETF(EWJ)의 최근 30 거래일 종가 흐름이에요.")
        case .sse:
            return MarketInfo(
                fullName: "상하이 증권거래소(Shanghai Stock Exchange)",
                basis: "상하이 A주 종가 기준 시가총액이에요.",
                schedule: "중국 A주 마감 후 매 거래일(한국시간 저녁) 갱신돼요.",
                officialName: "english.sse.com.cn", officialURLString: "http://english.sse.com.cn",
                chartNote: "중국 본토 A주 대형주를 대표하는 CSI 300 지수를 추종하는 대표 ETF(ASHR)의 최근 30 거래일 종가 흐름이에요.")
        case .szse:
            return MarketInfo(
                fullName: "선전 증권거래소(Shenzhen Stock Exchange)",
                basis: "선전 A주 종가 기준 시가총액이에요.",
                schedule: "중국 A주 마감 후 매 거래일(한국시간 저녁) 갱신돼요.",
                officialName: "szse.cn", officialURLString: "https://www.szse.cn/English/",
                chartNote: "선전 증시의 성장기업 시장을 대표하는 차이넥스트(ChiNext) 지수를 추종하는 대표 ETF(CNXT)의 최근 30 거래일 종가 흐름이에요.")
        case .nse:
            return MarketInfo(
                fullName: "인도 국립증권거래소(National Stock Exchange of India)",
                basis: "인도 NSE 종가 기준 시가총액이에요.",
                schedule: "인도 증시 마감 후 매 거래일(한국시간 밤) 갱신돼요.",
                officialName: "nseindia.com", officialURLString: "https://www.nseindia.com",
                chartNote: "인도 NSE 대표 지수인 니프티 50을 추종하는 대표 ETF(INDY)의 최근 30 거래일 종가 흐름이에요.")
        case .euronext:
            return MarketInfo(
                fullName: "유로넥스트(Euronext)",
                basis: "파리·암스테르담 상장 종목은 실시간, 밀라노 상장 종목은 종가 기준 시가총액이에요.",
                schedule: "유럽 정규장 시간에는 실시간으로, 장 마감 후 기준값이 갱신돼요.",
                officialName: "euronext.com", officialURLString: "https://live.euronext.com",
                chartNote: "유럽 대형주를 대표하는 유로 스톡스 50 지수를 추종하는 대표 ETF(EXW1)의 최근 30 거래일 종가 흐름이에요.")
        case .fwb:
            return MarketInfo(
                fullName: "프랑크푸르트 증권거래소(Frankfurt Stock Exchange)",
                basis: "Xetra 시스템 기준 실시간 시가총액이에요.",
                schedule: "유럽 정규장 시간에는 실시간으로, 장 마감 후 기준값이 갱신돼요.",
                officialName: "boerse-frankfurt.de", officialURLString: "https://www.boerse-frankfurt.de/en",
                chartNote: "독일 증시 대표 지수인 DAX를 추종하는 대표 ETF(EXS1)의 최근 30 거래일 종가 흐름이에요.")
        case .hkex, .twse, .six, .tsx:
            return nil   // comingSoon — ⓘ 미노출
        }
    }
}

// MARK: - Market Info (거래소 데이터 기준 상세)

/// ⓘ 상세 시트에 표시할 거래소별 정적 설명. 데이터 산출 기준·갱신 주기·공식 사이트 링크를 담는다.
struct MarketInfo {
    let fullName: String              // 거래소 정식명
    let basis: String                 // 시가총액 산출 기준 설명
    let schedule: String              // 갱신 주기(한국시간 안내)
    let officialName: String?         // 공식 사이트 표시명 (없으면 링크 미노출)
    let officialURLString: String?    // 공식 홈페이지 URL 문자열
    var chartNote: String? = nil      // 홈 상단 지수 그래프 설명(어떤 지수·기간). 그래프 있는 거래소만.
}

// MARK: - Sort State

enum SortField: Equatable { case rank, name, marketCap }
enum SortOrder: Equatable { case ascending, descending }


// MARK: - Market Data

struct MarketIndex: Identifiable {
    let id: String
    let name: String
    var value: Double
    var change: Double
    var changePercent: Double
}

// MARK: - Company Data

struct Company: Identifiable {
    // ticker를 ID로 사용해 ForEach가 안정적으로 뷰를 재사용할 수 있게 함
    var id: String { ticker }
    let rank: Int
    let previousRank: Int?     // nil = 첫 로드 (비교 대상 없음)
    let name: String
    let ticker: String
    let marketCapUSD: Double   // USD 조(trillion) 단위
    let change: Double         // changePercent (%) — API의 dp 값
    let color: Color
    let domain: String?        // 백엔드(DART) 해석 홈페이지 도메인 — 큐레이션 미등록 종목 로고 폴백용

    /// Ticker 기반 상장 거래소. 미등록 종목은 필터에서 ALL에만 노출됨.
    var market: Market? { tickerMarket[ticker] }
}

// MARK: - API Response DTOs

struct APICompanyResult: Decodable {
    let rank: Int
    let previousRank: Int?     // 전일 종가 기준 순위 (US만 내려옴; KR은 basDt로 클라이언트가 계산)
    let ticker: String
    let name: String
    let color: String          // hex 문자열 e.g. "#78BB17"
    let changePercent: Double  // % change → Company.change 에 매핑
    let marketCapUSD: Double   // trillion USD
    let domain: String?        // 홈페이지 도메인(로고 폴백용) — KOSPI/KOSDAQ만 내려옴, 없으면 nil
}

struct MarketCapResponse: Decodable {
    let exchangeRate: Double?              // KRW/USD 단일 (위젯·구버전 호환)
    let exchangeRates: [String: Double]?  // 다통화 rate 맵 {"KRW":..,"JPY":..} — 구버전 응답엔 없을 수 있어 옵셔널
    let basDt: String?         // KRX 기준일("YYYYMMDD") — 코스피/코스닥만 내려옴(EOD/D-1)
    let asOf: String?          // EOD 계열(JPX/SSE/SZSE/NSE 등) 스냅샷 거래일("YYYY-MM-DD"). 없으면 nil. basDt와 별개(표시 전용, KR 순위 baseline 무관)
    let data: [APICompanyResult]
    let stale: Bool?
    let error: String?
}

struct APIIndexData: Decodable {
    let id: String
    let name: String
    let value: Double
    let change: Double
    let changePercent: Double
}

struct MarketIndexResponse: Decodable {
    let data: [APIIndexData]
    let stale: Bool?
}

// MARK: - Market Chart (거래소 지수 스파크라인)

/// 홈 상단 스파크라인 데이터. 거래소를 대변하는 지수의 최근 ~30 거래일 종가 라인.
/// (US=대표 ETF의 1일봉, KR=data.go.kr 지수 일별 종가 — 백엔드 /api/market-chart가 소유.)
struct MarketChart: Codable {
    let name: String          // 대변 지수명(나스닥 100/다우 존스/S&P 500/코스피/코스닥)
    let points: [Double]      // 오래된→최신 종가
    let changePercent: Double // 첫→마지막 종가 변화율(%)
}

struct MarketChartResponse: Decodable {
    let exchange: String
    let name: String
    let points: [Double]
    let changePercent: Double
    let stale: Bool?
    let error: String?
}

// MARK: - Company Chart (종목 시가총액 히스토리)

/// 종목 상세 화면의 시가총액 차트 데이터 포인트.
/// 시총은 통화 무관 공통값인 USD 조(trillion) 단위로 통일해 저장하고, 표시 시점에 통화 환산한다.
/// (RankSnapshotStore·Company.marketCapUSD 와 동일한 단위 규약)
struct CompanyChartPoint: Codable, Equatable {
    let date: String     // 거래일 "YYYY-MM-DD" (종가 기준)
    let capUSD: Double    // 해당 거래일 종가 기준 시가총액, trillion USD
}

/// 한 종목의 시가총액 히스토리(오래된→최신). 백엔드 `/api/company-chart`가 소유한다.
/// (KR=공공데이터포털 mrktTotAmt 시계열, US=TD /market_cap 또는 time_series×주식수 — 백엔드 책임.)
struct CompanyChart: Codable, Equatable {
    let ticker: String
    let name: String
    let points: [CompanyChartPoint]   // 오래된→최신
    /// "지수 대비 성장률" 비교선용 거래소 지수. 백엔드가 points와 날짜 정렬해 같은 길이로 내려준다.
    /// 부재(백엔드 미제공/실패) 시 nil → 앱이 결정론적 시드로 폴백. (base 미적용 원값; 앱이 100으로 리베이스)
    var indexName: String? = nil
    var indexPoints: [Double]? = nil

    /// 기간 첫→마지막 종가 시총 변화율(%). 헤더 등락 표기용. 포인트 2개 미만이면 0.
    var changePercent: Double {
        guard let first = points.first?.capUSD, first > 0, let last = points.last?.capUSD else { return 0 }
        return (last - first) / first * 100
    }
}

/// company-chart 응답의 지수 블록. points는 종목 points와 1:1 정렬(오래된→최신).
struct CompanyChartIndexDTO: Decodable {
    let name: String
    let points: [Double]
}

struct CompanyChartResponse: Decodable {
    let ticker: String
    let name: String
    let points: [CompanyChartPoint]
    let index: CompanyChartIndexDTO?
    let stale: Bool?
    let error: String?
}

// MARK: - Company Metrics (투자지표 + 배당 소식)

/// 종목 상세의 투자지표. 비율 지표라 통화 무관. 백엔드 `/api/company-metrics`가 소유한다.
/// (US/글로벌=TD /statistics, KR=소스 미연동 → supported=false)
struct CompanyMetricsData: Decodable, Equatable {
    let per: Double?          // 주가수익비율(배)
    let pbr: Double?          // 주가순자산비율(배)
    let psr: Double?          // 주가매출비율(배)
    let roePct: Double?       // 자기자본이익률(%)
    let divYieldPct: Double?  // 배당수익률(%)
}

/// 종목 배당 소식. perShare는 currency 통화 기준 연 배당금.
struct CompanyDividendData: Decodable, Equatable {
    let perShare: Double?     // 주당 연 배당금
    let yieldPct: Double?     // 배당수익률(%)
    let freqCount: Int?       // 연간 지급 횟수
    let exDate: String?       // 배당락일 "YYYY-MM-DD"
    let payDate: String?      // 지급일
}

struct CompanyMetricsResponse: Decodable, Equatable {
    let ticker: String
    let supported: Bool
    let currency: String?
    let metrics: CompanyMetricsData?
    let dividend: CompanyDividendData?
}

// MARK: - Chart Range (종목 차트 기간 선택)

/// 종목 차트 기간 세그먼트(토스 오마주: 1주 / 1달 / 3달 / 1년 / 5년 / 전체).
/// rawValue = 백엔드 `?range=` 쿼리 값이자 로컬 캐시 키 접미사.
enum ChartRange: String, CaseIterable, Identifiable {
    case w1, m1, m3, y1, y5, all

    var id: String { rawValue }

    /// 세그먼트에 표시할 짧은 라벨.
    var label: String {
        switch self {
        case .w1:  return "1주"
        case .m1:  return "1달"
        case .m3:  return "3달"
        case .y1:  return "1년"
        case .y5:  return "5년"
        case .all: return "전체"
        }
    }

    /// 대략적인 조회 기간(달력일). nil = 전체 히스토리. 백엔드 요청·시드 생성·다운샘플 기준.
    var days: Int? {
        switch self {
        case .w1:  return 7
        case .m1:  return 30
        case .m3:  return 90
        case .y1:  return 365
        case .y5:  return 365 * 5
        case .all: return nil
        }
    }
}

