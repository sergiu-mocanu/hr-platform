-- Duration is derived from the dates, never typed in. For day-based types the
-- value column becomes an output of set_request_routing rather than an input.

create table public.public_holidays (
  day   date primary key,
  label text not null
);

alter table public.public_holidays enable row level security;

create policy public_holidays_select_authenticated
  on public.public_holidays for select to authenticated using (true);

insert into public.public_holidays (day, label) values
  ('2026-01-01', 'Jour de l''An'),
  ('2026-04-06', 'Lundi de Pâques'),
  ('2026-05-01', 'Fête du Travail'),
  ('2026-05-08', 'Victoire 1945'),
  ('2026-05-14', 'Ascension'),
  ('2026-05-25', 'Lundi de Pentecôte'),
  ('2026-07-14', 'Fête nationale'),
  ('2026-08-15', 'Assomption'),
  ('2026-11-01', 'Toussaint'),
  ('2026-11-11', 'Armistice 1918'),
  ('2026-12-25', 'Noël'),
  ('2027-01-01', 'Jour de l''An'),
  ('2027-03-29', 'Lundi de Pâques'),
  ('2027-05-01', 'Fête du Travail'),
  ('2027-05-06', 'Ascension'),
  ('2027-05-08', 'Victoire 1945'),
  ('2027-05-17', 'Lundi de Pentecôte'),
  ('2027-07-14', 'Fête nationale'),
  ('2027-08-15', 'Assomption'),
  ('2027-11-01', 'Toussaint'),
  ('2027-11-11', 'Armistice 1918'),
  ('2027-12-25', 'Noël');

alter table public.requests
  add column starts_afternoon boolean not null default false,
  add column ends_morning     boolean not null default false;

-- Half-days only count against a boundary that is itself a working day.
create function public.working_days(
  p_start           date,
  p_end             date,
  p_starts_afternoon boolean default false,
  p_ends_morning     boolean default false
)
returns numeric
language sql
stable
set search_path = ''
as $$
  with worked as (
    select d::date as day
    from generate_series(p_start, p_end, interval '1 day') d
    where extract(isodow from d) < 6
      and not exists (select 1 from public.public_holidays h where h.day = d::date)
  )
  select greatest(
    (select count(*) from worked)
    - case when p_starts_afternoon and exists (select 1 from worked where day = p_start)
           then 0.5 else 0 end
    - case when p_ends_morning and exists (select 1 from worked where day = p_end)
           then 0.5 else 0 end,
    0
  )::numeric;
$$;

grant execute on function public.working_days(date, date, boolean, boolean) to authenticated;

create or replace function public.set_request_routing()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_type  public.request_types;
  v_chain public.user_role[];
begin
  select * into v_type
  from public.request_types
  where code = new.request_type and is_active;

  if not found then
    raise exception 'Unknown or inactive request type: %', new.request_type;
  end if;

  if v_type.requires_dates and (new.start_date is null or new.end_date is null) then
    raise exception 'Request type % requires start_date and end_date', new.request_type;
  end if;

  -- Day-based types: the client's value is ignored and recomputed.
  if v_type.value_unit = 'days' and v_type.requires_dates then
    new.value := public.working_days(
      new.start_date, new.end_date, new.starts_afternoon, new.ends_morning);

    if new.value <= 0 then
      raise exception 'La période sélectionnée ne contient aucun jour ouvré';
    end if;
  end if;

  v_chain := public.resolve_approver_chain(new.request_type, new.value);

  if v_chain is null then
    raise exception 'No routing rule matches type % with value %',
      new.request_type, new.value;
  end if;

  new.approver_chain := v_chain;
  new.current_step   := 1;
  new.status         := 'pending';
  new.decided_at     := null;
  return new;
end;
$$;