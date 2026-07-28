//
//  TickerData.swift
//  Titans
//
//  정적 티커 조회 테이블. 신규 종목 추가 시 이 파일만 수정하면 됨.
//

import SwiftUI

// MARK: - Ticker → Market

/// 티커 → 상장 거래소 매핑. 미등록 종목은 필터에서 ALL에만 노출됨.
let tickerMarket: [String: Market] = [
    // NASDAQ
    "NVDA": .nasdaq, "AAPL": .nasdaq, "MSFT": .nasdaq, "GOOGL": .nasdaq,
    "AMZN": .nasdaq, "META": .nasdaq, "TSLA": .nasdaq, "AVGO": .nasdaq,
    "COST": .nasdaq, "NFLX": .nasdaq, "PLTR": .nasdaq, "AMD": .nasdaq, "MU": .nasdaq,
    "SPCX": .nasdaq,
    "CSCO": .nasdaq, "ADBE": .nasdaq, "TMUS": .nasdaq, "INTU": .nasdaq, "QCOM": .nasdaq,
    "AMAT": .nasdaq, "TXN": .nasdaq, "AMGN": .nasdaq, "ISRG": .nasdaq, "BKNG": .nasdaq,
    "GILD": .nasdaq,
    "INTC": .nasdaq, "LRCX": .nasdaq, "ARM": .nasdaq, "KLAC": .nasdaq, "PANW": .nasdaq,
    "LIN": .nasdaq, "ASML": .nasdaq,
    // Walmart는 Finnhub·나스닥 공식 모두 NASDAQ으로 분류
    "WMT": .nasdaq,
    // NYSE
    "BRK.B": .nyse, "JPM": .nyse, "TSM": .nyse, "LLY": .nyse,
    "V": .nyse, "ORCL": .nyse, "XOM": .nyse, "MA": .nyse, "UNH": .nyse,
    "JNJ": .nyse, "HD": .nyse, "PG": .nyse, "ABBV": .nyse, "KO": .nyse,
    "BAC": .nyse, "CVX": .nyse, "CRM": .nyse, "WFC": .nyse, "MRK": .nyse,
    "ACN": .nyse, "MCD": .nyse,
    "CAT": .nyse, "GE": .nyse, "MS": .nyse, "GS": .nyse, "PM": .nyse,
    "RTX": .nyse, "AXP": .nyse, "C": .nyse, "HSBC": .nyse,
    // KOSPI (KRX)
    "005930.KS": .kospi, "000660.KS": .kospi, "005935.KS": .kospi,
]

// MARK: - Ticker → Domain (logo.dev)

/// 티커 → 홈페이지 도메인. logo.dev 로고 요청 및 파비콘 폴백에 사용.
/// 신규 종목은 도메인만 추가하면 로고 파이프라인이 자동으로 동작함.
/// KR 종목 도메인은 백엔드(DART)가 내려주므로 여기에 등록 불필요.
let tickerDomain: [String: String] = [
    "NVDA":    "nvidia.com",
    "AAPL":    "apple.com",
    "MSFT":    "microsoft.com",
    "GOOGL":   "google.com",
    "AMZN":    "amazon.com",
    "META":    "meta.com",
    "TSLA":    "tesla.com",
    "BRK.B":   "berkshirehathaway.com",
    "AVGO":    "broadcom.com",
    "JPM":     "jpmorganchase.com",
    "TSM":     "tsmc.com",
    "LLY":     "lilly.com",
    "WMT":     "walmart.com",
    "V":       "visa.com",
    "ORCL":    "oracle.com",
    "XOM":     "exxonmobil.com",
    "MA":      "mastercard.com",
    "COST":    "costco.com",
    "NFLX":    "netflix.com",
    "UNH":     "unitedhealthgroup.com",
    "PLTR":    "palantir.com",
    "SPCX":    "spacex.com",
    "AMD":     "amd.com",
    "MU":      "micron.com",
    // 추가 NASDAQ 종목
    "CSCO":    "cisco.com",
    "ADBE":    "adobe.com",
    "TMUS":    "t-mobile.com",
    "INTU":    "intuit.com",
    "QCOM":    "qualcomm.com",
    "AMAT":    "appliedmaterials.com",
    "TXN":     "ti.com",
    "AMGN":    "amgen.com",
    "ISRG":    "intuitive.com",
    "BKNG":    "bookingholdings.com",
    "GILD":    "gilead.com",
    // 추가 NYSE 종목
    "JNJ":     "jnj.com",
    "HD":      "homedepot.com",
    "PG":      "pg.com",
    "ABBV":    "abbvie.com",
    "KO":      "coca-cola.com",
    "BAC":     "bankofamerica.com",
    "CVX":     "chevron.com",
    "CRM":     "salesforce.com",
    "WFC":     "wellsfargo.com",
    "MRK":     "merck.com",
    "ACN":     "accenture.com",
    "MCD":     "mcdonalds.com",
    // 추가 NASDAQ 종목 (시총 상위 유니버스 확장)
    "INTC":    "intel.com",
    "LRCX":    "lamresearch.com",
    "ARM":     "arm.com",
    "KLAC":    "kla.com",
    "PANW":    "paloaltonetworks.com",
    "LIN":     "linde.com",
    "ASML":    "asml.com",
    // 추가 NYSE 종목 (시총 상위 유니버스 확장)
    "CAT":     "caterpillar.com",
    "GE":      "geaerospace.com",
    "MS":      "morganstanley.com",
    "GS":      "goldmansachs.com",
    "PM":      "pmi.com",
    "RTX":     "rtx.com",
    "AXP":     "americanexpress.com",
    "C":       "citi.com",
    "HSBC":    "hsbc.com",
    "2222.SR": "aramco.com",
    // KRX (Korea) — KOSPI
    "005930.KS": "samsung.com",
    "000660.KS": "skhynix.com",
    "402340.KS": "sksquare.com",
    "009150.KS": "samsungsem.com",
    "005380.KS": "hyundai.com",
    "373220.KS": "lgensol.com",
    "032830.KS": "samsunglife.com",
    "207940.KS": "samsungbiologics.com",
    "105560.KS": "kbfg.com",
    "028260.KS": "samsungcnt.com",
    "000270.KS": "kia.com",
    "055550.KS": "shinhangroup.com",
    "012330.KS": "mobis.co.kr",
    "012450.KS": "hanwhaaerospace.com",
    "034730.KS": "sk.com",
    "034020.KS": "doosanenerbility.com",
    "068270.KS": "celltrion.com",
    "086790.KS": "hanafn.com",
    "006400.KS": "samsungsdi.com",
    "000250.KQ": "scd.co.kr",
    // KRX (Korea) — KOSDAQ
    "214450.KQ": "pharmaresearch.co.kr",
    "196170.KQ": "alteogen.com",
    "247540.KQ": "ecoprobm.co.kr",
    "086520.KQ": "ecopro.co.kr",
    "277810.KQ": "rainbow-robotics.com",
    "036930.KQ": "jseng.com",
    "240810.KQ": "wonikips.com",
    "058470.KQ": "leeno.co.kr",
    "298380.KQ": "ablbio.com",
    "039030.KQ": "eotechnics.com",
    "028300.KQ": "hlb.co.kr",
    "319660.KQ": "pskinc.com",
    "222800.KQ": "simmtech.com",
    "141080.KQ": "ligachembio.com",
    "108490.KQ": "robotis.com",
    "403870.KQ": "hpsp.co.kr",
    "440110.KQ": "fadu.io",
    "095340.KQ": "iscmfg.com",
    "095610.KQ": "tes.co.kr",
]

// MARK: - Local Logo Assets

/// 티커 → Xcode Assets 이미지 이름. logo.dev보다 우선 표시됨.
/// 직접 준비한 이미지를 넣을 때: Assets.xcassets에 "logo_[티커(점 제거)]" 이름으로 추가 후 여기 등록.
let tickerLocalLogo: [String: String] = [
    "AVGO":       "logo_AVGO",
    "NVDA":       "logo_NVDA",
    "TSM":        "logo_TSM",
    "AMZN":       "logo_AMZN",
    "2222.SR":    "logo_2222SR",
    "LLY":        "logo_LLY",
    "BRK.B":      "logo_BRKB",
    "AMD":        "logo_AMD",
    "V":          "logo_V",
    "WMT":        "logo_WMT",
    "META":       "logo_META",
    "AAPL":       "logo_AAPL",
    "GOOGL":      "logo_GOOGL",
    "SPCX":       "logo_SPCX",
    "COST":       "logo_COST",
    "PLTR":       "logo_PLTR",
    "CSCO":       "logo_CSCO",
    "NFLX":       "logo_NFLX",
    "TMUS":       "logo_TMUS",
    "TXN":        "logo_TXN",
    "AMGN":       "logo_AMGN",
    "QCOM":       "logo_QCOM",
    "MSFT":       "logo_MSFT",
    "XOM":        "logo_XOM",
    "BAC":        "logo_BAC",
    "JNJ":        "logo_JNJ",
    "ABBV":       "logo_ABBV",
    "MA":         "logo_MA",
    "UNH":        "logo_UNH",
    "KO":         "logo_KO",
    "CVX":        "logo_CVX",
    "ORCL":       "logo_ORCL",
    "HD":         "logo_HD",
    "ARM":        "logo_ARM",
    "INTC":       "logo_INTC",
    "ASML":       "logo_ASML",
    "CAT":        "logo_CAT",
    "GE":         "logo_GE",
    "000250.KQ":  "logo_000250KQ",
    "028300.KQ":  "logo_028300KQ",
    "036930.KQ":  "logo_036930KQ",
    "039030.KQ":  "logo_039030KQ",
    "058470.KQ":  "logo_058470KQ",
    "086520.KQ":  "logo_086520KQ",
    "095340.KQ":  "logo_095340KQ",
    "095610.KQ":  "logo_095610KQ",
    "108490.KQ":  "logo_108490KQ",
    "141080.KQ":  "logo_141080KQ",
    "214450.KQ":  "logo_214450KQ",
    "222800.KQ":  "logo_222800KQ",
    "240810.KQ":  "logo_240810KQ",
    "247540.KQ":  "logo_247540KQ",
    "277810.KQ":  "logo_277810KQ",
    "298380.KQ":  "logo_298380KQ",
    "319660.KQ":  "logo_319660KQ",
    "403870.KQ":  "logo_403870KQ",
    "440110.KQ":  "logo_440110KQ",
    // KOSPI — 추가 종목
    "000100.KS":  "logo_000100KS",  // 유한양행
    "000150.KS":  "logo_000150KS",  // 두산
    "000270.KS":  "logo_000270KS",
    "000500.KS":  "logo_000500KS",  // 가온전선
    "000660.KS":  "logo_000660KS",  // SK Hynix
    "000810.KS":  "logo_000810KS",  // 삼성화재
    "000880.KS":  "logo_000880KS",  // 한화
    "003550.KS":  "logo_373220KS",  // LG (지주) — LG 공통 로고
    "004170.KS":  "logo_004170KS",  // 신세계
    "005380.KS":  "logo_005380KS",  // Hyundai Motor
    "005387.KS":  "logo_005387KS",  // 현대차2우B
    "005490.KS":  "logo_005490KS",  // POSCO홀딩스
    "005930.KS":  "logo_005930KS",
    "005935.KS":  "logo_005935KS",  // 삼성전자우
    "006400.KS":  "logo_006400KS",
    "006800.KS":  "logo_006800KS",  // 미래에셋증권
    "009150.KS":  "logo_009150KS",  // Samsung EM
    "009540.KS":  "logo_009540KS",  // HD한국조선해양
    "009830.KS":  "logo_009830KS",  // 한화솔루션
    "010120.KS":  "logo_010120KS",  // LS Electric
    "010950.KS":  "logo_010950KS",  // S-Oil
    "011070.KS":  "logo_011070KS",  // LG이노텍
    "012330.KS":  "logo_012330KS",
    "012450.KS":  "logo_012450KS",  // Hanwha Aero.
    "015760.KS":  "logo_015760KS",  // 한국전력
    "018260.KS":  "logo_018260KS",  // 삼성SDS
    "024110.KS":  "logo_024110KS",  // 기업은행
    "028260.KS":  "logo_028260KS",
    "032640.KS":  "logo_032640KS",  // LG유플러스
    "032830.KS":  "logo_032830KS",
    "034020.KS":  "logo_034020KS",
    "034730.KS":  "logo_034730KS",
    "035420.KS":  "logo_035420KS",  // 네이버
    "035720.KS":  "logo_035720KS",  // 카카오
    "042660.KS":  "logo_042660KS",  // 한화오션
    "047040.KS":  "logo_047040KS",  // 대우건설
    "066570.KS":  "logo_066570KS",  // LG전자
    "086280.KS":  "logo_086280KS",  // 현대글로비스
    "090430.KS":  "logo_090430KS",  // 아모레퍼시픽
    "096770.KS":  "logo_096770KS",  // SK이노베이션
    "010130.KS":  "logo_010130KS",  // 고려아연
    "010140.KS":  "logo_010140KS",  // 삼성중공업
    "011200.KS":  "logo_011200KS",  // HMM
    "017670.KS":  "logo_017670KS",  // SK텔레콤
    "051910.KS":  "logo_373220KS",  // LG화학 — LG 공통 로고
    "055550.KS":  "logo_055550KS",  // Shinhan Fin.
    "064400.KS":  "logo_373220KS",  // LG씨엔에스 — LG 공통 로고
    "064350.KS":  "logo_064350KS",  // 현대로템
    "068270.KS":  "logo_068270KS",  // Celltrion
    "105560.KS":  "logo_105560KS",
    "128940.KS":  "logo_128940KS",  // 한미약품
    "138930.KS":  "logo_138930KS",  // BNK금융지주
    "207940.KS":  "logo_207940KS",
    "267250.KS":  "logo_267250KS",  // HD현대
    "267260.KS":  "logo_267260KS",  // HD현대일렉트릭
    "272210.KS":  "logo_272210KS",  // 한화시스템
    "298040.KS":  "logo_298040KS",  // 효성중공업
    "316140.KS":  "logo_316140KS",  // 우리금융지주
    "326030.KS":  "logo_326030KS",  // SK바이오팜
    "329180.KS":  "logo_329180KS",
    "373220.KS":  "logo_373220KS",
    "377300.KS":  "logo_377300KS",  // 카카오페이
    "402340.KS":  "logo_402340KS",
]

// MARK: - Logo Display Tweaks

/// 로컬 PNG에 어두운 배경이 포함된 로고 — 표시 시 배경을 자동 제거.
let tickersNeedDarkBgRemoval: Set<String> = [
    // 단색 배경 로고는 tickerCircleBackground로 원을 채우는 방식으로 전환해 여기서 제거
]

/// 로컬 PNG에 밝은 회색/흰색 배경이 포함된 로고 — 표시 시 배경을 자동 제거.
let tickersNeedLightBgRemoval: Set<String> = [
    "138930.KS",   // BNK금융지주 — gray background
    "005930.KS",   // 삼성전자 — gray background
    "005935.KS",   // 삼성전자우 — gray background
    "047810.KS",   // 한국항공우주 — gray background
    "068270.KS",   // Celltrion — gray background
    
]

/// 로컬 PNG에 단색 컬러 배경(녹색·노랑 등)이 있는 로고 — 귀퉁이 픽셀 샘플링으로 배경색을 자동 제거.
/// (배경 제거 대신 tickerCircleBackground로 원 자체를 브랜드 색상으로 채우는 방식을 선호)
let tickersNeedColoredBgRemoval: Set<String> = []

/// SVG viewBox 편심으로 인해 시각적 중심이 어긋나는 로고 — (x, y) 오프셋으로 보정.
/// 양수 x = 오른쪽, 음수 x = 왼쪽 / 양수 y = 아래, 음수 y = 위
let tickerLogoOffset: [String: CGPoint] = [
    "NVDA": CGPoint(x: -3, y:  0),
    "AAPL": CGPoint(x: -1, y: -1),
    "MCD":  CGPoint(x:  1, y:  0),
    "TSLA": CGPoint(x:  0, y:  3),
    "009540.KS": CGPoint(x:  3, y:  0), // HD한국조선해양
    "034730.KS": CGPoint(x:  2, y:  -1),
    "096770.KS": CGPoint(x:  2, y:  -1),
    "267250.KS": CGPoint(x:  3, y:  0), // HD현대
    "267260.KS": CGPoint(x:  3, y:  0), // HD현대일렉트릭
    "326030.KS": CGPoint(x:  2, y:  -1),
]

/// 기본 padding(8)과 다른 로고 — 작은 값일수록 로고가 원 안에서 더 크게 표시됨.
let tickerLogoPadding: [String: CGFloat] = [
    "000100.KS": 5,   // 유한양행
    "000660.KS": 0,   // SK Hynix
    "034020.KS": 2,
    "012330.KS": 2,
    "017670.KS": 2,
    "086280.KS": 0,   // 현대글로비스
    "NFLX":      0,
    "SPCX":      2,
    "MA":        2,
    // 원 전체를 브랜드 색상으로 채우는 로고 — 패딩 0으로 로고가 꽉 차게
    "000270.KS": 0,   // Kia
    "005380.KS": 6,   // Hyundai Motor
    "005930.KS": 6,   // Samsung Elec.
    "005935.KS": 6,   // 삼성전자우
    "006400.KS": 0,   // Samsung SDI
    "006800.KS": 2,   // 미래에셋증권
    "009150.KS": 0,   // Samsung EM
    "010120.KS": 4,   // LS ELECTRIC
    "010130.KS": 0,   // 고려아연
    "015760.KS": 4,   // 한국전력
    "028260.KS": 0,   // Samsung C&T
    "032830.KS": 0,   // Samsung Life
    "035420.KS": 0,   // 네이버
    "068270.KS": 0,    // Celltrion
    "105560.KS": 0,   // KB Financial
    "128940.KS": 4,   // 한미약품
    "207940.KS": 0,   // 삼성바이오로직스
    "035720.KS": 0,   // 카카오
    "271560.KS": 4,   // 오리온
    "377300.KS": 0,   // 카카오페이
    "329180.KS": 0,   // HD Hyundai HI
    "402340.KS": 2,   // SK Square
]

/// 흰색 원 배경 대신 다른 색상을 사용할 티커.
let tickerCircleBackground: [String: Color] = [
    "NFLX": Color.black,
    "SPCX": Color.black,
    "CSCO": Color(red: 0.07, green: 0.18, blue: 0.36),
    "ABBV": Color(red: 0.07, green: 0.13, blue: 0.30),
    // 브랜드 배경색으로 원을 채우는 로고
    "000270.KS": Color(red: 0.02,  green: 0.078, blue: 0.122), // Kia — dark navy #05141F
    "035420.KS": Color(red: 0.012, green: 0.780, blue: 0.353), // 네이버 — green #03C75A
    "105560.KS": Color(red: 0.969, green: 0.678, blue: 0.0),   // KB Financial — yellow #F7AD00
    "207940.KS": Color(red: 0.0,   green: 0.082, blue: 0.294), // 삼성바이오로직스 — dark navy #001549
    "035720.KS": Color(red: 1.0,   green: 0.804, blue: 0.0),   // 카카오 — yellow #FFCD00
    "377300.KS": Color(red: 1.0,   green: 0.804, blue: 0.0),   // 카카오페이 — yellow #FFCD00
]

/// 로고 원 타일 크기(pt). 전체 로고 크기를 바꾸려면 이 값만 수정.
let logoTileSize: CGFloat = 50
