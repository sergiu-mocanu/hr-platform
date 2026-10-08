-- Append-only history. Written by trigger, never by the application, so no
-- code path can produce a status change without a corresponding event.

create type request_event_type as enum (
  'submitted', 'approved', 'rejected', 'cancelled',
  'ai_check_completed', 'notification_sent', 'reminder_sent'
);

create table public.request_events (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references public.requests (id) on delete cascade,
  event_type  request_event_type not null,
  actor_id    uuid references public.profiles (id) on delete set null,
  from_status request_status,
  to_status   request_status,
  step        smallint,
  note        text,
  occurred_at timestamptz not null default now()
);

create index request_events_request_idx  on public.request_events (request_id, occurred_at);
create index request_events_type_idx     on public.request_events (event_type);

-- security definer: authenticated users have no insert policy on this table,
-- so the trigger writes on their behalf. That is the point — history cannot
-- be forged by the client, only produced by a real status change.
create function public.log_request_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.request_event_type;
begin
  if tg_op = 'INSERT' then
    v_event := 'submitted';
  else
    if new.status is not distinct from old.status then
      return new;
    end if;
    v_event := case new.status
      when 'approved'  then 'approved'
      when 'rejected'  then 'rejected'
      when 'cancelled' then 'cancelled'
    end;
    if v_event is null then
      return new;
    end if;
  end if;

  insert into public.request_events
    (request_id, event_type, actor_id, from_status, to_status, step)
  values
    (new.id, v_event, (select auth.uid()),
     case when tg_op = 'UPDATE' then old.status end,
     new.status, new.current_step);

  return new;
end;
$$;

create trigger requests_log_event
  after insert or update on public.requests
  for each row execute function public.log_request_event();

-- Rows may be added and (via cascade from requests) removed for retention
-- purposes, but never rewritten.
create function public.prevent_event_rewrite()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'request_events is append-only';
end;
$$;

create trigger request_events_immutable
  before update on public.request_events
  for each row execute function public.prevent_event_rewrite();

alter table public.request_events enable row level security;

create policy request_events_select_own
  on public.request_events for select to authenticated
  using (
    exists (
      select 1 from public.requests r
      where r.id = request_id
        and r.requester_id = (select auth.uid())
    )
  );