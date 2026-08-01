-- Titans · 유저 환경설정 동기화 테이블
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 실행.
--
-- 설계: 유저당 1행. RLS로 본인 행만 read/write.
--   · 로그인 시 앱이 이 행을 읽어 로컬(@AppStorage)에 반영(원격 우선)
--   · 계정에 행이 없으면 앱이 현재 로컬 값으로 INSERT(첫 기기 seed)
--   · 설정 변경 시 앱이 UPSERT(on conflict user_id)
--   · watchlist 는 관심종목 기능 도입 대비 예약 컬럼(현재 미사용)

create table if not exists public.user_prefs (
  user_id               uuid        primary key references auth.users(id) on delete cascade,
  is_dark_mode          boolean     not null default false,
  notifications_enabled boolean     not null default false,
  watchlist             jsonb       not null default '[]'::jsonb,
  updated_at            timestamptz not null default now()
);

-- 행 수준 보안: 로그인한 본인만 자신의 행에 접근.
alter table public.user_prefs enable row level security;

drop policy if exists "user_prefs owner select" on public.user_prefs;
create policy "user_prefs owner select" on public.user_prefs
  for select using (auth.uid() = user_id);

drop policy if exists "user_prefs owner insert" on public.user_prefs;
create policy "user_prefs owner insert" on public.user_prefs
  for insert with check (auth.uid() = user_id);

drop policy if exists "user_prefs owner update" on public.user_prefs;
create policy "user_prefs owner update" on public.user_prefs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 계정 삭제(auth.users 삭제) 시 on delete cascade 로 자동 정리되므로 별도 delete 정책 불필요.
