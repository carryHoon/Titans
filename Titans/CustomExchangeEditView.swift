//
//  CustomExchangeEditView.swift
//  Titans
//
//  "나만의 거래소" 편집 화면(토스 "관심 편집" 오마주).
//  종목 순서 변경(드래그) · 삭제(스와이프/− 버튼) · 종목 추가 · 거래소 자체 삭제 · 완료 저장.
//  강조 요소는 MarCap 브랜드 초록(Color.marcapAccent).
//

import SwiftUI

struct CustomExchangeEditView: View {
    let exchangeID: UUID
    let store: CustomExchangeStore
    /// 로고/이름 표시용 유니버스(홈에서 이미 로드된 전 거래소 종목).
    let universe: [Company]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String
    @State private var tickers: [String]   // 편집 중인 순서/구성 (완료 시 저장)
    @State private var showAddPicker = false
    @State private var editMode: EditMode = .active   // 진입 즉시 편집(드래그/삭제) 모드

    init(exchange: CustomExchange, store: CustomExchangeStore, universe: [Company]) {
        self.exchangeID = exchange.id
        self.store = store
        self.universe = universe
        _name = State(initialValue: exchange.name)
        _tickers = State(initialValue: exchange.tickers)
    }

    private func company(_ ticker: String) -> Company? {
        universe.first { $0.ticker == ticker }
    }

    var body: some View {
        NavigationStack {
            List {
                // + 종목 추가하기 (accent)
                Button {
                    showAddPicker = true
                } label: {
                    Label("기업 추가하기", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcapAccent)
                }
                .listRowSeparator(.hidden)

                // 종목 행 — 드래그 핸들(onMove) + 삭제(onDelete)
                ForEach(tickers, id: \.self) { ticker in
                    row(ticker)
                }
                .onDelete { tickers.remove(atOffsets: $0) }
                .onMove { tickers.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .environment(\.appTheme, colorScheme == .dark ? .dark : .light)
            .navigationTitle("\(name) 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { save(); dismiss() }
                        .fontWeight(.bold)
                        .tint(Color.marcapAccent)
                }
            }
            .safeAreaInset(edge: .bottom) { deleteExchangeButton }
            .sheet(isPresented: $showAddPicker) { addPickerSheet }
        }
    }

    private func row(_ ticker: String) -> some View {
        HStack(spacing: 12) {
            if let c = company(ticker) {
                BrandLogoTile(ticker: c.ticker, name: c.name, color: c.color, domain: c.domain)
                Text(c.name).font(.subheadline)
            } else {
                // 유니버스 미로드 티커도 순서 보존을 위해 표시(로고 자리엔 회색 원).
                Circle().fill(Color.secondary.opacity(0.2))
                    .frame(width: logoTileSize, height: logoTileSize)
                Text(ticker).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// 거래소 자체 삭제 — 편집 화면 외에 삭제 진입점이 없어 여기 하단에 둔다.
    private var deleteExchangeButton: some View {
        Button(role: .destructive) {
            store.remove(id: exchangeID)
            dismiss()
        } label: {
            Text("이 거래소 삭제")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// 종목 추가 — 생성 플로우의 그리드(TickerPickerStep)를 재사용. 이미 담긴 종목은 후보에서 제외.
    private var addPickerSheet: some View {
        NavigationStack {
            TickerPickerStep(
                title: name,
                universe: universe.filter { c in !tickers.contains(c.ticker) },
                actionTitle: "추가"
            ) { added in
                tickers.append(contentsOf: added)
                showAddPicker = false
            }
            .environment(\.appTheme, colorScheme == .dark ? .dark : .light)
        }
    }

    private func save() {
        guard var ex = store.exchange(id: exchangeID) else { return }
        ex.name = name
        ex.tickers = tickers
        store.update(ex)
    }
}
