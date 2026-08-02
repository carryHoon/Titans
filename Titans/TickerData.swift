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

/// 티커 → 홈페이지 도메인. logo.dev 공식 로고 요청에 사용.
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
    // NASDAQ top-100 확장 (2026-07)
    "PEP":     "pepsico.com",
    "CMCSA":   "comcast.com",
    "HON":     "honeywell.com",
    "ADP":     "adp.com",
    "VRTX":    "vrtx.com",
    "SBUX":    "starbucks.com",
    "MELI":    "mercadolibre.com",
    "PDD":     "pddholdings.com",
    "ADI":     "analog.com",
    "MDLZ":    "mondelezinternational.com",
    "REGN":    "regeneron.com",
    "APP":     "applovin.com",
    "MRVL":    "marvell.com",
    "CEG":     "constellationenergy.com",
    "CRWD":    "crowdstrike.com",
    "SNPS":    "synopsys.com",
    "CDNS":    "cadence.com",
    "MSTR":    "strategy.com",
    "NXPI":    "nxp.com",
    "FTNT":    "fortinet.com",
    "ORLY":    "oreillyauto.com",
    "ADSK":    "autodesk.com",
    "CSX":     "csx.com",
    "ABNB":    "airbnb.com",
    "MAR":     "marriott.com",
    "MCHP":    "microchip.com",
    "CTAS":    "cintas.com",
    "DASH":    "doordash.com",
    "PAYX":    "paychex.com",
    "PYPL":    "paypal.com",
    "AEP":     "aep.com",
    "ROP":     "ropertech.com",
    "FAST":    "fastenal.com",
    "KDP":     "keurigdrpepper.com",
    "DDOG":    "datadoghq.com",
    "ODFL":    "odfl.com",
    "EA":      "ea.com",
    "BKR":     "bakerhughes.com",
    "CPRT":    "copart.com",
    "EXC":     "exeloncorp.com",
    "GEHC":    "gehealthcare.com",
    "KHC":     "kraftheinzcompany.com",
    "TTWO":    "take2games.com",
    "CRWV":    "coreweave.com",
    "XEL":     "xcelenergy.com",
    "MNST":    "monsterbevcorp.com",
    "IDXX":    "idexx.com",
    "WDAY":    "workday.com",
    "FANG":    "diamondbackenergy.com",
    "TRI":     "thomsonreuters.com",
    "DXCM":    "dexcom.com",
    "MPWR":    "monolithicpower.com",
    "ROST":    "rossstores.com",
    "CCEP":    "cocacolaep.com",
    "TER":     "teradyne.com",
    "WBD":     "wbd.com",
    "PCAR":    "paccar.com",
    "FER":     "ferrovial.com",
    "SHOP":    "shopify.com",
    "WDC":     "westerndigital.com",
    "STX":     "seagate.com",
    "SNDK":    "sandisk.com",
    "LITE":    "lumentum.com",
    "ALAB":    "asteralabs.com",
    "NBIS":    "nebius.com",
    "RKLB":    "rocketlabusa.com",
    "AXON":    "axon.com",
    "ALNY":    "alnylam.com",
    "COIN":    "coinbase.com",
    "HOOD":    "robinhood.com",
    "TEAM":    "atlassian.com",
    "ZS":      "zscaler.com",
    "TTD":     "thetradedesk.com",
    "CTSH":    "cognizant.com",
    "IBKR":    "interactivebrokers.com",
    "NDAQ":    "nasdaq.com",
    "BIDU":    "baidu.com",
    "JD":      "jd.com",
    "NTES":    "neteasegames.com",
    // NYSE top-100 확장 (2026-07)
    "IBM":     "ibm.com",
    "NOW":     "servicenow.com",
    "UBER":    "uber.com",
    "DIS":     "disney.com",
    "VZ":      "verizon.com",
    "T":       "att.com",
    "SAP":     "sap.com",
    "BABA":    "alibabagroup.com",
    "TMO":     "thermofisher.com",
    "ABT":     "abbott.com",
    "DHR":     "danaher.com",
    "MDT":     "medtronic.com",
    "PFE":     "pfizer.com",
    "BMY":     "bms.com",
    "CVS":     "cvshealth.com",
    "CI":      "cigna.com",
    "ELV":     "elevancehealth.com",
    "ZTS":     "zoetis.com",
    "BSX":     "bostonscientific.com",
    "SYK":     "stryker.com",
    "HCA":     "hcahealthcare.com",
    "NVO":     "novonordisk.com",
    "BLK":     "blackrock.com",
    "SPGI":    "spglobal.com",
    "BX":      "blackstone.com",
    "SCHW":    "schwab.com",
    "ICE":     "theice.com",
    "CB":      "chubb.com",
    "PGR":     "progressive.com",
    "MMC":     "marshmclennan.com",
    "AON":     "aon.com",
    "MET":     "metlife.com",
    "PRU":     "prudential.com",
    "AIG":     "aig.com",
    "COF":     "capitalone.com",
    "USB":     "usbank.com",
    "PNC":     "pnc.com",
    "TFC":     "truist.com",
    "BK":      "bny.com",
    "KKR":     "kkr.com",
    "APO":     "apollo.com",
    "NKE":     "nike.com",
    "LOW":     "lowes.com",
    "MO":      "altria.com",
    "TGT":     "target.com",
    "CL":      "colgatepalmolive.com",
    "TJX":     "tjx.com",
    "UNP":     "up.com",
    "UPS":     "ups.com",
    "BA":      "boeing.com",
    "LMT":     "lockheedmartin.com",
    "DE":      "deere.com",
    "GD":      "gd.com",
    "MMM":     "3m.com",
    "ETN":     "eaton.com",
    "EMR":     "emerson.com",
    "NOC":     "northropgrumman.com",
    "ITW":     "itw.com",
    "NSC":     "norfolksouthern.com",
    "COP":     "conocophillips.com",
    "SLB":     "slb.com",
    "EOG":     "eogresources.com",
    "WMB":     "williams.com",
    "OXY":     "oxy.com",
    "KMI":     "kindermorgan.com",
    "PSX":     "phillips66.com",
    "MPC":     "marathonpetroleum.com",
    "VLO":     "valero.com",
    "SHW":     "sherwin-williams.com",
    "APD":     "airproducts.com",
    "FCX":     "fcx.com",
    "ECL":     "ecolab.com",
    "NEM":     "newmont.com",
    "NEE":     "nexteraenergy.com",
    "SO":      "southerncompany.com",
    "DUK":     "duke-energy.com",
    "PLD":     "prologis.com",
    "AMT":     "americantower.com",
    "TM":      "toyota.com",
    "SHEL":    "shell.com",
    "TTE":     "totalenergies.com",
    "UL":      "unilever.com",
    "SONY":    "sony.com",
    "BUD":     "ab-inbev.com",
    "BHP":     "bhp.com",
    "RIO":     "riotinto.com",
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

    // KOSPI — 추가 종목
    "000100.KS":  "logo_000100KS",  // 유한양행
    "000150.KS":  "logo_000150KS",  // 두산
    "000270.KS":  "logo_000270KS",
    "000500.KS":  "logo_000500KS",  // 가온전선
    "000660.KS":  "logo_000660KS",  // SK Hynix
    "000720.KS":  "logo_000720KS",  // 현대건설
    "000810.KS":  "logo_000810KS",  // 삼성화재
    "000880.KS":  "logo_000880KS",  // 한화
    "003230.KS":  "logo_003230KS",  // 삼양식품
    "003490.KS":  "logo_003490KS",  // 대한항공
    "003550.KS":  "logo_373220KS",  // LG
    "003670.KS":  "logo_003670KS",  // 포스코퓨처엠
    "004170.KS":  "logo_004170KS",  // 신세계
    "005380.KS":  "logo_005380KS",  // Hyundai Motor
    "005385.KS":  "logo_005385KS",  // 현대차우
    "005387.KS":  "logo_005387KS",  // 현대차2우B
    "005490.KS":  "logo_005490KS",  // POSCO홀딩스
    "005830.KS":  "logo_005830KS",  // DB손해보험
    "005930.KS":  "logo_005930KS",
    "005935.KS":  "logo_005935KS",  // 삼성전자우
    "005940.KS":  "logo_005940KS",  // NH투자증권
    "006260.KS":  "logo_006260KS",  // LS
    "006400.KS":  "logo_006400KS",
    "006800.KS":  "logo_006800KS",  // 미래에셋증권
    "007660.KS":  "logo_007660KS",  // 이수페타시스
    "009150.KS":  "logo_009150KS",  // Samsung EM
    "009540.KS":  "logo_009540KS",  // HD한국조선해양
    "009830.KS":  "logo_009830KS",  // 한화솔루션
    "010120.KS":  "logo_010120KS",  // LS Electric
    "010130.KS":  "logo_010130KS",  // 고려아연
    "010140.KS":  "logo_010140KS",  // 삼성중공업
    "010950.KS":  "logo_010950KS",  // S-Oil
    "011070.KS":  "logo_011070KS",  // LG이노텍
    "011200.KS":  "logo_011200KS",  // HMM
    "012330.KS":  "logo_012330KS",
    "012450.KS":  "logo_012450KS",  // Hanwha Aero.
    "0126Z0.KS":  "logo_0126Z0KS",  // 삼성에피스홀딩스
    "015760.KS":  "logo_015760KS",  // 한국전력
    "016360.KS":  "logo_016360KS",  // 삼성증권
    "017670.KS":  "logo_017670KS",  // SK텔레콤
    "018260.KS":  "logo_018260KS",  // 삼성SDS
    "021240.KS":  "logo_021240KS",  // 코웨이
    "024110.KS":  "logo_024110KS",  // 기업은행
    "028050.KS":  "logo_028050KS",  // 삼성E&A
    "028260.KS":  "logo_028260KS",
    "029780.KS":  "logo_029780KS",  // 삼성카드
    "030200.KS":  "logo_030200KS",  // KT
    "032640.KS":  "logo_032640KS",  // LG유플러스
    "032830.KS":  "logo_032830KS",
    "033780.KS":  "logo_033780KS",  // KT&G
    "034020.KS":  "logo_034020KS",
    "034220.KS":  "logo_034220KS",  // LG디스플레이
    "034730.KS":  "logo_034730KS",
    "035420.KS":  "logo_035420KS",  // 네이버
    "035720.KS":  "logo_035720KS",  // 카카오
    "036570.KS":  "logo_036570KS",  // NC
    "039490.KS":  "logo_039490KS",  // 키움증권
    "042660.KS":  "logo_042660KS",  // 한화오션
    "042700.KS":  "logo_042700KS",  // 한미반도체
    "047040.KS":  "logo_047040KS",  // 대우건설
    "047050.KS":  "logo_047050KS",  // 포스코인터네셔널
    "047810.KS":  "logo_047810KS",  // 한국항공우주
    "051910.KS":  "logo_373220KS",  // LG화학
    "051900.KS":  "logo_051900KS",  // LG생활건강
    "055550.KS":  "logo_055550KS",  // Shinhan Fin.
    "066570.KS":  "logo_066570KS",  // LG전자
    "064350.KS":  "logo_064350KS",  // 현대로템
    "064400.KS":  "logo_373220KS",  // LG씨엔에스
    "068270.KS":  "logo_068270KS",  // Celltrion
    "071050.KS":  "logo_071050KS",  // 한국금융지주
    "078930.KS":  "logo_078930KS",  // GS
    "086280.KS":  "logo_086280KS",  // 현대글로비스
    "088980.KS":  "logo_088980KS",  // 맥쿼리인프라
    "090430.KS":  "logo_090430KS",  // 아모레퍼시픽
    "096770.KS":  "logo_096770KS",  // SK이노베이션
    "105560.KS":  "logo_105560KS",
    "128940.KS":  "logo_128940KS",  // 한미약품
    "138040.KS":  "logo_138040KS",  // 메리츠금융지주
    "138930.KS":  "logo_138930KS",  // BNK금융지주
    "161390.KS":  "logo_161390KS",  // 한국타이어앤테크놀로지
    "175330.KS":  "logo_175330KS",  // JB금융지주
    "180640.KS":  "logo_180640KS",  // 한진칼
    "207940.KS":  "logo_207940KS",
    "259960.KS":  "logo_259960KS",  // 크래프톤
    "267250.KS":  "logo_267250KS",  // HD현대
    "267260.KS":  "logo_267260KS",  // HD현대일렉트릭
    "267270.KS":  "logo_267270KS",  // HD건설기계
    "271560.KS":  "logo_271560KS",  // 오리온
    "272210.KS":  "logo_272210KS",  // 한화시스템
    "278470.KS":  "logo_278470KS",  // 에이피알
    "298040.KS":  "logo_298040KS",  // 효성중공업
    "316140.KS":  "logo_316140KS",  // 우리금융지주
    "323410.KS":  "logo_323410KS",  // 카카오뱅크
    "326030.KS":  "logo_326030KS",  // SK바이오팜
    "329180.KS":  "logo_329180KS",  // HD  Hyundai HI
    "352820.KS":  "logo_352820KS",  // 하이브
    "373220.KS":  "logo_373220KS",
    "377300.KS":  "logo_377300KS",  // 카카오페이
    "402340.KS":  "logo_402340KS",
    "443060.KS":  "logo_443060KS",  // HD현대마린솔루션
    
    "000250.KQ":  "logo_000250KQ", // SamchunDang
    "0009K0.KQ":  "logo_0009K0KQ", // 에임드바이오
    "003380.KQ":  "logo_003380KQ", // 하림지주
    "005290.KQ":  "logo_005290KQ", // 동진쎄미켐
    "007390.KQ":  "logo_007390KQ", // 네이처셀
    "010170.KQ":  "logo_010170KQ", // 대한광통신
    "014620.KQ":  "logo_014620KQ", // 성광벤드
    "028300.KQ":  "logo_028300KQ", // HLB
    "030530.KQ":  "logo_030530KQ", // 원익홀딩스
    "031330.KQ":  "logo_031330KQ", // 에스에이엠티
    "031980.KQ":  "logo_031980KQ", // 피에스케이홀딩스
    "032190.KQ":  "logo_032190KQ", // 다우데이타
    "032820.KQ":  "logo_032820KQ", // 우리기술
    "035760.KQ":  "logo_035760KQ", // CJ ENM
    "035900.KQ":  "logo_035900KQ", // JYP Ent.
    "036540.KQ":  "logo_036540KQ", // SFA반도체
    "036930.KQ":  "logo_036930KQ", // Jusung Eng.
    "038500.KQ":  "logo_038500KQ", // 삼표시멘트
    "039030.KQ":  "logo_039030KQ", // EO Technics
    "039200.KQ":  "logo_039200KQ", // 오스코텍
    "041510.KQ":  "logo_041510KQ", // 에스엠
    "043260.KQ":  "logo_043260KQ", // 성호전자
    "056190.KQ":  "logo_056190KQ", // SFA
    "058470.KQ":  "logo_058470KQ", // Leeno Ind.
    "058610.KQ":  "logo_058610KQ", // 에스피지
    "060370.KQ":  "logo_060370KQ", // LS마린솔루션
    "064760.KQ":  "logo_064760KQ", // 티씨케이
    "065350.KQ":  "logo_065350KQ", // 신성델타테크
    "067310.KQ":  "logo_067310KQ", // 하나마이크론
    "068760.KQ":  "logo_068760KQ", // 셀트리온제약
    "078600.KQ":  "logo_078600KQ", // 대주전자재료
    "080220.KQ":  "logo_080220KQ", // 제주반도체
    "082920.KQ":  "logo_082920KQ", // 비츠로셀
    "083450.KQ":  "logo_083450KQ", // GST
    "083650.KQ":  "logo_083650KQ", // 비에이치아이
    "084370.KQ":  "logo_084370KQ", // 유진테크
    "085660.KQ":  "logo_085660KQ", // 차바이오텍
    "086520.KQ":  "logo_086520KQ", // Ecopro
    "086450.KQ":  "logo_086450KQ", // 동국제약
    "087010.KQ":  "logo_087010KQ", // 펩트론
    "089030.KQ":  "logo_089030KQ", // 테크윙
    "089970.KQ":  "logo_089970KQ", // 브이엠
    "090710.KQ":  "logo_090710KQ", // 휴림로봇
    "093320.KQ":  "logo_093320KQ", // 케이아이엔엑스
    "095340.KQ":  "logo_095340KQ", // ISC
    "095610.KQ":  "logo_095610KQ", // Tes
    "096530.KQ":  "logo_096530KQ", // 씨젠
    "098460.KQ":  "logo_098460KQ", // 고영
    "101490.KQ":  "logo_101490KQ", // 에스앤에스텍
    "108490.KQ":  "logo_108490KQ", // Robotis
    "122870.KQ":  "logo_122870KQ", // 와이지엔터테인먼트
    "127120.KQ":  "logo_127120KQ", // 제이에스링크
    "131290.KQ":  "logo_131290KQ", // 티에스이
    "131970.KQ":  "logo_131970KQ", // 두산테스나
    "140410.KQ":  "logo_140410KQ", // 메지온
    "141080.KQ":  "logo_141080KQ", // LigaChem Bio
    "140860.KQ":  "logo_140860KQ", // 파크시스템스
    "145020.KQ":  "logo_145020KQ", // 휴젤
    "166090.KQ":  "logo_166090KQ", // 하나머티리얼즈
    "178320.KQ":  "logo_178320KQ", // 서진시스템
    "183300.KQ":  "logo_183300KQ", // 코미코
    "195940.KQ":  "logo_195940KQ", // HK이노엔
    "196170.KQ":  "logo_196170KQ", // Alteogen
    "204270.KQ":  "logo_204270KQ", // 제이앤티씨
    "213420.KQ":  "logo_213420KQ", // 덕산네오룩스
    "214150.KQ":  "logo_214150KQ", // 클래시스
    "214370.KQ":  "logo_214370KQ", // 케어젠
    "214450.KQ":  "logo_214450KQ", // Pharma Research
    "218410.KQ":  "logo_218410KQ", // RFHIC
    "222800.KQ":  "logo_222800KQ", // Simmtech
    "226950.KQ":  "logo_226950KQ", // 올릭스
    "237690.KQ":  "logo_237690KQ", // 에스티팜
    "240810.KQ":  "logo_240810KQ", // Wonik IPS
    "241710.KQ":  "logo_241710KQ", // 코스메카코리아
    "247540.KQ":  "logo_247540KQ", // Ecopro BM
    "253450.KQ":  "logo_253450KQ", // 스튜디오드래곤
    "257720.KQ":  "logo_257720KQ", // 실리콘투
    "263750.KQ":  "logo_263750KQ", // 펄어비스
    "277810.KQ":  "logo_277810KQ", // Rainbow Robotics
    "281740.KQ":  "logo_281740KQ", // 레이크머티리얼즈
    "290650.KQ":  "logo_290650KQ", // 엘앤씨바이오
    "293490.KQ":  "logo_293490KQ", // 카카오게임즈
    "298380.KQ":  "logo_298380KQ", // ABL Bio
    "310210.KQ":  "logo_310210KQ", // 보로노이
    "319400.KQ":  "logo_319400KQ", // 현대무벡스
    "319660.KQ":  "logo_319660KQ", // PSK
    "323280.KQ":  "logo_323280KQ", // 태성
    "328130.KQ":  "logo_328130KQ", // 루닛
    "347850.KQ":  "logo_347850KQ", // 디앤디파마텍
    "347700.KQ":  "logo_347700KQ", // 스피어
    "357780.KQ":  "logo_357780KQ", // 솔브레인
    "388720.KQ":  "logo_388720KQ", // 유일로보틱스
    "403870.KQ":  "logo_403870KQ", // HPSP
    "420770.KQ":  "logo_420770KQ", // 기가비스
    "437730.KQ":  "logo_437730KQ", // 삼현
    "440110.KQ":  "logo_440110KQ", // FADU
    "458870.KQ":  "logo_458870KQ", // 씨어스
    "475830.KQ":  "logo_475830KQ", // 오름테라퓨틱
    "491000.KQ":  "logo_491000KQ", // 리브스메드
    "950160.KQ":  "logo_950160KQ", // 코오롱티슈진
]

// MARK: - Logo Display Tweaks

/// 로컬 PNG에 어두운 배경이 포함된 로고 — 표시 시 배경을 자동 제거.
let tickersNeedDarkBgRemoval: Set<String> = [
    // 단색 배경 로고는 tickerCircleBackground로 원을 채우는 방식으로 전환해 여기서 제거
]

/// 로컬 PNG에 밝은 회색/흰색 배경이 포함된 로고 — 표시 시 배경을 자동 제거.
let tickersNeedLightBgRemoval: Set<String> = [
    "138930.KS",   // BNK금융지주
    "005930.KS",   // 삼성전자
    "005935.KS",   // 삼성전자우
    "047810.KS",   // 한국항공우주
    "068270.KS",   // Celltrion
    "071050.KS",   // 한국금융지주
    "161390.KS",   // 한국타이어앤테크놀로지

    "000250.KQ",   // Samchundang
    "035900.KQ",   // JYP Ent.
    "064760.KQ",   // 티씨케이
    "068760.KQ",   // 셀트리온제약
    "108490.KQ",   // Robotis
    "141080.KQ",   // LigaChem Bio
    "140410.KQ",   // 메지온
    "178320.KQ",   // 서진시스템
    "237690.KQ",   // 에스티팜
    "290650.KQ",   // 엘앤씨바이오
    
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
    "267270.KS": CGPoint(x:  3, y:  0), // HD건설기계
    "326030.KS": CGPoint(x:  2, y:  -1),
    "443060.KS": CGPoint(x:  3, y:  0), // HD현대마린솔루션
]

/// 기본 padding(8)과 다른 로고 — 작은 값일수록 로고가 원 안에서 더 크게 표시됨.
let tickerLogoPadding: [String: CGFloat] = [
    "NFLX":      0,
    "SPCX":      2,
    "MA":        2,
    
    "000250.KQ": 2,   // Samchundang
    "028300.KQ": 0,   // HLB
    "036930.KQ": 0,   // Jusung Eng.
    "039030.KQ": 6,   // EO Technics
    "041510.KQ": 0,   // 에스엠
    "058470.KQ": 4,   // Leeno Ind.
    "068760.KQ": 0,   // 셀트리온제약
    "084370.KQ": 4,   // 유진테크
    "086520.KQ": 4,   // Ecopro
    "087010.KQ": 4,   // 펩트론
    "095340.KQ": 4,   // ISC
    "095610.KQ": -8,  // Tes
    "108490.KQ": 2,   // Robotis
    "141080.KQ": 0,   // LigaChem Bio
    "145020.KQ": 4,   // 휴젤
    "214150.KQ": 4,   // 클래시스
    "214370.KQ": 1,   // 케어젠
    "214450.KQ": 3,   // Pharma Research
    "222800.KQ": 4,   // Simmtech
    "226950.KQ": -1,  // 올릭스
    "247540.KQ": 4,   // Ecopro BM
    "257720.KQ": -4,  // 실리콘투
    "277810.KQ": 0,   // Rainbow Robotics
    "298380.KQ": 6,   // ABL Bio
    "319400.KQ": 2,   // 현대무벡스
    "319660.KQ": 7,   // PSK
    "347850.KQ": 1,   // 디앤디파마텍
    "403870.KQ": -4,  // HPSP
    "440110.KQ": 0,   // FADU
    
    "000100.KS": 5,   // 유한양행
    "000660.KS": 0,   // SK Hynix
    "000150.KS": 3,   // 두산
    "000270.KS": 0,   // Kia
    "000720.KS": 2,   // 현대건설
    "003230.KS": 7,   // 삼양식품
    "003490.KS": 0,   // 대한항공
    "003670.KS": 4,   // 포스코퓨처엠
    "005380.KS": 6,   // Hyundai Motor
    "005385.KS": 6,   // 현대차우
    "005387.KS": 6,   // 현대차2우B
    "005490.KS": 4,   // POSCO홀딩스
    "005830.KS": 2,   // DB손해보험
    "005930.KS": 6,   // Samsung Elec.
    "005935.KS": 6,   // 삼성전자우
    "005940.KS": 6,   // NH투자증권
    "006260.KS": 0,   // LS
    "006400.KS": 0,   // Samsung SDI
    "006800.KS": 2,   // 미래에셋증권
    "009150.KS": 0,   // Samsung EM
    "010120.KS": 4,   // LS ELECTRIC
    "010130.KS": -2,  // 고려아연
    "010140.KS": 0,   // 삼성중공업
    "010950.KS": 2,   // S-Oil
    "011200.KS": 0,   // HMM
    "012330.KS": 2,
    "0126Z0.KS": 0,   // 삼성에피스홀딩스
    "018260.KS": 0,   // 삼성에스디에스
    "015760.KS": 4,   // 한국전력
    "016360.KS": 0,   // 삼성증권
    "017670.KS": 2,
    "021240.KS": 4,   // 코웨이
    "024110.KS": 4,   // 기업은행
    "028050.KS": 0,   // 삼성E&A
    "028260.KS": 0,   // Samsung C&T
    "029780.KS": 0,   // 삼성카드
    "030200.KS": 12,  // KT
    "032830.KS": 0,   // Samsung Life
    "033780.KS": 4,   // KT&G
    "034020.KS": 2,
    "035420.KS": 0,   // 네이버
    "035720.KS": 0,   // 카카오
    "036570.KS": 8,   // NC
    "039490.KS": 12,  // 키움증권
    "042700.KS": 4,   // 한미반도체
    "047040.KS": 0,   // 대우건설
    "047050.KS": 4,   // 포스코인터네셔널
    "047810.KS": 0,   // 한국항공우주
    "064350.KS": 4,   // 현대로템
    "068270.KS": 0,   // Celltrion
    "071050.KS": 4,   // 한국금융지주
    "078930.KS": -16, // GS
    "086280.KS": 0,   // 현대글로비스
    "090430.KS": 6,   // 아모레퍼시픽
    "105560.KS": 0,   // KB Financial
    "128940.KS": 4,   // 한미약품
    "138040.KS": -2,  // 메리츠금융지주
    "161390.KS": 0,   // 한국타이어앤테크놀로지
    "175330.KS": 0,   // JB금융지주
    "180640.KS": 6,   // 한진칼
    "207940.KS": 0,   // 삼성바이오로직스
    "241560.KS": 3,   // 두산밥캣
    "259960.KS": 4,   // 크래프톤
    "271560.KS": -2,  // 오리온
    "278470.KS": 6,   // 에이피알
    "323410.KS": 0,   // 카카오뱅크
    "352820.KS": 4,   // 하이브
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
    // 삼성 계열 — 로고 PNG가 #25279D 네이비 배경 정사각형이라 clipShape 안티앨리어싱 시 흰 원이 비침
    "006400.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성SDI
    "009150.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // Samsung EM
    "010140.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성중공업
    "016360.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성증권
    "018260.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성SDS
    "0126Z0.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성에피스홀딩스
    "028050.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성E&A
    "028260.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // Samsung C&T
    "029780.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성카드
    "032830.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성생명
    "000270.KS": Color(red: 0.02,  green: 0.078, blue: 0.122), // Kia — dark navy #05141F
    "035420.KS": Color(red: 0.012, green: 0.780, blue: 0.353), // 네이버 — green #03C75A
    "105560.KS": Color(red: 0.969, green: 0.678, blue: 0.0),   // KB Financial — yellow #F7AD00
    "207940.KS": Color(red: 0.0,   green: 0.082, blue: 0.294), // 삼성바이오로직스 — dark navy #001549
    "035720.KS": Color(red: 1.0,   green: 0.804, blue: 0.0),   // 카카오 — yellow #FFCD00
    "377300.KS": Color(red: 1.0,   green: 0.804, blue: 0.0),   // 카카오페이 — yellow #FFCD00
]

/// 로고 원 타일 크기(pt). 전체 로고 크기를 바꾸려면 이 값만 수정.
let logoTileSize: CGFloat = 50
