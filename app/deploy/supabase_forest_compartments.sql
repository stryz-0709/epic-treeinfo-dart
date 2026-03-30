-- Forest compartment management table
-- Run in Supabase SQL Editor to persist compartment data.

create table if not exists public.forest_compartments (
  id text primary key,
  name text not null,
  region text,
  area_ha numeric(10,2),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_forest_compartments_region on public.forest_compartments(region);

create or replace function public.set_forest_compartments_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_set_forest_compartments_updated_at on public.forest_compartments;
create trigger trg_set_forest_compartments_updated_at
before update on public.forest_compartments
for each row
execute function public.set_forest_compartments_updated_at();

alter table public.forest_compartments enable row level security;

drop policy if exists "deny direct forest_compartments access" on public.forest_compartments;
create policy "deny direct forest_compartments access"
  on public.forest_compartments
  for all
  to anon, authenticated
  using (false)
  with check (false);

-- Seed sample compartments
insert into public.forest_compartments (id, name, region, area_ha, notes)
values
  ('fc-001', 'Tiểu khu 1 - Khu bảo tồn Bắc', 'Bắc', 120.5, 'Rừng phòng hộ đầu nguồn'),
  ('fc-002', 'Tiểu khu 2 - Khu rừng trồng', 'Bắc', 85.0, 'Rừng trồng keo và bạch đàn'),
  ('fc-003', 'Tiểu khu 3 - Khu sinh thái Nam', 'Nam', 200.0, 'Khu vực đa dạng sinh học cao'),
  ('fc-004', 'Tiểu khu 4 - Đồi phía Tây', 'Tây', 95.3, 'Khu vực dễ bị sạt lở'),
  ('fc-005', 'Tiểu khu 5 - Ven sông Đông', 'Đông', 150.0, 'Rừng ngập mặn ven sông')
on conflict (id) do nothing;
