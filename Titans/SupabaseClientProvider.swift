//
//  SupabaseClientProvider.swift
//  Titans
//
//  앱 전역에서 공유하는 단일 SupabaseClient 인스턴스.
//  클라이언트는 access/refresh 토큰을 Keychain에 자동 보관하므로, 여러 곳에서 새로
//  만들지 말고 이 하나를 공유해야 세션이 일관되게 유지된다.
//

import Foundation
import Supabase

enum SupabaseClientProvider {
    /// 앱 수명 동안 공유되는 단일 클라이언트.
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(
            // 다음 메이저에서 기본값이 되는 동작으로 미리 opt-in.
            // 로컬 저장 세션을 (만료 여부와 무관하게) 초기 세션으로 즉시 발행한다.
            // 만료 세션 처리는 AuthManager.observeAuthState()의 isExpired 체크가 담당.
            auth: SupabaseClientOptions.AuthOptions(
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
