// US 시총 기준값(stats) 스냅샷 갱신 스크립트 — GitHub Actions 스케줄러가 실행한다.
//
// Vercel Hobby의 함수 실행시간(~60s)·크론(1회/일) 제약 때문에 서버리스 함수로는 전체 갱신
// (~58종목 × 50 credits, 6초당 1콜 ≈ 6분)을 완주할 수 없다. 그래서 GitHub Actions 러너에서
// 이 스크립트가 직접 Twelve Data를 페칭해 Upstash에 write 한다(Vercel 함수 미경유).
//
// 필요 env (GitHub Secrets → workflow env):
//   TWELVE_DATA_API_KEY, UPSTASH_REDIS_REST_URL, UPSTASH_REDIS_REST_TOKEN
// lib/us-stats 의 refreshUsStats()를 그대로 재사용한다(페이싱·재시도·SAR·Upstash 저장 공유).
//
// 로컬 실행: npx tsx --env-file=.env.local scripts/refresh-us-stats.ts

import { refreshUsStats } from '../lib/us-stats'

async function main() {
  if (!process.env.TWELVE_DATA_API_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (!process.env.UPSTASH_REDIS_REST_URL || !process.env.UPSTASH_REDIS_REST_TOKEN) {
    throw new Error('UPSTASH_REDIS_REST_URL/TOKEN 미설정 — 스냅샷을 Upstash에 저장할 수 없음')
  }

  const started = Date.now()
  const { updated, failed } = await refreshUsStats()
  const secs = ((Date.now() - started) / 1000).toFixed(0)
  console.log(`[refresh-us-stats] 완료 (${secs}s): ${updated} updated, ${failed} failed`)

  // 일부 실패는 직전값 유지로 서비스에 영향 없음(비정상 종료 아님). 로그로만 남긴다.
  process.exit(0)
}

main().catch((err) => {
  console.error('[refresh-us-stats] 실패:', err)
  process.exit(1)
})
