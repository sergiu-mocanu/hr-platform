-- Single entry point for approval decisions. Called by the frontend with a
-- user JWT, and by n8n with the service key plus an explicit approver id.
--
-- security definer is required (approvers have no direct write rights) and is
-- precisely why every authorisation rule below is enforced in the body: RLS
-- does not apply inside this function.

create function public.record_approval(
  p_request_id  uuid,
  p_decision    approval_decision,
  p_comment     text default null,
  p_approver_id uuid default null
)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_role     public.user_role;
  v_request  public.requests;
  v_approval public.approvals;
  v_is_direct_manager boolean;
begin
  -- A real session always wins; p_approver_id only applies to service callers.
  v_actor := coalesce((select auth.uid()), p_approver_id);
  if v_actor is null then
    raise exception 'No approver identified';
  end if;

  select * into v_request from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'Request % not found', p_request_id;
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Request % is already %', p_request_id, v_request.status;
  end if;

  if v_request.requester_id = v_actor then
    raise exception 'A request cannot be decided by its requester';
  end if;

  select role into v_role from public.profiles where id = v_actor;
  if v_role is null then
    raise exception 'Unknown approver %', v_actor;
  end if;

  select * into v_approval from public.approvals
  where request_id = p_request_id
    and step = v_request.current_step
    and decision is null;

  if not found then
    raise exception 'No open approval at step % for request %',
      v_request.current_step, p_request_id;
  end if;

  if v_role <> v_approval.approver_role then
    raise exception 'Step % requires role %, actor holds %',
      v_approval.step, v_approval.approver_role, v_role;
  end if;

  -- Any RH or DRH may act, but only the requester's own manager may.
  if v_approval.approver_role = 'manager' then
    select exists (
      select 1 from public.profiles
      where id = v_request.requester_id and manager_id = v_actor
    ) into v_is_direct_manager;

    if not v_is_direct_manager then
      raise exception 'Actor is not the direct manager of the requester';
    end if;
  end if;

  update public.approvals
  set decision = p_decision, comment = p_comment,
      approver_id = v_actor, decided_at = now()
  where id = v_approval.id;

  if p_decision = 'rejected' then
    update public.requests set status = 'rejected', decided_at = now()
    where id = p_request_id returning * into v_request;

  elsif v_request.current_step < cardinality(v_request.approver_chain) then
    update public.requests set current_step = current_step + 1
    where id = p_request_id returning * into v_request;

    insert into public.approvals (request_id, step, approver_role)
    values (p_request_id, v_request.current_step,
            v_request.approver_chain[v_request.current_step]);

  else
    update public.requests set status = 'approved', decided_at = now()
    where id = p_request_id returning * into v_request;
  end if;

  return v_request;
end;
$$;

revoke all on function public.record_approval(uuid, approval_decision, text, uuid) from public;
grant execute on function public.record_approval(uuid, approval_decision, text, uuid)
  to authenticated, service_role;