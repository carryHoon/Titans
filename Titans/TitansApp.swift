//
//  TitansApp.swift
//  Titans
//
//  Created by MacH on 7/21/26.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct TitansApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // 광고 동의(UMP) → ATT → Mobile Ads SDK 시작을 순서대로 처리한다.
                    // (전면 광고는 아하모먼트 이전 리텐션 보호를 위해 미노출 — 배너만 운용.)
                    await AdsConsentManager.shared.start()
                }
        }
    }
}
