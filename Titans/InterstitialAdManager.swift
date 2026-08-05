//
//  InterstitialAdManager.swift
//  surFin
//
//  전면(Interstitial) 광고 로딩·노출 관리.
//  섹션(거래소) 전환이 N번째마다 전면 광고를 1회 노출하고, 노출 후 다음 광고를 미리 재로딩한다.
//

import Foundation
import UIKit
import GoogleMobileAds

@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialAdManager()

    private var interstitial: InterstitialAd?
    private var isLoading = false
    /// 섹션 전환 누적 횟수. interstitialSectionInterval 의 배수마다 노출.
    private var sectionSwitchCount = 0

    private override init() { super.init() }

    // MARK: - 로딩

    /// 전면 광고를 미리 로드해 둔다(동의/SDK 시작 이후 호출).
    func preload() {
        guard interstitial == nil, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let ad = try await InterstitialAd.load(
                    with: AdsConfig.interstitialUnitID,
                    request: Request()
                )
                ad.fullScreenContentDelegate = self
                interstitial = ad
            } catch {
                interstitial = nil
            }
        }
    }

    // MARK: - 노출 트리거

    /// 섹션 전환 시 호출. N번째 전환마다 전면 광고를 노출한다.
    func handleSectionSwitch() {
        sectionSwitchCount += 1
        guard sectionSwitchCount % AdsConfig.interstitialSectionInterval == 0 else {
            // 노출 타이밍이 아니면 다음 노출을 대비해 미리 로드만 해 둔다.
            if interstitial == nil { preload() }
            return
        }
        present()
    }

    private func present() {
        guard let ad = interstitial,
              let root = AdsConsentManager.topViewController() else {
            // 아직 준비 안 됐으면 이번 회차는 건너뛰고 로드만 시작한다.
            preload()
            return
        }
        ad.present(from: root)
    }

    // MARK: - FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        preload()   // 다음 노출을 위해 즉시 재로딩
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        interstitial = nil
        preload()
    }
}
