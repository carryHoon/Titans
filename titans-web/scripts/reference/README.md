# 정확도 진단 기준 데이터 (reference)

`node scripts/accuracy-check.mjs` 가 앱의 시총 순위를 비교하는 두 종류의 기준 파일이 여기 들어갑니다.

## 1. 공식 기준 — `<거래소>.json`  (직접 입력)

공홈에서 확인한 **공식 top-20**을 넣어두면, 앱이 공식과 얼마나 일치하는지(특히 **누락**) 자동으로 점검합니다.

형식:
```json
{
  "source": "출처 설명",
  "asOf": "2026-06-30",
  "top": [
    { "ticker": "AAPL",      "name": "Apple" },
    { "ticker": "005930.KS", "name": "Samsung" }
  ]
}
```

- `ticker` 는 **앱이 쓰는 티커 형식과 정확히 동일**해야 합니다
  (미국: `AAPL`, `BRK.B` / 한국: `005930.KS`, `196170.KQ`).
- 순서 = 공식 시총 순위. `name` 은 리포트 표기에만 쓰이며 비교엔 티커만 사용.

거래소별 공식 출처 예시 (1차 출시 범위):
| 거래소 | 공식/기준 출처 |
|--------|----------------|
| kospi/kosdaq | KRX 정보데이터시스템 / 네이버 증권 시가총액 순위 |
| nasdaq/nyse  | nasdaq.com 스크리너, companiesmarketcap.com |

## 2. 베이스라인 — `<거래소>.baseline.json`  (자동 생성)

지금처럼 정확도가 **검증된 좋은 상태**일 때 스냅샷을 떠 두는 파일입니다:

```bash
node scripts/accuracy-check.mjs --save-baseline
```

이후 데이터 소스를 EODHD 등으로 바꾼 뒤 인자 없이 다시 실행하면, **바뀐 결과가 예전 좋은 상태 대비 누락/순위가 틀어졌는지** 즉시 비교해 줍니다.

> 팁: 소스 교체 작업 전에 `--save-baseline` 을 먼저 찍어두는 것이 핵심입니다.
