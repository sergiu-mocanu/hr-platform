-- Everything an email about a request needs, in one call.
--
-- Recipients are derived from the step the request currently sits at, so the
-- same function serves the first notification and every later escalation.
-- Keeping this in SQL means n8n never reimplements "who should hear about
-- this", and the email template can gain fields without touching a workflow.

create function public.request_notification_payload(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_request   public.requests;
  v_type      public.request_types;
  v_requester public.profiles;
  v_role      public.user_role;
  v_to        jsonb;
  v_cc        jsonb;
begin
  select * into v_request from public.requests where id = p_request_id;
  if not found then
    raise exception 'Request % not found', p_request_id;
  end if;

  select * into v_type      from public.request_types where code = v_request.request_type;
  select * into v_requester from public.profiles      where id = v_request.requester_id;

  v_role := v_request.approver_chain[v_request.current_step];

  -- A manager step goes to that employee's manager; RH and DRH steps go to
  -- everyone holding the role.
  if v_role = 'manager' then
    select coalesce(jsonb_agg(jsonb_build_object('full_name', m.full_name, 'email', m.email)), '[]'::jsonb)
    into v_to
    from public.profiles m
    where m.id = v_requester.manager_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('full_name', p.full_name, 'email', p.email)), '[]'::jsonb)
    into v_to
    from public.profiles p
    where p.role = v_role;
  end if;

  -- S2: HR is kept informed from the start whenever the amount puts them in
  -- the chain, even though they only decide at their own step.
  if 'rh' = any(v_request.approver_chain) and v_role <> 'rh' then
    select coalesce(jsonb_agg(jsonb_build_object('full_name', p.full_name, 'email', p.email)), '[]'::jsonb)
    into v_cc
    from public.profiles p
    where p.role = 'rh';
  else
    v_cc := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'request_id',    v_request.id,
    'type_code',     v_request.request_type,
    'type_label',    v_type.label,
    'value',         v_request.value,
    'unit',          v_type.value_unit,
    'start_date',    v_request.start_date,
    'end_date',      v_request.end_date,
    'details',       v_request.details,
    'status',        v_request.status,
    'step',          v_request.current_step,
    'step_count',    cardinality(v_request.approver_chain),
    'approver_role', v_role,
    'requester',     jsonb_build_object('full_name', v_requester.full_name,
                                        'email',     v_requester.email),
    'to',            v_to,
    'cc',            v_cc
  );
end;
$$;

revoke all on function public.request_notification_payload(uuid) from public;
grant execute on function public.request_notification_payload(uuid) to service_role;