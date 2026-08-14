import { NextResponse } from 'next/server'
import { refreshDeStats } from '@/lib/de-snapshot'

export const runtime        = 'nodejs'
export const dynamic        = 'force-dynamic'
export const maxDuration    = 300  // Vercel 상한. gap 6s면 39종목 ≈ 4분이라 이 라우트(서버리스)는 완주
                                   // 가능하나, 프로덕션 갱신은 GH Actions(무제한)로 돌린다. 이 라우트는 로컬/수동 편의용.

// 독일 FWB 시총 스냅샷 갱신 트리거(내부용, 로컬·수동 편의).
// ⚠️ 프로덕션 정기 갱신은 GitHub Actions(.github/workflows/refresh-de.yml)가 러너에서
//    scripts/refresh-de-stats.ts 를 직접 실행해 Upstash에 write 한다(refresh-us/jpx/eu 와 동일 이유).
//
// 보호: REFRESH_SECRET 또는 CRON_SECRET 과 일치해야만 실행.
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
    const { updated, failed } = await refreshDeStats()
    return NextResponse.json({ ok: true, updated, failed })
  } catch (err) {
    console.error('[refresh-de] failed:', err)
    return NextResponse.json({ ok: false, error: String(err) }, { status: 500 })
  }
}
