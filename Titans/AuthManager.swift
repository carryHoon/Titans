//  AuthManager.swift
//  앱 전역 인증 상태의 단일 소스(source of truth).
//  Supabase 세션을 복원·구독해 로그인/로그아웃을 SwiftUI에 반영하고, provider별 로그인과
//  로그아웃·계정삭제 진입점을 제공한다. 토큰은 supabase-swift가 Keychain에 자동 보관한다.
//  보안 메모(Apple): 재생공격(replay) 방지를 위해 매 로그인마다 랜덤 nonce를 만들어
//  SHA256 해시를 Apple 요청에 넣고, 원본 nonce를 Supabase 검증에 전달한다.

import Foundation
import Supabase
import AuthenticationServices
import CryptoKit

@MainActor
@Observable
final class AuthManager {

    /// 앱이 관찰하는 인증 상태.
    enum State {
        case loading            // 세션 복원 중(스플래시 동안)
        case signedOut          // 비로그인(익명 사용 허용)
        case signedIn(User)     // 로그인됨
    }

    private(set) var state: State = .loading

    /// 세션 복원이 아직 끝나지 않았는지.
    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    /// 로그인 상태 여부.
    var isSignedIn: Bool { currentUser != nil }

    /// 현재 로그인 유저(없으면 nil).
    var currentUser: User? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    /// 현재 로그인 유저의 이메일(없으면 nil). SDK 타입을 뷰에 노출하지 않기 위한 창구.
    var userEmail: String? { currentUser?.email }

    /// 현재 로그인 유저의 ID(UUID 문자열, 없으면 nil). 동기화 키로 사용.
    var userId: String? { currentUser?.id.uuidString }

    private let client = SupabaseClientProvider.shared
    private var observeTask: Task<Void, Never>?

    /// Apple 로그인 1회에 대응하는 원본 nonce(요청↔검증 사이 보관).
    private var currentNonce: String?

    init() {
        observeAuthState()
    }

    // MARK: - 세션 관찰

    /// authStateChanges를 구독해 상태를 갱신한다.
    /// 구독 시 `.initialSession` 이벤트가 즉시 발행되며, 이때 `.loading`이 해소된다.
    private func observeAuthState() {
        observeTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.client.auth.authStateChanges {
                switch change.event {
                case .initialSession:
                    // emitLocalSessionAsInitialSession=true 에서는 만료된 로컬 세션도 그대로
                    // 발행되므로, 만료 여부를 확인해 로그인으로 오인하지 않는다. 세션이 유효하면
                    // 로그인 처리하고, 만료/부재면 비로그인. (유효 세션은 이후 자동 리프레시가
                    // .tokenRefreshed 를, 갱신 실패 시 .signedOut 을 이어서 발행한다.)
                    if let session = change.session, !session.isExpired {
                        self.state = .signedIn(session.user)
                    } else {
                        self.state = .signedOut
                    }
                case .signedIn, .tokenRefreshed, .userUpdated:
                    self.state = change.session.map { .signedIn($0.user) } ?? .signedOut
                case .signedOut, .userDeleted:
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign in with Apple (네이티브)

    /// SignInWithAppleButton의 onRequest에서 호출: 스코프 지정 + nonce 세팅.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// SignInWithAppleButton의 onCompletion에서 호출: ID token으로 Supabase 로그인.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async throws {
        guard let nonce = currentNonce else { throw AuthError.missingNonce }
        defer { currentNonce = nil }

        let authorization = try result.get()
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthError.invalidAppleCredential
        }

        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )

        // Apple은 최초 1회만 이름을 준다 → 있으면 유저 메타데이터에 저장.
        if let fullName = credential.fullName,
           fullName.givenName != nil || fullName.familyName != nil {
            let joined = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !joined.isEmpty {
                _ = try? await client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(joined)])
                )
            }
        }
    }

    // MARK: - Kakao (Supabase 관리형 OAuth)

    /// 카카오 로그인. Supabase의 OAuth 엔드포인트를 ASWebAuthenticationSession으로 띄우고,
    /// 완료되면 콜백 URL(SupabaseConfig.redirectURL)로 돌아와 세션을 저장한다.
    /// 세션 반영은 authStateChanges 구독이 담당하므로 여기서는 로그인 요청만 한다.
    func signInWithKakao() async throws {
        try await client.auth.signInWithOAuth(
            provider: .kakao,
            redirectTo: SupabaseConfig.redirectURL
        )
    }

    // MARK: - Google (Supabase 관리형 OAuth)

    /// 구글 로그인. 카카오와 동일하게 Supabase의 OAuth 엔드포인트를 ASWebAuthenticationSession으로
    /// 띄우고, 완료되면 콜백 URL(SupabaseConfig.redirectURL)로 돌아와 세션을 저장한다.
    /// 세션 반영은 authStateChanges 구독이 담당하므로 여기서는 로그인 요청만 한다.
    func signInWithGoogle() async throws {
        try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: SupabaseConfig.redirectURL
        )
    }

    // MARK: - 이메일/비밀번호 (Supabase 내장)

    /// 이메일 회원가입. Supabase가 비밀번호 해싱·확인메일을 처리한다.
    func signUpEmail(email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }

    /// 이메일 로그인.
    func signInEmail(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// 비밀번호 재설정 메일 발송.
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - 로그아웃

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - 계정 삭제 (App Store 심사 필수)

    /// 계정을 영구 삭제한다.
    /// 클라이언트는 admin 권한이 없으므로, 유저 JWT를 검증해 service_role로 삭제하는
    /// Supabase Edge Function('delete-account')을 호출한다. user_prefs 등 관련 데이터는
    /// auth.users 삭제 시 FK on delete cascade 로 함께 제거된다.
    func deleteAccount() async throws {
        try await client.functions.invoke("delete-account")
        // 서버에서 유저가 삭제되면 로컬 세션은 무효 → Keychain 정리 및 상태 갱신.
        try? await client.auth.signOut()
    }

    // MARK: - 오류

    enum AuthError: LocalizedError {
        case missingNonce
        case invalidAppleCredential

        var errorDescription: String? {
            switch self {
            case .missingNonce:          return "로그인 요청이 유효하지 않습니다. 다시 시도해 주세요."
            case .invalidAppleCredential: return "Apple 로그인 정보를 확인할 수 없습니다."
            }
        }
    }

    // MARK: - Nonce 유틸 (Apple 공식 샘플 기반)

    /// 암호학적으로 안전한 랜덤 nonce 문자열.
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else {
                fatalError("SecRandomCopyBytes 실패: \(status)")
            }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    /// nonce의 SHA256 16진 문자열.
    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
