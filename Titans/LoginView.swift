//
//  LoginView.swift
//  surFin
//
//  스플래시 이후 (비로그인·최초 진입 시) 보여지는 로그인 화면.
//  브랜드 무드: "surFin — Ride the Market". 시장의 등락을 파도로 은유한다.
//
//  구성(위 → 아래):
//    1) OceanHero  — 동적으로 말려 올라가 배럴(터널)을 만드는 파도 + 왼→오로 상승하는
//                    주식 그래프 + 그래프 끝점 아래에서 0→100 으로 오르는 퍼센트 카운터.
//    2) 브랜드 텍스트("RIDE THE MARKET" / "surFin") — 배럴·그래프가 다 채워진 직후 페이드인.
//    3) 소셜 로그인(메인) — Apple · Google · Kakao 원형 버튼.
//    4) 하단(서브)         — 회원가입 · 로그인 없이 둘러보기.
//
//  로그인은 선택이다. 실제 세션 전환은 AuthManager가 authStateChanges로 감지해
//  RootView가 자동으로 ContentView로 넘어간다. 이 화면은 "요청"만 하고 상태는 소유하지 않는다.
//

import SwiftUI
import AuthenticationServices
import UIKit

/// 인트로(로딩) 연출 길이. 서버에서 데이터를 받아오는 체감 시간(2~3초)을 대신한다.
/// 이 시간 동안 파도가 배럴로 말리고, 그래프가 상승하며, 퍼센트가 0→100 으로 오른다.
private let kIntroDuration: Double = 2.4

// MARK: - LoginView

struct LoginView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @Environment(AuthManager.self) private var auth

    /// "로그인 없이 둘러보기" 선택 시 호출(익명으로 앱 진입).
    let onContinueAnonymously: () -> Void

    // 인트로가 끝난 뒤 순차적으로 드러나는 요소들.
    @State private var revealBrand = false
    @State private var revealControls = false

    // 소셜/이메일 진행 상태
    @State private var appleCoordinator = AppleSignInCoordinator()
    @State private var isBusy = false
    @State private var showEmailSheet = false
    @State private var alertMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        GeometryReader { geo in
            let heroH = geo.size.height * 0.60
            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 파도 히어로 — 브랜드 텍스트를 파도(파랑) 위에 얹어 흰 글씨가 보이게 한다.
                    OceanHeroView()
                        .frame(height: heroH)
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: Color.white.opacity(0.75), location: 0.55),
                                    .init(color: .white, location: 1.0)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: heroH * 0.25)
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottom) {
                            brand.padding(.bottom, heroH * 0.28)
                        }

                    VStack(spacing: 24) {
                        socialSection
                        bottomLinks
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 26)

                    Spacer(minLength: 0)
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 12)

                if isBusy {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView().controlSize(.large).tint(.black)
                }
            }
        }
        .task {
            // 배럴·그래프가 다 채워진 직후 → 브랜드 텍스트, 이어서 소셜/하단이 페이드인.
            try? await Task.sleep(for: .seconds(kIntroDuration))
            withAnimation(.easeOut(duration: 0.7)) { revealBrand = true }
            try? await Task.sleep(for: .seconds(0.28))
            withAnimation(.easeOut(duration: 0.7)) { revealControls = true }
        }
        .sheet(isPresented: $showEmailSheet) {
            EmailAuthSheet(isDarkMode: isDarkMode)
                .environment(auth)
        }
        .alert("알림", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("안내", isPresented: .init(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
    }

    private var background: Color { .white }

    // MARK: 브랜드 텍스트

    private var brand: some View {
        VStack(spacing: 6) {
            Text("RIDE THE MARKET")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .tracking(5)
                .foregroundStyle(.white)

            HStack(spacing: 0) {
                Text("sur").foregroundStyle(.white)
                Text("Fin").foregroundStyle(.black)
            }
            .font(.system(size: 66, weight: .bold, design: .rounded))
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 2)
        .opacity(revealBrand ? 1 : 0)
        .offset(y: revealBrand ? 0 : 14)
    }

    // MARK: 메인 — 소셜 로그인 (원형)

    private var socialSection: some View {
        HStack(spacing: 26) {
            SocialCircleButton(kind: .apple)  { signInWithApple() }
            SocialCircleButton(kind: .google) { comingSoon("Google") }
            SocialCircleButton(kind: .kakao)  { signInWithKakao() }
        }
        .opacity(revealControls ? 1 : 0)
        .offset(y: revealControls ? 0 : 14)
    }

    // MARK: 서브 — 회원가입 · 둘러보기

    private var bottomLinks: some View {
        HStack(spacing: 16) {
            Button("회원가입") { showEmailSheet = true }
            Rectangle()
                .fill(.black.opacity(0.2))
                .frame(width: 1, height: 12)
            Button("로그인 없이 둘러보기") { onContinueAnonymously() }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.black.opacity(0.55))
        .opacity(revealControls ? 1 : 0)
    }

    // MARK: 액션

    private func signInWithApple() {
        appleCoordinator.start(configure: { auth.prepareAppleRequest($0) }) { result in
            Task { await handleApple(result) }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.handleAppleCompletion(result)
        } catch {
            // 사용자가 취소한 경우는 오류로 표시하지 않는다.
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            alertMessage = error.localizedDescription
        }
    }

    private func signInWithKakao() {
        Task { await handleKakao() }
    }

    private func handleKakao() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signInWithKakao()
        } catch {
            // 사용자가 웹 로그인 창을 닫은(취소한) 경우는 오류로 표시하지 않는다.
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return }
            alertMessage = error.localizedDescription
        }
    }

    private func comingSoon(_ provider: String) {
        infoMessage = "\(provider) 로그인은 곧 지원될 예정이에요. 지금은 Apple 또는 이메일로 시작해 주세요."
    }
}

// MARK: - OceanHeroView (파도 배럴 + 상승 그래프 + 퍼센트 카운터)

/// 하나의 `TimelineView(.animation)`으로 전 요소를 프레임 단위로 갱신한다.
///   • fill(0→1)  : 인트로 진행도. 그래프 상승·배럴 말림·퍼센트 숫자가 이 값에 동기화된다.
///   • phase      : 파도의 지속적인 잔물결(인트로가 끝난 뒤에도 계속 살아 움직이게 함).
private struct OceanHeroView: View {
    /// 디자인 확인용 고정 진행도(nil이면 시간 기반 인트로 연출). 프리뷰 전용.
    var debugProgress: Double? = nil

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let fill = debugProgress ?? easeInOut(min(1, max(0, elapsed / kIntroDuration)))
            let phase = elapsed

            Canvas { ctx, size in
                draw(ctx, size: size, fill: fill, phase: phase)
            }
        }
    }

    // 팔레트 — 실제 파도 사진 기준: 립 안쪽은 밝은 청록, 베이스로 갈수록 딥블루, 크레스트는 흰 포말.
    private let waveTeal  = Color(red: 0.52, green: 0.82, blue: 0.90)   // 립 안쪽 청록(밝음)
    private let waveMid   = Color(red: 0.20, green: 0.56, blue: 0.84)   // 페이스 중간
    private let waveDeep  = Color(red: 0.07, green: 0.30, blue: 0.62)   // 베이스 딥블루
    private let waveBase  = Color(red: 0.04, green: 0.18, blue: 0.44)   // 최하단
    private let greenTip  = Color(red: 0.30, green: 0.82, blue: 0.48)
    private let greenDeep = Color(red: 0.12, green: 0.64, blue: 0.36)

    private func draw(_ ctx: GraphicsContext, size: CGSize, fill p: Double, phase: Double) {
        let w = size.width, h = size.height
        func n(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        let pp = CGFloat(min(1, max(0, p)))
        // "밀려 말려 올라가는" 형성 보간: 평평한 너울(0) → 말려 올라간 배럴(1).
        func L(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * pp }
        // 형성이 끝난 뒤에도 살아 움직이도록 하는 잔물결.
        let sway = CGFloat(sin(phase * 0.8)) * 0.006
        let bob  = CGFloat(sin(phase * 1.1)) * 0.006

        // 하나의 몸통으로 그린 브레이킹 웨이브. 크레스트가 오른쪽으로 던져지며 끝(tip)이
        // 아래로 훅(hook)지게 말리고, 그 아래를 감싸는 초승달 음영으로 배럴의 둥근 깊이를 만든다.
        // 형성 보간: 평평한 너울(0) → 높이 솟아 말린 배럴(1).
        let leftY  = L(0.74, 0.60) + bob      // 왼쪽 수면
        let crestX = 0.50 + sway
        let crestY = L(0.52, 0.15) + bob      // 크레스트: 점점 높이 솟음
        let tipX   = L(0.54, 0.66) + sway     // 훅 끝: 앞(오른쪽)으로 던져짐
        let tipY   = L(0.40, 0.66)            // 그리고 아래로 뚝 떨어짐(그래프와 교차)

        // 배럴은 "음영"이 아니라 말리는 형태 + 빛 + 포말로만 연상시킨다(실제 파도 사진 기준).
        let mouthC = n(0.44, 0.46)   // 튜브(배럴) 입구 중심 — 여기서 빛이 새어나오듯 밝다.

        // 1) 뒤 너울(back swell) — 깊이용 은은한 레이어
        var swell = Path()
        swell.move(to: n(-0.1, 1.0))
        swell.addLine(to: n(-0.1, leftY + 0.05))
        swell.addQuadCurve(to: n(crestX + 0.06, crestY + 0.14), control: n(0.10, leftY - 0.06))
        swell.addQuadCurve(to: n(1.1, 0.72), control: n(0.84, crestY + 0.10))
        swell.addLine(to: n(1.1, 1.0)); swell.closeSubpath()
        ctx.fill(swell, with: .linearGradient(
            Gradient(colors: [waveMid.opacity(0.5), waveMid.opacity(0.0)]),
            startPoint: n(0, 0.15), endPoint: n(0, 0.95)))

        // 2) 파도 몸통 — 립 안쪽 청록 → 베이스 딥블루. 크레스트가 던져져 훅이 아래로 말린다.
        var body = Path()
        body.move(to: n(-0.05, 1.0))
        body.addLine(to: n(-0.05, leftY))
        body.addCurve(to: n(crestX, crestY),                       // 왼쪽 앞면이 솟아 크레스트로
                      control1: n(0.12, leftY - 0.12), control2: n(0.34, crestY - 0.02))
        body.addCurve(to: n(tipX, tipY),                           // 크레스트가 던져져 훅 끝이 아래로
                      control1: n(crestX + 0.20, crestY - 0.05), control2: n(tipX + 0.12, tipY - 0.22))
        body.addCurve(to: n(1.05, 0.82),                           // 훅 뒤로 오른쪽 꼬리가 쓸려 내려감
                      control1: n(tipX + 0.05, tipY + 0.12), control2: n(0.86, 0.76))
        body.addLine(to: n(1.05, 1.0)); body.closeSubpath()
        // 크레스트(위)는 딥블루로 어둡게 → 흰 포말이 도드라짐. 가운데 페이스는 햇빛 받아 청록.
        // → 베이스는 다시 딥블루. 사진의 명암 배치를 흉내낸다.
        ctx.fill(body, with: .linearGradient(
            Gradient(stops: [
                .init(color: waveDeep, location: 0.00),
                .init(color: waveMid,  location: 0.22),
                .init(color: waveTeal, location: 0.50),
                .init(color: waveDeep, location: 0.80),
                .init(color: waveBase, location: 1.00)
            ]),
            startPoint: n(0.42, 0.06), endPoint: n(0.18, 1.0)))

        // 3) 밝은 튜브 코어 — 배럴 입구로 빛이 새어나오는 느낌(어두운 음영 대신 밝게).
        var glowCtx = ctx
        glowCtx.opacity = Double(pp)
        glowCtx.fill(body, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.85), waveTeal.opacity(0.25), .clear]),
            center: mouthC, startRadius: 2, endRadius: w * 0.26))

        // 4) 포말 줄기(streaks) — 페이스를 따라 흘러내리는 얇은 흰 물결선(사진의 세로 결).
        var streakCtx = ctx
        streakCtx.opacity = Double(pp) * 0.8
        for i in 0..<5 {
            let t = CGFloat(i) / 4.0
            let sx = 0.20 + t * 0.30
            var s = Path()
            s.move(to: n(sx, crestY + 0.10))
            s.addCurve(to: n(sx - 0.06 + t * 0.02, leftY - 0.02),
                       control1: n(sx - 0.01, crestY + 0.24),
                       control2: n(sx - 0.05, (crestY + leftY) / 2))
            streakCtx.stroke(s, with: .color(.white.opacity(0.35)),
                             style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        // 5) 말리는 결(curl lines) — 훅 안쪽을 감아 도는 나선 결. 배럴의 둥근 형태를 선으로만 암시.
        var curlCtx = ctx
        curlCtx.opacity = Double(pp)
        for i in 0..<3 {
            let o = CGFloat(i) * 0.028
            var c = Path()
            c.move(to: n(0.33 + o, 0.53))
            c.addCurve(to: n(crestX + 0.02, crestY + 0.11 + o),
                       control1: n(0.29 + o, 0.42), control2: n(0.35 + o, crestY + 0.07))
            c.addCurve(to: n(tipX - 0.03, tipY - 0.04),
                       control1: n(crestX + 0.20, crestY + 0.01 + o), control2: n(tipX + 0.02, tipY - 0.17))
            curlCtx.stroke(c, with: .color(.white.opacity(0.5 - Double(i) * 0.13)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }

        // 6) 포말 크레스트 — 립 능선을 따라 두툼한 흰 포말(감싸는 선이 아니라 부드러운 밴드).
        var crest = Path()
        crest.move(to: n(0.16, leftY - 0.10))
        crest.addCurve(to: n(crestX, crestY - 0.01),
                       control1: n(0.20, crestY + 0.06), control2: n(0.36, crestY - 0.02))
        crest.addCurve(to: n(tipX + 0.02, tipY - 0.02),
                       control1: n(crestX + 0.22, crestY - 0.06), control2: n(tipX + 0.14, tipY - 0.24))
        var crestCtx = ctx
        crestCtx.opacity = Double(pp)
        crestCtx.stroke(crest, with: .color(.white.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        crestCtx.stroke(crest, with: .color(.white.opacity(0.35)),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))

        // 7) 스프레이 물방울 — 크레스트 위로 흩날리는 포말 점들.
        var sprayCtx = ctx
        sprayCtx.opacity = Double(pp)
        let sprayPts: [(CGFloat, CGFloat, CGFloat)] = [
            (crestX - 0.04, crestY - 0.05, 2.4), (crestX + 0.08, crestY - 0.07, 3),
            (crestX + 0.20, crestY - 0.05, 2.2), (crestX + 0.32, crestY + 0.0, 2.6),
            (crestX + 0.12, crestY - 0.12, 1.8), (tipX + 0.04, tipY - 0.10, 2)
        ]
        for (fx, fy, r) in sprayPts {
            let pt = n(fx, fy)
            sprayCtx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                          with: .color(.white.opacity(0.8)))
        }

        // Crest opening — radial white wash from the top centre. Thins the wave visually
        // near the crest so white background shows through: the higher you go, the narrower
        // the form appears (barrel-with-a-hole silhouette).
        let topOpen = ctx
        topOpen.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.92), location: 0.00),
                    .init(color: .white.opacity(0.45), location: 0.22),
                    .init(color: .clear,               location: 0.55)
                ]),
                center: n(0.50, 0.00),
                startRadius: 0,
                endRadius: h * 0.55))

        // 주식 그래프 — 틀(트랙)은 이미 있고, 초록이 빨대처럼 왼→오로 채워진다.
        let box = CGRect(x: w * 0.14, y: h * 0.13, width: w * 0.74, height: h * 0.46)
        let norm: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.92), CGPoint(x: 0.13, y: 0.74),
            CGPoint(x: 0.26, y: 0.82), CGPoint(x: 0.40, y: 0.52),
            CGPoint(x: 0.55, y: 0.62), CGPoint(x: 0.70, y: 0.34),
            CGPoint(x: 0.84, y: 0.44), CGPoint(x: 1.00, y: 0.06)
        ]
        let pts = norm.map { CGPoint(x: box.minX + $0.x * box.width,
                                     y: box.minY + $0.y * box.height) }
        // 트랙(빈 틀)
        var track = Path(); track.addLines(pts)
        let end = pts[pts.count - 1]
        let prev = pts[pts.count - 2]
        let angle = atan2(end.y - prev.y, end.x - prev.x)
        ctx.stroke(track, with: .color(.black.opacity(0.10)),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        drawArrowHead(ctx, at: end, angle: angle, color: .black.opacity(0.10), size: 13)
        // 초록 채움
        let (green, _, _) = polyline(pts, upTo: p)
        ctx.stroke(green, with: .linearGradient(
            Gradient(colors: [greenDeep, greenTip]),
            startPoint: pts.first ?? .zero, endPoint: end),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        // 채움이 끝점에 도달하면 초록 화살촉이 서서히 켜진다.
        let arrowIn = max(0, min(1, (p - 0.85) / 0.15))
        if arrowIn > 0 {
            drawArrowHead(ctx, at: end, angle: angle, color: greenTip.opacity(arrowIn), size: 13)
        }

        // 7) 퍼센트 — 화살표 끝점에 고정, 숫자만 0→100 으로 증가.
        let pct = Int((p * 100).rounded())
        let label = Text("\(pct)%")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(greenDeep)
        ctx.draw(label, at: CGPoint(x: min(end.x, w - 26), y: end.y - 16), anchor: .center)
    }

    /// 꺾은선 `pts`를 길이 기준으로 `t`(0~1)만큼 그린 경로와, 그 끝점·진행 방향(rad)을 돌려준다.
    private func polyline(_ pts: [CGPoint], upTo t: Double) -> (Path, CGPoint, CGFloat) {
        var path = Path()
        guard pts.count > 1 else { return (path, pts.first ?? .zero, 0) }

        // 전체 길이
        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
            lengths.append(d); total += d
        }
        let target = CGFloat(max(0, min(1, t))) * total

        path.move(to: pts[0])
        var walked: CGFloat = 0
        var tip = pts[0]
        var angle: CGFloat = 0
        for i in 1..<pts.count {
            let seg = lengths[i-1]
            if walked + seg <= target || seg == 0 {
                path.addLine(to: pts[i])
                walked += seg
                tip = pts[i]
                angle = atan2(pts[i].y - pts[i-1].y, pts[i].x - pts[i-1].x)
            } else {
                let f = (target - walked) / seg
                let p = CGPoint(x: pts[i-1].x + (pts[i].x - pts[i-1].x) * f,
                                y: pts[i-1].y + (pts[i].y - pts[i-1].y) * f)
                path.addLine(to: p)
                tip = p
                angle = atan2(pts[i].y - pts[i-1].y, pts[i].x - pts[i-1].x)
                break
            }
        }
        return (path, tip, angle)
    }

    private func drawArrowHead(_ ctx: GraphicsContext, at p: CGPoint,
                               angle: CGFloat, color: Color, size: CGFloat) {
        let a1 = angle + .pi * 0.82
        let a2 = angle - .pi * 0.82
        var head = Path()
        head.move(to: p)
        head.addLine(to: CGPoint(x: p.x + cos(a1) * size, y: p.y + sin(a1) * size))
        head.move(to: p)
        head.addLine(to: CGPoint(x: p.x + cos(a2) * size, y: p.y + sin(a2) * size))
        ctx.stroke(head, with: .color(color),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }
}

/// 부드러운 가감속 곡선(cubic ease-in-out).
private func easeInOut(_ x: Double) -> Double {
    x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

// MARK: - SocialCircleButton (원형 소셜 로그인 버튼)

private struct SocialCircleButton: View {
    enum Kind { case apple, google, kakao }

    let kind: Kind
    let action: () -> Void

    private let diameter: CGFloat = 62

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(background)
                symbol
            }
            .frame(width: diameter, height: diameter)
            // 배경색과 겹쳐 구획이 안 되는 경우를 대비해 원 테두리로 구획한다.
            .overlay(Circle().stroke(ring, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var background: Color {
        switch kind {
        case .apple:  return .black
        case .google: return .white
        case .kakao:  return Color(red: 0.996, green: 0.898, blue: 0.0) // Kakao Yellow #FEE500
        }
    }

    /// 흰 배경(구글)은 검정 계열 테두리로, 나머지는 은은한 흰 테두리로 구획.
    private var ring: Color {
        kind == .google ? Color.black.opacity(0.14) : Color.white.opacity(0.18)
    }

    @ViewBuilder
    private var symbol: some View {
        switch kind {
        case .apple:
            Image(systemName: "applelogo")
                .font(.system(size: 27))
                .foregroundStyle(.white)
                .offset(y: -1)
        case .google:
            Image("SocialGoogle")
                .resizable()
                .scaledToFit()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        case .kakao:
            // 카카오 공식 말풍선 심볼(투명 배경) — 노랑 배경 위에 얹는다.
            Image("KakaoLoginSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 28)
        }
    }

    private var accessibilityLabelText: String {
        switch kind {
        case .apple:  return "Apple로 로그인"
        case .google: return "Google로 로그인"
        case .kakao:  return "카카오로 로그인"
        }
    }
}

// MARK: - AppleSignInCoordinator (커스텀 원형 버튼용 네이티브 Apple 로그인)

/// `SignInWithAppleButton`(정형 버튼) 대신 원형 아이콘 버튼을 쓰기 위해
/// `ASAuthorizationController`를 직접 구동한다. nonce/스코프 설정은 AuthManager가 담당.
@MainActor
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var onResult: ((Result<ASAuthorization, Error>) -> Void)?

    func start(configure: (ASAuthorizationAppleIDRequest) -> Void,
               onResult: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.onResult = onResult
        let request = ASAuthorizationAppleIDProvider().createRequest()
        configure(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            onResult?(.success(authorization)); onResult = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            onResult?(.failure(error)); onResult = nil
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let key = scene?.keyWindow { return key }
        if let scene { return UIWindow(windowScene: scene) }
        return UIWindow(frame: .zero)
    }
}

// MARK: - EmailAuthSheet (회원가입/이메일 로그인)

/// "회원가입" 진입 시 표시되는 이메일 가입/로그인 시트. Supabase 내장 이메일 인증 사용.
private struct EmailAuthSheet: View {
    let isDarkMode: Bool
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var isSignUpMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var alertMessage: String?
    @State private var infoMessage: String?

    private var theme: AppTheme { isDarkMode ? .dark : .light }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        Text(isSignUpMode ? "이메일로 회원가입" : "이메일로 로그인")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.label)
                            .padding(.top, 12)

                        field("이메일", text: $email, isSecure: false)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        field("비밀번호", text: $password, isSecure: true)
                            .textContentType(isSignUpMode ? .newPassword : .password)

                        Button {
                            Task { await submit() }
                        } label: {
                            Text(isSignUpMode ? "회원가입" : "로그인")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 12).fill(theme.label))
                        }
                        .disabled(!isFormValid || isBusy)
                        .opacity(isFormValid ? 1 : 0.5)

                        HStack {
                            Button(isSignUpMode ? "이미 계정이 있어요" : "계정 만들기") {
                                withAnimation { isSignUpMode.toggle() }
                            }
                            Spacer()
                            Button("비밀번호를 잊으셨나요?") {
                                Task { await sendReset() }
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryLabel)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                if isBusy {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView().controlSize(.large).tint(theme.label)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
        }
        .alert("알림", isPresented: .init(
            get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: { Text(alertMessage ?? "") }
        .alert("안내", isPresented: .init(
            get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: { Text(infoMessage ?? "") }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        Group {
            if isSecure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .font(.system(size: 15))
        .foregroundStyle(theme.label)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.stroke, lineWidth: 1))
    }

    private var isFormValid: Bool { email.contains("@") && password.count >= 6 }

    private func submit() async {
        isBusy = true
        defer { isBusy = false }
        do {
            if isSignUpMode {
                try await auth.signUpEmail(email: email, password: password)
                if auth.currentUser == nil {
                    infoMessage = "확인 메일을 보냈어요. 메일의 링크로 인증을 완료한 뒤 로그인해 주세요."
                }
            } else {
                try await auth.signInEmail(email: email, password: password)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func sendReset() async {
        guard email.contains("@") else {
            alertMessage = "비밀번호를 재설정할 이메일 주소를 먼저 입력해 주세요."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.resetPassword(email: email)
            infoMessage = "비밀번호 재설정 메일을 보냈어요."
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

#Preview("Login") {
    LoginView(onContinueAnonymously: {})
        .environment(AuthManager())
}

// 형성된 배럴/그래프 최종 모습 확인용(프리뷰 전용).
#Preview("Hero – Formed") {
    ZStack {
        LinearGradient(colors: [.white, Color(red: 0.95, green: 0.97, blue: 1.0)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack {
            OceanHeroView(debugProgress: 1.0)
                .frame(height: 460)
            Spacer()
        }
    }
}
