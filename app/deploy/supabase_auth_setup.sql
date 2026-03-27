-- Supabase auth storage for EarthRanger backend-managed login
-- Run this script in Supabase SQL Editor before enabling Supabase-backed login/account management.

create table if not exists public.app_users (
  username text primary key,
  password_hash text not null,
  role text not null check (role in ('admin', 'leader', 'ranger', 'viewer')),
  display_name text not null,
  region text,
  position text,
  phone text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_app_users_role on public.app_users(role);

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
