//
//  PrefsSync.swift
//  Titans
//
//  로그인 상태에서 로컬 환경설정(@AppStorage: isDarkMode, notificationsEnabled)을
//  Supabase user_prefs 테이블과 동기화한다.
//
//  정책:
//   · 로그인 시 원격 우선(pull) — 계정에 저장된 값이 있으면 로컬에 적용.
//   · 계정에 행이 없으면 현재 로컬 값으로 초기화(seed).
//   · 로그인 상태에서 설정이 바뀌면 디바운스 후 원격에 upsert(push).
//   · 비로그인 상태에서는 동기화하지 않음(로컬 @AppStorage 그대로).
//
//  @AppStorage는 UserDefaults를 관찰하므로, 여기서 UserDefaults를 직접 읽고/쓰면
//  UI(@AppStorage 바인딩)와 자연히 일치한다.
//

import Foundation
import Supabase

@MainActor
final class PrefsSync {
    static let shared = PrefsSync()

    private let client = SupabaseClientProvider.shared
    private let defaults = UserDefaults.standard

    private let darkKey  = "isDarkMode"
    private let notifKey = "notificationsEnabled"

    private var userId: String?
    private var isApplyingRemote = false        // 원격 적용 중엔 push 방지(피드백 루프 차단)
    private var lastDark: Bool?
    private var lastNotif: Bool?
    private var pushTask: Task<Void, Never>?

    /// 원격 행 형태(테이블 컬럼과 1:1).
    private struct Row: Codable {
        let user_id: String
        let is_dark_mode: Bool
        let notifications_enabled: Bool
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
            return
        }
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
                isApplyingRemote = false
                lastDark = r.is_dark_mode
                lastNotif = r.notifications_enabled
            } else {
                // 계정에 아직 설정이 없음 → 이 기기의 현재 값으로 seed.
                await push()
            }
        } catch {
            // 네트워크/일시 오류는 조용히 무시(다음 로그인·변경에 재시도).
        }
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
        let row = Row(
            user_id: userId,
            is_dark_mode: defaults.bool(forKey: darkKey),
            notifications_enabled: defaults.bool(forKey: notifKey)
        )
        do {
            try await client
                .from("user_prefs")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // 조용히 무시(다음 변경에 재시도).
        }
    }
}
