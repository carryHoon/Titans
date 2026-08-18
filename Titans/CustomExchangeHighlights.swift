//
//  CustomExchangeHighlights.swift
//  Titans
//
//  "나만의 거래소"(커스텀 서브셋)와 기존 거래소가 공유하는 하이라이트 엔진.
//
//  설계: 하이라이트 규칙(정상탈환/조달러돌파/급상승/급하락/대형등락/TopN진입/현재1위)은
//        입력 [Company] 하나에만 의존하는 순수 함수다. 따라서 기존 거래소는 서버가 준 rank/previousRank를
//        그대로 쓰고, 커스텀 거래소는 서브셋 로컬 순위로 재계산한 [Company]를 넣기만 하면 동일 규칙이 적용된다.
//        규칙 로직을 여기 한 곳에 두어 양쪽이 공유(드리프트 방지) — 기존 ContentView.highlights(for:)는 이 함수에 위임한다.
//

import SwiftUI

// MARK: - 하이라이트 규칙 (순수 함수 — 기존/커스텀 공유)

/// 주어진 [Company] 기준으로 "오늘의 순위 사건"을 우선순위대로 만든다.
/// 마지막에 현재 1위(폴백)를 항상 넣어 변동이 없어도 비지 않게 한다(👑 서열 프레이밍).
/// rank/previousRank는 호출자가 정한 기준(거래소 서버값 또는 서브셋 로컬 재계산값)을 그대로 신뢰한다.
func buildHighlights(from list: [Company], currency: Currency, exchangeRate: Double) -> [Highlight] {
    guard !list.isEmpty else { return [] }
    // 하나라도 previousRank가 있으면 "전일 비교 기준(baseline)"이 존재한다고 본다.
    // (배포 직후 KR처럼 전부 nil이면 순위변동 사건을 만들지 않고 현재 1위만 보여준다.)
    let hasBaseline = list.contains { $0.previousRank != nil }
    let n = list.count
    var result: [Highlight] = []
    var used = Set<String>()

    // 1) 정상 탈환 — 현재 1위인데 전일엔 1위가 아니었던 종목(가장 극적).
    if let top = list.first(where: { $0.rank == 1 }),
       let prev = top.previousRank, prev > 1 {
        result.append(Highlight(kind: .overtake, company: top,
            title: "정상 탈환", detail: "1위 등극", rankDelta: prev - 1))
        used.insert(top.ticker)
    }

    // 2) 조 달러 돌파 — 오늘 정수 "조 달러(USD 1T)" 문턱을 상향 돌파한 종목(희소·상징적).
    //    prevCap = cap / (1 + change%/100). marketCapUSD 단위가 이미 조(trillion) USD.
    //    (JPX는 change=0이라 자연히 미발생. 표시통화 무관하게 USD 조 클럽 기준.)
    if let breakout = list.compactMap({ c -> (Company, Int)? in
        guard c.change > -100 else { return nil }
        let cap = c.marketCapUSD
        let prevCap = cap / (1 + c.change / 100)
        let k = Int(floor(cap))
        guard k >= 1, Double(k) > prevCap, cap >= Double(k) else { return nil }  // 정수 조 상향 돌파
        return (c, k)
    }).max(by: { $0.1 < $1.1 }), !used.contains(breakout.0.ticker) {
        let c = breakout.0
        result.append(Highlight(kind: .capMilestone, company: c,
            title: "시총 돌파", detail: "\(breakout.1)조 달러 돌파", rankDelta: nil))
        used.insert(c.ticker)
    }

    // 3) 급상승 — (previousRank - rank)가 가장 큰(가장 많이 오른) 종목.
    if let riser = list.compactMap({ c -> (Company, Int)? in
        guard let p = c.previousRank else { return nil }
        let d = p - c.rank
        return d > 0 ? (c, d) : nil
    // 상승 칸수 큰 것 우선, 동점이면 순위 높은(rank 작은) 기업 우선.
    }).max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rank > $1.0.rank }), !used.contains(riser.0.ticker) {
        let c = riser.0
        result.append(Highlight(kind: .topGainer, company: c,
            title: "최대 상승", detail: "\(c.previousRank!)위 → \(c.rank)위", rankDelta: riser.1))
        used.insert(c.ticker)
    }

    // 4) 급하락 — (previousRank - rank)가 가장 작은(가장 많이 내린) 종목. rankDelta 음수.
    if let faller = list.compactMap({ c -> (Company, Int)? in
        guard let p = c.previousRank else { return nil }
        let d = p - c.rank
        return d < 0 ? (c, d) : nil
    // 하락 칸수 큰 것(delta 더 음수) 우선, 동점이면 순위 높은(rank 작은) 기업 우선.
    }).min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rank < $1.0.rank }), !used.contains(faller.0.ticker) {
        let c = faller.0
        result.append(Highlight(kind: .topLoser, company: c,
            title: "최대 하락", detail: "\(c.previousRank!)위 → \(c.rank)위", rankDelta: faller.1))
        used.insert(c.ticker)
    }

    // 5) 대형 등락률 — |당일 등락률|이 가장 큰 종목(3% 이상). 순위가 안 변한 날도 살아있게.
    if let mover = list.filter({ abs($0.change) >= 3.0 && !used.contains($0.ticker) })
        .max(by: { abs($0.change) < abs($1.change) }) {
        let up = mover.change >= 0
        // 기업명 → 순위 → 퍼센테이지 순서: 유저가 순위를 인지하고 리스트에서 바로 찾아 내려갈 수 있게.
        result.append(Highlight(kind: .bigMove, company: mover,
            title: up ? "시총 급등" : "시총 급락", detail: "\(mover.rank)위",
            rankDelta: nil, percentMove: mover.change))
        used.insert(mover.ticker)
    }

    // 6) Top-N 진입 — 오늘 Top10/50/100(현재 목록 크기 내 유효한 것) 문턱을 처음 넘은 종목.
    //    prevEff = previousRank ?? (n+1)(추적 밖). 가장 권위 있는(작은) 문턱 크로싱을 고른다.
    if hasBaseline {
        let thresholds = [10, 50, 100].filter { $0 <= n }
        var best: (c: Company, t: Int)? = nil
        for c in list where !used.contains(c.ticker) {
            let prevEff = c.previousRank ?? (n + 1)
            guard let t = thresholds.first(where: { prevEff > $0 && c.rank <= $0 }) else { continue }
            if best == nil || t < best!.t || (t == best!.t && c.rank < best!.c.rank) {
                best = (c, t)
            }
        }
        if let b = best {
            result.append(Highlight(kind: .newEntry, company: b.c,
                title: "Top\(b.t) 진입", detail: "\(b.c.rank)위", rankDelta: nil))
            used.insert(b.c.ticker)
        }
    }

    // 7) 폴백/기본 — 현재 1위(서열). 변화가 없어도 항상 채워 절대 비지 않게 한다.
    if let leader = list.first(where: { $0.rank == 1 }) ?? list.first {
        let cap = formatMarketCap(leader.marketCapUSD, currency: currency, exchangeRate: exchangeRate)
        result.append(Highlight(kind: .leader, company: leader,
            title: "현재 1위", detail: "1위 · \(cap)", rankDelta: nil))
    }
    return result
}

// MARK: - 서브셋 재랭킹 (커스텀 거래소 전용)

/// 커스텀 거래소 하이라이트의 비교 기준.
enum HighlightBaseline: Equatable {
    case dayOverDay          // 어제 대비 — 당일 등락률로 전일 시총을 역산(저장 불필요)
    case window(days: Int)   // N일 전 대비 — RankSnapshotStore의 과거 시총 스냅샷 사용
}

/// 유니버스에서 `tickers` 부분집합을 골라 **서브셋 로컬 순위**로 rank/previousRank를 다시 계산한 [Company]를 만든다.
/// 반환 결과를 buildHighlights에 넣으면 "그 거래소만을 위한" 하이라이트가 나온다.
///  · rank        = 오늘 시총(marketCapUSD) 내림차순 1…n
///  · previousRank(dayOverDay)  = 전일 시총 역산값 내림차순
///  · previousRank(window)      = 과거 스냅샷 시총 내림차순. 스냅샷에 없는 종목은 nil(순위변동 계산에서 제외).
/// 유니버스에 존재하지 않는 티커(미로드/데이터 없음)는 건너뛴다.
func rerankSubset(universe: [Company], tickers: [String],
                  baseline: HighlightBaseline,
                  today: String = RankSnapshotStore.todayKST()) -> [Company] {
    // 티커 → Company (유니버스에 실제 존재하는 것만).
    var byTicker: [String: Company] = [:]
    for c in universe where byTicker[c.ticker] == nil { byTicker[c.ticker] = c }
    let members = tickers.compactMap { byTicker[$0] }
    guard !members.isEmpty else { return [] }

    // 오늘 서브셋 순위 = 시총 내림차순.
    let ranked = members.sorted { $0.marketCapUSD > $1.marketCapUSD }

    // 전일/과거 기준 시총 맵 → previousRank 계산.
    let prevRank = previousRankMap(for: ranked, baseline: baseline, today: today)

    return ranked.enumerated().map { idx, c in
        Company(
            rank:         idx + 1,
            previousRank: prevRank[c.ticker],
            name:         c.name,
            ticker:       c.ticker,
            marketCapUSD: c.marketCapUSD,
            change:       c.change,
            color:        c.color,
            domain:       c.domain
        )
    }
}

/// 서브셋 각 종목의 previousRank(서브셋 로컬)를 계산한다.
private func previousRankMap(for ranked: [Company], baseline: HighlightBaseline, today: String) -> [String: Int] {
    // (ticker, 과거 시총) 목록 — 과거 시총을 아는 종목만.
    let pastCaps: [(ticker: String, cap: Double)]
    switch baseline {
    case .dayOverDay:
        pastCaps = ranked.map { c in
            let denom = 1 + c.change / 100
            let prevCap = denom > 0 ? c.marketCapUSD / denom : c.marketCapUSD  // change<=-100 방어
            return (c.ticker, prevCap)
        }
    case .window(let days):
        let tickerSet = Set(ranked.map(\.ticker))
        guard let base = RankSnapshotStore.baseline(daysAgo: days, tickers: tickerSet, today: today) else {
            return [:]   // 아직 과거 스냅샷 없음 → 전부 nil(현재 1위 폴백만 노출)
        }
        pastCaps = ranked.compactMap { c in base[c.ticker].map { (c.ticker, $0) } }
    }

    // 과거 시총 내림차순으로 previousRank 1…m 부여.
    var map: [String: Int] = [:]
    for (i, entry) in pastCaps.sorted(by: { $0.cap > $1.cap }).enumerated() {
        map[entry.ticker] = i + 1
    }
    return map
}
