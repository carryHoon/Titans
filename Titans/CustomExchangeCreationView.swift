//
//  CustomExchangeCreationView.swift
//  Titans
//
//  "나만의 거래소" 생성 플로우(토스 "관심 그룹 만들기" 오마주).
//  1단계: 이름 짓기 + 테마 프리셋 칩 → 2단계: 로드된 유니버스에서 종목 그리드 멀티셀렉트.
//  토스가 파랑으로 강조하는 CTA/선택 요소는 전부 MarCap 브랜드 초록(Color.marcapAccent)으로 대체한다.
//

import SwiftUI
import StoreKit

struct CustomExchangeCreationView: View {
    /// 선택 가능한 유니버스 — 홈에서 이미 로드된 전 거래소 종목(JPX 포함). 별도 조회 없음.
    let universe: [Company]
    let store: CustomExchangeStore
    /// 생성 완료 시 새 거래소를 전달(호출자가 해당 탭으로 이동시키는 용도).
    var onCreated: (CustomExchange) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview

    @State private var name: String = ""
    @State private var showPicker = false

    /// 이름 프리셋 — 탭하면 이름 필드를 채운다(토스의 국내/해외/배당주/단기매매 오마주, 우리 테마로).
    private let presets = ["반도체", "빅테크", "K-대장주", "자동차", "배당주"]

    var body: some View {
        NavigationStack {
            namingStep
                .navigationDestination(isPresented: $showPicker) { pickerStep }
        }
        .environment(\.appTheme, colorScheme == .dark ? .dark : .light)
    }

    // MARK: 1단계 — 이름 짓기

    private var namingStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("어떤 주제로 거래소를 만들까요?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            TextField("거래소 이름을 지어보세요", text: $name)
                .font(.title2.weight(.bold))
                .textFieldStyle(.plain)
                .submitLabel(.next)
                .onSubmit { if canProceed { showPicker = true } }
                .padding(.top, 12)

            Rectangle()
                .fill(canProceed ? Color.marcapAccent : Color.secondary.opacity(0.3))
                .frame(height: 2)
                .padding(.top, 6)

            // 테마 프리셋 칩
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button { name = preset } label: {
                        Text(preset)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showPicker = true
            } label: {
                Text("확인")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.marcapAccent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .opacity(canProceed ? 1 : 0.4)
            }
            .disabled(!canProceed)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: 2단계 — 종목 그리드 멀티셀렉트

    private var pickerStep: some View {
        TickerPickerStep(
            title: name.trimmingCharacters(in: .whitespaces),
            universe: universe
        ) { selectedTickers in
            let ex = store.add(name: name.trimmingCharacters(in: .whitespaces), tickers: selectedTickers)
            onCreated(ex)
            dismiss()
            // 나만의 거래소를 처음 완성한 '아하' 순간에 앱스토어 리뷰를 요청한다(노출 빈도는 시스템이 제어).
            // 시트 dismiss 전환이 끝난 뒤 표시되도록 잠시 지연.
            let review = requestReview
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                review()
            }
        }
    }
}

// MARK: - 종목 그리드 선택 화면

struct TickerPickerStep: View {
    let title: String
    let universe: [Company]
    var actionTitle: String = "선택"   // 버튼 문구: "N개 \(actionTitle)" (생성=선택, 편집 추가=추가)
    var onConfirm: ([String]) -> Void

    @State private var query: String = ""
    @State private var selected: [String] = []   // 선택 순서 보존

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// 시총 내림차순 + 검색 필터. (대형주가 먼저 보이도록)
    private var filtered: [Company] {
        let base = universe.sorted { $0.marketCapUSD > $1.marketCapUSD }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.name.lowercased().contains(q) || $0.ticker.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(filtered) { company in
                        cell(company)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("\(title)에 기업 추가")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onConfirm(selected)
            } label: {
                Text(selected.isEmpty ? "기업을 선택하세요" : "\(selected.count)개 \(actionTitle)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.marcapAccent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .opacity(selected.isEmpty ? 0.4 : 1)
            }
            .disabled(selected.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("검색 / 직접입력", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func cell(_ company: Company) -> some View {
        let isSelected = selected.contains(company.ticker)
        return Button {
            if isSelected { selected.removeAll { $0 == company.ticker } }
            else { selected.append(company.ticker) }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    BrandLogoTile(ticker: company.ticker, name: company.name,
                                  color: company.color, domain: company.domain)
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(Color.marcapAccent, lineWidth: 3)
                            }
                        }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.marcapAccent)
                            .background(Circle().fill(.background))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(company.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
