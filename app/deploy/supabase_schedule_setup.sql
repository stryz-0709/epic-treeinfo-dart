-- Supabase schedule persistence + audit trail for EarthRanger mobile schedule APIs
-- Run after app/deploy/supabase_auth_setup.sql.

create extension if not exists "pgcrypto";

create table if not exists public.schedules (
  schedule_id uuid primary key default gen_random_uuid(),
  work_date date not null,
  username text not null references public.app_users(username) on update cascade on delete restrict,
  display_name text not null,
  region text,
  role text not null check (role in ('admin', 'leader', 'ranger', 'viewer')),
  note text not null default '',
  created_by_username text not null references public.app_users(username) on update cascade on delete restrict,
  created_by_display_name text not null,
  updated_by_username text not null references public.app_users(username) on update cascade on delete restrict,
  updated_by_display_name text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz
);

-- Backward-compatible migration path from previous draft schema
-- (ranger_* column names + shift_label).
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'ranger_username'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'username'
  ) then
    alter table public.schedules rename column ranger_username to username;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'ranger_display_name'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'display_name'
  ) then
    alter table public.schedules rename column ranger_display_name to display_name;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'ranger_region'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'region'
  ) then
    alter table public.schedules rename column ranger_region to region;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'ranger_role'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'role'
  ) then
    alter table public.schedules rename column ranger_role to role;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedules'
      and column_name = 'shift_label'
  ) then
    alter table public.schedules drop column shift_label;
  end if;
end
$$;

comment on table public.schedules is 'Workshift assignments persisted for monitoring and mobile schedule APIs.';
comment on column public.schedules.username is 'Canonical stable identity key used for sorting/filtering.';
comment on column public.schedules.display_name is 'Display-name snapshot at assignment time.';
comment on column public.schedules.region is 'Region snapshot at assignment time.';
comment on column public.schedules.role is 'Role snapshot at assignment time.';

-- Canonical identity remediation + strict-readiness safety checks.
-- Guard against normalization collisions before any canonical rewrite.
do $$
declare
  v_app_users_collision_count integer := 0;
  v_schedule_collision_count integer := 0;
begin
  select count(*) into v_app_users_collision_count
  from (
    select lower(trim(username)) as canonical_username
    from public.app_users
    group by lower(trim(username))
    having count(*) > 1
  ) app_user_collisions;

  if v_app_users_collision_count > 0 then
    raise exception
      'Canonical username collision(s) detected in public.app_users (%). Resolve collisions before enabling strict schedule readiness.',
      v_app_users_collision_count
      using errcode = '23505';
  end if;

  update public.app_users
  set username = lower(trim(username))
  where username <> lower(trim(username));

  update public.schedules
  set
    username = lower(trim(username)),
    created_by_username = lower(trim(created_by_username)),
    updated_by_username = lower(trim(updated_by_username))
  where
    username <> lower(trim(username))
    or created_by_username <> lower(trim(created_by_username))
    or updated_by_username <> lower(trim(updated_by_username));

  select count(*) into v_schedule_collision_count
  from (
    select work_date, lower(trim(username)) as canonical_username
    from public.schedules
    where deleted_at is null
    group by work_date, lower(trim(username))
    having count(*) > 1
  ) schedule_collisions;

  if v_schedule_collision_count > 0 then
    raise exception
      'Duplicate-active canonical schedule collision(s) detected (%). Remediate before enabling strict schedule readiness.',
      v_schedule_collision_count
      using errcode = '23505';
  end if;
end
$$;

alter table public.schedules
  drop constraint if exists chk_schedules_username_canonical;
alter table public.schedules
  add constraint chk_schedules_username_canonical
  check (username = lower(trim(username)));

alter table public.schedules
  drop constraint if exists chk_schedules_created_by_username_canonical;
alter table public.schedules
  add constraint chk_schedules_created_by_username_canonical
  check (created_by_username = lower(trim(created_by_username)));

alter table public.schedules
  drop constraint if exists chk_schedules_updated_by_username_canonical;
alter table public.schedules
  add constraint chk_schedules_updated_by_username_canonical
  check (updated_by_username = lower(trim(updated_by_username)));

create or replace view public.schedules_with_user_profile as
select
  s.schedule_id,
  s.work_date,
  s.username,
  s.display_name as display_name_snapshot,
  u.display_name as display_name_current,
  s.region as region_snapshot,
  u.region as region_current,
  s.role as role_snapshot,
  u.role as role_current,
  s.note,
  s.created_by_username,
  s.created_by_display_name,
  s.updated_by_username,
  s.updated_by_display_name,
  s.created_at,
  s.updated_at,
  s.deleted_at
from public.schedules s
left join public.app_users u
  on u.username = s.username;

comment on view public.schedules_with_user_profile is
  'Schedule rows with both snapshot fields and current app_users profile values (region/role/display_name).';

drop index if exists public.uq_schedules_active_assignment;
create unique index uq_schedules_active_assignment
  on public.schedules(work_date, username)
  where deleted_at is null;

-- Pre-cutover audit queries (must return 0 rows for go-live):
-- 1) Non-canonical app_users usernames
-- select username
-- from public.app_users
-- where username <> lower(trim(username));
--
-- 2) Non-canonical active schedules usernames
-- select schedule_id, username
-- from public.schedules
-- where deleted_at is null
--   and username <> lower(trim(username));
--
-- 3) Duplicate-active normalized identity collisions
-- select work_date, lower(trim(username)) as canonical_username, count(*) as active_rows
-- from public.schedules
-- where deleted_at is null
-- group by work_date, lower(trim(username))
-- having count(*) > 1;

drop index if exists public.idx_schedules_work_date_username;
create index idx_schedules_work_date_username
  on public.schedules(work_date, username);

drop index if exists public.idx_schedules_username_work_date;
create index idx_schedules_username_work_date
  on public.schedules(username, work_date);

create index if not exists idx_schedules_updated_at
  on public.schedules(updated_at desc);

create or replace function public.sync_schedule_user_profile_from_app_users()
returns trigger
language plpgsql
as $$
declare
  v_user record;
begin
  select
    u.username,
    u.display_name,
    u.region,
    u.role
  into v_user
  from public.app_users u
  where u.username = new.username;

  if v_user.username is null then
    raise exception 'Unknown app_users.username for schedules row: %', new.username
      using errcode = '23503';
  end if;

  new.display_name := v_user.display_name;
  new.region := v_user.region;
  new.role := v_user.role;
  return new;
end;
$$;

drop trigger if exists trg_sync_schedule_user_profile on public.schedules;
create trigger trg_sync_schedule_user_profile
before insert or update of username on public.schedules
for each row
execute function public.sync_schedule_user_profile_from_app_users();

create or replace function public.set_schedules_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_set_schedules_updated_at on public.schedules;
create trigger trg_set_schedules_updated_at
before update on public.schedules
for each row
execute function public.set_schedules_updated_at();

create table if not exists public.schedule_action_logs (
  log_id bigint generated always as identity primary key,
  schedule_id uuid not null,
  action_type text not null check (action_type in ('create', 'update', 'delete')),
  actor_username text not null,
  actor_display_name text not null,
  action_timestamp timestamptz not null default timezone('utc', now()),
  request_id text,
  before_data jsonb,
  after_data jsonb
);

comment on table public.schedule_action_logs is 'Immutable audit history for schedule create/update/delete operations.';
comment on column public.schedule_action_logs.before_data is 'Row snapshot before change.';
comment on column public.schedule_action_logs.after_data is 'Row snapshot after change.';

create index if not exists idx_schedule_action_logs_schedule_ts
  on public.schedule_action_logs(schedule_id, action_timestamp desc);

create index if not exists idx_schedule_action_logs_actor_ts
  on public.schedule_action_logs(actor_username, action_timestamp desc);

create or replace function public.log_schedule_action()
returns trigger
language plpgsql
as $$
declare
  v_actor_username text;
  v_actor_display_name text;
begin
  if tg_op = 'INSERT' then
    v_actor_username := coalesce(new.created_by_username, new.updated_by_username, 'unknown');
    v_actor_display_name := coalesce(new.created_by_display_name, new.updated_by_display_name, v_actor_username);

    insert into public.schedule_action_logs(
      schedule_id,
      action_type,
      actor_username,
      actor_display_name,
      action_timestamp,
      before_data,
      after_data
    )
    values (
      new.schedule_id,
      'create',
      v_actor_username,
      v_actor_display_name,
      timezone('utc', now()),
      null,
      to_jsonb(new)
    );

    return new;
  elseif tg_op = 'UPDATE' then
    v_actor_username := coalesce(new.updated_by_username, old.updated_by_username, old.created_by_username, 'unknown');
    v_actor_display_name := coalesce(new.updated_by_display_name, old.updated_by_display_name, old.created_by_display_name, v_actor_username);

    insert into public.schedule_action_logs(
      schedule_id,
      action_type,
      actor_username,
      actor_display_name,
      action_timestamp,
      before_data,
      after_data
    )
    values (
      new.schedule_id,
      'update',
      v_actor_username,
      v_actor_display_name,
      timezone('utc', now()),
      to_jsonb(old),
      to_jsonb(new)
    );

    return new;
  else
    v_actor_username := coalesce(old.updated_by_username, old.created_by_username, 'unknown');
    v_actor_display_name := coalesce(old.updated_by_display_name, old.created_by_display_name, v_actor_username);

    insert into public.schedule_action_logs(
      schedule_id,
      action_type,
      actor_username,
      actor_display_name,
      action_timestamp,
      before_data,
      after_data
    )
    values (
      old.schedule_id,
      'delete',
      v_actor_username,
      v_actor_display_name,
      timezone('utc', now()),
      to_jsonb(old),
      null
    );

    return old;
  end if;
end;
$$;

drop trigger if exists trg_log_schedule_action on public.schedules;
create trigger trg_log_schedule_action
after insert or update or delete on public.schedules
for each row
execute function public.log_schedule_action();

alter table public.schedules enable row level security;
alter table public.schedule_action_logs enable row level security;

drop policy if exists "deny direct schedules access" on public.schedules;
create policy "deny direct schedules access"
  on public.schedules
  for all
  to anon, authenticated
  using (false)
  with check (false);

drop policy if exists "deny direct schedule logs access" on public.schedule_action_logs;
create policy "deny direct schedule logs access"
  on public.schedule_action_logs
  for all
  to anon, authenticated
  using (false)
  with check (false);
