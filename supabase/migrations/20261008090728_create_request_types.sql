-- Request catalogue and approval routing. Both are business configuration:
-- versioned here rather than seeded, so a threshold change is a reviewable
-- migration.

create table public.request_types (
  code                  text primary key,
  label                 text not null,
  value_unit            text not null check (value_unit in ('days', 'eur')),
  requires_dates        boolean not null default false,
  affects_leave_balance boolean not null default false,
  is_active             boolean not null default true
);

-- One row per (type, threshold band). approver_chain is ordered: the request
-- visits each role in turn.
create table public.routing_rules (
  id             bigint generated always as identity primary key,
  request_type   text not null references public.request_types (code) on delete cascade,
  max_value      numeric,
  approver_chain user_role[] not null check (cardinality(approver_chain) > 0),
  unique nulls not distinct (request_type, max_value)
);

-- Lowest band whose ceiling covers the value; the open-ended band last.
create function public.resolve_approver_chain(p_request_type text, p_value numeric)
returns user_role[]
language sql
stable
set search_path = ''
as $$
  select approver_chain
  from public.routing_rules
  where request_type = p_request_type
    and (max_value is null or coalesce(p_value, 0) <= max_value)
  order by max_value asc nulls last
  limit 1;
$$;

insert into public.request_types
  (code, label, value_unit, requires_dates, affects_leave_balance) values
  ('conges',     'Congés',       'days', true,  true),
  ('teletravail','Télétravail',  'days', true,  false),
  ('materiel',   'Matériel',     'eur',  false, false),
  ('formation',  'Formation',    'eur',  true,  false);

insert into public.routing_rules (request_type, max_value, approver_chain) values
  ('conges',         5, array['manager']::user_role[]),
  ('conges',        15, array['manager','rh']::user_role[]),
  ('conges',      null, array['manager','rh','drh']::user_role[]),
  ('teletravail',    5, array['manager']::user_role[]),
  ('teletravail', null, array['manager','rh']::user_role[]),
  ('materiel',     500, array['manager']::user_role[]),
  ('materiel',    2000, array['manager','rh']::user_role[]),
  ('materiel',    null, array['manager','rh','drh']::user_role[]),
  ('formation',   1000, array['manager','rh']::user_role[]),
  ('formation',   null, array['manager','rh','drh']::user_role[]);

alter table public.request_types enable row level security;
alter table public.routing_rules enable row level security;

create policy request_types_select_authenticated
  on public.request_types for select to authenticated using (true);

create policy routing_rules_select_authenticated
  on public.routing_rules for select to authenticated using (true);