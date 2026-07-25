import { NextResponse } from 'next/server'
import { refreshIfNew } from '@/lib/kr-snapshot'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// 코스피/코스닥 스냅샷 갱신 트리거(내부용). 서버리스(Vercel)에선 in-process 폴러가 못 도므로
// 외부 스케줄러(GitHub Actions 크론)가 이 라우트를 주기적으로 때려 새 영업일이면 스냅샷을 굳힌다.
//
// 보호: REFRESH_SECRET 과 일치해야만 실행. 시크릿은 헤더(x-refresh-secret) 또는 쿼리(?secret=)로.
//   · 헤더 방식 권장(URL 로그에 안 남음). GitHub Actions가 헤더로 보낸다.
// 응답: { ok, updated } — updated=true면 새 영업일을 받아 스냅샷을 새로 저장했다는 뜻.
export async function GET(req: Request) {
  return handle(req)
}

// GitHub Actions는 POST로 호출한다(부수효과가 있는 트리거라 POST가 관례적으로 맞다).
export async function POST(req: Request) {
  return handle(req)
}

async function handle(req: Request): Promise<Response> {
  const expected = process.env.REFRESH_SECRET
  if (!expected) {
    return NextResponse.json({ ok: false, error: 'REFRESH_SECRET 미설정' }, { status: 500 })
  }

  const url = new URL(req.url)
  const provided = req.headers.get('x-refresh-secret') ?? url.searchParams.get('secret')
  if (provided !== expected) {
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
