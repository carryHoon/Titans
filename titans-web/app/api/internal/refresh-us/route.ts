import { NextResponse } from 'next/server'
import { refreshUsStats } from '@/lib/us-stats'

export const runtime        = 'nodejs'
export const dynamic        = 'force-dynamic'
export const maxDuration    = 120  // stagger fetch(3개/4초 × ~20그룹 ≈ 80s) 여유

// US 시총 기준값(stats) 스냅샷 갱신 트리거(내부용, 로컬·수동 편의).
// ⚠️ 프로덕션 정기 갱신은 이 라우트가 아니라 GitHub Actions(.github/workflows/refresh-us.yml)가
//    러너에서 scripts/refresh-us-stats.ts 를 직접 실행해 Upstash에 write 한다. 전체 갱신은
//    ~6분이 걸려 Vercel Hobby 함수 시간(~60s)을 넘기므로, 이 라우트로는 prod에서 완주 못 한다.
//    로컬(next dev)에선 시간 제한이 없어 이 라우트로 수동 갱신할 수 있다.
//
// 보호: REFRESH_SECRET 또는 CRON_SECRET 과 일치해야만 실행. 헤더(x-refresh-secret)·쿼리(?secret=)·
//    Authorization: Bearer 중 하나로 전달. 응답: { ok, updated, failed }.
export async function GET(req: Request) {
  return handle(req)
}

// 부수효과가 있는 트리거라 POST 도 지원(스케줄러 관례).
export async function POST(req: Request) {
  return handle(req)
}

async function handle(req: Request): Promise<Response> {
  // REFRESH_SECRET(수동·GitHub Actions) 또는 CRON_SECRET(Vercel Cron이 자동 주입) 중
  // 하나만 일치하면 통과. 둘 다 미설정이면 설정 오류(500).
  const refreshSecret = process.env.REFRESH_SECRET
  const cronSecret    = process.env.CRON_SECRET
  if (!refreshSecret && !cronSecret) {
    return NextResponse.json({ ok: false, error: 'REFRESH_SECRET/CRON_SECRET 미설정' }, { status: 500 })
  }

  const url      = new URL(req.url)
  const bearer   = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  const provided = req.headers.get('x-refresh-secret') ?? url.searchParams.get('secret') ?? bearer
  const ok = (!!refreshSecret && provided === refreshSecret) || (!!cronSecret && provided === cronSecret)
  if (!ok) {
    return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 })
  }

  try {
    const { updated, failed } = await refreshUsStats()
    return NextResponse.json({ ok: true, updated, failed })
  } catch (err) {
    console.error('[refresh-us] failed:', err)
    return NextResponse.json({ ok: false, error: String(err) }, { status: 500 })
  }
}
