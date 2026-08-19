//  AdsConsentManager.swift
//  광고 동의(UMP) → 추적 투명성(ATT) → Mobile Ads SDK 시작을 순서대로 처리한다.
//  순서가 중요하다:
//   1) Google UMP 동의 정보 갱신 + (필요 시) 동의 양식 표시
//      — GDPR/EEA · 미국 주(州) 개인정보 보호법 대응.
//   2) ATT(App Tracking Transparency) 프롬프트
//      — IDFA 접근 허용 여부. 맞춤형 광고 eCPM에 영향. UMP 동의 확보 뒤 노출.
//   3) canRequestAds 이면 MobileAds.shared.start() 로 SDK 초기화.

import Foundation
import UIKit
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdsConsentManager {
    static let shared = AdsConsentManager()
    private init() {}

    /// SDK가 이미 시작됐는지(중복 start 방지).
    private var didStartSDK = false

    /// 앱 시작 시 1회 호출. 동의 흐름을 마친 뒤 광고 SDK를 시작한다.
    func start() async {
        await requestConsentIfNeeded()
        await requestTrackingAuthorization()
        startAdsSDKIfPossible()
    }

    // MARK: - UMP 동의

    private func requestConsentIfNeeded() async {
        let parameters = RequestParameters()
        #if DEBUG
        // 디버그에서 동의 양식을 강제로 확인하려면 geography 를 .EEA 로 바꾸고,
        // AdMob 콘솔의 "테스트 기기" 해시를 testDeviceIdentifiers 에 추가한다.
        let debug = DebugSettings()
        debug.geography = .disabled
        parameters.debugSettings = debug
        #endif

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { _ in
                continuation.resume()
            }
        }

        guard let root = Self.topViewController() else { return }
        try? await ConsentForm.loadAndPresentIfRequired(from: root)
    }

    // MARK: - ATT

    private func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - SDK 시작

    private func startAdsSDKIfPossible() {
        guard !didStartSDK, ConsentInformation.shared.canRequestAds else { return }
        didStartSDK = true
        MobileAds.shared.start { _ in }
    }

    // MARK: - 개인정보 옵션(설정 화면용)

    /// 사용자가 동의를 다시 설정할 수 있어야 하는 지역인지 여부.
    /// true 이면 설정 화면에 "광고 개인정보 설정" 진입점을 노출해야 한다.
    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// 개인정보 옵션(동의 재설정) 양식을 표시한다.
    func presentPrivacyOptionsForm() async {
        guard let root = Self.topViewController() else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: root)
    }

    // MARK: - Helper

    /// 현재 최상단에 표시 중인 뷰컨트롤러 — 동의 양식/전면 광고 표시에 사용.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
