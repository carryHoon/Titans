import { NextResponse } from 'next/server'
import { refreshJpxStats } from '@/lib/jpx-snapshot'

export const runtime        = 'nodejs'
export const dynamic        = 'force-dynamic'
export const maxDuration    = 300  // 106종목 × 2.5s ≈ 4.4분 (+ 재시도 여유)

// JPX 시총 스냅샷 갱신 트리거(내부용, 로컬·수동 편의).
// ⚠️ 프로덕션 정기 갱신은 GitHub Actions(.github/workflows/refresh-jpx.yml)가 러너에서
//    scripts/refresh-jpx-stats.ts 를 직접 실행해 Upstash에 write 한다(refresh-us 와 동일 이유:
//    Vercel Hobby 함수 시간 제약). 로컬(next dev)에선 이 라우트로 수동 갱신할 수 있다.
//
// 보호: REFRESH_SECRET 또는 CRON_SECRET 과 일치해야만 실행. 헤더(x-refresh-secret)·쿼리(?secret=)·
//    Authorization: Bearer 중 하나로 전달. 응답: { ok, updated, failed }.
export async function GET(req: Request) {
  return handle(req)
}

export async function POST(req: Request) {
  return handle(req)
}

async function handle(req: Request): Promise<Response> {
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
    const { updated, failed } = await refreshJpxStats()
    return NextResponse.json({ ok: true, updated, failed })
  } catch (err) {
    console.error('[refresh-jpx] failed:', err)
    return NextResponse.json({ ok: false, error: String(err) }, { status: 500 })
  }
}
