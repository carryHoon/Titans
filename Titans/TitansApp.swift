//
//  TitansApp.swift
//  Titans
//
//  Created by MacH on 7/21/26.
//

import SwiftUI

@main
struct TitansApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // 광고 동의(UMP) → ATT → Mobile Ads SDK 시작을 순서대로 처리한 뒤
                    // 전면 광고를 미리 로드해 둔다.
                    await AdsConsentManager.shared.start()
                    InterstitialAdManager.shared.preload()
                }
        }
    }
}
