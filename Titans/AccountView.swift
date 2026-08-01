//
//  AccountView.swift
//  Titans
//
//  로그인된 사용자의 계정 화면. 현재 로그인 정보 표시 + 로그아웃.
//  (회원 탈퇴는 Phase 5에서 Edit Function 연동과 함께 추가된다.)
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    private var theme: AppTheme { isDarkMode ? .dark : .light }

    private var email: String { auth.userEmail ?? "로그인됨" }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 프로필 헤더
                VStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.20, green: 0.50, blue: 1.00),
                                     Color(red: 0.55, green: 0.20, blue: 0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(.white))
                    Text(email)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.label)
                }
                .padding(.top, 24)

                // 로그아웃
                Button {
                    Task { await signOut() }
                } label: {
                    Text("로그아웃")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))
                }
                .disabled(isBusy)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                // 회원 탈퇴 (App Store 심사 필수: 앱 내 계정 삭제)
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("회원 탈퇴")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                }
                .disabled(isBusy)
                .padding(.bottom, 24)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("내 계정")
        .navigationBarTitleDisplayMode(.inline)
        .alert("알림", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "정말 탈퇴하시겠어요?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("계정 영구 삭제", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("계정과 동기화된 모든 데이터(관심 종목·설정)가 영구적으로 삭제되며 복구할 수 없습니다.")
        }
    }

    private func signOut() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signOut()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.deleteAccount()
            dismiss()
        } catch {
            errorMessage = "탈퇴 처리 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
