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
    // JPX (도쿄) — 시총 상위 큐레이션. 백엔드가 종목코드(4자리)만 티커로 내려줘 키도 코드 그대로.
    // logo.dev가 커버 못 하는 도메인은 자동으로 이니셜 폴백(무해).
    "7203":    "toyota.com",
    "8306":    "mufg.jp",
    "6758":    "sony.com",
    "6861":    "keyence.com",
    "9432":    "ntt.com",
    "6501":    "hitachi.com",
    "9984":    "softbank.jp",
    "8035":    "tel.com",
    "9983":    "fastretailing.com",
    "4063":    "shinetsu.co.jp",
    "8316":    "smfg.co.jp",
    "6098":    "recruit.co.jp",
    "8058":    "mitsubishicorp.com",
    "9433":    "kddi.com",
    "7974":    "nintendo.com",
    "4568":    "daiichisankyo.com",
    "4519":    "chugai-pharm.co.jp",
    "7267":    "honda.com",
    "8031":    "mitsui.com",
    "4502":    "takeda.com",
    "8001":    "itochu.co.jp",
    "6981":    "murata.com",
    "6902":    "denso.com",
    "7741":    "hoya.com",
    "6954":    "fanuc.co.jp",
    "8411":    "mizuhogroup.com",
    "8053":    "sumitomocorp.com",
    "8002":    "marubeni.com",
    "6594":    "nidec.com",
    "4661":    "olc.co.jp",
    "6367":    "daikin.com",
    "4452":    "kao.com",
    "7309":    "shimano.com",
    "5108":    "bridgestone.com",
    "6301":    "komatsu.com",
    "2802":    "ajinomoto.com",
    "6752":    "panasonic.com",
    "7751":    "canon.com",
    "6503":    "mitsubishielectric.com",
    "8766":    "tokiomarinehd.com",
    "8630":    "sompo-hd.com",
    "8725":    "ms-ad-hd.com",
    "4543":    "terumo.com",
    "7733":    "olympus-global.com",
    "9434":    "softbank.jp",
    "8309":    "smth.jp",
    "3382":    "7andi.com",
    "9022":    "jr-central.co.jp",
    "9020":    "jreast.co.jp",
    "5401":    "nipponsteel.com",
    "5411":    "jfe-holdings.co.jp",
    "5713":    "smm.co.jp",
    "2502":    "asahigroup-holdings.com",
    "2503":    "kirinholdings.com",
    "2914":    "jt.com",
    "6702":    "fujitsu.com",
    "6701":    "nec.com",
    "6723":    "renesas.com",
    "6857":    "advantest.com",
    "6146":    "disco.co.jp",
    "7735":    "screen.co.jp",
    "6971":    "kyocera.com",
    "6762":    "tdk.com",
    "5802":    "sei.co.jp",
    "4503":    "astellas.com",
    "4523":    "eisai.com",
    "4528":    "ono-pharma.com",
    "4578":    "otsuka.com",
    "4507":    "shionogi.com",
    "8604":    "nomura.com",
    "8601":    "daiwa-grp.jp",
    "8750":    "dai-ichi-life.co.jp",
    "8591":    "orix.co.jp",
    "9843":    "nitorihd.co.jp",
    "4901":    "fujifilm.com",
    "4612":    "nipponpaint-holdings.com",
    "8113":    "unicharm.co.jp",
    "4911":    "shiseido.com",
    "2587":    "suntory.co.jp",
    "2801":    "kikkoman.com",
    "9735":    "secom.co.jp",
    "3659":    "nexon.com",
    "7832":    "bandainamco.co.jp",
    "9766":    "konami.com",
    "9697":    "capcom.com",
    "4755":    "rakuten.com",
    "4385":    "mercari.com",
    "6869":    "sysmex.co.jp",
    "6645":    "omron.com",
    "6506":    "yaskawa-global.com",
    "6273":    "smcworld.com",
    "6326":    "kubota.com",
    "7951":    "yamaha.com",
    "9101":    "nyk.com",
    "9104":    "mol.co.jp",
    "9107":    "kline.co.jp",
    "7259":    "aisin.com",
    "9502":    "chuden.co.jp",
    "9501":    "tepco.co.jp",
    "9503":    "kepco.co.jp",
    "9531":    "tokyo-gas.co.jp",
    "1605":    "inpex.co.jp",
    "5020":    "eneos.co.jp",
    "1925":    "daiwahouse.com",
    "1928":    "sekisuihouse.co.jp",
    "9532":    "osakagas.co.jp",
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
    "2222:TADAWUL":    "logo_2222SR", // Saudi Aramco
    "ABBV":       "logo_ABBV",  // AbbVie
    "APP":        "logo_APP",   // AppLovin
    "AAPL":       "logo_AAPL",  // Apple
    "ABNB":       "logo_ABNB",  // Airbnb
    "ADI":        "logo_ADI",   // Analog Devices
    "ADP":        "logo_ADP",   // ADP
    "ADBE":       "logo_ADBE",  // Adobe
    "ADSK":       "logo_ADSK",  // Autodesk
    "AEP":        "logo_AEP",   // American Elec. Pwr
    "ASML":       "logo_ASML",  // ASML
    "AVGO":       "logo_AVGO",  // Broadcom
    "ARM":        "logo_ARM",   // Arm Holdings
    "ALAB":       "logo_ALAB",  // Astera Labs
    "AMAT":       "logo_AMAT",  // Applied Materials
    "AMZN":       "logo_AMZN",  // Amazon
    "AMGN":       "logo_AMGN",  // Amgen
    "AMD":        "logo_AMD",   // AMD
    "AXON":       "logo_AXON",  // Axon Enterprise
    "AXP":        "logo_AXP",   // American Express
    "BABA":       "logo_BABA",  // Alibaba
    "BAC":        "logo_BAC",   // Bank of America
    "BRK.B":      "logo_BRKB",  // Berkshire
    "BKNG":       "logo_BKNG",  // Booking Holdings
    "BKR":        "logo_BKR",   // Baker Hughes
    "BHP":        "logo_BHP",   // BHP
    "C":          "logo_C",     // Citigroup
    "CAT":        "logo_CAT",   // Caterpillar
    "CCEP":       "logo_CCEP",  // Coca-Cola EP
    "CDNS":       "logo_CDNS",  // Cadence
    "CSCO":       "logo_CSCO",  // Cisco
    "CSX":        "logo_CSX",   // CSX
    "CEG":        "logo_CEG",   // Constellation En.
    "CRWV":       "logo_CRWV",  // CoreWeave
    "COST":       "logo_COST",  // Costco
    "CMCSA":      "logo_CMCSA", // Comcast
    "CVX":        "logo_CVX",   // Chevron
    "CTAS":       "logo_CTAS",  // Cintas
    "CRWD":       "logo_CRWD",  // CrowdStrike
    "DASH":       "logo_DASH",  // DoorDash
    "DDOG":       "logo_DDOG",  // Datadog
    "EA":         "logo_EA",    // Electronic Arts
    "EXC":        "logo_EXC",   // Exelon
    "FANG":       "logo_FANG",  // Diamondback En.
    "FTNT":       "logo_FTNT",  // Fortinet
    "FAST":       "logo_FAST",  // Fastenal
    "FER":        "logo_FER",   // Ferrovial
    "GS":         "logo_GS",    // Goldman Sachs
    "GE":         "logo_GE",    // GE Aerospace
    "GOOGL":      "logo_GOOGL", // Alphabet
    "GILD":       "logo_GILD",  // Gilead Sciences
    "HD":         "logo_HD",    // Home Depot
    "HOOD":       "logo_HOOD",  // Robinhood
    "HON":        "logo_HON",   // Honeywell
    "HSBC":       "logo_HSBC",  // HSBC
    "IBKR":       "logo_IBKR",  // Interactive Brokers
    "IBM":        "logo_IBM",   // IBM
    "IDXX":       "logo_IDXX",  // Idexx Labs
    "ISRG":       "logo_ISRG",  // Intuitive Surgical
    "INTC":       "logo_INTC",  // Intel
    "INTU":       "logo_INTU",  // Intuit
    "JD":         "logo_JD",    // JD.com
    "JNJ":        "logo_JNJ",   // J&J
    "JPM":        "logo_JPM",   // JPMorgan
    "KLAC":       "logo_KLAC",  // KLA
    "KDP":        "logo_KDP",   // Keurig Dr Pepper
    "KO":         "logo_KO",    // Coca-Cola
    "LLY":        "logo_LLY",   // Eli Lilly
    "LIN":        "logo_LIN",   // Linde
    "LITE":       "logo_LITE",  // Lumentum
    "LRCX":       "logo_LRCX",  // Lam Research
    "MA":         "logo_MA",    // Mastercard
    "MAR":        "logo_MAR",   // Marriott
    "MCHP":       "logo_MCHP",  // Microchip
    "MNST":       "logo_MNST",  // Monster Beverage
    "MDLZ":       "logo_MDLZ",  // Mondelez
    "MS":         "logo_MS",    // Morgan Stanley
    "MSFT":       "logo_MSFT",  // Microsoft
    "META":       "logo_META",  // Meta
    "MELI":       "logo_MELI",  // MercadoLibre
    "MPWR":       "logo_MPWR",  // Monolithic Power
    "MRVL":       "logo_MRVL",  // Marvell
    "MRK":        "logo_MRK",   // Merck
    "MU":         "logo_MU",    // Micron
    "NBIS":       "logo_NBIS",  // Nebius Group
    "NDAQ":       "logo_NDAQ",  // Nasdaq Inc.
    "NTES":       "logo_NTES",  // NetEase
    "NVDA":       "logo_NVDA",  // NVIDIA
    "NFLX":       "logo_NFLX",  // Netflix
    "NXPI":       "logo_NXPI",  // NXP Semiconductors
    "ODFL":       "logo_ODFL",  // Old Dominion
    "ORLY":       "logo_ORLY",  // O'Reilly Auto
    "ORCL":       "logo_ORCL",  // Oracle
    "PANW":       "logo_PANW",  // Palo Alto Networks
    "PAYX":       "logo_PAYX",  // Paychex
    "PCAR":       "logo_PCAR",  // Paccar
    "PDD":        "logo_PDD",   // PDD Holdings
    "PM":         "logo_PM",    // Philip Morris
    "PEP":        "logo_PEP",   // PepsiCo
    "PLTR":       "logo_PLTR",  // Palantir
    "PYPL":       "logo_PYPL",  // PayPal
    "PG":         "logo_PG",    // P&G
    "QCOM":       "logo_QCOM",  // Qualcomm
    "RTX":        "logo_RTX",   // RTX
    "REGN":       "logo_REGN",  // Regeneron
    "ROST":       "logo_ROST",  // Ross Stores
    "RKLB":       "logo_RKLB",  // Rocket Lab
    "SAP":        "logo_SAP",   // SAP
    "SHEL":       "logo_SHEL",  // Shell
    "SBUX":       "logo_SBUX",  // Starbucks
    "SPCX":       "logo_SPCX",  // SpaceX
    "SHOP":       "logo_SHOP",  // Shopify
    "STX":        "logo_STX",   // Seagate
    "SNDK":       "logo_SNDK",  // Sandisk
    "SNPS":       "logo_SNPS",  // Synopsys
    "TSM":        "logo_TSM",   // TSMC
    "TSLA":       "logo_TSLA",  // Tesla
    "TTWO":       "logo_TTWO",  // Take-Two
    "TRI":        "logo_TRI",   // Thomson Reuters
    "TMUS":       "logo_TMUS",  // T-Mobile
    "TM":         "logo_TM",    // Toyota
    "TMO":        "logo_TMO",   // Thermo
    "TER":        "logo_TER",   // Teradyne
    "TXN":        "logo_TXN",   // Texas Instruments
    "UNH":        "logo_UNH",   // UnitedHealth
    "V":          "logo_V",     // Visa
    "VRTX":       "logo_VRTX",  // Vertex Pharma
    "WDC":        "logo_WDC",   // Western Digital
    "WBD":        "logo_WBD",   // Warner Bros. Disc.
    "WDAY":       "logo_WDAY",  // Workday
    "WMT":        "logo_WMT",   // Walmart
    "WFC":        "logo_WFC",   // Wells Fargo
    "XOM":        "logo_XOM",   // ExxonMobil
    "XEL":        "logo_XEL",   // Xcel Energy
    "NVO":        "logo_NVO",   // Novo Nordisk
    "VZ":         "logo_VZ",    // Verizon
    "MCD":        "logo_MCD",   // McDonald's
    "TTE":        "logo_TTE",   // TotalEnergies
    "SCHW":       "logo_SCHW",  // Charles Schwab
    "ABT":        "logo_ABT",   // Abbott
    "BA":         "logo_BA",    // Boeing
    "BLK":        "logo_BLK",   // BlackRock
    "DIS":        "logo_DIS",   // Disney
    "TJX":        "logo_TJX",   // TJX Companies
    "NEE":        "logo_NEE",   // NextEraEnergy
    "ETN":        "logo_ETN",   // Eaton
    "UNP":        "logo_UNP",   // Union Pacific
    "BX":         "logo_BX",    // Blackstone
    "DE":         "logo_DE",    // Deere
    "BUD":        "logo_BUD",   // AB InBev
    "RIO":        "logo_RIO",   // Rio Tinto
    "T":          "logo_T",     // AT&T
    "CRM":        "logo_CRM",   // Salesforce
    "UBER":       "logo_UBER",  // Uber
    "PFE":        "logo_PFE",   // Pfizer
    "DHR":        "logo_DHR",   // Danaher
    "COP":        "logo_COP",   // ConocoPhillips
    "SONY":       "logo_SONY",  // Sony
    "LMT":        "logo_LMT",   // LockheedMartin
    "CB":         "logo_CB",    // Chubb
    "PLD":        "logo_PLD",   // Prologis
    "COF":        "logo_COF",   // Capital One
    "BMY":        "logo_BMY",   // Bristol Myers
    "SYK":        "logo_SYK",   // Stryker
    "NOW":        "logo_NOW",   // ServiceNow
    "LOW":        "logo_LOW",   // Lowe's
    "PGR":        "logo_PGR",   // Progressive
    "CVS":        "logo_CVS",   // CVS Health
    "SPGI":       "logo_SPGI",  // S&P Global
    "NEM":        "logo_NEM",   // Newmont
    "MO":         "logo_MO",    // Altria
    "MDT":        "logo_MDT",   // Medtronic
    "ACN":        "logo_ACN",   // Accenture
    "BK":         "logo_BK",    // BNY
    "SO":         "logo_SO",    // Southern Co.
    "GD":         "logo_GD",    // General Dynamics
    "PNC":        "logo_PNC",   // PNC Financial
    "USB":        "logo_USB",   // U.S. Bancorp
    "FCX":        "logo_FCX",   // Freeport
    "DUK":        "logo_DUK",   // Duke Energy
    "MMC":        "logo_MMC",   // Marsh McLennan
    "MMM":        "logo_MMM",   // 3M
    "KKR":        "logo_KKR",   // KKR
    "SHW":        "logo_SHW",   // Sherwin-Williams
    "HCA":        "logo_HCA",   // HCA Healthcare
    "UPS":        "logo_UPS",   // UPS
    "EMR":        "logo_EMR",   // Emerson
    "WMB":        "logo_WMB",   // Williams
    "VLO":        "logo_VLO",   // Valero
    "ELV":        "logo_ELV",   // Elevance Health
    "ITW":        "logo_ITW",   // Illinois
    "ICE":        "logo_ICE",   // Intercontinental
    "MPC":        "logo_MPC",   // Marathon Petrol
    "PSX":        "logo_PSX",   // Phillips 66
    "NOC":        "logo_NOC",   // Northrop
    "AMT":        "logo_AMT",   // American Tower
    "ECL":        "logo_ECL",   // Ecolab
    "AON":        "logo_AON",   // Aon
    "NSC":        "logo_NSC",   // Norfolk Southern
    "UL":         "logo_UL",    // Unilever

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
    "005930.KS":  "logo_005930KS",  // Samsung Elec.
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
    "119850.KQ":  "logo_119850KQ", // 지엔씨에너지
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
    "417200.KQ":  "logo_417200KQ", // LS머트리얼즈
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
    "017670.KS",   // SK텔레콤
    "034730.KS",   // SK Inc.
    "047810.KS",   // 한국항공우주
    "068270.KS",   // Celltrion
    "071050.KS",   // 한국금융지주
    "096770.KS",   // SK이노베이션
    "138930.KS",   // BNK금융지주
    "161390.KS",   // 한국타이어앤테크놀로지
    "326030.KS",   // SK바이오팜
    "402340.KS",   // SK Square

    "000250.KQ",   // Samchundang
    "032820.KQ",   // 우리기술
    "035900.KQ",   // JYP Ent.
    "043260.KQ",   // 성호전자
    "064760.KQ",   // 티씨케이
    "068760.KQ",   // 셀트리온제약
    "090710.KQ",   // 휴림로봇
    "096530.KQ",   // 씨젠
    "108490.KQ",   // Robotis
    "141080.KQ",   // LigaChem Bio
    "140410.KQ",   // 메지온
    "178320.KQ",   // 서진시스템
    "183300.KQ",   // 코미코
    "204270.KQ",   // 제이앤티씨
    "218410.KQ",   // RFHIC
    "237690.KQ",   // 에스티팜
    "281740.KQ",   // 레이크머티리얼즈
    "290650.KQ",   // 엘앤씨바이오
    "323280.KQ",   // 태성
    "420770.KQ",   // 기가비스
    "475830.KQ",   // 오름테라퓨틱
    "950160.KQ",   // 코오롱티슈진
    
    "ITW",         // ITW
    
]

/// 로컬 PNG에 단색 컬러 배경(녹색·노랑 등)이 있는 로고 — 귀퉁이 픽셀 샘플링으로 배경색을 자동 제거.
/// (배경 제거 대신 tickerCircleBackground로 원 자체를 브랜드 색상으로 채우는 방식을 선호)
let tickersNeedColoredBgRemoval: Set<String> = []

/// SVG viewBox 편심으로 인해 시각적 중심이 어긋나는 로고 — (x, y) 오프셋으로 보정.
/// 양수 x = 오른쪽, 음수 x = 왼쪽 / 양수 y = 아래, 음수 y = 위
let tickerLogoOffset: [String: CGPoint] = [
    "AAPL": CGPoint(x: 0, y: -1),       // Apple
    "ADI": CGPoint(x: 1, y: 2),
    "AEP": CGPoint(x: 1, y: 0),         // American Elec.
    "APP": CGPoint(x: 0, y: -2),        // AppLovin
    "AXON": CGPoint(x: 0, y: -4),       // Axon
    "BKNG": CGPoint(x: 1, y: 0),        // Booking Holdings
    "CTAS": CGPoint(x: 0.5, y: 0),      // Cintas
    "CVX": CGPoint(x: 0, y: 1.5),        // Chevron
    "GILD":  CGPoint(x:  0, y:  1),     // Gilead Sciences
    "IBKR": CGPoint(x: 1, y: 0),        // Interactive
    "INTC": CGPoint(x:  1, y:  0),      // Intel
    "MCD":  CGPoint(x:  0, y:  -1),
    "NVDA": CGPoint(x: -3, y:  0),      // Nvidia
    "NTES": CGPoint(x: -1, y:  0),      // NetEase
    "NXPI": CGPoint(x: 1, y:  0),       // NXP
    "PYPL": CGPoint(x: 1, y:  0),       // PayPal
    "SAP": CGPoint(x: 0.5, y:  0),      // SAP
    "BHP": CGPoint(x: 1, y:  0),        // BHP
    "C": CGPoint(x: -0.5, y:  0),       // C
    "ABT": CGPoint(x: 0.5, y:  0),      // Abbott
    "TJX": CGPoint(x: 1.5, y:  1),      // TJX Companies
    "UNP": CGPoint(x: 0, y:  0.5),      // Union Pacific
    "NVO": CGPoint(x: 0.5, y:  0),      // Novo
    "BLK": CGPoint(x: 0.5, y:  0),      // BlackRock
    "DHR": CGPoint(x: 1, y:  1.5),      // DHR
    "UBER": CGPoint(x: 0.5, y:  0),     // Uber
    "SONY": CGPoint(x: 0.5, y:  0),     // Sony
    "CB": CGPoint(x: 0.5, y:  0),       // Chubb
    "RIO": CGPoint(x: 0.5, y:  0),      // Rio Tinto
    "SYK": CGPoint(x: 0.5, y:  0),      // Stryker
    "PGR": CGPoint(x: 0.5, y:  0),      // Progressive
    "ACN": CGPoint(x: 3.5, y:  0),        // Accenture
    "BK": CGPoint(x: 1.5, y:  0),        // BNY
    "UL": CGPoint(x: 0.0, y:  1.5),        // UL
    "SO": CGPoint(x: 0.0, y:  -0.5),        // Southern
    "FCX": CGPoint(x: 0.0, y:  -1),        // Freeport
    "MMM": CGPoint(x: -0.5, y:  0),        // 3M
    "UPS": CGPoint(x: 0.5, y:  1),         // UPS
    "MPC": CGPoint(x: 1, y:  -1.5),        // MPC
    "ECL": CGPoint(x: 0.5, y:  1),        // Ecolab
    "PSX": CGPoint(x: 0, y:  1),        // Phillips 66
    "VLO": CGPoint(x: 0, y:  0.5),        // Valero
    "WMB": CGPoint(x: 1, y:  0),        // Williams
    "KKR": CGPoint(x: 0.5, y:  1),        // KKR
    "TM": CGPoint(x: 0.5, y:  0),        // Toyota
   
   
    "000720.KS": CGPoint(x:  -1.5, y:  -2), // 현대건설
    "009540.KS": CGPoint(x:  3, y:  0),     // HD한국조선해양
    "021240.KS": CGPoint(x:  0, y:  1),     // 코웨이
    "033780.KS": CGPoint(x:  0, y:  -3),    // KT&G
    "042700.KS": CGPoint(x:  0.5, y:  0),   // 한미반도체
    "047040.KS": CGPoint(x:  2, y:  0),     // 대우건설
    "047810.KS": CGPoint(x:  1, y:  0),     // 한국항공우주
    "267250.KS": CGPoint(x:  3, y:  0),     // HD현대
    "267260.KS": CGPoint(x:  3, y:  0),     // HD현대일렉트릭
    "267270.KS": CGPoint(x:  3, y:  0),     // HD건설기계
    "329180.KS": CGPoint(x:  -1.5, y:  -2), // HD Hyundai HI
    "443060.KS": CGPoint(x:  3, y:  0),     // HD현대마린솔루션
    "031980.KQ": CGPoint(x:  1, y:  0),     // 피에스케이홀딩스
    "036540.KQ": CGPoint(x:  0.5, y:  0),   // SFA반도체
    "038500.KQ": CGPoint(x:  0, y:  2),     // 삼표시멘트
    "041830.KQ": CGPoint(x:  1, y:  0),     // 인바디
    "065350.KQ": CGPoint(x:  0, y:  26),    // 신성델타테크
    "067310.KQ": CGPoint(x:  1.5, y:  0),   // 하나마이크론
    "082920.KQ": CGPoint(x:  0, y:  3),     // 비츠로셀
    "083450.KQ": CGPoint(x:  0.5, y:  0),   // GST
    "083650.KQ": CGPoint(x:  -1, y:  0),    // 비에이치아이
    "090710.KQ": CGPoint(x:  0.5, y:  0),   // 휴림로봇
    "101490.KQ": CGPoint(x:  0.5, y:  0),   // 에스앤에스텍
    "166090.KQ": CGPoint(x:  1.5, y:  0),   // 하나머티리얼즈
    "214370.KQ": CGPoint(x:  -0.5, y:  0.5),// 케어젠
    "319400.KQ": CGPoint(x:  -1.5, y:  -2), // 현대무벡스
    "319660.KQ": CGPoint(x:  1, y:  0),     // PSK
    "458870.KQ": CGPoint(x:  1, y:  0),     // 씨어스
    "476830.KQ": CGPoint(x:  0.5, y:  0),   // 알지노믹스
]

/// 기본 padding(8)과 다른 로고 — 작은 값일수록 로고가 원 안에서 더 크게 표시됨.
let tickerLogoPadding: [String: CGFloat] = [
    "2222:TADAWUL":      0, // Saudi Aramco
    "ADI":       -30,  // Analog Devices
    "AMD":       0,    // AMD
    "AMAT":      0,    // Applied Materials
    "AMGN":      0,    // Amgen
    "APP":       4,    // AppLovin
    "AEP":       2,    // American Elec. Pwr
    "ALAB":      0,    // Astera Labs
    "BAC":       6,    // Bank of America
    "BKR":       -4,   // Baker Hughes
    "BRK.B":     0,    // Berkshire
    "BHP":       7,    // BHP
    "CAT":       0,    // Caterpillar
    "CCEP":      0,    // Coca-Cola
    "CDNS":      0,    // Cadence
    "CSCO":      0,    // Cisco
    "COIN":      -4,   // Coinbase
    "COST":      0,    // Coscto
    "CMCSA":     4,    // Comcast
    "CTAS":      4,    // Cintas
    "CRWV":      6,    // CoreWeave
    "CEG":       7,    // Constellation En.
    "EA":        0,    // Electronic Arts
    "FAST":      0,    // Fastenal
    "FER":       0,    // Ferrovial
    "HOOD":      0,    // Robinhood
    "HON":      10,    // Honeywell
    "IBKR":      6,    // Interactive
    "IDXX":      4,    // Idexx Labs
    "ISRG":      6,    // Intuitive Surgical
    "INTC":      -1,   // Intel
    "INTU":      5,    // Intuit
    "JD":        0,    // JD.com
    "JNJ":       4,    // J&J
    "JPM":       0,    // JPMorgan
    "KLAC":      0,    // KLA
    "KDP":      10,    // Keurig
    "LLY":       0,    // Eli Lilly
    "LIN":       0,    // Linde
    "MAR":       2,    // Marriott
    "MCD":       6,    // Mc
    "MDLZ":      0,    // Mondelez
    "MU":        0,    // Micron
    "MNST":      0,    // Monster Beverage
    "MSFT":      10,   // Microsoft
    "MPWR":      6,    // Monolithic
    "NTES":      2,    // NetEase
    "NFLX":      0,    // Netflix
    "NXPI":      5,    // NXP Semiconductors
    "NBIS":      0,    // Nebius
    "NDAQ":      -0.5, // Nasdaq Inc.
    "ODFL":      -2,   // Old
    "ORLY":      2,    // O'Reilly Auto
    "PANW":      6,    // Palo Alto
    "PAYX":      0,    // Paychex
    "PCAR":      0,    // Paccar
    "PEP":       4,    // PepsiCo
    "PDD":       0,    // PDD Holdings
    "QCOM":      0,    // Qualcomm
    "ROST":      0,    // Ross Stores
    "RKLB":      -2,   // Rocket Lab
    "REGN":      0,    // Regeneron
    "SPCX":      4,    // SapceX
    "SNDK":      0,    // Sandisk
    "SNPS":      5,    // Synopsys
    "STX":       0,    // Seagate
    "TSLA":      -2,   // Tesla
    "TER":       0,    // Teradyne
    "TMUS":      0,    // T-Mobile
    "V":         0,    // Visa
    "VRTX":      0,    // Vertex Pharma
    "WMT":       0,    // Walmart
    "WBD":       0,    // Warner Bros.
    "WDAY":      0,    // Workday
    "WDC":       0,    // Western
    "KO":        0,    // Coca-Cola
    "CVX":       10,   // Chevron
    "HSBC":      6,   // HSBC
    "HD":        0,   // Home Depot
    "MS":        0,   // Morgan Stanley
    "PG":        -0.5,   // P&G
    "WFC":       0,   // Wells Fargo
    "AXP":       0,   // American Express
    "TM":        -2,   // TM
    "VZ":        0,   // Verizon
    "SCHW":      0,   // Charles
    "ABT":       0,   // Abbott
    "BA":        0,   // Boeing
    "DIS":       0,   // Disney
    "BX":        0,   // Blackstone
    "CRM":       0,   // Salesforce
    "NOW":       0,   // ServiceNow
    "SPGI":      0,   // S&P Global
    "GD":        0,   // General Dynamics
    "USB":       0,   // U.S. Bancorp
    "MMC":       0,   // Marsh
    "SHW":       0,   // Sherwin
    "ELV":       0,   // Elevance
    "ICE":       0,   // Intercontinental
    "NOC":       0,   // Northrop
    "AMT":       0,   // American Tower
    "NSC":       2,   // Norfolk Southern
    "IBM":      -3,   // IBM
    "BLK":       5,   // BlackRock
    "TJX":       7,   // TJX
    "TMO":       0,   // Thermo
    "ETN":       7,   // Eaton
    "COP":       7,   // COP
    "UL":        10,   // Unilever
    "RIO":       5,   // Rio Tinto
    "LMT":       6,   // Lockheed
    "CB":        4,   // Chubb
    "COF":       6,   // Captial One
    "SYK":       4,   // Stryker
    "PGR":       2,   // Progressive
    "CVS":       2,   // CVS Health
    "NEM":       10,  // Newmont
    "MDT":       2,   // Medtronic
    "ACN":       10,  // Accenture
    "BK":        2,    // BNY
    "SO":        3,    // Southern Co.
    "MO":        2,    // Altria
    "HCA":       4,    // HCA Healthcare
    "EMR":       4,    // EMR
    "VLO":       4,    // Valero
    "ITW":       0,    // ITW
    "MPC":       4,    // Marathon
    "PSX":       -4,   // Phillips 66
    "ECL":       4,    // Ecolab
    "AON":       4,    // Aon
    "LOW":       0,    // Lowe's
    "KKR":       4,    // KKR
    "SAP":       4,    // SAP
    
    "000250.KQ": 2,   // Samchundang
    "0009K0.KQ": -3,  // 에임드바이오
    "003380.KQ": 6,   // 하림
    "007390.KQ": -4,  // 네이처셀
    "028300.KQ": 0,   // HLB
    "031330.KQ": 0,   // 에스에이엠티
    "032820.KQ": 0,   // 우리기술
    "035900.KQ": 10,  // JYP
    "036540.KQ": -7,  // SFA반도체
    "036930.KQ": 0,   // Jusung Eng.
    "038500.KQ": -1.5,// 삼표시멘트
    "039030.KQ": 6,   // EO Technics
    "039200.KQ": 6,   // 오스코텍
    "041510.KQ": 0,   // 에스엠
    "041830.KQ": 0,   // 인바디
    "043260.KQ": -3,  // 성호전자
    "058470.KQ": 4,   // Leeno Ind.
    "058610.KQ": 7,   // 에스피지
    "060370.KQ": -3,  // LS마린솔루션
    "064760.KQ": 2,   // 티씨케이
    "065350.KQ": -54, // 신성델타크
    "067310.KQ": -3,  // 하나마이크론
    "068760.KQ": 0,   // 셀트리온제약
    "078600.KQ": 0,   // 대주전자재료
    "080220.KQ": 7,   // 제주반도체
    "082920.KQ": -13, // 비츠로셀
    "083450.KQ": 3,   // GST
    "083650.KQ": -11, // 비에이치아이
    "084370.KQ": 4,   // 유진테크
    "085660.KQ": 4,   // 차바이오텍
    "086450.KQ": 4,   // 동국제약
    "086520.KQ": 4,   // Ecopro
    "087010.KQ": 4,   // 펩트론
    "089030.KQ": 4,   // 테크윙
    "089970.KQ": 6,   // qmdldpa
    "090710.KQ": 0,   // 휴림로봇
    "095340.KQ": 4.5, // ISC
    "095610.KQ": -8,  // Tes
    "096530.KQ": -1,  // 씨젠
    "098460.KQ": 4,   // 고영
    "101490.KQ": -38, // 에스앤에스텍
    "108490.KQ": 2,   // Robotis
    "115180.KQ": 3,   // 큐리언트
    "119850.KQ": 0,   // 지엔씨에너지
    "131290.KQ": -3,  // 티에스이
    "131970.KQ": 3,   // 두산테스나
    "140410.KQ": -1,  // 메지온
    "140860.KQ": 4,   // 파크시스템스
    "141080.KQ": 0,   // LigaChem Bio
    "145020.KQ": 4,   // 휴젤
    "166090.KQ": 4,   // 하나머티리얼즈
    "178320.KQ": 4,   // 서진시스템
    "183300.KQ": 0,   // 코미코
    "189300.KQ": 0,   // 인텔리안테크
    "195940.KQ": 0,   // HK이노엔
    "204270.KQ": -3,  // 제이앤티씨
    "213420.KQ": 0,   // 덕산네오룩스
    "214150.KQ": 4,   // 클래시스
    "214370.KQ": 1,   // 케어젠
    "214450.KQ": 2,   // Pharma Research
    "218410.KQ": -2,  // RFHIC
    "222800.KQ": 4,   // Simmtech
    "226950.KQ": -1,  // 올릭스
    "237690.KQ": -2,  // 에스티팜
    "241710.KQ": 2,   // 코스메카코리아
    "247540.KQ": 4,   // Ecopro BM
    "257720.KQ": -4,  // 실리콘투
    "263750.KQ": 10,  // 펄어비스
    "277810.KQ": 0,   // Rainbow Robotics
    "281740.KQ": 0,   // 레이크머티리얼즈
    "290650.KQ": -1,  // 엘앤씨바이오
    "293490.KQ": 0,   // 카카오게임즈
    "298380.KQ": 6,   // ABL Bio
    "319660.KQ": 7,   // PSK
    "323280.KQ": -3,  // 태성
    "347700.KQ": 2,   // 스피어
    "347850.KQ": -1,  // 디앤디파마텍
    "357780.KQ": 0,   // 솔브레인
    "388720.KQ": 0,   // 유일로보틱스
    "403870.KQ": -4,  // HPSP
    "417200.KQ": -3,  // LS머트리얼즈
    "420770.KQ": 2,   // 기가비스
    "440110.KQ": 0,   // FADU
    "458870.KQ": -4,  // 씨어스
    "475830.KQ": 2,   // 오름테라퓨틱
    "476830.KQ": 0,   // 알지노믹스
    "491000.KQ": 1,   // 리브스메드
    "950160.KQ": 0,   // 코오롱티슈진
    
    "000100.KS": 5,   // 유한양행
    "000660.KS": -4,  // SK Hynix
    "000150.KS": 3,   // 두산
    "000270.KS": 0,   // Kia
    "000810.KS": 0,   // 삼성화재
    "001440.KS": 5,   // 대한전선
    "003230.KS": 7,   // 삼양식품
    "003490.KS": 0,   // 대한항공
    "003670.KS": 4,   // 포스코퓨처엠
    "005380.KS": 6,   // Hyundai Motor
    "005385.KS": 6,   // 현대차우
    "005387.KS": 6,   // 현대차2우B
    "005490.KS": 4,   // POSCO홀딩스
    "005830.KS": 2,   // DB손해보험
    "005930.KS": 0,   // Samsung Elec.
    "005935.KS": 0,   // 삼성전자우
    "005940.KS": 6,   // NH투자증권
    "006260.KS": -3,  // LS
    "006400.KS": 0,   // Samsung SDI
    "006800.KS": 2,   // 미래에셋증권
    "009150.KS": 0,   // Samsung EM
    "010120.KS": -3,  // LS ELECTRIC
    "010130.KS": -2,  // 고려아연
    "010140.KS": 0,   // 삼성중공업
    "010950.KS": 2,   // S-Oil
    "011200.KS": 0,   // HMM
    "012330.KS": 2,
    "0126Z0.KS": 0,   // 삼성에피스홀딩스
    "018260.KS": 0,   // 삼성에스디에스
    "015760.KS": 2,   // 한국전력
    "016360.KS": 0,   // 삼성증권
    "017670.KS": -4,  // SK텔레콤
    "021240.KS": 4,   // 코웨이
    "024110.KS": 4,   // 기업은행
    "028050.KS": 0,   // 삼성E&A
    "028260.KS": 0,   // Samsung C&T
    "029780.KS": 0,   // 삼성카드
    "030200.KS": 12,  // KT
    "032830.KS": 0,   // Samsung Life
    "033780.KS": 4,   // KT&G
    "034020.KS": 2,
    "034730.KS": -4,  // SK Inc.
    "035420.KS": 0,   // 네이버
    "035720.KS": 0,   // 카카오
    "036570.KS": 8,   // NC
    "039490.KS": 12,  // 키움증권
    "042700.KS": 4,   // 한미반도체
    "047040.KS": 0,   // 대우건설
    "047050.KS": 4,   // 포스코인터네셔널
    "047810.KS": 0,   // 한국항공우주
    "062040.KS": 4,   // 산일전기
    "064350.KS": 4,   // 현대로템
    "068270.KS": 0,   // Celltrion
    "071050.KS": 4,   // 한국금융지주
    "078930.KS": -16, // GS
    "079550.KS": -0.5,// LIG
    "086280.KS": 0,   // 현대글로비스
    "090430.KS": 6,   // 아모레퍼시픽
    "096770.KS": -4,  // SK이노베이션
    "105560.KS": 0,   // KB Financial
    "128940.KS": 2,   // 한미약품
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
    "326030.KS": -4,  // SK바이오팜
    "352820.KS": 4,   // 하이브
    "353200.KS": 0,   // 대덕전자
    "377300.KS": 0,   // 카카오페이
    "402340.KS": -4,  // SK Square
]

/// 흰색 원 배경 대신 다른 색상을 사용할 티커.
let tickerCircleBackground: [String: Color] = [
    "ADBE": Color.red,   // Adobe
    "ADI": Color.black,  // ADI
    "AMAT": Color.black, // Applied Materials
    "ALAB": Color.black, // Astera
    "AMD": Color.black,  // AMD
    "ADSK": Color.black, // Autodesk
    "AXON": Color.black, // Axon Enterprise
    "BLK": Color.black,  // BlackRock
    "CDNS": Color.black, // Cadence
    "CCEP": Color.black, // Coca-Cola
    "EA": Color.black,   // Electronic Arts
    "FAST": Color.black, // Fastenal
    "MU": Color.black,   // Micron
    "NFLX": Color.black, // Netflix
    "SPCX": Color.black, // SpaceX
    "JD": Color.black,   // JD
    "JPM": Color.brown,  // JPMorgan
    "MA": Color.black,   // Mastercard
    "MDLZ": Color.black, // Mondelez
    "MNST": Color.black, // Monster Beverage
    "MRVL": Color.black, // Marvell
    "NDAQ": Color.black, // Nasdaq
    "PAYX": Color.black, // Paychex
    "PCAR": Color.black, // Paccar
    "WDC": Color.black,  // Western
    "WBD": Color.black,  // Warner Bros
    "WDAY": Color.black, // Workday
    "ROST": Color.black, // Ross Stores
    "REGN": Color.black, // Regeneron
    "RKLB": Color.black, // Rocket Lab
    "TTWO": Color.black, // Take-Two
    "TER": Color.black,  // Teradyne
    "HON": Color.red,    // Honeywell
    "VRTX": Color.black, // Vertax
    "BUD": Color.black,  // AB InBev
    "UBER": Color.black, // Uber
    "SONY": Color.black, // Sony
    "AON": Color.red,    // Aon
    "FCX": Color.black,    // Freeport
    "AMT": Color.black,    // American
    "NOC": Color.black,    // Northrop
    "ICE": Color.black,    // Intercontinental
    "ELV": Color.black,    // Elevance
    "SHW": Color.black,    // Sherwin
    "USB": Color.black,    // US Bancorp
    "GD": Color.black,    // GD
    "LOW": Color.black,    // Lowe's
    "NOW": Color.black,    // ServiceNow
    "BX": Color.black,    // Blackstone
    "DIS": Color.black,    // Disney
    "BA": Color.black,    // Boeing
    "VZ": Color.black,    // Verizon
    "IBM": Color.black,    // IBM
    "AXP": Color.black,    // AXP
    "PG": Color.black,    // P&G
    "MS": Color.black,    // Morgan
    "CAT": Color.black,    // CAT
    "KO": Color.black,    // Coca-cola
    
    
    "ABNB": Color(red: 1.0000, green: 0.2078, blue: 0.3686),   // Airbnb
    "ABBV": Color(red: 0.027, green: 0.114, blue: 0.286),      // ABBV
    "ADP": Color(red: 0.8078, green: 0.0980, blue: 0.1412),    // ADP
    "ASML": Color(red: 0.043, green: 0.114, blue: 0.522),      // ASML
    "AMGN": Color(red: 0.1020, green: 0.2196, blue: 0.3373),   // Amgen
    "ARM": Color(red: 0.0, green: 0.5686, blue: 0.7412),       // ARM
    "BKR": Color(red: 0.0471, green: 0.0510, blue: 0.0588),    // Baker Hughes
    "BRK.B": Color(red: 0.169, green: 0.196, blue: 0.573),     // Berkshire
    "CSCO": Color(red: 0.07, green: 0.18, blue: 0.36),
    "CSX": Color(red: 0.0980, green: 0.0980, blue: 0.4392),    // CSX
    "CRWD": Color(red: 0.9882, green: 0.0, blue: 0.0),         // Crowd
    "DDOG": Color(red: 0.3098, green: 0.1373, blue: 0.5961),   // Datadog
    "DASH": Color(red: 1.0000, green: 0.1412, blue: 0.0),      // DoorDash
    "FTNT": Color(red: 0.8902, green: 0.1490, blue: 0.2118),   // Fortinet
    "IDXX": Color(red: 0.0, green: 0.4980, blue: 1.0),         // Idexx Labs
    "ISRG": Color(red: 0.0588, green: 0.1451, blue: 0.8196),   // Intuitive Surgical
    "INTU": Color(red: 0.1176, green: 0.5647, blue: 1.0000),   // Intuit
    "JNJ": Color(red: 0.890, green: 0.140, blue: 0.030),       // J&J
    "KLAC": Color(red: 0.0, green: 0.4824, blue: 0.7765),      // KLA
    "LRCX": Color(red: 0.416, green: 0.417, blue: 0.522),      // Lam Research
    "LIN": Color(red: 0.0, green: 0.1843, blue: 0.3529),       // Linde
    "MPWR": Color(red: 0.0, green: 0.4000, blue: 1.0000),      // Monolithic Power
    "ORCL": Color(red: 0.78, green: 0.275, blue: 0.204),       // Oracle
    "PLTR": Color(red: 0.117, green: 0.129, blue: 0.141),      // Palantir
    "SHOP": Color(red: 0.5843, green: 0.7529, blue: 0.2863),   // Shopify
    "SNPS": Color(red: 0.4235, green: 0.1882, blue: 0.5098),   // Synopsys
    "TMUS": Color(red: 0.8863, green: 0.0, blue: 0.4549),      // T-Mobile
    "TXN": Color(red: 0.8, green: 0.0, blue: 0.0),             // Texas Instruments
    "TRI": Color(red: 1.0, green: 0.4, blue: 0.0),             // Thomson Reuters
    "QCOM": Color(red: 0.1647, green: 0.1647, blue: 0.9176),   // QCOM
    "V":     Color(red: 0.082, green: 0.204, blue: 0.800),     // Visa
    "WMT":   Color(red: 0.000, green: 0.322, blue: 0.894),     // Walmart
    "GS":   Color(red: 0.471, green: 0.545, blue: 0.729),      // GS
    "BABA":   Color(red: 1.0, green: 0.4, blue: 0.0),      // Alibaba
    "NVO":   Color(red: 0.098, green: 0.098, blue: 0.439),      // Novo Nordisk
    "MCD":   Color(red: 0.78, green: 0.0, blue: 0.0),      // McDonald's
    "NEE":   Color(red: 0.29, green: 0.29, blue: 0.29),      // NextEra
    "ETN":   Color(red: 0.0, green: 0.373, blue: 0.529),      // Eaton
    "RIO":   Color(red: 0.8039, green: 0.1725, blue: 0.1725),      // Rio Tinto
    "LMT":   Color(red: 0.0235, green: 0.3020, blue: 0.6392),      // Lockheed
    "CB":   Color(red: 0.4118, green: 0.2078, blue: 0.6118),      // CB
    "COF":   Color(red: 0.2, green: 0.2, blue: 0.2),      // Capital One
    "SYK":   Color(red: 1.0, green: 0.7294, blue: 0.0),      // Stryker
    "PGR":   Color(red: 0.0, green: 0.4824, blue: 0.6549),       // Progressive
    "ECL":   Color(red: 0.0, green: 0.4, blue: 0.8),       // Ecolab
    "KKR":   Color(red: 0.2078, green: 0.0549, blue: 0.2784),       // KKR
    "WMB":   Color(red: 0.0, green: 0.4941, blue: 0.7804),          // WMB
    "NSC":   Color(red: 0.133, green: 0.145, blue: 0.165),       // NSC
    "ABT":   Color(red: 0.0, green: 0.0, blue: 0.5020),       // Abbott
    
   
    "189300.KQ": Color.black, // 인텔리안테크
    "213420.KQ": Color.black, // 덕산네오룩스
    "388720.KQ": Color.black, // 유일로보틱스
    "079550.KS": Color.black, // LIG
    "175330.KS": Color.black, // JB금융지주
    "353200.KS": Color.black, // 대덕전자
    "000810.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성화재
    "005930.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // Samsung Elec.
    "005935.KS": Color(red: 0.145, green: 0.153, blue: 0.616), // 삼성전자우
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
    "000270.KS": Color(red: 0.02,  green: 0.078, blue: 0.122), // Kia
    "035420.KS": Color(red: 0.012, green: 0.780, blue: 0.353), // 네이버
    "105560.KS": Color(red: 0.969, green: 0.678, blue: 0.0),   // KB Financial
    "207940.KS": Color(red: 0.0,   green: 0.082, blue: 0.294), // 삼성바이오로직스
    "035720.KS": Color(red: 1.0,   green: 0.804, blue: 0.0),   // 카카오
    "377300.KS": Color(red: 1.0,   green: 0.804, blue: 0.0),   // 카카오페이
]

/// 로고 원 타일 크기(pt). 전체 로고 크기를 바꾸려면 이 값만 수정.
let logoTileSize: CGFloat = 50
