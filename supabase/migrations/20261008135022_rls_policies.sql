-- Full visibility model.
--
--   salarie : own records only
--   manager : own records + those of direct reports
--   rh, drh : everything
--
-- The helpers below are security definer on purpose. A policy on profiles
-- that reads profiles to find the caller's role would recurse infinitely;
-- RLS does not apply inside a definer function, which breaks the cycle.
-- Each one reads only the caller's own context, never arbitrary rows.

create function public.caller_role()
returns user_role
language sql stable security definer set search_path = ''
as $$ select role from public.profiles where id = (select auth.uid()) $$;

create function public.caller_is_hr()
returns boolean
language sql stable security definer set search_path = ''
as $$ select public.caller_role() in ('rh', 'drh') $$;

create function public.caller_manages(p_employee_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = p_employee_id and manager_id = (select auth.uid())
  )
$$;

-- Shared visibility rule for everything hanging off a request.
create function public.caller_can_see_request(p_request_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.requests r
    where r.id = p_request_id
      and (
        r.requester_id = (select auth.uid())
        or public.caller_is_hr()
        or public.caller_manages(r.requester_id)
      )
  )
$$;

grant execute on function public.caller_role()                 to authenticated;
grant execute on function public.caller_is_hr()                to authenticated;
grant execute on function public.caller_manages(uuid)          to authenticated;
grant execute on function public.caller_can_see_request(uuid)  to authenticated;

-- profiles: readable by everyone, as an internal directory. The columns are
-- name, email, role, department and manager — ordinary directory data, no
-- leave or request information. Only HR may modify it.
drop policy profiles_select_own on public.profiles;

create policy profiles_select_all
  on public.profiles for select to authenticated using (true);

create policy profiles_update_hr
  on public.profiles for update to authenticated
  using ((select public.caller_is_hr()))
  with check ((select public.caller_is_hr()));

-- requests
drop policy requests_select_own on public.requests;

create policy requests_select_visible
  on public.requests for select to authenticated
  using (
    requester_id = (select auth.uid())
    or (select public.caller_is_hr())
    or (select public.caller_manages(requester_id))
  );

-- approvals, events, balances, ai_checks follow the parent request.
drop policy approvals_select_own_request on public.approvals;

create policy approvals_select_visible
  on public.approvals for select to authenticated
  using ((select public.caller_can_see_request(request_id)));

drop policy request_events_select_own on public.request_events;

create policy request_events_select_visible
  on public.request_events for select to authenticated
  using ((select public.caller_can_see_request(request_id)));

drop policy ai_checks_select_own_request on public.ai_checks;

create policy ai_checks_select_visible
  on public.ai_checks for select to authenticated
  using ((select public.caller_can_see_request(request_id)));

drop policy leave_balances_select_own on public.leave_balances;

create policy leave_balances_select_visible
  on public.leave_balances for select to authenticated
  using (
    employee_id = (select auth.uid())
    or (select public.caller_is_hr())
    or (select public.caller_manages(employee_id))
  );