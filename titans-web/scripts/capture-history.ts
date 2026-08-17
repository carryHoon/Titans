// 순위 히스토리 적재 스크립트 — GitHub Actions 크론이 refresh-* 갱신 이후 하루 1회 실행한다.
//
// 각 거래소 스냅샷(Upstash)에서 EOD 순위를 재현해 rank-hist:<feed> 링버퍼에 append 한다.
// 라이브 quote·업스트림 재fetch 없이 스냅샷만 읽으므로 TD 크레딧 소모가 없다(파생 순위만 저장).
//
// 필요 env (GitHub Secrets → workflow env):
//   UPSTASH_REDIS_REST_URL, UPSTASH_REDIS_REST_TOKEN — 스냅샷 읽기 + 히스토리 쓰기
//   TWELVE_DATA_API_KEY — ALL/NASDAQ의 KRW 주입분 환산에 쓰는 FX(getUsdKrwQuote) 조회용
//   DATA_GO_KR_KEY — kr-snapshot 게터의 안전망 부트스트랩 대비(정상적으로는 store에서 read만)
//
// 로컬 실행: npx tsx --env-file=.env.local scripts/capture-history.ts

import { captureAllRankHistory } from '../lib/rank-history'

async function main() {
  if (!process.env.UPSTASH_REDIS_REST_URL || !process.env.UPSTASH_REDIS_REST_TOKEN) {
    throw new Error('UPSTASH_REDIS_REST_URL/TOKEN 미설정 — 히스토리를 Upstash에 저장할 수 없음')
  }

  const started = Date.now()
  const results = await captureAllRankHistory()
  const secs = ((Date.now() - started) / 1000).toFixed(0)

  for (const r of results) {
    const detail = r.status === 'error' ? `error: ${r.error}` : `${r.status} (date=${r.date ?? '-'}, ${r.count ?? 0}종목)`
    console.log(`[capture-history] ${r.feed.padEnd(9)} → ${detail}`)
  }

  const appended = results.filter(r => r.status === 'appended').length
  const errored  = results.filter(r => r.status === 'error').length
  console.log(`[capture-history] 완료 (${secs}s): ${appended} appended, ${errored} error, ${results.length} feeds`)

  // 일부 피드 실패(스냅샷 결손 등)는 나머지 적재를 막지 않는다 → 정상 종료.
  process.exit(0)
}

main().catch((err) => {
  console.error('[capture-history] 실패:', err)
  process.exit(1)
})
