-- Deterministic pre-qualification. Everything the brief asks the agent to
-- verify is arithmetic, so it is computed here: testable, free, and incapable
-- of being wrong in the way a model can be. The LLM receives these findings
-- and writes the prose synthesis.

create function public.run_request_checks(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_request   public.requests;
  v_type      public.request_types;
  v_findings  jsonb := '[]'::jsonb;
  v_available numeric;
  v_year      smallint;
  v_count     integer;
  v_names     text;
begin
  select * into v_request from public.requests where id = p_request_id;
  if not found then
    raise exception 'Request % not found', p_request_id;
  end if;

  select * into v_type from public.request_types where code = v_request.request_type;

  -- 1. Dates in the past
  if v_request.start_date is not null and v_request.start_date < current_date then
    v_findings := v_findings || jsonb_build_object(
      'check', 'dates', 'status', 'warning',
      'detail', 'La période commence dans le passé (' || v_request.start_date || ').');
  elsif v_request.start_date is not null then
    v_findings := v_findings || jsonb_build_object(
      'check', 'dates', 'status', 'ok',
      'detail', 'Dates cohérentes.');
  end if;

  -- 2. Leave balance, excluding this request from the pending total
  if v_type.affects_leave_balance and v_request.start_date is not null then
    v_year := extract(year from v_request.start_date)::smallint;

    select b.entitled_days + b.carried_over_days - b.taken_days
           - coalesce((
               select sum(r.value) from public.requests r
               join public.request_types t on t.code = r.request_type
               where r.requester_id = v_request.requester_id
                 and t.affects_leave_balance
                 and r.status = 'pending'
                 and r.id <> v_request.id
                 and extract(year from r.start_date) = v_year
             ), 0)
    into v_available
    from public.leave_balances b
    where b.employee_id = v_request.requester_id and b.year = v_year;

    if v_available is null then
      v_findings := v_findings || jsonb_build_object(
        'check', 'balance', 'status', 'warning',
        'detail', 'Aucun solde de congés enregistré pour ' || v_year || '.');
    elsif v_request.value > v_available then
      v_findings := v_findings || jsonb_build_object(
        'check', 'balance', 'status', 'warning',
        'available', v_available, 'requested', v_request.value,
        'detail', 'Solde insuffisant : ' || v_request.value || ' jours demandés pour '
                  || v_available || ' disponibles.');
    else
      v_findings := v_findings || jsonb_build_object(
        'check', 'balance', 'status', 'ok',
        'available', v_available, 'requested', v_request.value,
        'detail', 'Solde suffisant : ' || v_available || ' jours disponibles.');
    end if;
  end if;

  -- 3. The same person already has an overlapping request of this type
  if v_request.start_date is not null then
    select count(*) into v_count
    from public.requests r
    where r.requester_id = v_request.requester_id
      and r.request_type = v_request.request_type
      and r.id <> v_request.id
      and r.status in ('pending', 'approved')
      and r.start_date <= v_request.end_date
      and r.end_date   >= v_request.start_date;

    if v_count > 0 then
      v_findings := v_findings || jsonb_build_object(
        'check', 'duplicate', 'status', 'warning', 'count', v_count,
        'detail', v_count || ' autre(s) demande(s) du même type sur la même période.');
    else
      v_findings := v_findings || jsonb_build_object(
        'check', 'duplicate', 'status', 'ok', 'detail', 'Aucun doublon détecté.');
    end if;
  end if;

  -- 4. Teammates absent over the same period
  if v_type.affects_leave_balance and v_request.start_date is not null then
    select count(*), string_agg(distinct p.full_name, ', ')
    into v_count, v_names
    from public.requests r
    join public.profiles p on p.id = r.requester_id
    join public.request_types t on t.code = r.request_type
    where t.affects_leave_balance
      and r.status in ('pending', 'approved')
      and r.requester_id <> v_request.requester_id
      and p.manager_id = (select manager_id from public.profiles
                          where id = v_request.requester_id)
      and r.start_date <= v_request.end_date
      and r.end_date   >= v_request.start_date;

    if v_count > 0 then
      v_findings := v_findings || jsonb_build_object(
        'check', 'team_overlap', 'status', 'warning', 'with', v_names,
        'detail', 'Absence simultanée dans l''équipe : ' || v_names || '.');
    else
      v_findings := v_findings || jsonb_build_object(
        'check', 'team_overlap', 'status', 'ok',
        'detail', 'Aucune absence simultanée dans l''équipe.');
    end if;
  end if;

  return jsonb_build_object(
    'request_id', v_request.id,
    'verdict', case when v_findings @> '[{"status":"warning"}]'::jsonb
                    then 'warning' else 'ok' end,
    'findings', v_findings
  );
end;
$$;

revoke all on function public.run_request_checks(uuid) from public;
grant execute on function public.run_request_checks(uuid) to service_role;