-- Current position of a request in its approval chain. One row per step,
-- created as the request reaches it.
--
-- Steps are 1-based to match Postgres array indexing: step N is
-- approver_chain[N]. Migration 3 defaulted current_step to 0; corrected here.

alter table public.requests alter column current_step set default 1;
update public.requests set current_step = 1 where current_step = 0;

alter table public.requests add constraint requests_step_within_chain
  check (current_step between 1 and cardinality(approver_chain));

create or replace function public.set_request_routing()
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
  new.current_step   := 1;
  new.status         := 'pending';
  new.decided_at     := null;
  return new;
end;
$$;

create type approval_decision as enum ('approved', 'rejected');

create table public.approvals (
  id            bigint generated always as identity primary key,
  request_id    uuid not null references public.requests (id) on delete cascade,
  step          smallint not null check (step >= 1),
  approver_role user_role not null,
  approver_id   uuid references public.profiles (id) on delete set null,
  decision      approval_decision,
  comment       text,
  assigned_at   timestamptz not null default now(),
  decided_at    timestamptz,
  unique (request_id, step),
  constraint approvals_decision_consistent check ((decision is null) = (decided_at is null)),
  constraint approvals_decided_has_approver check (decision is null or approver_id is not null)
);

create index approvals_pending_idx
  on public.approvals (approver_role, assigned_at)
  where decision is null;

-- The first step is opened as soon as the request exists; later steps are
-- opened by record_approval() as the chain advances.
create function public.open_first_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.approvals (request_id, step, approver_role)
  values (new.id, 1, new.approver_chain[1]);
  return new;
end;
$$;

create trigger requests_open_first_approval
  after insert on public.requests
  for each row execute function public.open_first_approval();

alter table public.approvals enable row level security;

-- Requesters see the progress of their own requests.
create policy approvals_select_own_request
  on public.approvals for select to authenticated
  using (
    exists (
      select 1 from public.requests r
      where r.id = request_id and r.requester_id = (select auth.uid())
    )
  );