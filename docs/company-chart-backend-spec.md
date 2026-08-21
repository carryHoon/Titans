# `/api/company-chart` — 종목 시가총액 히스토리 API 계약서

앱의 종목 상세 화면(`CompanyDetailView`)이 소비하는 **종목별 일별 시가총액 시계열** 엔드포인트.
titans-web(Vercel) 저장소에 구현한다. iOS 클라이언트는 이미 이 계약대로 호출하며, 부재 시 시드 곡선으로 폴백한다.

---

## 1. 요청

```
GET /api/company-chart?ticker={TICKER}&range={RANGE}
```

| 파라미터 | 필수 | 값 | 설명 |
|----------|------|-----|------|
| `ticker` | ✓ | 예: `NVDA`, `005930` | 앱 `Company.ticker` 그대로(URL 인코딩됨). KR은 6자리 단축코드. |
| `range`  | ✓ | `w1` `m1` `m3` `y1` `y5` `all` | 1주 / 1달 / 3달 / 1년 / 5년 / 전체 |

- `ticker` 형태(숫자 6자리 vs 알파벳)와 내부 티커→거래소 매핑으로 KR/US·글로벌을 분기한다.

## 2. 응답 (200)

```json
{
  "ticker": "NVDA",
  "name": "NVIDIA",
  "points": [
    { "date": "2024-01-02", "capUSD": 1.482 },
    { "date": "2024-01-03", "capUSD": 1.501 }
  ],
  "stale": false
}
```

| 필드 | 타입 | 규약 |
|------|------|------|
| `ticker` | string | 요청 티커 에코 |
| `name` | string | 표시용 종목명 |
| `points` | array | **오래된→최신** 정렬. 각 원소 `{date, capUSD}` |
| `points[].date` | string | 거래일 `"YYYY-MM-DD"` (**종가 기준**) |
| `points[].capUSD` | number | 해당 거래일 종가 시가총액, **trillion USD** 단위(통화 무관 공통값; 앱이 표시 시 환산) |
| `stale` | bool? | 캐시 신선도(옵션) |
| `error` | string? | 실패 사유(옵션). 있으면 앱은 시드 폴백 |

> ⚠️ 단위 규약이 핵심: 앱 전역(`Company.marketCapUSD`, `RankSnapshotStore`)이 **trillion USD**를 쓴다. KR·기타 통화 원천값은 **반드시 USD 환산 후 조 단위로** 내려줄 것. (예: 삼성전자 시총 500조원 → USD 환산 → 약 0.36 trillion USD)

`points`는 최소 2개 이상. 2개 미만이면 `error`를 채우거나 빈 배열 반환(앱이 시드로 폴백).

---

## 3. 데이터 소스별 구현

### 3-1. 🇰🇷 KOSPI/KOSDAQ — 공공데이터포털 (확정, 무료)

- **서비스**: 금융위원회_주식시세정보 `getStockPriceInfo` (data.go.kr, 서비스 15094808)
- **핵심 필드**: `mrktTotAmt` = **일별 시가총액(원)** 이 응답에 그대로 있음 → 가격×주식수 재계산 불필요
- **기간 조회**: `beginBasDt`/`endBasDt`(YYYYMMDD) + `likeSrtnCd`(단축코드) 또는 `isinCd`
- **환산**: `capUSD = mrktTotAmt(KRW) / 1e12 / (KRW per USD)` — 기존 FX 소스(exchangeRates) 재사용
- **주의**: D-1 lag(영업일+1 오후 1시 갱신). "종가 기준" 그래프라 부합. 단일 `DATA_GO_KR_KEY` 사용.
- **⚠️ 기간 한계(중요)**: 이 API는 **2020년 이후 데이터만** 제공한다(금융공공데이터 2020 개방, 지수시세정보 2020-01-01~). 따라서 `y5`까지는 커버 가능하나 **`all`(상장 이후 거시뷰)은 불가** — 삼성전자 2007~ 같은 장기 그래프를 못 만든다.
  - 실제 시작일은 `beginBasDt=20000101`로 프로브해 확정할 것.
  - **장기 KR이 필요하면** 별도 소스 필요: KRX 정보데이터시스템 / `pykrx` / `FinanceDataReader`(Naver·KRX 원천). **단 상업 재배포 라이선스 리스크가 미해결**이라 도입 전 법적 검토 필수.
  - 잠정: KR `all`은 2020~현재까지만 제공하고, UI 문구로 "2020년부터"를 밝히거나 라이선스 확보 후 확장.

### 3-2. 🇺🇸/글로벌 — Twelve Data (프로브 후 확정)

**먼저 실측 프로브**(실 키로): TD `/market_cap`(fundamentals) 엔드포인트가
- (a) **Venture 플랜에서 열리는지**
- (b) **크레딧 소모량**
- (c) start_date/end_date로 **일별 시계열**을 실제 반환하는지 (콜당 최대 5000 포인트)

| 결과 | 경로 |
|------|------|
| 열림 | **경로 A**: `/market_cap?symbol=&start_date=&end_date=` → 그대로 `points`로 매핑(정밀 히스토리) |
| 막힘/불충분 | **경로 B(근사)**: `/time_series`(일봉 종가, 상장 이후·split 조정) **× 현재 발행주식수**. TD가 발행주식수 *히스토리*는 안 주므로 과거 자사주매입/증자 미반영 → **근사치**. 헤더/문구에 정밀도 한계 감안 |

- 환산: 원천이 USD면 그대로 /1e12, 비USD 거래소는 해당 통화→USD.
- 라이선스: 소비자앱 display + 히스토리는 벤처플랜 서면 허용([[titans-td-license-redistribution]]). **attribution 표기 필수** — 앱은 KR=`공공데이터포털(금융위원회)`, 그 외=`Twelve Data`를 상세화면 하단에 이미 노출.

---

## 4. 다운샘플 / 캐시

- **다운샘플**: `range`별 포인트 상한을 두어 페이로드를 줄인다(권장 상한: w1≈7, m1≈30, m3≈60, y1≈120, y5≈180, all≈200). 원천이 더 촘촘하면 등간격 샘플링.
- **캐시**: EOD(하루 1회 변동) → **24h 캐시**. 기존 `/api/market-chart`의 캐시 정책 재사용.
- **비용**: KR은 무료. US는 티커×range 조합을 24h 캐시로 크레딧 최소화. 인기 종목 워밍업 크론 고려([[titans-twelve-data-architecture]]).

## 5. 엣지 케이스

- 미지원 티커/데이터 없음 → `{ "error": "...", "points": [] }` (앱이 시드 폴백, 크래시 없음)
- 신규 상장(히스토리 짧음) → 있는 만큼만. `all`도 상장일까지.
- 멀티클래스(BRK.B 등) 기존 이슈([[titans-us-marketcap-accuracy]])는 히스토리에도 동일하게 존재 — 프로브 시 확인.

---

## 6. 클라이언트 계약(참고, 변경 금지)

- 모델: `CompanyChartPoint {date, capUSD}`, `CompanyChart {ticker, name, points}`, DTO `CompanyChartResponse` (`Titans/SurFinModels.swift`)
- 로더: `CompanyChartStore.fetchRemote(_:)` → 위 URL 호출, 실패 시 결정론적 시드 (`Titans/CompanyChartStore.swift`)
- 즉 **백엔드는 이 응답 스키마만 충족하면 UI/인터랙션 변경 없이 실데이터로 대체**된다.
