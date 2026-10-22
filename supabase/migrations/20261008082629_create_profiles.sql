-- Employee directory, mirroring auth.users with business attributes.

create type user_role as enum ('salarie', 'manager', 'rh', 'drh');

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null unique,
  full_name   text not null,
  role        user_role not null default 'salarie',
  manager_id  uuid references public.profiles (id) on delete set null,
  department  text,
  created_at  timestamptz not null default now()
);

create index profiles_manager_id_idx on public.profiles (manager_id);

-- A profile row is created automatically for every new auth user.
-- security definer is required: the trigger fires in the auth schema context,
-- which has no rights on public. An empty search_path forces fully-qualified
-- names and prevents search_path hijacking.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS is enabled from the start: any table in the public schema is reachable
-- through PostgREST with the anon key. Full policy set comes in séance 3.
alter table public.profiles enable row level security;

create policy profiles_select_own
  on public.profiles for select
  using ((select auth.uid()) = id);