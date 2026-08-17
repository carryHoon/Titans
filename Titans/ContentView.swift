//
//  ContentView.swift
//  Titans
//
//  Created by MacH on 7/21/26.
//

import SwiftUI
import Combine   // ObservableObject / @Published
import CryptoKit // 로고 디스크 캐시 파일명 해시(SHA256)
import UIKit
import GoogleMobileAds // 적응형 배너 크기 계산(currentOrientationAnchoredAdaptiveBanner)

// MARK: - Logo Source

// logo.dev publishable token — 도메인으로 공식 브랜드 로고를 받는다(Clearbit 후속 표준).
// publishable(pk_) 키라 클라이언트 노출용으로 안전. fallback=404로 미보유 시 404를 받아
// 앱의 다음 폴백(이니셜 타일)이 동작하게 한다.
private let logoDevToken = "pk_J8vaeyLSSxewXruh0z5O9g"


// MARK: - Color(hex:) Extension

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - UIImage Background Removal

private extension UIImage {
    /// 어두운 무채색 픽셀(배경)을 투명하게 만든다.
    /// 채도(saturation) + 밝기(brightness) 기준으로 판별해
    /// 짙은 레드 그림자처럼 어두워도 채색된 픽셀은 보존한다.
    func removingDarkBackground() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for i in 0..<(w * h) {
            let r = CGFloat(buf[i*4]) / 255,
                g = CGFloat(buf[i*4+1]) / 255,
                b = CGFloat(buf[i*4+2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            let sat = hi == 0 ? 0.0 : (hi - lo) / hi
            if sat < 0.3 && hi < 0.3 { // 어둡고 무채색인 픽셀 → 투명 처리
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    /// 밝은 회색/흰색 배경 픽셀을 투명하게 만든다.
    /// 채도가 낮고(무채색) 밝기가 높은(회색·흰색) 픽셀만 제거해 채색된 로고 요소는 보존한다.
    func removingLightBackground() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for i in 0..<(w * h) {
            let r = CGFloat(buf[i*4]) / 255,
                g = CGFloat(buf[i*4+1]) / 255,
                b = CGFloat(buf[i*4+2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            let sat = hi == 0 ? 0.0 : (hi - lo) / hi
            if sat < 0.12 && hi > 0.50 { // 밝고 무채색인 픽셀(회색·흰색) → 투명 처리
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    /// 네 귀퉁이 픽셀의 평균색을 배경색으로 간주하고, 그 색에 가까운 픽셀을 투명하게 만든다.
    /// 녹색(네이버)·노랑(KB금융) 같은 단색 컬러 배경 로고에 적용.
    func removingDominantBackground(tolerance: CGFloat = 0.22) -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 1, h > 1 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let corners = [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0
        for (cx, cy) in corners {
            let idx = cy * w + cx
            bgR += CGFloat(buf[idx*4])   / 255
            bgG += CGFloat(buf[idx*4+1]) / 255
            bgB += CGFloat(buf[idx*4+2]) / 255
        }
        bgR /= 4; bgG /= 4; bgB /= 4
        let tol2 = tolerance * tolerance
        for i in 0..<(w * h) {
            let r = CGFloat(buf[i*4])   / 255
            let g = CGFloat(buf[i*4+1]) / 255
            let b = CGFloat(buf[i*4+2]) / 255
            let d2 = (r-bgR)*(r-bgR) + (g-bgG)*(g-bgG) + (b-bgB)*(b-bgB)
            if d2 < tol2 {
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    /// 원격(logo.dev) 로고가 불투명한 사각 배경을 갖는지 판별한다.
    /// 네 귀퉁이가 모두 불투명하면 배경이 있는 로고로 보고 원을 꽉 채우게 하고,
    /// 하나라도 투명하면 아이콘형 로고로 보고 기존 여백을 유지한다.
    func hasOpaqueBackground() -> Bool {
        guard let cg = cgImage else { return false }
        let w = cg.width, h = cg.height
        guard w > 1, h > 1 else { return false }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for (cx, cy) in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)] {
            if buf[(cy*w+cx)*4+3] < 230 { return false }  // 반투명·투명 귀퉁이 → 아이콘형
        }
        return true
    }
}

private enum LogoProcessingCache {
    static let shared = NSCache<NSString, UIImage>()
}

/// 원격 로고(logo.dev) 영구 캐시 — 메모리(NSCache) + 디스크(Caches/LogoCache).
///
/// logo.dev 응답은 `max-age=86400`(24h)이라 기본 URLCache로는 유저가 매일 재호출한다.
/// 로고는 거의 안 바뀌므로 이 캐시가 24h 만료를 무시하고 폰에 오래(기본 60일) 보관해
/// logo.dev 무료 플랜(월 50만) 호출을 최소화한다. device-side 캐싱이라 약관을 준수한다
/// (서버 캐싱/self-host는 logo.dev Pro 전용이라 여기선 절대 하지 않는다).
final class LogoStore {
    static let shared = LogoStore()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let ttl: TimeInterval = 60 * 24 * 60 * 60   // 60일

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("LogoCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// 메모리 → 디스크(TTL 이내) → 네트워크 순. 200이 아니면 nil을 반환해 다음 폴백을 유도한다.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }

        let file = fileURL(for: url)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl,
           let data = try? Data(contentsOf: file),
           let img = UIImage(data: data) {
            memory.setObject(img, forKey: key)
            return img
        }

        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        memory.setObject(img, forKey: key)
        return img
    }
}

// MARK: - Proportional Scaled Layout (기기별 비례 축소)

/// 콘텐츠를 항상 `referenceWidth`(디자인 기준 기기 = iPhone 17 Pro)의 폭으로 먼저 배치한 뒤,
/// 실제 사용 가능한 폭에 맞춰 전체를 균일하게 축소한다.
/// 덕분에 어떤 기기에서도 기준 기기와 **동일한 레이아웃·비율**이 유지되고,
/// 화면이 좁으면 폰트와 간격이 함께 비례 축소되어 줄바꿈(2줄)이 발생하지 않는다.
/// (기준 폭보다 넓은 기기에서는 확대하지 않고 원본 크기를 유지)
struct ProportionalScaledLayout<Content: View>: View {
    var referenceWidth: CGFloat
    @ViewBuilder var content: Content

    @State private var availableWidth: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private var scale: CGFloat {
        guard availableWidth > 0 else { return 1 }
        return min(1, availableWidth / referenceWidth)
    }

    var body: some View {
        content
            // 항상 기준 기기 폭으로 배치 → 디자인 시점과 동일한 한 줄 레이아웃 보장
            .frame(width: referenceWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            // 실제 폭 비율만큼 전체(폰트·간격 포함)를 균일 축소
            .scaleEffect(scale, anchor: .topLeading)
            // scaleEffect는 레이아웃 크기를 바꾸지 않으므로, 축소된 실제 크기를 프레임으로 반영
            .frame(width: referenceWidth * scale, height: contentHeight * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var viewModel = MarketCapViewModel()
    @Environment(AuthManager.self) private var auth

    // 상단 하이라이트 티커의 현재 로테이션 인덱스. 거래소 전환 시 0으로 리셋.
    @State private var highlightIndex: Int = 0
    @State private var currentTime: Date = Date()
    // 시가총액을 표시할 단일 통화. 온보딩에서 선택하고 메뉴에서 변경 가능(USD 포함 전 통화가 동등한 선택지).
    // PrefsSync가 로그인 시 이 @AppStorage에 반영한다. 홈/검색/행 전부 이 값 하나로 표시.
    @AppStorage("displayCurrency") private var displayCurrency: Currency = .usd
    @State private var selectedMarket: Market = .all
    @State private var sortField: SortField = .rank
    @State private var sortOrder: SortOrder = .ascending

    // 화면(윈도우) 전체 높이 — 헤더 세로 간격을 기기별 "동일 비율"로 스케일링하기 위한 기준값.
    // 기준: iPhone 17 Pro(874pt). 모든 기기에서 헤더가 화면의 동일한 세로 비율을 차지하도록 함.
    @State private var viewportHeight: CGFloat = 874

    // 라이트/다크 모드는 iOS 시스템 설정을 그대로 따른다.
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    // 검색 / 메뉴 화면 표시 상태
    @State private var showSearch = false
    @State private var showMenu = false

    /// 현재 표시 통화의 환산 rate(1 USD 당 금액). formatMarketCap에 전달된다.
    private var displayRate: Double { viewModel.rate(for: displayCurrency) }

    /// 검색 대상 유니버스 — ALL 피드 + 현재까지 로드된 거래소별 피드를 티커 기준으로 합침.
    /// (별도 API 없이 이미 라이브로 받고 있는 데이터를 그대로 검색에 재사용)
    private var searchableCompanies: [Company] {
        var seen = Set<String>()
        var merged: [Company] = []
        for c in viewModel.companies + viewModel.exchangeFeeds.values.flatMap(\.companies) {
            if seen.insert(c.ticker).inserted { merged.append(c) }
        }
        return merged
    }

    /// 현재 선택 모드에 대응하는 테마. isDarkMode 변경 시 색상이 보간되도록 명시적 Color 사용.
    private var theme: AppTheme { isDarkMode ? .dark : .light }

    /// 헤더(Live 바~탭 필터) 세로 여백에 곱해지는 높이 비례 계수.
    /// 화면이 낮은 기기일수록 여백이 함께 줄어들어, 헤더가 어떤 기기에서도 화면의 동일한 세로 비율을 차지한다.
    private var vScale: CGFloat { min(max(viewportHeight / 874, 0.85), 1.12) }

    private func selectMarket(_ market: Market) {
        guard market != selectedMarket else { return }
        selectedMarket = market
    }

    // MARK: 섹션별 데이터 헬퍼 — TabView 각 페이지가 자체 상태를 독립적으로 읽는다

    private func feed(for market: Market) -> ExchangeFeed? {
        guard market.apiExchangeParam != nil else { return nil }
        return viewModel.exchangeFeeds[market] ?? ExchangeFeed()
    }

    private func companies(for market: Market) -> [Company] {
        if let f = feed(for: market) { return f.companies }
        guard market != .all else { return viewModel.companies }
        return viewModel.companies.filter { $0.market == market }
    }

    private func sortedCompanies(for market: Market) -> [Company] {
        let list = companies(for: market)
        switch sortField {
        case .rank:
            return sortOrder == .ascending
                ? list.sorted { $0.rank < $1.rank }
                : list.sorted { $0.rank > $1.rank }
        case .name:
            return sortOrder == .ascending
                ? list.sorted { $0.name < $1.name }
                : list.sorted { $0.name > $1.name }
        case .marketCap:
            return sortOrder == .ascending
                ? list.sorted { $0.marketCapUSD < $1.marketCapUSD }
                : list.sorted { $0.marketCapUSD > $1.marketCapUSD }
        }
    }

    /// 현재 거래소의 "오늘의 순위 사건"을 우선순위대로 만든다.
    /// 마지막에 현재 1위(폴백)를 항상 넣어 변동이 없어도 비지 않게 한다(👑 서열 프레이밍).
    private func highlights(for market: Market) -> [Highlight] {
        let list = companies(for: market)
        guard !list.isEmpty else { return [] }
        // 하나라도 previousRank가 있으면 "전일 비교 기준(baseline)"이 존재한다고 본다.
        // (배포 직후 KR처럼 전부 nil이면 순위변동 사건을 만들지 않고 현재 1위만 보여준다.)
        let hasBaseline = list.contains { $0.previousRank != nil }
        let n = list.count
        var result: [Highlight] = []
        var used = Set<String>()

        // 1) 정상 탈환 — 현재 1위인데 전일엔 1위가 아니었던 종목(가장 극적).
        if let top = list.first(where: { $0.rank == 1 }),
           let prev = top.previousRank, prev > 1 {
            result.append(Highlight(kind: .overtake, company: top,
                title: "정상 탈환", detail: "1위 등극", rankDelta: prev - 1))
            used.insert(top.ticker)
        }

        // 2) 조 달러 돌파 — 오늘 정수 "조 달러(USD 1T)" 문턱을 상향 돌파한 종목(희소·상징적).
        //    prevCap = cap / (1 + change%/100). marketCapUSD 단위가 이미 조(trillion) USD.
        //    (JPX는 change=0이라 자연히 미발생. 표시통화 무관하게 USD 조 클럽 기준.)
        if let breakout = list.compactMap({ c -> (Company, Int)? in
            guard c.change > -100 else { return nil }
            let cap = c.marketCapUSD
            let prevCap = cap / (1 + c.change / 100)
            let k = Int(floor(cap))
            guard k >= 1, Double(k) > prevCap, cap >= Double(k) else { return nil }  // 정수 조 상향 돌파
            return (c, k)
        }).max(by: { $0.1 < $1.1 }), !used.contains(breakout.0.ticker) {
            let c = breakout.0
            result.append(Highlight(kind: .capMilestone, company: c,
                title: "시총 돌파", detail: "\(breakout.1)조 달러 돌파", rankDelta: nil))
            used.insert(c.ticker)
        }

        // 3) 급상승 — (previousRank - rank)가 가장 큰(가장 많이 오른) 종목.
        if let riser = list.compactMap({ c -> (Company, Int)? in
            guard let p = c.previousRank else { return nil }
            let d = p - c.rank
            return d > 0 ? (c, d) : nil
        // 상승 칸수 큰 것 우선, 동점이면 순위 높은(rank 작은) 기업 우선.
        }).max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rank > $1.0.rank }), !used.contains(riser.0.ticker) {
            let c = riser.0
            result.append(Highlight(kind: .topGainer, company: c,
                title: "최대 상승", detail: "\(c.previousRank!)위 → \(c.rank)위", rankDelta: riser.1))
            used.insert(c.ticker)
        }

        // 3) 급하락 — (previousRank - rank)가 가장 작은(가장 많이 내린) 종목. rankDelta 음수.
        if let faller = list.compactMap({ c -> (Company, Int)? in
            guard let p = c.previousRank else { return nil }
            let d = p - c.rank
            return d < 0 ? (c, d) : nil
        // 하락 칸수 큰 것(delta 더 음수) 우선, 동점이면 순위 높은(rank 작은) 기업 우선.
        }).min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rank < $1.0.rank }), !used.contains(faller.0.ticker) {
            let c = faller.0
            result.append(Highlight(kind: .topLoser, company: c,
                title: "최대 하락", detail: "\(c.previousRank!)위 → \(c.rank)위", rankDelta: faller.1))
            used.insert(c.ticker)
        }

        // 5) 대형 등락률 — |당일 등락률|이 가장 큰 종목(3% 이상). 순위가 안 변한 날도 살아있게.
        if let mover = list.filter({ abs($0.change) >= 3.0 && !used.contains($0.ticker) })
            .max(by: { abs($0.change) < abs($1.change) }) {
            let up = mover.change >= 0
            // 기업명 → 순위 → 퍼센테이지 순서: 유저가 순위를 인지하고 리스트에서 바로 찾아 내려갈 수 있게.
            result.append(Highlight(kind: .bigMove, company: mover,
                title: up ? "시총 급등" : "시총 급락", detail: "\(mover.rank)위",
                rankDelta: nil, percentMove: mover.change))
            used.insert(mover.ticker)
        }

        // 6) Top-N 진입 — 오늘 Top10/50/100(현재 목록 크기 내 유효한 것) 문턱을 처음 넘은 종목.
        //    prevEff = previousRank ?? (n+1)(추적 밖). 가장 권위 있는(작은) 문턱 크로싱을 고른다.
        if hasBaseline {
            let thresholds = [10, 50, 100].filter { $0 <= n }
            var best: (c: Company, t: Int)? = nil
            for c in list where !used.contains(c.ticker) {
                let prevEff = c.previousRank ?? (n + 1)
                guard let t = thresholds.first(where: { prevEff > $0 && c.rank <= $0 }) else { continue }
                if best == nil || t < best!.t || (t == best!.t && c.rank < best!.c.rank) {
                    best = (c, t)
                }
            }
            if let b = best {
                result.append(Highlight(kind: .newEntry, company: b.c,
                    title: "Top\(b.t) 진입", detail: "\(b.c.rank)위", rankDelta: nil))
                used.insert(b.c.ticker)
            }
        }

        // 5) 폴백/기본 — 현재 1위(서열). 변화가 없어도 항상 채워 절대 비지 않게 한다.
        if let leader = list.first(where: { $0.rank == 1 }) ?? list.first {
            let cap = formatMarketCap(leader.marketCapUSD, currency: displayCurrency, exchangeRate: displayRate)
            result.append(Highlight(kind: .leader, company: leader,
                title: "현재 1위", detail: "1위 · \(cap)", rankDelta: nil))
        }
        return result
    }

    private func isLoading(for market: Market) -> Bool {
        if let f = feed(for: market) { return f.isLoading && f.companies.isEmpty }
        return viewModel.isLoading && viewModel.companies.isEmpty
    }

    private func isError(for market: Market) -> Bool {
        if let f = feed(for: market) { return f.isError && f.companies.isEmpty }
        return viewModel.isError && viewModel.companies.isEmpty
    }

    private func isStale(for market: Market) -> Bool {
        if let f = feed(for: market) { return f.isStale }
        return viewModel.isStale
    }

    private func basDt(for market: Market) -> String? { feed(for: market)?.basDt }
    private func asOf(for market: Market) -> String? { feed(for: market)?.asOf }

    // MARK: 섹션 페이지 — 각 거래소별 스크롤 가능한 기업 목록

    @ViewBuilder
    private func marketPage(for market: Market) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !isError(for: market) && !market.comingSoon {
                    ColumnHeader(sortField: $sortField, sortOrder: $sortOrder)
                }

                if market.comingSoon {
                    ComingSoonView(market: market)
                } else if isLoading(for: market) {
                    ForEach(1...20, id: \.self) { rank in
                        SkeletonCompanyRow(rank: rank)
                    }
                } else if isError(for: market) {
                    ErrorStateView()
                } else if companies(for: market).isEmpty {
                    EmptyMarketView(market: market)
                } else {
                    let list = sortedCompanies(for: market)
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, company in
                        CompanyRow(
                            company: company,
                            currency: displayCurrency,
                            exchangeRate: displayRate
                        )
                        if (index + 1) % AdsConfig.bannerRowInterval == 0 && index + 1 < list.count {
                            AdBannerSlot()
                        }
                    }
                    // v1은 ALL 섹션을 상위 20개만 노출. v2에서 100개로 확대 예정이라
                    // 마지막 종목 아래에 "확장 준비 중" 안내를 붙인다.
                    if market == .all {
                        ExpansionFooter()
                    }
                }
            }
            .padding(.horizontal, 16)
            // 마지막 항목이 하단 페이드 구간을 지나 완전히 읽히도록 여유만 둔다(임의 흰 여백 제거).
            .padding(.bottom, 44)
        }
        // 토스식 하단 페이드 — 거래소 필터의 좌우 페이드와 동일한 방식(그라데이션 마스크).
        // 마지막 행이 배경으로 서서히 사라지며 "아래로 더 있다"를 인지시킨다. 상단은 불투명 유지.
        .mask(
            VStack(spacing: 0) {
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
            }
        )
        .background(theme.background)
    }

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // 고정 헤더 — 섹션을 스와이프해도 항상 화면 상단에 유지
            LiveIndicatorBar(
                market: selectedMarket,
                currentTime: currentTime,
                basDt: basDt(for: selectedMarket),
                asOf: asOf(for: selectedMarket),
                vScale: vScale,
                onSearch: { showSearch = true },
                onMenu: { withAnimation(.easeInOut(duration: 0.32)) { showMenu = true } }
            )
            .padding(.top, 6 * vScale)

            // 상단 하이라이트 블록 — 좌측: "오늘의 순위 사건"(카테고리+기업정보 2줄 로테이션),
            // 우측: 거래소 지수 스파크라인. 블록을 한 행만큼 키워 아래 목록이 8→7개로 노출된다.
            // 블록 높이는 vScale(기준 iPhone 17 Pro 874pt) 비례라 모든 기기에서 동일 비율 유지.
            // ※ 목록 노출 개수 미세조정 knob = 아래 .frame(height:) 값(1행 ≈ 78pt).
            HStack(alignment: .center, spacing: 12) {
                MarketHighlightTicker(
                    highlights: highlights(for: selectedMarket),
                    currentIndex: highlightIndex,
                    vScale: vScale
                )
                // 매핑된 거래소(ALL·US·KR)에서만 그래프 노출 — 미매핑 탭은 티커가 폭을 회수한다.
                if selectedMarket.chartParam != nil {
                    MarketIndexSparkline(chart: viewModel.charts[selectedMarket], vScale: vScale)
                        .frame(width: 130 * vScale)
                        .offset(x: -18 * vScale)   // 그래프를 살짝 왼쪽으로(기기별 비율 유지)
                }
            }
            .frame(height: 92 * vScale)
            .padding(.leading, 30)      // 하이라이트 행을 상단 바보다 살짝 왼쪽으로
            .padding(.trailing, 17)
            .padding(.top, 2 * vScale)
            .padding(.bottom, 4 * vScale)

            if isStale(for: selectedMarket) {
                StaleBanner()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            MarketFilterBar(selected: selectedMarket, onSelect: selectMarket)
                .padding(.bottom, 12 * vScale)

            // 섹션별 페이지 — TabView가 손가락 드래그에 비례한 이동과 스냅을 네이티브로 처리.
            // 모든 Market.allCases 섹션이 동일하게 좌우 스와이프로 전환된다.
            TabView(selection: $selectedMarket) {
                ForEach(Market.allCases) { market in
                    marketPage(for: market)
                        .tag(market)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            // 리스트를 화면 맨 아래까지 흘려보내 하단 흰 여백(안전영역 갭)을 없애고 표시 공간 확보.
            // (하단 페이드가 홈 인디케이터 위로 자연스럽게 콘텐츠를 감싼다.)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .foregroundStyle(theme.label)
        .environment(\.appTheme, theme)
        .background(theme.background.ignoresSafeArea())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewportHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewportHeight = h }
            }
            .ignoresSafeArea()
        )
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // 로그인 완료 시 어느 섹션에 있었든 홈의 ALL 섹션으로 되돌린다.
            if signedIn {
                showMenu = false
                selectedMarket = .all
            }
        }
        .onChange(of: selectedMarket) { _, _ in
            // 거래소 전환 시 하이라이트 로테이션을 처음(우선순위 최상단)부터 다시 시작.
            highlightIndex = 0
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(
                companies: searchableCompanies,
                currency: displayCurrency,
                exchangeRate: displayRate,
                onDismiss: { showSearch = false }
            )
        }
        .animation(.easeInOut(duration: 0.45), value: colorScheme)
        .task {
            while !Task.isCancelled {
                await viewModel.fetch()
                // 서버 quote 캐시(20초)와 정렬. sleep이 fetch 뒤라 실제 간격은 항상 20초 초과 → 매 호출 신선.
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .task {
            // 검색 유니버스 워밍업: 홈 기본 데이터(ALL)가 먼저 뜨도록 잠깐 양보한 뒤,
            // 백엔드 피드를 가진 모든 거래소를 1회 프리페치한다. 이후 거래소 탭 방문 없이도 검색이 전 종목을 커버한다.
            try? await Task.sleep(for: .seconds(1))
            await viewModel.prefetchExchangesForSearch()
        }
        .task(id: selectedMarket) {
            guard selectedMarket.apiExchangeParam != nil else { return }
            while !Task.isCancelled {
                await viewModel.fetchExchange(selectedMarket)
                // 서버 quote 캐시(20초)와 정렬. sleep이 fetch 뒤라 실제 간격은 항상 20초 초과 → 매 호출 신선.
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .task(id: selectedMarket) {
            // 거래소 지수 스파크라인 — 탭 진입 시 1회 로드(일별 데이터라 캐시되면 재호출 없음).
            await viewModel.fetchChart(selectedMarket)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                currentTime = Date()
            }
        }
        .task {
            // 상단 하이라이트 로테이션 — 현재 거래소 하이라이트 개수만큼 순환. 1개(폴백만)면 정지.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                let count = highlights(for: selectedMarket).count
                guard count > 1 else { continue }
                // 토스식 — 바운스 없이 천천히 부드럽게 위로 넘어가며 입체적으로 안착.
                withAnimation(.smooth(duration: 0.9)) {
                    highlightIndex = (highlightIndex + 1) % count
                }
            }
        }
        // 홈스크린/맥 위젯용 스냅샷 — 앱 활성 시 즉시 1회 + 5분마다 갱신.
        // 4개 거래소 Top5와 로고 PNG를 App Group에 써서 위젯이 오프라인으로 표시할 수 있게 한다.
        .task {
            while !Task.isCancelled {
                await WidgetSnapshotWriter.update()
                try? await Task.sleep(for: .seconds(300))
            }
        }

        if showMenu {
            MenuView(
                onDismiss: { withAnimation(.easeInOut(duration: 0.32)) { showMenu = false } }
            )
            .transition(.move(edge: .trailing))
            .zIndex(2)
        }
        } // ZStack
    }
}

// MARK: - Stale Banner

struct StaleBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text("API 일시 오류 — 마지막 캐시 데이터 표시 중")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Ad Banner Slot (띠배너 광고 — Google Mobile Ads 적응형 배너)

/// 기업 리스트 `AdsConfig.bannerRowInterval`개마다 삽입되는 띠배너(가로 스트립) 광고.
///
/// 리스트 좌우 패딩(16pt)을 제외한 폭에 맞춘 앵커드 적응형 배너를 로드한다.
/// 광고가 아직 로드되지 않았을 때도 리스트 흐름이 튀지 않도록, 배너와 동일한 크기의
/// 지면(자리)을 항상 확보한다.
struct AdBannerSlot: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        // 리스트 콘텐츠 폭 = 화면 폭 - 좌우 패딩(16*2). 이 폭에 맞춘 적응형 배너 크기 계산.
        // iOS 26에서 UIScreen.main이 deprecated → Apple 권장대로 활성 window scene의
        // screen에서 폭을 얻는다. (렌더링 중인 뷰는 항상 scene을 가지므로 폴백 상수는 사실상 미사용)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let width = (scene?.screen.bounds.width ?? 393) - 32
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)

        BannerAdView(adUnitID: AdsConfig.bannerUnitID, adSize: adSize)
            .frame(width: adSize.size.width, height: adSize.size.height)
            .frame(maxWidth: .infinity)
            // 광고 로딩 전에도 지면이 비어 보이지 않도록 옅은 배경을 깔아 둔다.
            .background(theme.fill.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .padding(.vertical, 2)
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(theme.secondaryLabel)
            Text("백엔드 서버에 연결할 수 없습니다")
                .font(.system(size: 16, weight: .semibold))
            Text("네트워크 상태를 확인한 뒤 다시 시도해주세요")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Skeleton Company Row

struct SkeletonCompanyRow: View {
    let rank: Int
    @Environment(\.appTheme) private var theme
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 20)

            RoundedRectangle(cornerRadius: 14)
                .fill(theme.fill)
                .frame(width: logoTileSize, height: logoTileSize)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 72, height: 14)
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 40, height: 11)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 68, height: 14)
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.fill)
                    .frame(width: 48, height: 11)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(shimmer ? 0.45 : 1.0)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.85)
                .repeatForever(autoreverses: true)
                .delay(Double(rank) * 0.06)
            ) {
                shimmer = true
            }
        }
    }
}

// MARK: - Market Filter Bar (가로 스크롤 칩)

struct MarketFilterBar: View {
    let selected: Market
    let onSelect: (Market) -> Void
    @Environment(\.appTheme) private var theme
    @Namespace private var chipNamespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Market.allCases) { market in
                        chip(market)
                            .id(market)
                    }
                }
                // 선택 캡슐이 칩 사이를 미끄러지듯 이동하도록 선택값 변화를 스프링으로 애니메이션.
                // (ALL은 맨 왼쪽 끝이라 스크롤 재정렬 모션이 없어, 애니메이션이 없으면 캡슐이
                //  툭 튀어 보였다. matchedGeometryEffect + 이 애니메이션으로 모든 칩이 균일하게 미끄러진다.)
                .animation(.spring(response: 0.22, dampingFraction: 0.9), value: selected)
                // CompanyRow / ColumnHeader의 좌우 패딩(16)과 시작점을 맞춤
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            // 양 끝을 옅게 페이드시켜 "가로 스크롤 가능"을 직관적으로 안내.
            // 배경색에 의존하지 않도록 콘텐츠 자체를 마스크로 흐리게 처리한다.
            .mask(edgeFadeMask)
            // 선택된 섹션이 바뀌면 해당 칩이 가운데로 스크롤됨 (Toss 스타일)
            .onChange(of: selected) { _, newValue in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// 좌우 끝 20pt 구간을 투명하게 페이드아웃하는 마스크.
    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private func chip(_ market: Market) -> some View {
        let isSelected = selected == market
        Button {
            onSelect(market)
        } label: {
            Text(market.title)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? theme.background : theme.label)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(theme.label)
                            // 선택 칩이 바뀔 때 캡슐 프레임이 이전 칩→새 칩으로 보간되어 미끄러진다.
                            .matchedGeometryEffect(id: "selectedChip", in: chipNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Launch Vote (출시 투표 집계)

/// 기기 고유 식별자 — 서버가 SET으로 세어 한 기기가 여러 번 눌러도 1로 집계(중복 방지).
enum DeviceID {
    static let current: String = {
        let key = "titansDeviceID"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }()
}

/// titans-web `/api/launch-vote` 클라이언트.
enum LaunchVoteAPI {
    private static var base: URL {
        URL(string: "\(MarketCapViewModel.apiBase)/api/launch-vote")!
    }

    /// 거래소별 하트 수. 실패 시 빈 딕셔너리.
    static func counts() async -> [String: Int] {
        do {
            let (data, _) = try await URLSession.shared.data(from: base)
            return try JSONDecoder().decode(CountsResponse.self, from: data).counts
        } catch {
            return [:]
        }
    }

    /// 하트 추가(wants=true)/취소(false). 성공 시 갱신된 총합, 실패 시 nil.
    static func vote(market: String, wants: Bool) async -> Int? {
        var req = URLRequest(url: base)
        req.httpMethod = wants ? "POST" : "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["market": market, "deviceId": DeviceID.current])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(VoteResponse.self, from: data).count
        } catch {
            return nil
        }
    }

    private struct CountsResponse: Decodable { let counts: [String: Int] }
    private struct VoteResponse: Decodable { let count: Int }
}

// MARK: - Coming Soon View (1차 출시 범위 밖 — 준비 중 + 출시 투표)

struct ComingSoonView: View {
    let market: Market
    @Environment(\.appTheme) private var theme

    /// 이 기기에서 하트를 눌렀는지(즉시 UI 반영 + 서버 확인 전 상태 유지).
    @AppStorage private var wantsLaunch: Bool
    @State private var count: Int = 0
    @State private var isBusy = false

    init(market: Market) {
        self.market = market
        _wantsLaunch = AppStorage(wrappedValue: false, "launchWish_\(market.rawValue)")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 38))
                .foregroundStyle(theme.tertiaryLabel)
            Text("\(market.title) 준비 중")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            Text("하트가 많은 증권거래소부터 출시돼요")
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center)

            // 하트 토글 — 서버 집계와 연동. 누르면 총 인원 수가 동적으로 갱신됨
            VStack(spacing: 8) {
                Button {
                    Task { await toggleVote() }
                } label: {
                    Image(systemName: wantsLaunch ? "heart.fill" : "heart")
                        .font(.system(size: 34))
                        .foregroundStyle(wantsLaunch ? Color.pink : theme.tertiaryLabel)
                        .scaleEffect(wantsLaunch ? 1.0 : 0.92)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Text("\(count)명이 출시를 원해요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
                    .contentTransition(.numericText())
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .task(id: market) { await loadCount() }
    }

    private func loadCount() async {
        if let c = await LaunchVoteAPI.counts()[market.rawValue] {
            withAnimation(.snappy) { count = c }
        }
    }

    private func toggleVote() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let newValue = !wantsLaunch
        // 낙관적 UI — 서버 응답 전 즉시 반영
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            wantsLaunch = newValue
            count = max(0, count + (newValue ? 1 : -1))
        }

        if let serverCount = await LaunchVoteAPI.vote(market: market.rawValue, wants: newValue) {
            withAnimation(.snappy) { count = serverCount }
        } else {
            // 실패 → 롤백
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                wantsLaunch = !newValue
                count = max(0, count + (newValue ? -1 : 1))
            }
        }
    }
}

// MARK: - Empty Market View (필터 결과 없음)

struct EmptyMarketView: View {
    let market: Market
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(theme.tertiaryLabel)
            Text("\(market.title) 상장 종목이 없습니다")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Expansion Footer (ALL 섹션 하단 — v2 확대 예고)

/// ALL 섹션은 v1에서 상위 20개만 노출한다. 마지막 종목 아래에 붙어
/// "더 많은 기업이 곧 추가된다"는 것을 알려주는 안내 푸터. (v2에서 100개로 확대 예정)
struct ExpansionFooter: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 26))
                .foregroundStyle(theme.tertiaryLabel)
            Text("확장 준비 중이에요")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            Text("Coming Soon 2026.10.01")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Live Indicator Bar

struct LiveIndicatorBar: View {
    let market: Market                      // 현재 섹션 — 상태 문구(실시간/종가 기준)를 결정
    let currentTime: Date                   // 실시간 섹션 시계
    let basDt: String?                      // 코스피/코스닥 기준일("YYYYMMDD")
    var asOf: String? = nil                 // JPX/SSE/SZSE/NSE 스냅샷 거래일("YYYY-MM-DD")
    var vScale: CGFloat = 1                 // 헤더 세로 비례 계수 (기기별 동일 비율)
    var onSearch: () -> Void = {}           // 돋보기 → 검색 화면
    var onMenu: () -> Void = {}             // ≡ → 메뉴
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            // market이 바뀌면 텍스트 내용이 교체되고, 그 너비 변화가 스프링으로 자연스럽게 애니메이션됨.
            // 왼쪽 시작점은 고정, 오른쪽만 텍스트 길이에 맞춰 늘었다 줄었다 함.
            MarketStatusView(market: market, currentTime: currentTime, basDt: basDt, asOf: asOf)

            Spacer()

            // 우측 상단 액션 버튼 — 토스 스타일 (검색 · 메뉴)
            HStack(spacing: 27) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)

                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 22, weight: .medium))
        }
        .padding(.leading, 28)
        .padding(.trailing, 32)   // 검색·메뉴 버튼을 우측 끝에서 조금 안쪽으로. 통화 토글(테두리 pill)은 글리프보다 시각적으로 왼쪽에 보여, trailing을 더 작게(17) 줘 우측을 시각적으로 맞춘다. (통화 토글과 함께 8pt씩 오른쪽으로 이동: 40→32.)
        .padding(.vertical, 6 * vScale)
        // market 변경 시 텍스트 너비 변화(레이아웃)를 스프링으로 애니메이션
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: market)
    }
}

// MARK: - Market Status View (섹션별 데이터 기준 표시)

/// 화면 좌측 상단의 데이터 기준 인디케이터. 초록 하이라이트 단어가 **선택된 거래소명**으로 바뀌어,
/// 옆의 날짜/시각이 어느 거래소 기준인지 한눈에 보이게 한다(섹션 전환 시 함께 동적으로 갱신).
///  · realtime(NASDAQ/NYSE/EURONEXT/FWB, 60초 폴링): "NASDAQ HH:mm 기준" / ALL은 "HH:mm 기준 · 일부 종가"
///  · eodDated(KOSPI/KOSDAQ=basDt, SSE/SZSE/NSE=asOf): "KOSPI 2026.07.23 종가 기준" (갱신된 실제 거래일)
///  · reportedCap(JPX=asOf): "JPX 2026.07.23 기준" — 제공사 보고 시가총액(일별 주가 미반영)이라 "종가" 미표기
///  · comingSoon(데이터 없음): "HKEX 출시 준비 중" (초록 대신 흐린 색으로 구분)
/// 우측 ⓘ 버튼으로 거래소별 데이터 기준·갱신 주기·공식 사이트 링크(MarketInfoSheet)를 연다.
struct MarketStatusView: View {
    let market: Market
    let currentTime: Date
    let basDt: String?                      // "20260723" (코스피/코스닥만)
    var asOf: String? = nil                 // "2026-07-23" (JPX/SSE/SZSE/NSE EOD 스냅샷 거래일)
    @Environment(\.appTheme) private var theme
    @State private var showInfo = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// basDt("YYYYMMDD")·asOf("YYYY-MM-DD") 둘 다 "YY.MM.DD"로 정규화(연도 2자리 — ⓘ 버튼 공간 확보용,
    /// 모든 EOD 거래소 공통). 형식이 다르면 원본 그대로.
    private func formatDate(_ s: String) -> String {
        let digits = s.filter { $0.isNumber }
        guard digits.count == 8 else { return s }
        return "\(digits.dropFirst(2).prefix(2)).\(digits.dropFirst(4).prefix(2)).\(digits.dropFirst(6).prefix(2))"
    }

    /// EOD 섹션의 기준일 원본 — KR은 basDt, 그 외(JPX/CN/NSE)는 asOf.
    private var eodDate: String? { basDt ?? asOf }

    /// 거래소명 옆 부가 문구 — 데이터 형태(dataBasis)에 따라 기준일/실시간 시각/준비 중.
    private var detail: String {
        switch market.dataBasis {
        case .comingSoon:
            return "출시 준비 중"
        case .eodDated:
            // KR·중국·인도: "YYYY.MM.DD 종가 기준". 날짜는 갱신된 거래일이라 주말/공휴일 오해가 없다.
            return eodDate.map { "\(formatDate($0)) 종가 기준" } ?? "불러오는 중"
        case .reportedCap:
            // JPX: 제공사 보고 시가총액(일별 주가 미반영) → "종가 기준"으로 표기하지 않는다.
            // 날짜는 데이터를 확인·갱신한 기준일(asOf). "기준"만 붙여 종가 산출 오해를 방지.
            return eodDate.map { "\(formatDate($0)) 기준" } ?? "불러오는 중"
        case .realtime:
            let time = Self.timeFormatter.string(from: currentTime)
            // ALL은 KR(종가) + US(실시간)를 섞어 보여주므로 단서를 덧붙인다.
            if market == .all { return "\(time) 기준 · 일부 종가" }
            return "\(time) 기준"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // 국가 국기 아이콘 — 원형 클리핑으로 일관된 모양 유지.
            // 레이아웃 프레임은 모든 섹션에서 18로 고정한다. (ALL만 프레임을 키우면
            // 진입/이탈 시 국기 크기 변화가 텍스트 너비 스프링과 경쟁하는 두 번째 레이아웃
            // 애니메이션이 되어 헤더가 툭 끊겨 보인다.)
            // 글로브 PNG는 내부 여백이 커 작아 보이므로, 레이아웃은 그대로 두고 시각적으로만
            // scaleEffect로 키운다 — 가로 레이아웃에 영향을 주지 않아 텍스트 스프링이 균일해진다.
            Image(market.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .scaleEffect(market == .all ? 1.33 : 1.0)
                .opacity(market.comingSoon ? 0.35 : 1.0)

            // 초록 하이라이트 = 선택된 거래소명 (준비 중은 흐린 색)
            Text(market.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(market.comingSoon ? theme.secondaryLabel : Color.green)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()          // 실시간 시계 자릿수 흔들림 방지
                .foregroundStyle(theme.secondaryLabel)

            // ⓘ 데이터 기준 상세 — 무엇을 기준으로 어떻게 갱신되는지 + 공식 사이트 링크.
            // 배치: 국기 → 거래소명 → 기준일 → ⓘ (맨 오른쪽이라 탭하기 쉬움). comingSoon(정보 없음)은 숨긴다.
            if let info = market.info {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(market.title) 데이터 기준 안내")
                .sheet(isPresented: $showInfo) {
                    MarketInfoSheet(market: market, info: info)
                }
            }
        }
    }
}

// MARK: - Market Info Sheet (거래소 데이터 기준 상세 + 공식 사이트 링크)

/// ⓘ 버튼으로 열리는 상세 시트. "이 시가총액이 무엇을 기준으로 어떻게 갱신되는지"를 명확히 밝혀
/// 유저가 공식 거래소 사이트와 직접 대조할 수 있게 한다(리텐션·신뢰 목적).
struct MarketInfoSheet: View {
    let market: Market
    let info: MarketInfo
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 — 국기 + 거래소 정식명 + 닫기
            HStack(spacing: 10) {
                Image(market.flagImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(market.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.label)
                    Text(info.fullName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }
            .padding(.bottom, 20)

            // 데이터 기준 · 갱신 주기
            infoRow(icon: "chart.bar.doc.horizontal", title: "시가총액 기준", body: info.basis)
            Divider().overlay(theme.stroke).padding(.vertical, 14)
            infoRow(icon: "clock.arrow.circlepath", title: "갱신 주기", body: info.schedule)

            // 홈 상단 지수 그래프 설명 — 그래프가 있는 거래소만 노출.
            if let chartNote = info.chartNote {
                Divider().overlay(theme.stroke).padding(.vertical, 14)
                infoRow(icon: "chart.xyaxis.line", title: "지수 그래프", body: chartNote)
            }

            // USD 환산 안내 — 공식 사이트 수치와의 소폭 차이 이유를 미리 밝혀 신뢰 확보.
            Text("시가총액은 미국 달러(USD)로 환산해 순위를 매깁니다. 환율 변동 및 발행주식수 반영 시점 차이로 공식 사이트 수치와 소폭 다를 수 있습니다.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 20)

            // 공식 사이트 링크 — 유저가 직접 대조. 대표 도메인으로 오픈(Safari).
            if let name = info.officialName,
               let urlString = info.officialURLString,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("공식 사이트에서 확인  ·  \(name)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(theme.label)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func infoRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.label)
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Single Market Ticker (하나의 카드, 종목 순환)

struct SingleMarketTicker: View {
    let indices: [MarketIndex]
    let currentIndex: Int
    var vScale: CGFloat = 1                 // 헤더 세로 비례 계수 (기기별 동일 비율)

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<indices.count, id: \.self) { i in
                    if i == currentIndex {
                        MarketIndexRow(index: indices[i])
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50 * vScale)
            .clipped()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6 * vScale)
    }
}

// MARK: - Highlight (오늘의 순위 사건)

/// 상단 티커에 로테이션으로 노출되는 "오늘의 순위 사건". company는 로고/색 표시용.
struct Highlight: Identifiable {
    enum Kind { case overtake, topGainer, topLoser, bigMove, capMilestone, newEntry, leader }
    /// 하이라이트 섹션 통일 색 — 상승(화살표·숫자)=빨강, 하락=파랑.
    static let increaseColor = Color(red: 0.95, green: 0.20, blue: 0.20)
    static let decreaseColor = Color(red: 0.10, green: 0.43, blue: 0.92)
    static let entryColor    = Color(red: 0.12, green: 0.66, blue: 0.42)  // 신규 진입=초록(하락 파랑과 혼동 방지)
    static let milestoneColor = Color(red: 0.80, green: 0.52, blue: 0.05) // 조 달러 돌파=앰버
    let id = UUID()
    let kind: Kind
    let company: Company
    let title: String
    let detail: String
    let rankDelta: Int?          // 양수=상승 칸수(빨강 ▲), 음수=하락 칸수(파랑 ▼), nil=표시 없음. (prev - rank)
    var percentMove: Double? = nil  // 대형 등락률(%) — 양수=빨강 ▲%, 음수=파랑 ▼%. bigMove 전용.

    var emoji: String {
        switch kind {
        case .overtake:     return "⚔️"
        case .topGainer:    return "🔺"
        case .topLoser:     return "🔷"
        case .bigMove:      return "🔥"
        case .capMilestone: return "🏆"
        case .newEntry:     return "🆕"
        case .leader:       return "👑"
        }
    }

    /// 카테고리 인디케이터를 이모지 대신 커스텀 아이콘(Assets.xcassets)으로 대체하는 에셋명.
    /// nil이면 emoji를 사용한다. (시총 급락은 전용 아이콘이 없어 emoji로 폴백)
    var categoryAsset: String? {
        switch kind {
        case .leader:    return "cat_leader"   // 현재 1위 — 트로피
        case .topGainer: return "cat_gainer"   // 최대 상승 — 상승 화살표
        case .topLoser:  return "cat_loser"    // 최대 하락 — 하락 화살표
        case .bigMove:   return (percentMove ?? 0) >= 0 ? "cat_surge" : nil  // 시총 급등만 아이콘
        default:         return nil
        }
    }

    /// 타이틀 칩 색.
    var accent: Color {
        switch kind {
        case .overtake, .topGainer: return Self.increaseColor
        case .topLoser:             return Self.decreaseColor
        case .bigMove:              return (percentMove ?? 0) >= 0 ? Self.increaseColor : Self.decreaseColor
        case .capMilestone:         return Self.milestoneColor
        case .newEntry:             return Self.entryColor
        case .leader:               return Color(red: 0.86, green: 0.62, blue: 0.10)
        }
    }
}

// MARK: - Market Highlight Ticker (카테고리 + 기업정보 2줄 로테이션)

/// "오늘의 순위 사건"을 카테고리(1줄) + 기업정보(2줄)로 순환 노출. 우측 지수 그래프와
/// 한 HStack에 나란히 놓이므로, 폭은 부모가 관리하고(여기선 maxWidth 채움) 좌측 정렬만 한다.
struct MarketHighlightTicker: View {
    let highlights: [Highlight]
    let currentIndex: Int
    var vScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(highlights.enumerated()), id: \.offset) { i, h in
                if i == currentIndex {
                    HighlightRow(highlight: h, vScale: vScale)
                        // 토스식 입체 상승 전환: 새 항목이 아래에서 떠오르며(move+scale) 커지고 나타나고,
                        // 이전 항목은 위로 떠오르며 작아지고 사라진다. scale+opacity 크로스페이드로 깊이감.
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom)
                                .combined(with: .scale(scale: 0.93, anchor: .bottom))
                                .combined(with: .opacity),
                            removal: .move(edge: .top)
                                .combined(with: .scale(scale: 0.93, anchor: .top))
                                .combined(with: .opacity)
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66 * vScale)
        .clipped()
    }
}

struct HighlightRow: View {
    let highlight: Highlight
    var vScale: CGFloat = 1
    @Environment(\.appTheme) private var theme

    var body: some View {
        // 기본은 2줄(카테고리 / 기업명+등락수치). 둘째 줄이 우측 지수그래프와 충돌할 만큼
        // 길어지면 ViewThatFits가 자동으로 3줄(카테고리 / 기업명 / 등락수치)로 전환한다.
        ViewThatFits(in: .horizontal) {
            twoLine
            threeLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 카테고리 칩 (아이콘/이모지 + 타이틀) — 조금 크고 굵게.
    // 지정 아이콘(에셋)이 있으면 이미지로, 없으면 이모지로 렌더한다.
    private var categoryChip: some View {
        HStack(spacing: 5) {
            if let asset = highlight.categoryAsset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Text(highlight.emoji)
                    .font(.system(size: 14))
            }
            Text(highlight.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(highlight.accent)
        }
        .fixedSize()
    }

    // 기업명
    private func companyName(scale: CGFloat) -> some View {
        Text(highlight.company.name)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(theme.label)
            .lineLimit(1)
            .minimumScaleFactor(scale)
            .fixedSize(horizontal: scale >= 1, vertical: false)
    }

    // 등락수치 = 순위/부가정보(detail) + 델타·등락률 화살표
    @ViewBuilder private var changeInfo: some View {
        Text(highlight.detail)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.secondaryLabel)
            .lineLimit(1)
            .fixedSize()
        if let d = highlight.rankDelta, d != 0 {
            let up = d > 0
            HStack(spacing: 1) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Text("\(abs(d))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(up ? Highlight.increaseColor : Highlight.decreaseColor)
            .fixedSize()
        } else if let p = highlight.percentMove {
            let up = p >= 0
            HStack(spacing: 1) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text(String(format: "%.2f%%", abs(p)))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(up ? Highlight.increaseColor : Highlight.decreaseColor)
            .fixedSize()
        }
    }

    // 2줄: 카테고리 / (기업명 + 등락수치). 한 줄이 넓으면 ViewThatFits가 이걸 버리고 threeLine 선택.
    private var twoLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            categoryChip
            HStack(spacing: 6) {
                companyName(scale: 1)
                changeInfo
            }
            .fixedSize(horizontal: true, vertical: false)   // 실제 폭을 그대로 보고해 ViewThatFits가 충돌을 판정
        }
        // 2줄일 때만 텍스트를 살짝 위로. 3줄은 그대로 유지. 오프셋을 vScale로 스케일해
        // 모든 기기에서 동일 비율로 적용한다.
        .offset(y: -10.5 * vScale)
    }

    // 3줄: 카테고리 / 기업명 / 등락수치
    private var threeLine: some View {
        VStack(alignment: .leading, spacing: 1) {
            categoryChip
            companyName(scale: 0.7)
            HStack(spacing: 5) { changeInfo }
        }
        // 3줄일 때도 텍스트를 아주 살짝 위로. vScale로 스케일해 모든 기기 동일 비율.
        .offset(y: -2 * vScale)
    }
}

// MARK: - Market Index Sparkline (거래소 지수 라인그래프)

/// 홈 상단 우측의 미니 지수 라인. 축·격자 없이 라인 + 아래 그라데이션 채움만 그리는
/// 토스 스타일 스파크라인. 상승=빨강 / 하락=파랑(앱 공통 컨벤션 재사용).
struct MarketIndexSparkline: View {
    let chart: MarketChart?
    var vScale: CGFloat = 1
    @Environment(\.appTheme) private var theme

    private var up: Bool { (chart?.changePercent ?? 0) >= 0 }
    private var lineColor: Color { up ? Highlight.increaseColor : Highlight.decreaseColor }

    // 지수 수치(최신 종가) 표기용 — 천 단위 구분 + 소수 2자리.
    private static let valueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            // 상단: 지수 실제 수치(최신 종가) + 기간 변화율 — 상승 빨강 / 하락 파랑.
            // (지수명은 홈에서 빼고 각 거래소 ⓘ 상세에서 설명한다.)
            if let chart, let latest = chart.points.last {
                HStack(spacing: 4) {
                    Text(Self.valueFormatter.string(from: NSNumber(value: latest)) ?? String(format: "%.2f", latest))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    HStack(spacing: 1) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%.2f%%", abs(chart.changePercent)))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(lineColor)
                .lineLimit(1)
            } else {
                // 로딩/실패 시 상단 라벨 높이만 유지(레이아웃 점프 방지).
                Text(" ").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            // 라인 — 데이터가 없으면(로딩/실패) 빈 프레임만 유지해 레이아웃 점프 방지.
            SparklineShapeView(points: chart?.points ?? [], color: lineColor)
                .frame(height: 40 * vScale)
        }
    }
}

/// 종가 배열을 min~max로 정규화해 라인 + 하단 그라데이션 채움 + 점선 기준선으로 렌더.
/// 토스 오마주: 구간 시작값에 회색 점선 baseline(전일 종가 느낌)을 깔고, 라인 아래를
/// 라인 색으로 은은하게 그라데이션 채움. 라인은 둥근 조인으로 부드럽게.
struct SparklineShapeView: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if points.count >= 2, let lo = points.min(), let hi = points.max(), hi > lo {
                let range = hi - lo
                // 위/아래 3% 여백을 둬 라인이 프레임 가장자리에 붙지 않게 한다.
                let padY = h * 0.06
                let plotH = h - padY * 2
                let stepX = w / CGFloat(points.count - 1)
                let pts: [CGPoint] = points.enumerated().map { i, v in
                    CGPoint(x: CGFloat(i) * stepX,
                            y: padY + (plotH - CGFloat((v - lo) / range) * plotH))
                }
                let baselineY = pts[0].y   // 구간 시작값 = 토스식 점선 기준선

                ZStack {
                    // 하단 그라데이션 채움 (라인 아래 → 바닥)
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h))
                        p.addLine(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    // 점선 기준선 (구간 시작값)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: baselineY))
                        p.addLine(to: CGPoint(x: w, y: baselineY))
                    }
                    .stroke(Color.gray.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    // 라인
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

// MARK: - Market Index Row (카드 내부 콘텐츠)

struct MarketIndexRow: View {
    let index: MarketIndex
    @Environment(\.appTheme) private var theme

    private var isPositive: Bool { index.change >= 0 }
    // 토스증권 컨벤션: 상승=빨강, 하락=파랑
    private var trendColor: Color {
        isPositive
            ? Color(red: 0.95, green: 0.20, blue: 0.20)
            : Color(red: 0.10, green: 0.43, blue: 0.92)
    }

    private static let valueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private var formattedValue: String {
        Self.valueFormatter.string(from: NSNumber(value: index.value)) ?? "\(index.value)"
    }

    private var formattedChangePercent: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)\(String(format: "%.2f", index.changePercent))%"
    }

    var body: some View {
        // name · value · percent 를 균일한 8pt 간격으로 묶어 좌측 정렬한다(토스식 tight 그룹).
        // 값과 % 사이에 확장되는 Spacer를 두지 않으므로 둘이 양 끝으로 벌어지지 않는다.
        // 남는 폭은 맨 뒤 Spacer(minLength: 0)가 흡수 → 어떤 기기 폭에서도 간격은 8pt로 동일.
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(index.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize()                       // 짧은 지수명은 항상 온전히 표시
            Text(formattedValue)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .contentTransition(.numericText())
                .lineLimit(1)                      // 자릿수 많은 값도 절대 줄바꿈 금지
                .minimumScaleFactor(0.5)           // 공간 부족 시 값 폰트만 축소해 한 줄 유지
            Text(formattedChangePercent)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)
                .fixedSize()                       // 퍼센트도 항상 온전히 표시
            Spacer(minLength: 0)                   // 그룹 좌측 정렬 (여분 폭 흡수)
        }
    }
}

// MARK: - Brand Logo Tile

/// 로컬 에셋 우선 표시 매핑. Assets.xcassets에 이미지 추가 후 여기에 등록하면
/// 해당 기업은 URL 대신 로컬 이미지를 우선 표시함.
/// 예: "TSLA": "logo_TSLA"
// 로고 파일을 Assets.xcassets에 추가한 뒤 여기에 "TICKER": "asset_name" 형태로 매핑

private struct LogoImage: View {
    let localAssetName: String?    // Xcode Assets 로컬 이미지 (우선)
    let logoDevURL: URL?           // logo.dev 공식 로고 (도메인 기반)
    let ticker: String
    let name: String
    let color: Color

    @State private var remoteImage: UIImage?
    @State private var remoteResolved = false
    @State private var remoteFillsCircle = false   // 배경 있는 원격 로고는 원을 꽉 채움

    var body: some View {
        if let assetName = localAssetName, let raw = UIImage(named: assetName) {
            let cacheKey = ticker as NSString
            if tickersNeedDarkBgRemoval.contains(ticker) {
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingDarkBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else if tickersNeedLightBgRemoval.contains(ticker) {
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingLightBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else if tickersNeedColoredBgRemoval.contains(ticker) {
                let processed: UIImage = {
                    if let cached = LogoProcessingCache.shared.object(forKey: cacheKey) { return cached }
                    guard let p = raw.removingDominantBackground() else { return raw }
                    LogoProcessingCache.shared.setObject(p, forKey: cacheKey)
                    return p
                }()
                styledLogo(Image(uiImage: processed))
            } else {
                styledLogo(Image(assetName))
            }
        } else {
            remoteBody
        }
    }

    // 폴백 순서: logo.dev(공식 로고) → 이니셜 타일.
    // 로고 소스는 라이선스 근거가 있는 것만 사용한다(로컬 에셋 / logo.dev 정식 토큰).
    // AsyncImage 대신 LogoStore(영구 캐시)로 로드해 logo.dev 재호출을 최소화한다.
    @ViewBuilder private var remoteBody: some View {
        Group {
            if let img = remoteImage {
                // 배경이 있는(불투명) 원격 로고는 여백 없이 원을 꽉 채운다.
                styledLogo(Image(uiImage: img), paddingOverride: remoteFillsCircle ? 0 : nil)
            } else if remoteResolved {
                textFallback
            } else {
                Color.clear
            }
        }
        // 행이 다른 종목으로 재사용되면(URL 변경) 다시 로드. 캐시 히트는 네트워크 없이 즉시.
        .task(id: remoteKey) { await loadRemote() }
    }

    private var remoteKey: String {
        logoDevURL?.absoluteString ?? ""
    }

    private func loadRemote() async {
        remoteImage = nil
        remoteResolved = false
        remoteFillsCircle = false
        if let url = logoDevURL, let img = await LogoStore.shared.image(for: url) {
            remoteImage = img
            remoteFillsCircle = img.hasOpaqueBackground()
        }
        remoteResolved = true
    }

    @ViewBuilder
    private func styledLogo(_ image: Image, paddingOverride: CGFloat? = nil) -> some View {
        image
            .resizable()
            .scaledToFit()
            .padding(paddingOverride ?? tickerLogoPadding[ticker] ?? 8)
    }

    /// 숫자 티커(예: KRX "005930.KS")는 이니셜이 무의미하므로, 알파벳 티커면 티커,
    /// 아니면 회사명의 첫 글자로 폴백 이니셜을 만든다.
    private var fallbackInitials: String {
        if ticker.first?.isLetter == true {
            return String(ticker.prefix(2)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var textFallback: some View {
        Text(fallbackInitials)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}


struct BrandLogoTile: View {
    let ticker: String
    let name: String
    let color: Color
    var domain: String? = nil   // 백엔드(DART) 해석 도메인 — 큐레이션(tickerDomain) 미등록 신규 종목 폴백

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    // 큐레이션 도메인이 있으면 그대로 우선(기존 로고 표시 불변), 없을 때만 백엔드 도메인을 쓴다.
    private var resolvedDomain: String? { tickerDomain[ticker] ?? domain }

    // logo.dev 공식 로고. fallback=404로 미보유 시 404 → LogoImage가 이니셜 타일로 폴백.
    private var logoDevURL: URL? {
        resolvedDomain.flatMap {
            URL(string: "https://img.logo.dev/\($0)?token=\(logoDevToken)&size=200&format=png&retina=true&fallback=404")
        }
    }

    var body: some View {
        let offset = tickerLogoOffset[ticker] ?? .zero
        ZStack {
            Circle().fill(tickerCircleBackground[ticker] ?? .white)
            LogoImage(
                localAssetName: tickerLocalLogo[ticker],
                logoDevURL: logoDevURL,
                ticker: ticker,
                name: name,
                color: color
            )
            .offset(x: offset.x, y: offset.y)
        }
        .frame(width: logoTileSize, height: logoTileSize)
        .clipShape(Circle())
        // 라이트 모드에서는 흰 로고 원이 흰 배경에 묻혀 경계가 사라진다.
        // 다크 모드의 원과 동일한 크기(logoTileSize)로 얇은 테두리를 둘러 원 프레임을 살린다.
        .overlay {
            if colorScheme == .light {
                Circle().strokeBorder(theme.stroke, lineWidth: 1)
            }
        }
    }
}

// MARK: - Column Header

struct ColumnHeader: View {
    @Binding var sortField: SortField
    @Binding var sortOrder: SortOrder
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            sortButton("순위", field: .rank)

            // CompanyRow의 로고(폭 50) 자리만큼 비워서 '기업'을 기업명 라인에 맞춤
            Color.clear.frame(width: logoTileSize, height: 0)

            sortButton("기업", field: .name)

            Spacer()

            sortButton("시가총액", field: .marketCap)
                // 헤더 "시가총액" 라벨만 오른쪽으로 조금 이동 — trailing 8→4로 4pt 우측 이동.
                // 화면 끝 기준 고정 pt라 모든 기기에서 동일하게 적용된다.
                .padding(.trailing, -3)
        }
        .font(.system(size: 12, weight: .semibold))
        // CompanyRow의 내부 좌우 패딩(16)과 정렬을 맞춤
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func sortButton(_ title: String, field: SortField) -> some View {
        let isActive = sortField == field
        HStack(spacing: 3) {
            // 제목 탭: 해당 컬럼 활성화(토글). 방향은 위/아래 화살표로 명시적으로 고른다.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isActive {
                        sortOrder = sortOrder == .ascending ? .descending : .ascending
                    } else {
                        sortField = field
                        sortOrder = .ascending
                    }
                }
            } label: {
                Text(title)
                    .foregroundStyle(isActive ? theme.label : theme.secondaryLabel)
            }
            .buttonStyle(.plain)

            // 위 화살표 = 오름차순, 아래 화살표 = 내림차순 (각각 개별 탭)
            VStack(spacing: 1) {
                chevron("chevron.up",   field: field, order: .ascending,  isActive: isActive)
                chevron("chevron.down", field: field, order: .descending, isActive: isActive)
            }
        }
    }

    /// 방향 화살표 한 개 — 탭하면 해당 컬럼을 그 방향으로 정렬한다.
    @ViewBuilder
    private func chevron(_ system: String, field: SortField, order: SortOrder, isActive: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                sortField = field
                sortOrder = order
            }
        } label: {
            Image(systemName: system)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isActive && sortOrder == order ? theme.label : theme.tertiaryLabel)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Market Cap Formatting

/// 원화 조(兆)/억(億) 단위 표기용 포매터 — 천 단위 구분(US 메가캡을 원화로 볼 때 6,380조원 등).
/// 소수 자릿수와 단위는 호출부에서 값 크기에 따라 동적으로 설정한다.
private let krwTrillionFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f
}()

/// 시총 표시 문자열 — 통화별 단위 동적 변환. 목록·검색 화면이 공유한다.
/// `exchangeRate` = "1 USD 당 해당 통화 금액"(USD면 1.0). marketCapUSD 는 trillion USD 단위.
/// · 서구식(USD·EUR): 1T 이상 T, 1T 미만이면 크기에 맞춰 B(십억)·M(백만)로 동적 전환, 통화기호 접두.
/// · 동아시아(KRW·JPY·CNY): 만진법. 1조 미만 → 억 단위 정수; 100조 미만 → 조 소수 2자리; 1000조 미만 → 1자리; 이상 → 정수.
func formatMarketCap(_ marketCapUSD: Double, currency: Currency, exchangeRate: Double) -> String {
    let converted = marketCapUSD * exchangeRate   // 해당 통화의 trillion(兆) 단위 금액

    if currency.usesEastAsianUnits {
        let words = currency.eastAsianUnitWords
        if converted < 1 {
            // 1조 미만: 억 단위 정수로 표시 (1조 = 1만 억)
            let eok = converted * 10_000
            krwTrillionFormatter.minimumFractionDigits = 0
            krwTrillionFormatter.maximumFractionDigits = 0
            let s = krwTrillionFormatter.string(from: NSNumber(value: eok))
                ?? "\(Int(eok.rounded()))"
            return "\(s)\(words.hundredMillion)"
        } else {
            let digits: Int
            if converted < 100       { digits = 2 }
            else if converted < 1000 { digits = 1 }
            else                     { digits = 0 }
            krwTrillionFormatter.minimumFractionDigits = digits
            krwTrillionFormatter.maximumFractionDigits = digits
            let s = krwTrillionFormatter.string(from: NSNumber(value: converted))
                ?? String(format: "%.\(digits)f", converted)
            return "\(s)\(words.trillion)"
        }
    } else {
        // 서구식(USD·EUR): T/B/M
        let symbol = currency.westernSymbol
        let t = converted
        if t >= 1 {
            return String(format: "\(symbol)%.2fT", t)
        } else if t >= 0.001 {                     // 1B = 0.001T
            return String(format: "\(symbol)%.2fB", t * 1_000)
        } else {
            return String(format: "\(symbol)%.2fM", t * 1_000_000)
        }
    }
}

// MARK: - Company Row

struct CompanyRow: View {
    let company: Company
    let currency: Currency
    let exchangeRate: Double
    @Environment(\.appTheme) private var theme

    private var formattedMarketCap: String {
        formatMarketCap(company.marketCapUSD, currency: currency, exchangeRate: exchangeRate)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("\(company.rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.tertiaryLabel)
                    // 세 자리 순위(예: 100)가 컬럼 폭을 넘어 줄바꿈되지 않도록 한 줄 고정
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let prev = company.previousRank, prev != company.rank {
                    let delta = prev - company.rank  // 양수 = 순위 상승 (숫자 감소)
                    HStack(spacing: 1) {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 7, weight: .bold))
                        Text("\(abs(delta))")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(delta > 0
                        ? Color(red: 0.95, green: 0.20, blue: 0.20)
                        : Color(red: 0.10, green: 0.43, blue: 0.92))
                }
            }
            // 세 자리 순위(100)도 한 줄로 담기도록 폭을 24로. 중앙 정렬 유지.
            .frame(width: 24, alignment: .center)

            BrandLogoTile(ticker: company.ticker, name: company.name, color: company.color, domain: company.domain)

            VStack(alignment: .leading, spacing: 3) {
                Text(company.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(company.ticker)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryLabel)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedMarketCap)
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.numericText())

                HStack(spacing: 2) {
                    Image(systemName: company.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.2f%%", abs(company.change)))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(company.change >= 0 ? .green : .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
