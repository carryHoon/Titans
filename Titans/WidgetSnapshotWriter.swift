//
//  WidgetSnapshotWriter.swift
//  Titans
//
//  앱이 활성 거래소(NASDAQ/NYSE/KOSPI/KOSDAQ/JPX/SSE/SZSE/EURONEXT/FWB/NSE)의 Top 시가총액을 받아 App Group 컨테이너에
//  스냅샷 JSON으로 쓰고, 각 종목 로고를 앱과 동일한 규칙으로 최종 렌더링해 PNG로 저장한다.
//  위젯 익스텐션은 네트워크 없이 이 스냅샷/PNG만 읽어 앱과 픽셀 단위로 동일하게 표시한다.
//
//  재사용: MarketCapResponse/APICompanyResult(DTO), MarketCapViewModel.host, LogoStore,
//         TickerData.swift 테이블(tickerLocalLogo/tickerCircleBackground/…), logoTileSize.
//  로고 배경제거 픽셀 함수는 ContentView.swift에서 private이라 아래에 동일 로직을 복제한다.
//

import SwiftUI
import UIKit
import WidgetKit

enum WidgetSnapshotWriter {

    /// 위젯에 노출할 거래소와 백엔드 `?exchange=` 파라미터.
    /// 앱 활성 거래소(Market.apiExchangeParam != nil) 10개와 동일하게 유지한다.
    private static let exchanges: [String] = [
        "nasdaq", "nyse", "kospi", "kosdaq", "jpx", "sse", "szse", "euronext", "fwb", "nse"
    ]

    /// 크기별 최대 노출 수(Large=Top8)에 맞춰 저장 상한.
    private static let topCount = 8

    // logo.dev publishable token — ContentView와 동일(pk_ 공개 토큰이라 노출 안전).
    private static let logoDevToken = "pk_J8vaeyLSSxewXruh0z5O9g"

    /// 사전 렌더 로고 캐시 버전. **로컬 로고 에셋(Assets.xcassets)을 교체할 때마다 +1 할 것.**
    /// 렌더 캐시 키가 티커뿐이라, 에셋만 바꾸면 `renderLogoIfNeeded`의 `fileExists` 스킵 때문에
    /// 위젯이 낡은 PNG를 계속 읽는다. 이 값이 저장된 값과 다르면 캐시를 통째로 비우고 재렌더한다.
    private static let logoCacheVersion = 2
    private static let logoCacheVersionKey = "widgetLogoCacheVersion"

    /// 앱 활성 시 호출. 실패한 거래소는 직전 스냅샷을 보존하고, 성공한 거래소만 갱신한다.
    static func update() async {
        // 로고 에셋이 교체됐으면(=캐시 버전 상승) 낡은 PNG를 먼저 비워 새 에셋으로 다시 그리게 한다.
        invalidateLogoCacheIfNeeded()

        var snapshot = WidgetStore.load()
            ?? WidgetSnapshot(exchanges: [:], updatedAt: .distantPast)

        // 환율은 어느 피드든 내려주는 값을 공유. 없으면 마지막 저장값/기본값 사용.
        var resolvedRate = persistedRate()
        var resolvedRates = persistedRates()   // 다통화 맵(KRW/JPY/CNY/EUR)

        var fetched: [String: [WidgetCompany]] = [:]
        var basDts: [String: String?] = [:]
        var asOfs: [String: String?] = [:]

        for param in exchanges {
            guard let result = try? await fetchExchange(param: param) else { continue }
            fetched[param] = result.companies
            basDts[param] = result.basDt
            asOfs[param] = result.asOf
            if let rate = result.rate { resolvedRate = rate }
            if let rates = result.rates { resolvedRates = rates }
        }

        persistRate(resolvedRate)
        persistRates(resolvedRates)

        // 성공한 거래소만 스냅샷에 반영(실패분은 기존 값 유지).
        for param in exchanges {
            guard let companies = fetched[param] else { continue }
            snapshot.exchanges[param] = WidgetExchangeData(
                exchangeRate: resolvedRate,
                exchangeRates: resolvedRates.isEmpty ? nil : resolvedRates,
                basDt: basDts[param] ?? nil,
                asOf: asOfs[param] ?? nil,
                companies: companies
            )
        }
        snapshot.updatedAt = Date()

        // 노출 대상 종목 로고를 최종 PNG로 렌더링(없는 것만).
        var seen = Set<String>()
        for companies in snapshot.exchanges.values {
            for c in companies.companies where seen.insert(c.ticker).inserted {
                await renderLogoIfNeeded(ticker: c.ticker, name: c.name,
                                         color: Color(hex: c.colorHex), domain: c.domain)
            }
        }

        WidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Fetch

    private static func fetchExchange(param: String) async throws
        -> (companies: [WidgetCompany], rate: Double?, rates: [String: Double]?, basDt: String?, asOf: String?) {
        guard let url = URL(string: "\(MarketCapViewModel.apiBase)/api/market-cap?exchange=\(param)")
        else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(MarketCapResponse.self, from: data)
        if let apiError = decoded.error, decoded.data.isEmpty {
            throw NSError(domain: "WidgetSnapshot", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: apiError])
        }
        // 순위변동(previousRank)은 전 거래소 서버 제공값 사용. KR도 백엔드가 직전 basDt 스냅샷 대비로
        // 계산해 내려주므로(market-cap 라우트) 위젯도 그대로 실어 나른다.
        let top = decoded.data.sorted { $0.rank < $1.rank }.prefix(topCount)
        let companies = top.map { api in
            WidgetCompany(
                rank: api.rank,
                previousRank: api.previousRank,
                name: api.name,
                ticker: api.ticker,
                marketCapUSD: api.marketCapUSD,
                changePercent: api.changePercent,
                colorHex: api.color,
                domain: api.domain
            )
        }
        return (companies, decoded.exchangeRate, decoded.exchangeRates, decoded.basDt, decoded.asOf)
    }

    // MARK: - Exchange rate persistence (App Group UserDefaults)

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSharedConstants.appGroupID)
    }
    private static func persistedRate() -> Double {
        let v = defaults?.double(forKey: "widgetExchangeRate") ?? 0
        return v > 0 ? v : 1450
    }
    private static func persistRate(_ rate: Double) {
        defaults?.set(rate, forKey: "widgetExchangeRate")
    }
    private static func persistedRates() -> [String: Double] {
        (defaults?.dictionary(forKey: "widgetExchangeRates") as? [String: Double]) ?? [:]
    }
    private static func persistRates(_ rates: [String: Double]) {
        guard !rates.isEmpty else { return }
        defaults?.set(rates, forKey: "widgetExchangeRates")
    }

    // MARK: - Logo cache invalidation

    /// 저장된 캐시 버전이 현재 `logoCacheVersion`과 다르면 사전 렌더 로고를 통째로 지우고
    /// 버전을 갱신한다. (기존 설치본은 저장값이 0이라 이번 업데이트에서 한 번 재렌더된다.)
    private static func invalidateLogoCacheIfNeeded() {
        let stored = defaults?.integer(forKey: logoCacheVersionKey) ?? 0
        guard stored != logoCacheVersion else { return }
        if let dir = WidgetStore.logosDirURL {
            try? FileManager.default.removeItem(at: dir)
        }
        defaults?.set(logoCacheVersion, forKey: logoCacheVersionKey)
    }

    // MARK: - Logo rendering (앱 BrandLogoTile 합성 규칙 재현)

    @MainActor
    private static func renderLogoIfNeeded(ticker: String, name: String,
                                           color: Color, domain: String?) async {
        guard let dest = WidgetStore.logoURL(ticker: ticker) else { return }
        if FileManager.default.fileExists(atPath: dest.path) { return }  // 이미 있으면 스킵

        // 1) 최종 로고 이미지 확보: 로컬 에셋(배경제거 반영) 우선 → logo.dev → 없으면 이니셜(PNG 생략)
        var logoImage: UIImage?
        var isRemote = false
        if let assetName = tickerLocalLogo[ticker], let raw = UIImage(named: assetName) {
            logoImage = processedLocal(raw, ticker: ticker)
        } else if let url = logoDevURL(ticker: ticker, domain: domain) {
            logoImage = await LogoStore.shared.image(for: url)
            isRemote = true
        }
        guard let image = logoImage else { return }  // 위젯이 이니셜 타일로 폴백

        // 2) 앱 BrandLogoTile과 동일한 원형 타일로 합성 후 래스터화
        let offset = tickerLogoOffset[ticker] ?? .zero
        // 배경이 있는(불투명) 원격 로고는 앱과 동일하게 여백 없이 원을 꽉 채운다.
        let pad = (isRemote && image.wsHasOpaqueBackground()) ? 0 : (tickerLogoPadding[ticker] ?? 8)
        let tile = ZStack {
            Circle().fill(tickerCircleBackground[ticker] ?? .white)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(pad)
                .offset(x: offset.x, y: offset.y)
        }
        .frame(width: logoTileSize, height: logoTileSize)
        .clipShape(Circle())

        let renderer = ImageRenderer(content: tile)
        renderer.scale = 3
        renderer.isOpaque = false
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else { return }
        // 로고 저장 폴더(widget_logos)를 먼저 보장한다. (save()보다 렌더가 앞서 실행되므로
        // 여기서 만들지 않으면 폴더 부재로 write가 조용히 실패해 로고가 전부 이니셜로 폴백됨)
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: dest, options: .atomic)
    }

    private static func logoDevURL(ticker: String, domain: String?) -> URL? {
        let resolved = tickerDomain[ticker] ?? domain
        return resolved.flatMap {
            URL(string: "https://img.logo.dev/\($0)?token=\(logoDevToken)&size=200&format=png&retina=true&fallback=404")
        }
    }

    /// 로컬 에셋에 배경제거 세트가 걸려 있으면 앱과 동일하게 처리.
    private static func processedLocal(_ raw: UIImage, ticker: String) -> UIImage {
        if tickersNeedDarkBgRemoval.contains(ticker) {
            return raw.wsRemovingDarkBackground() ?? raw
        } else if tickersNeedLightBgRemoval.contains(ticker) {
            return raw.wsRemovingLightBackground() ?? raw
        } else if tickersNeedColoredBgRemoval.contains(ticker) {
            return raw.wsRemovingDominantBackground() ?? raw
        }
        return raw
    }
}

// MARK: - UIImage 배경제거 (ContentView.swift의 private 로직 복제)

private extension UIImage {
    /// 원격(logo.dev) 로고가 불투명한 사각 배경을 갖는지 판별한다(앱 hasOpaqueBackground 복제).
    func wsHasOpaqueBackground() -> Bool {
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
            if buf[(cy*w+cx)*4+3] < 230 { return false }
        }
        return true
    }

    func wsRemovingDarkBackground() -> UIImage? {
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
            let r = CGFloat(buf[i*4]) / 255, g = CGFloat(buf[i*4+1]) / 255, b = CGFloat(buf[i*4+2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            let sat = hi == 0 ? 0.0 : (hi - lo) / hi
            if sat < 0.3 && hi < 0.3 {
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    func wsRemovingLightBackground() -> UIImage? {
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
            let r = CGFloat(buf[i*4]) / 255, g = CGFloat(buf[i*4+1]) / 255, b = CGFloat(buf[i*4+2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            let sat = hi == 0 ? 0.0 : (hi - lo) / hi
            if sat < 0.12 && hi > 0.50 {
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    func wsRemovingDominantBackground(tolerance: CGFloat = 0.22) -> UIImage? {
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
            bgR += CGFloat(buf[idx*4]) / 255
            bgG += CGFloat(buf[idx*4+1]) / 255
            bgB += CGFloat(buf[idx*4+2]) / 255
        }
        bgR /= 4; bgG /= 4; bgB /= 4
        let tol2 = tolerance * tolerance
        for i in 0..<(w * h) {
            let r = CGFloat(buf[i*4]) / 255, g = CGFloat(buf[i*4+1]) / 255, b = CGFloat(buf[i*4+2]) / 255
            let d2 = (r-bgR)*(r-bgR) + (g-bgG)*(g-bgG) + (b-bgB)*(b-bgB)
            if d2 < tol2 {
                buf[i*4] = 0; buf[i*4+1] = 0; buf[i*4+2] = 0; buf[i*4+3] = 0
            }
        }
        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }
}
