-- Leave entitlement per employee per year. taken_days is maintained by
-- trigger when a leave request is approved; pending days are derived, not
-- stored, so a cancelled request needs no compensating write.

create table public.leave_balances (
  id                bigint generated always as identity primary key,
  employee_id       uuid not null references public.profiles (id) on delete cascade,
  year              smallint not null check (year between 2000 and 2100),
  entitled_days     numeric(5,1) not null default 25 check (entitled_days >= 0),
  carried_over_days numeric(5,1) not null default 0  check (carried_over_days >= 0),
  taken_days        numeric(5,1) not null default 0  check (taken_days >= 0),
  unique (employee_id, year)
);

-- security_invoker: the view is evaluated with the caller's rights, so RLS on
-- leave_balances and requests still applies through it.
create view public.leave_balance_summary
with (security_invoker = true) as
select
  b.employee_id,
  b.year,
  b.entitled_days,
  b.carried_over_days,
  b.taken_days,
  coalesce(p.pending_days, 0) as pending_days,
  b.entitled_days + b.carried_over_days - b.taken_days - coalesce(p.pending_days, 0)
    as available_days
from public.leave_balances b
left join lateral (
  select sum(r.value) as pending_days
  from public.requests r
  join public.request_types t on t.code = r.request_type
  where r.requester_id = b.employee_id
    and t.affects_leave_balance
    and r.status = 'pending'
    and extract(year from r.start_date) = b.year
) p on true;

-- Known limitation: leave spanning 31 December is attributed entirely to the
-- year of start_date.
create function public.apply_leave_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_affects boolean;
begin
  if new.status <> 'approved' or old.status = 'approved' then
    return new;
  end if;

  select affects_leave_balance into v_affects
  from public.request_types where code = new.request_type;

  if not coalesce(v_affects, false) or new.value is null then
    return new;
  end if;

  insert into public.leave_balances (employee_id, year, taken_days)
  values (new.requester_id, extract(year from new.start_date)::smallint, new.value)
  on conflict (employee_id, year) do update
    set taken_days = public.leave_balances.taken_days + excluded.taken_days;

  return new;
end;
$$;

create trigger requests_apply_leave_balance
  after update on public.requests
  for each row execute function public.apply_leave_balance();

alter table public.leave_balances enable row level security;

create policy leave_balances_select_own
  on public.leave_balances for select to authenticated
  using ((select auth.uid()) = employee_id);