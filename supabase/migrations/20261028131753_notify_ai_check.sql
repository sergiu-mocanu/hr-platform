-- Third outbound hook: the AI pre-qualification runs in parallel with the
-- approver notification rather than delaying it.

insert into public.app_settings (key, value)
values ('n8n_ai_check_url', '');

create function public.notify_n8n_ai_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text;
  v_secret text;
begin
  select value into v_url
  from public.app_settings where key = 'n8n_ai_check_url';

  if coalesce(v_url, '') = '' then
    return new;
  end if;

  select coalesce(value, '') into v_secret
  from public.app_settings where key = 'n8n_webhook_secret';

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('record', to_jsonb(new)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

create trigger requests_notify_ai_check
  after insert on public.requests
  for each row execute function public.notify_n8n_ai_check();