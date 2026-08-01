import { NextResponse } from 'next/server'
import { refreshIfNew } from '@/lib/kr-snapshot'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 코스피/코스닥 스냅샷 갱신 트리거(내부용). 서버리스(Vercel)에선 in-process 폴러가 못 도므로
// 외부 스케줄러가 이 라우트를 주기적으로 때려 새 영업일이면 스냅샷을 굳힌다.
//   · 주(primary): Vercel Cron(vercel.json) — Authorization: Bearer $CRON_SECRET 을 자동 주입.
//   · 백업(backup): GitHub Actions(.github/workflows/refresh-kr.yml) — x-refresh-secret 헤더.
//   둘 다 같은 발행 창(영업일 오후)으로 돌지만 refreshIfNew()가 멱등(평소 프로브 1콜)이라 겹쳐도 무해.
//
// 보호: REFRESH_SECRET(수동·GitHub Actions) 또는 CRON_SECRET(Vercel Cron) 중 하나만 일치하면 통과.
//   시크릿은 헤더(x-refresh-secret)·쿼리(?secret=)·Authorization: Bearer 중 하나로 전달.
// 응답: { ok, updated } — updated=true면 새 영업일을 받아 스냅샷을 새로 저장했다는 뜻.
export async function GET(req: Request) {
  return handle(req)
}

// GitHub Actions는 POST로 호출한다(부수효과가 있는 트리거라 POST가 관례적으로 맞다).
export async function POST(req: Request) {
  return handle(req)
}

async function handle(req: Request): Promise<Response> {
  // REFRESH_SECRET(수동·GitHub Actions 백업) 또는 CRON_SECRET(Vercel Cron이 자동 주입하는
  // Authorization: Bearer) 중 하나만 일치하면 통과. 둘 다 미설정이면 설정 오류(500).
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
    const updated = await refreshIfNew()
    return NextResponse.json({ ok: true, updated })
  } catch (err) {
    console.error('[refresh-kr] failed:', err)
    return NextResponse.json({ ok: false, error: String(err) }, { status: 500 })
  }
}
