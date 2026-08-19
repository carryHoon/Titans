//
//  CustomExchangeEditView.swift
//  Titans
//
//  "나만의 거래소" 편집 화면(토스 "관심 편집" 오마주).
//  상단: 거래소 칩 스트립 — 꾹 눌러 드래그로 순서 변경, 선택 칩 우측 연필(✏️)로 이름 변경.
//  하단: 선택된 거래소의 종목 순서 변경(드래그) · 삭제(스와이프/− 버튼) · 종목 추가 · 거래소 삭제.
//  강조 요소는 MarCap 브랜드 초록(Color.marcapAccent).
//

import SwiftUI

struct CustomExchangeEditView: View {
    let store: CustomExchangeStore
    /// 로고/이름 표시용 유니버스(홈에서 이미 로드된 전 거래소 종목).
    let universe: [Company]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 현재 편집 중인 거래소. 칩을 탭하면 다른 거래소로 전환(토스처럼).
    @State private var selectedID: UUID
    @State private var name: String
    @State private var tickers: [String]   // 편집 중인 순서/구성 (전환/완료 시 저장)
    @State private var showAddPicker = false
    @State private var showRename = false
    @State private var editMode: EditMode = .active   // 진입 즉시 편집(드래그/삭제) 모드

    // 칩 드래그 재정렬 상태
    @State private var chipFrames: [UUID: CGRect] = [:]   // 칩별 프레임(칩 스트립 좌표계)
    @State private var draggingID: UUID? = nil            // 현재 들어올린 칩
    @State private var dragLocation: CGPoint = .zero       // 손가락 위치(칩 스트립 좌표계)

    private let chipSpace = "chipStrip"
    private let wobbleAmplitude: Double = 0.8              // 흔들림 각도(도) — 얕고 자글자글하게(토스식)

    init(exchange: CustomExchange, store: CustomExchangeStore, universe: [Company]) {
        self.store = store
        self.universe = universe
        _selectedID = State(initialValue: exchange.id)
        _name = State(initialValue: exchange.name)
        _tickers = State(initialValue: exchange.tickers)
    }

    /// 라이트/다크 시스템 설정을 그대로 따른다(홈과 동일).
    private var theme: AppTheme { colorScheme == .dark ? .dark : .light }

    private func company(_ ticker: String) -> Company? {
        universe.first { $0.ticker == ticker }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupChipStrip
                Divider()
                stockList
            }
            .environment(\.editMode, $editMode)
            .environment(\.appTheme, theme)
            .navigationTitle("관심 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { commitCurrent(); dismiss() }
                        .fontWeight(.bold)
                        .tint(Color.marcapAccent)
                }
            }
            .safeAreaInset(edge: .bottom) { deleteExchangeButton }
            .sheet(isPresented: $showAddPicker) { addPickerSheet }
            .sheet(isPresented: $showRename) {
                RenameExchangeSheet(currentName: name) { newName in
                    name = newName
                    store.rename(id: selectedID, to: newName)
                }
                .environment(\.appTheme, theme)
            }
        }
    }

    // MARK: 상단 — 거래소 칩 스트립(드래그 재정렬 + 연필 이름변경)

    private var groupChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.exchanges.enumerated()), id: \.element.id) { index, ex in
                    groupChip(ex, index: index)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ChipFramePreferenceKey.self,
                                    value: [ex.id: geo.frame(in: .named(chipSpace))])
                            }
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .coordinateSpace(name: chipSpace)
        // 드래그 중엔 스크롤을 막아 칩 이동 제스처가 스크롤에 뺏기지 않게 한다.
        .scrollDisabled(draggingID != nil)
        .onPreferenceChange(ChipFramePreferenceKey.self) { chipFrames = $0 }
        .sensoryFeedback(.selection, trigger: draggingID)   // 칩을 들어올릴 때 햅틱
    }

    @ViewBuilder
    private func groupChip(_ ex: CustomExchange, index: Int) -> some View {
        let isSelected = ex.id == selectedID
        let isDragging = draggingID == ex.id
        // 선택 칩 이름은 로컬 편집값(name)을, 나머지는 스토어값을 표시.
        let label = isSelected ? name : ex.name
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? theme.background : theme.label)
            if isSelected {
                // 토스처럼 선택된 칩 우측에 연필 — 탭하면 이름 변경.
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.background)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(isSelected ? theme.label : Color.secondary.opacity(0.12))
        }
        .contentShape(Capsule())
        // 토스식 지글 — phaseAnimator가 상태 변화(재정렬 등)와 무관하게 계속 순환해 멈추지 않는다.
        // 들어올린 칩만 흔들림을 멈춘다(dragging → 0도).
        .phaseAnimator([false, true]) { content, phase in
            content.rotationEffect(.degrees(wobbleDegrees(index: index, phase: phase, dragging: isDragging)))
        } animation: { _ in .easeInOut(duration: 0.12) }
        // 들어올린 칩은 살짝 커지며 떠오른다.
        .scaleEffect(isDragging ? 1.08 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 6, y: 3)
        .offset(dragOffset(for: ex.id))
        .zIndex(isDragging ? 1 : 0)
        // 재정렬 시 이웃 칩만 부드럽게(오버슈트 없이) 미끄러진다. 들어올린 칩은 손가락을 즉시 따라가야 하므로 애니메이션 없음.
        .animation(isDragging ? nil : .easeInOut(duration: 0.22), value: chipIndex(ex.id))
        .onTapGesture {
            if isSelected {
                showRename = true          // 선택된 칩(연필) 재탭 → 이름 변경
            } else {
                switchTo(ex.id)            // 다른 칩 탭 → 현재 편집 저장 후 전환
            }
        }
        // 꾹 눌러 들어올린 뒤 좌우로 끌면 실시간으로 다른 칩과 자리를 바꾼다.
        .gesture(
            LongPressGesture(minimumDuration: 0.28)
                .sequenced(before: DragGesture(coordinateSpace: .named(chipSpace)))
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }
                    if draggingID != ex.id {
                        draggingID = ex.id
                        // 집는 순간엔 오프셋 0에서 시작하도록 손가락 위치를 칩 중심으로 초기화.
                        if let home = chipFrames[ex.id] { dragLocation = CGPoint(x: home.midX, y: home.midY) }
                    }
                    if let drag {
                        dragLocation = drag.location
                        reorder(dragging: ex.id, x: drag.location.x)
                    }
                }
                .onEnded { _ in
                    // 손을 떼면 들어올린 칩이 제자리로 — 오버슈트(튕김) 없이 부드럽게 안착.
                    withAnimation(.easeOut(duration: 0.18)) {
                        draggingID = nil
                    }
                }
        )
    }

    // MARK: 칩 드래그 헬퍼

    /// 지글 각도 — 들어올린 칩은 0, 나머지는 인덱스 홀짝을 반대 위상으로 두어 ±진폭을 오간다.
    private func wobbleDegrees(index: Int, phase: Bool, dragging: Bool) -> Double {
        guard !dragging else { return 0 }
        let base = index % 2 == 0 ? wobbleAmplitude : -wobbleAmplitude
        return phase ? base : -base
    }

    /// store 내 현재 순서 인덱스 — 재정렬 시 이웃 칩 이동을 애니메이션할 트리거 값.
    private func chipIndex(_ id: UUID) -> Int {
        store.exchanges.firstIndex { $0.id == id } ?? 0
    }

    /// 들어올린 칩을 손가락 아래로 붙인다(칩의 홈 중심 기준 오프셋).
    private func dragOffset(for id: UUID) -> CGSize {
        guard draggingID == id, let home = chipFrames[id] else { return .zero }
        return CGSize(width: dragLocation.x - home.midX, height: dragLocation.y - home.midY)
    }

    /// 손가락 x가 다른 칩 위를 지나면 그 칩과 순서를 바꿔 실시간으로 재정렬.
    /// (애니메이션은 각 칩의 .animation(value:)이 담당 — 여기서 감싸면 들어올린 칩까지 튕긴다.)
    private func reorder(dragging id: UUID, x: CGFloat) {
        guard let overID = chipFrames.first(where: { key, rect in
            key != id && x >= rect.minX && x <= rect.maxX
        })?.key else { return }
        store.moveExchange(fromID: id, toID: overID)
    }

    // MARK: 하단 — 선택된 거래소의 종목 편집

    private var stockList: some View {
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
            let removingID = selectedID
            // 삭제 후 남은 거래소가 있으면 그쪽으로 전환, 없으면 화면을 닫는다.
            let remaining = store.exchanges.filter { $0.id != removingID }
            store.remove(id: removingID)
            if let next = remaining.first {
                selectedID = next.id
                name = next.name
                tickers = next.tickers
            } else {
                dismiss()
            }
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
            .environment(\.appTheme, theme)
        }
    }

    // MARK: 저장/전환

    /// 현재 편집 중인 거래소의 이름/종목을 스토어에 반영.
    private func commitCurrent() {
        guard var ex = store.exchange(id: selectedID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { ex.name = trimmed }
        ex.tickers = tickers
        store.update(ex)
    }

    /// 다른 거래소 칩으로 전환 — 현재 편집 내용을 먼저 저장한 뒤 대상 거래소를 로드.
    private func switchTo(_ id: UUID) {
        commitCurrent()
        guard let ex = store.exchange(id: id) else { return }
        selectedID = id
        name = ex.name
        tickers = ex.tickers
    }
}

// MARK: - 칩 프레임 수집(드래그 재정렬용)

/// 각 거래소 칩의 프레임을 칩 스트립 좌표계로 모아 드래그 시 목표 위치를 계산한다.
private struct ChipFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - 거래소 이름 변경 시트(토스 "그룹 이름" 오마주)

/// 선택된 거래소의 이름을 바꾸는 간단한 시트. 생성 1단계와 동일한 룩앤필.
private struct RenameExchangeSheet: View {
    let currentName: String
    var onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(currentName: String, onConfirm: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onConfirm = onConfirm
        _name = State(initialValue: currentName)
    }

    private var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("어떤 이름으로 바꿀까요?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)

                TextField("거래소 이름", text: $name)
                    .font(.title2.weight(.bold))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit { confirm() }
                    .padding(.top, 12)

                Rectangle()
                    .fill(canProceed ? Color.marcapAccent : Color.secondary.opacity(0.3))
                    .frame(height: 2)
                    .padding(.top, 6)

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
                Button { confirm() } label: {
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
        .presentationDetents([.height(220)])
    }

    private func confirm() {
        guard canProceed else { return }
        onConfirm(name.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}
