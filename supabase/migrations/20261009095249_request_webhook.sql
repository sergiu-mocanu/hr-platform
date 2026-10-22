-- Outbound notification to n8n when a request is created.
--
-- This is what the dashboard's "Database Webhooks" feature generates, written
-- by hand so it lives in migrations and can be reviewed and reused.

create extension if not exists pg_net with schema extensions;

-- Runtime configuration. RLS is enabled with no policies at all, so anon and
-- authenticated can read nothing; only the service role and security definer
-- functions reach it.
create table public.app_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

insert into public.app_settings (key, value) values
  ('n8n_request_created_url', ''),
  ('n8n_webhook_secret', '');

-- Payload mirrors the shape Supabase's own webhooks emit, so the two are
-- interchangeable.
create function public.notify_n8n_request_created()
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
  from public.app_settings where key = 'n8n_request_created_url';

  -- Unconfigured is a valid state: inserts must not fail because n8n is absent.
  if coalesce(v_url, '') = '' then
    return new;
  end if;

  select coalesce(value, '') into v_secret
  from public.app_settings where key = 'n8n_webhook_secret';

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'type',   tg_op,
      'table',  tg_table_name,
      'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', null
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

create trigger requests_notify_n8n
  after insert on public.requests
  for each row execute function public.notify_n8n_request_created();