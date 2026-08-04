//
//  AdsConfig.swift
//  surFin
//
//  AdMob(Google Mobile Ads) 광고 단위/앱 ID 및 노출 정책 중앙 설정.
//
//  개발·테스트(DEBUG) 빌드에서는 Google 공식 "테스트 광고 단위 ID"를 사용한다.
//  실제 광고 단위로 개발 중 반복 요청/클릭하면 "무효 트래픽" 정책 위반으로 계정이
//  정지될 수 있으므로, 반드시 테스트 ID로만 검증하고 실 ID는 스토어 배포(RELEASE)에서만 쓴다.
//  참고: https://developers.google.com/admob/ios/test-ads
//

import Foundation

enum AdsConfig {

    // MARK: - 실 광고 ID (RELEASE 전용)
    //
    // ⚠️ 출시 전 반드시 AdMob 콘솔에서 발급받은 실제 값으로 교체할 것.
    //    (앱 ID는 Info.plist 의 GADApplicationIdentifier 도 함께 교체해야 함)

    /// AdMob 앱 ID (Info.plist 의 GADApplicationIdentifier 와 동일해야 함)
    static let releaseAppID        = "ca-app-pub-1154843579671524~1864394354"
    /// 배너 광고 단위 ID
    static let releaseBanner       = "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"   // TODO: 실제 배너 단위 ID
    /// 전면(Interstitial) 광고 단위 ID
    static let releaseInterstitial = "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"   // TODO: 실제 전면 단위 ID

    // MARK: - Google 공식 테스트 광고 단위 ID (DEBUG 전용, 교체 금지)

    private static let testBanner       = "ca-app-pub-3940256099942544/2435281174"
    private static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"

    // MARK: - 빌드별 실사용 ID

    #if DEBUG
    static let bannerUnitID       = testBanner
    static let interstitialUnitID = testInterstitial
    #else
    static let bannerUnitID       = releaseBanner
    static let interstitialUnitID = releaseInterstitial
    #endif

    // MARK: - 노출 정책

    /// 리스트에서 배너를 삽입하는 간격 (N개 종목마다 1개).
    static let bannerRowInterval = 20

    /// 전면 광고를 노출하는 섹션 전환 간격 (N번째 전환마다 1회).
    static let interstitialSectionInterval = 10
}
