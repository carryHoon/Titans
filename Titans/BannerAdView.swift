//
//  BannerAdView.swift
//  surFin
//
//  리스트에 삽입되는 적응형(adaptive) 배너 광고. ContentView 의 AdBannerSlot 에서 사용된다.
//

import SwiftUI
import GoogleMobileAds

/// GoogleMobileAds 의 UIKit `BannerView` 를 SwiftUI 로 감싼 래퍼.
///
/// 폭에 맞춘 앵커드 적응형 배너를 로드한다. 실제 표시 크기는 `adSize.size` 로 결정되므로
/// 호출부에서 동일한 `adSize` 로 `.frame(...)` 을 지정해 레이아웃을 고정한다.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = AdsConsentManager.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // 회전 등으로 rootViewController 가 없어졌을 때를 대비해 최신 값으로 갱신.
        if uiView.rootViewController == nil {
            uiView.rootViewController = AdsConsentManager.topViewController()
        }
    }
}
