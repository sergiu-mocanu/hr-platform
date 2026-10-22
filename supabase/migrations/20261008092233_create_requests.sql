-- The request itself. approver_chain is snapshotted at insert so that changes
-- to routing_rules never alter the path of an in-flight request.

create type request_status as enum ('pending', 'approved', 'rejected', 'cancelled');

create table public.requests (
  id             uuid primary key default gen_random_uuid(),
  requester_id   uuid not null references public.profiles (id) on delete cascade,
  request_type   text not null references public.request_types (code),
  status         request_status not null default 'pending',
  value          numeric check (value is null or value > 0),
  start_date     date,
  end_date       date,
  details        text,
  approver_chain user_role[] not null,
  current_step   smallint not null default 0,
  submitted_at   timestamptz not null default now(),
  decided_at     timestamptz,
  constraint requests_dates_ordered check (end_date is null or start_date <= end_date),
  constraint requests_decided_at_consistent check (
    (status = 'pending') = (decided_at is null)
  )
);

create index requests_requester_idx on public.requests (requester_id);
create index requests_status_idx    on public.requests (status);
create index requests_submitted_idx on public.requests (submitted_at);

-- Validates against the type catalogue and resolves the approval chain.
-- Runs as the invoker: request_types and routing_rules are readable by any
-- authenticated user, so no elevated rights are needed.
create function public.set_request_routing()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_type  public.request_types;
  v_chain public.user_role[];
begin
  select * into v_type
  from public.request_types
  where code = new.request_type and is_active;

  if not found then
    raise exception 'Unknown or inactive request type: %', new.request_type;
  end if;

  if v_type.requires_dates and (new.start_date is null or new.end_date is null) then
    raise exception 'Request type % requires start_date and end_date', new.request_type;
  end if;

  v_chain := public.resolve_approver_chain(new.request_type, new.value);

  if v_chain is null then
    raise exception 'No routing rule matches type % with value %',
      new.request_type, new.value;
  end if;

  new.approver_chain := v_chain;
  new.current_step   := 0;
  new.status         := 'pending';
  new.decided_at     := null;
  return new;
end;
$$;

create trigger requests_set_routing
  before insert on public.requests
  for each row execute function public.set_request_routing();

alter table public.requests enable row level security;

create policy requests_select_own
  on public.requests for select to authenticated
  using ((select auth.uid()) = requester_id);

create policy requests_insert_own
  on public.requests for insert to authenticated
  with check ((select auth.uid()) = requester_id);

create policy requests_cancel_own
  on public.requests for update to authenticated
  using ((select auth.uid()) = requester_id and status = 'pending')
  with check (status in ('pending', 'cancelled'));