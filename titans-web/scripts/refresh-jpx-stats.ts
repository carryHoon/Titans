// JPX 시총 스냅샷 갱신 스크립트 — GitHub Actions 스케줄러가 실행한다.
//
// TD가 JPX 가격 피드를 안 줘 시총 기준값(/statistics)만 하루 1회 받아 Upstash에 굳힌다
// (유저 경로는 스냅샷 read만). lib/jpx-snapshot 의 refreshJpxStats()를 그대로 재사용한다
// (페이싱·재시도·prev 롤링·Upstash 저장 공유).
//
// 필요 env (GitHub Secrets → workflow env):
//   TWELVE_DATA_API_KEY, UPSTASH_REDIS_REST_URL, UPSTASH_REDIS_REST_TOKEN
//
// 로컬 실행: npx tsx --env-file=.env.local scripts/refresh-jpx-stats.ts

import { refreshJpxStats } from '../lib/jpx-snapshot'

async function main() {
  if (!process.env.TWELVE_DATA_API_KEY) throw new Error('TWELVE_DATA_API_KEY 미설정')
  if (!process.env.UPSTASH_REDIS_REST_URL || !process.env.UPSTASH_REDIS_REST_TOKEN) {
    throw new Error('UPSTASH_REDIS_REST_URL/TOKEN 미설정 — 스냅샷을 Upstash에 저장할 수 없음')
  }

  const started = Date.now()
  const { updated, failed } = await refreshJpxStats()
  const secs = ((Date.now() - started) / 1000).toFixed(0)
  console.log(`[refresh-jpx-stats] 완료 (${secs}s): ${updated} updated, ${failed} failed`)

  // 일부 실패는 직전값 유지로 서비스에 영향 없음(비정상 종료 아님). 로그로만 남긴다.
  process.exit(0)
}

main().catch((err) => {
  console.error('[refresh-jpx-stats] 실패:', err)
  process.exit(1)
})
