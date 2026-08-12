//
//  ProfileSettingsView.swift
//  surFin
//
//  메뉴 > 프로필 섹션에서 진입하는 설정 화면들.
//   · NicknameEditView       — 닉네임 변경(온보딩 이후 1회만 허용, 소진 시 잠금)
//   · DisplayCurrencyEditView — 표시 통화 변경(횟수 제한 없음, 즉시 홈에 반영)
//
//  저장은 모두 PrefsSync(로컬 @AppStorage + 원격 user_prefs)를 통해 처리한다.
//

import SwiftUI

// MARK: - 닉네임 변경

struct NicknameEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var nickname: String = PrefsSync.shared.nickname ?? ""
    @State private var isBusy = false
    @State private var showConfirm = false

    private let maxNicknameLength = 20
    private let accent = Color(red: 0.2, green: 0.8, blue: 0.4)

    private var theme: AppTheme { colorScheme == .dark ? .dark : .light }
    private var canChange: Bool { PrefsSync.shared.canChangeNickname }

    private var trimmed: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 저장 가능: 변경 권한이 있고, 비어있지 않으며, 기존과 다를 때.
    private var canSave: Bool {
        canChange && !trimmed.isEmpty && trimmed != (PrefsSync.shared.nickname ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if canChange {
                    Text("닉네임은 한 번만 변경할 수 있어요. 신중하게 정해주세요.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryLabel)

                    TextField("닉네임", text: $nickname)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.label)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: nickname) { _, newValue in
                            if newValue.count > maxNicknameLength {
                                nickname = String(newValue.prefix(maxNicknameLength))
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))

                    Text("\(trimmed.count)/\(maxNicknameLength)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryLabel)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Button {
                        showConfirm = true
                    } label: {
                        Text("변경하기")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || isBusy)
                    .padding(.top, 4)
                } else {
                    // 이미 1회 변경함 → 잠금(읽기 전용).
                    VStack(alignment: .leading, spacing: 8) {
                        Text("현재 닉네임")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryLabel)
                        Text(PrefsSync.shared.nickname ?? "-")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.label)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))

                    Label("닉네임은 한 번만 변경할 수 있어요. 이미 변경하셨습니다.", systemImage: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("닉네임")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isBusy {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView().controlSize(.large).tint(theme.label)
            }
        }
        .confirmationDialog(
            "닉네임을 변경할까요?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("변경") { save() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("닉네임은 한 번만 변경할 수 있어요. ‘\(trimmed)’(으)로 변경하면 이후에는 바꿀 수 없습니다.")
        }
    }

    private func save() {
        guard canSave else { return }
        isBusy = true
        Task {
            await PrefsSync.shared.changeNickname(trimmed)
            isBusy = false
            dismiss()
        }
    }
}

// MARK: - 표시 통화 변경

struct DisplayCurrencyEditView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("displayCurrency") private var displayCurrencyRaw: String = Currency.usd.rawValue

    private let accent = Color(red: 0.2, green: 0.8, blue: 0.4)
    private var theme: AppTheme { colorScheme == .dark ? .dark : .light }
    private var current: Currency { Currency.from(displayCurrencyRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("시가총액을 달러와 함께 이 통화로도 볼 수 있어요.\n‘달러’를 고르면 달러로만 표시돼요.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(Currency.allCases, id: \.self) { currency in
                        row(currency)
                    }
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("표시 통화")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ currency: Currency) -> some View {
        let isSelected = current == currency
        return Button {
            guard !isSelected else { return }
            Task { await PrefsSync.shared.setDisplayCurrency(currency) }
        } label: {
            HStack(spacing: 14) {
                Text(currency.toggleSymbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? accent : theme.label)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.onboardingLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Text(currency.onboardingSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accent)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
