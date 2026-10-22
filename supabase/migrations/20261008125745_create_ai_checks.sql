-- Output of the AI pre-qualification step. Advisory only: no value here ever
-- changes a request's status. Token counts feed docs/cost-log.md.

create type ai_verdict as enum ('ok', 'warning', 'unavailable');

create table public.ai_checks (
  id            bigint generated always as identity primary key,
  request_id    uuid not null references public.requests (id) on delete cascade,
  verdict       ai_verdict not null,
  summary       text not null,
  findings      jsonb not null default '[]'::jsonb,
  model         text,
  input_tokens  integer check (input_tokens  is null or input_tokens  >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  cost_eur      numeric(10,6) check (cost_eur is null or cost_eur >= 0),
  checked_at    timestamptz not null default now(),
  constraint ai_checks_findings_is_array check (jsonb_typeof(findings) = 'array')
);

create index ai_checks_request_idx on public.ai_checks (request_id, checked_at desc);

-- Most recent check per request, for the approver view and the dashboard.
-- id breaks ties: now() is fixed for a transaction, so two checks written in
-- one n8n execution share a checked_at.
create view public.latest_ai_check
with (security_invoker = true) as
select distinct on (request_id) *
from public.ai_checks
order by request_id, checked_at desc, id desc;

alter table public.ai_checks enable row level security;

-- No insert policy: only the service role (n8n) writes here.
create policy ai_checks_select_own_request
  on public.ai_checks for select to authenticated
  using (
    exists (
      select 1 from public.requests r
      where r.id = request_id and r.requester_id = (select auth.uid())
    )
  );