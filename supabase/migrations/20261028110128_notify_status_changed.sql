-- Notifies the requester when their request is decided. Separate webhook from
-- the creation notification: different audience, different template.

insert into public.app_settings (key, value)
values ('n8n_status_changed_url', '');

create function public.notify_n8n_status_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url    text;
  v_secret text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  select value into v_url
  from public.app_settings where key = 'n8n_status_changed_url';

  if coalesce(v_url, '') = '' then
    return new;
  end if;

  select coalesce(value, '') into v_secret
  from public.app_settings where key = 'n8n_webhook_secret';

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'type',   'UPDATE',
      'table',  tg_table_name,
      'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', to_jsonb(old)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

create trigger requests_notify_status_changed
  after update on public.requests
  for each row execute function public.notify_n8n_status_changed();