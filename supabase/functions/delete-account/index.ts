// Supabase Edge Function: delete-account
//
// 계정 영구 삭제. 앱은 admin 권한이 없으므로, 이 함수가 호출자의 JWT로 신원을 확인한 뒤
// service_role 로 해당 유저를 삭제한다. user_prefs 등은 auth.users 삭제 시
// FK(on delete cascade)로 함께 제거된다.
//
// 배포: Supabase 대시보드 → Edge Functions → 새 함수 'delete-account' 로 이 코드 배포.
//       SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY 는 런타임에
//       자동 주입되므로 별도 시크릿 설정이 필요 없다.
//
// ⚠️ service_role 키는 이 서버 함수 안에서만 쓰인다(앱에는 절대 넣지 않음).

import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  // 프리플라이트(브라우저 대비, 앱 호출엔 무해).
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return json({ error: 'missing authorization' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // 1) 호출자 신원 확인 — 전달된 유저 JWT로 본인 확인.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser()

  if (userErr || !user) {
    return json({ error: 'invalid or expired session' }, 401)
  }

  // 2) service_role 로 유저 삭제(관련 데이터는 FK cascade 로 함께 삭제).
  const admin = createClient(supabaseUrl, serviceKey)
  const { error: delErr } = await admin.auth.admin.deleteUser(user.id)
  if (delErr) {
    return json({ error: delErr.message }, 500)
  }

  return json({ ok: true }, 200)
})

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
