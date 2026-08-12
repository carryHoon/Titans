//
//  PrefsSync.swift
//  Titans
//
//  로그인 상태에서 로컬 환경설정(@AppStorage: isDarkMode, notificationsEnabled, displayCurrency)과
//  프로필(nickname)을 Supabase user_prefs 테이블과 동기화한다.
//
//  정책:
//   · 로그인 시 원격 우선(pull) — 계정에 저장된 값이 있으면 로컬에 적용.
//   · 계정에 행이 없으면 현재 로컬 값으로 초기화(seed). 단 nickname은 온보딩 전까지 nil.
//   · 로그인 상태에서 설정이 바뀌면 디바운스 후 원격에 upsert(push).
//   · 비로그인 상태에서는 동기화하지 않음(로컬 @AppStorage 그대로).
//
//  @AppStorage는 UserDefaults를 관찰하므로, 여기서 UserDefaults를 직접 읽고/쓰면
//  UI(@AppStorage 바인딩)와 자연히 일치한다. 온보딩 게이팅에 필요한 nickname/didLoadRemote는
//  @Observable 프로퍼티로 노출해 RootView가 관찰한다.
//

import Foundation
import Supabase

@MainActor
@Observable
final class PrefsSync {
    static let shared = PrefsSync()

    /// 원격에서 읽어온 닉네임(없으면 nil = 온보딩 미완료). RootView가 온보딩 게이팅에 사용.
    private(set) var nickname: String?
    /// 온보딩 이후 닉네임을 1회 변경했는지. true면 더 이상 변경 불가(메뉴에서 잠금 표시).
    private(set) var nicknameChanged = false
    /// 로그인 후 원격 pull이 한 번이라도 끝났는지. false면 아직 온보딩 여부를 판단하지 않는다.
    private(set) var didLoadRemote = false

    @ObservationIgnored private let client = SupabaseClientProvider.shared
    @ObservationIgnored private let defaults = UserDefaults.standard

    @ObservationIgnored private let darkKey     = "isDarkMode"
    @ObservationIgnored private let notifKey    = "notificationsEnabled"
    @ObservationIgnored private let currencyKey = "displayCurrency"
    @ObservationIgnored private let nicknameKey = "nickname"

    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var isApplyingRemote = false   // 원격 적용 중엔 push 방지(피드백 루프 차단)
    @ObservationIgnored private var lastDark: Bool?
    @ObservationIgnored private var lastNotif: Bool?
    @ObservationIgnored private var pushTask: Task<Void, Never>?

    /// 원격 행 형태(테이블 컬럼과 1:1). nickname/display_currency는 마이그레이션 지연에도 안전하도록
    /// 디코딩 시 옵셔널로 둔다(없으면 기본값 적용).
    private struct Row: Codable {
        let user_id: String
        let is_dark_mode: Bool
        let notifications_enabled: Bool
        let nickname: String?
        let nickname_changed: Bool?
        let display_currency: String?
    }

    private init() {
        // 로컬 설정 변경 감지 → push. (관련 없는 키 변경은 값 비교로 걸러냄)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.localChanged() }
        }
    }

    /// 로그인 상태 변화에 반응. RootView에서 auth.userId 변화 시 호출.
    func update(userId: String?) {
        self.userId = userId
        guard userId != nil else {
            pushTask?.cancel()
            lastDark = nil
            lastNotif = nil
            nickname = nil
            nicknameChanged = false
            didLoadRemote = false
            return
        }
        didLoadRemote = false
        Task { await pull() }
    }

    // MARK: - Pull (원격 → 로컬)

    private func pull() async {
        guard let userId else { return }
        do {
            let rows: [Row] = try await client
                .from("user_prefs")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            if let r = rows.first {
                isApplyingRemote = true
                defaults.set(r.is_dark_mode, forKey: darkKey)
                defaults.set(r.notifications_enabled, forKey: notifKey)
                defaults.set(r.display_currency ?? Currency.usd.rawValue, forKey: currencyKey)
                if let n = r.nickname { defaults.set(n, forKey: nicknameKey) }
                isApplyingRemote = false
                lastDark = r.is_dark_mode
                lastNotif = r.notifications_enabled
                nickname = (r.nickname?.isEmpty == false) ? r.nickname : nil
                nicknameChanged = r.nickname_changed ?? false
            } else {
                // 계정에 아직 설정이 없음 → 이 기기의 현재 값으로 seed(닉네임은 온보딩 전이라 nil).
                nickname = nil
                nicknameChanged = false
                await push()
            }
        } catch {
            // 네트워크/일시 오류는 조용히 무시(다음 로그인·변경에 재시도).
        }
        didLoadRemote = true
    }

    // MARK: - Push (로컬 → 원격)

    private func localChanged() {
        guard userId != nil, !isApplyingRemote else { return }
        let d = defaults.bool(forKey: darkKey)
        let n = defaults.bool(forKey: notifKey)
        // 동기화 대상 키가 실제로 바뀐 경우에만 push(불필요한 네트워크 방지).
        guard d != lastDark || n != lastNotif else { return }
        lastDark = d
        lastNotif = n

        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))   // 디바운스
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func push() async {
        guard let userId else { return }
        let row = currentRow(userId: userId)
        do {
            try await client
                .from("user_prefs")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // 조용히 무시(다음 변경에 재시도).
        }
    }

    /// 현재 로컬 값으로 구성한 원격 행. 부분 push가 다른 컬럼을 지우지 않도록 항상 전체를 담는다.
    private func currentRow(userId: String) -> Row {
        let storedNickname = defaults.string(forKey: nicknameKey)
        return Row(
            user_id: userId,
            is_dark_mode: defaults.bool(forKey: darkKey),
            notifications_enabled: defaults.bool(forKey: notifKey),
            nickname: (storedNickname?.isEmpty == false) ? storedNickname : nickname,
            nickname_changed: nicknameChanged,
            display_currency: defaults.string(forKey: currencyKey) ?? Currency.usd.rawValue
        )
    }

    // MARK: - 온보딩 완료

    /// 온보딩(닉네임 + 표시 통화) 결과를 로컬·원격에 즉시 반영한다.
    /// 로컬 @AppStorage(displayCurrency)와 nickname을 먼저 쓰고, 원격에 upsert 한다.
    func completeOnboarding(nickname: String, currency: Currency) async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        isApplyingRemote = true
        defaults.set(trimmed, forKey: nicknameKey)
        defaults.set(currency.rawValue, forKey: currencyKey)
        isApplyingRemote = false
        self.nickname = trimmed.isEmpty ? nil : trimmed

        guard let userId else { return }
        let row = currentRow(userId: userId)
        do {
            try await client
                .from("user_prefs")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // 실패해도 로컬엔 반영됨 → 다음 설정 변경/로그인에 재동기화된다.
        }
    }

    // MARK: - 설정 변경(메뉴)

    /// 닉네임 변경 가능 여부. 온보딩 최초 설정은 변경으로 치지 않으며, 그 후 1회만 허용한다.
    var canChangeNickname: Bool { !nicknameChanged }

    /// 닉네임을 1회 변경한다. 이미 변경한 적 있으면(canChangeNickname == false) 무시하고 false 반환.
    /// 성공 시 nicknameChanged=true 로 잠그고 로컬·원격에 반영한다.
    @discardableResult
    func changeNickname(_ newNickname: String) async -> Bool {
        guard canChangeNickname else { return false }
        let trimmed = newNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isApplyingRemote = true
        defaults.set(trimmed, forKey: nicknameKey)
        isApplyingRemote = false
        nickname = trimmed
        nicknameChanged = true   // 1회 변경 소진 → 잠금

        guard let userId else { return true }
        let row = currentRow(userId: userId)
        do {
            try await client
                .from("user_prefs")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // 로컬엔 반영됨 → 다음 변경/로그인에 재동기화.
        }
        return true
    }

    /// 표시 통화를 변경한다(횟수 제한 없음). 로컬 @AppStorage(displayCurrency)에 먼저 반영해
    /// 홈 화면이 즉시 갱신되고, 원격에 upsert 한다.
    func setDisplayCurrency(_ currency: Currency) async {
        isApplyingRemote = true
        defaults.set(currency.rawValue, forKey: currencyKey)
        isApplyingRemote = false

        guard let userId else { return }
        let row = currentRow(userId: userId)
        do {
            try await client
                .from("user_prefs")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // 로컬엔 반영됨 → 다음 변경/로그인에 재동기화.
        }
    }
}
