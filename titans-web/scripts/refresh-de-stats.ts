// 독일 FWB 시총 스냅샷 갱신 스크립트 — GitHub Actions 스케줄러가 실행한다.
// lib/de-snapshot 의 refreshDeStats()를 재사용(페이싱·재시도·prev 롤링·Upstash 저장 공유).
//
// 필요 env (GitHub Secrets → workflow env):
//   TWELVE_DATA_API_KEY, UPSTASH_REDIS_REST_URL, UPSTASH_REDIS_REST_TOKEN
//
// 로컬 실행: npx tsx --env-file=.env.local scripts/refresh-de-stats.ts

import { refreshDeStats } from '../lib/de-snapshot'

async function main() {
  if (!process.env.TWELVE_DATA_API_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (!process.env.UPSTASH_REDIS_REST_URL || !process.env.UPSTASH_REDIS_REST_TOKEN) {
    throw new Error('UPSTASH_REDIS_REST_URL/TOKEN 미설정 — 스냅샷을 Upstash에 저장할 수 없음')
  }

  const started = Date.now()
  const { updated, failed } = await refreshDeStats()
  const secs = ((Date.now() - started) / 1000).toFixed(0)
  console.log(`[refresh-de-stats] 완료 (${secs}s): ${updated} updated, ${failed} failed`)
  process.exit(0)
}

main().catch((err) => {
  console.error('[refresh-de-stats] 실패:', err)
  process.exit(1)
})
