-- Supabase auth storage for EarthRanger backend-managed login
-- Run this script in Supabase SQL Editor before enabling Supabase-backed login/account management.

create table if not exists public.app_users (
  username text primary key,
  password_hash text not null,
  role text not null check (role in ('admin', 'leader', 'ranger', 'viewer')),
  display_name text not null,
  region text,
  team text,
  position text,
  phone text,
  status text not null default 'active' check (status in ('active', 'pending', 'rejected')),
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

-- Migration: add status and avatar_url to existing tables
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'app_users' AND column_name = 'sub_region'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'app_users' AND column_name = 'team'
  ) THEN
    ALTER TABLE public.app_users RENAME COLUMN sub_region TO team;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'app_users' AND column_name = 'team'
  ) THEN
    ALTER TABLE public.app_users ADD COLUMN team text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'app_users' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.app_users
      ADD COLUMN status text NOT NULL DEFAULT 'active'
      CHECK (status IN ('active', 'pending', 'rejected'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'app_users' AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE public.app_users ADD COLUMN avatar_url text;
  END IF;
END $$;

create index if not exists idx_app_users_role on public.app_users(role);
create index if not exists idx_app_users_region_team on public.app_users(region, team);

create or replace function public.set_app_users_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_set_app_users_updated_at on public.app_users;
create trigger trg_set_app_users_updated_at
before update on public.app_users
for each row
execute function public.set_app_users_updated_at();

-- Optional hardening for direct table access:
alter table public.app_users enable row level security;

-- Example policy for service-role/backend usage only.
-- Service-role bypasses RLS by design; this blocks anon/authenticated clients.
drop policy if exists "deny direct app_users access" on public.app_users;
create policy "deny direct app_users access"
  on public.app_users
  for all
  to anon, authenticated
  using (false)
  with check (false);
