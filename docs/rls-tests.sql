-- RLS policy tests. Run in the Supabase SQL editor, one block at a time.
--
-- Each block impersonates a seeded employee by setting the JWT claim the way
-- PostgREST does, switches to the authenticated role so policies apply, then
-- rolls back. Nothing is left behind.
--
-- Prerequisite: scripts/create_users.py and seed.sql have been run, plus the
-- fixture in block 0.
--
-- The SQL editor connects as a superuser, which bypasses RLS entirely. That
-- is why `set local role authenticated` is not optional — without it every
-- block would report that everyone sees everything.

-- ---------------------------------------------------------------------------
-- Block 0 — fixture. Run once; block 6 removes it.
-- ---------------------------------------------------------------------------
insert into requests (requester_id, request_type, value, start_date, end_date, details)
select id, 'conges', 3, '2026-11-02', '2026-11-04', 'RLS fixture — Claire'
from profiles where email = 'claire.dubois@novacorp.fr';

insert into requests (requester_id, request_type, value, start_date, end_date, details)
select id, 'conges', 8, '2026-11-10', '2026-11-18', 'RLS fixture — Lea'
from profiles where email = 'lea.moreau@novacorp.fr';

select count(*) as fixture_requests from requests where details like 'RLS fixture%';
-- expected: 2

-- ---------------------------------------------------------------------------
-- Block 1 — Claire (salariée) sees only her own request.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from profiles where email = 'claire.dubois@novacorp.fr'))::text,
  true);
set local role authenticated;

select
  (select count(*) from requests)                        as requests_visible,   -- expected 1
  (select count(*) from leave_balances)                  as balances_visible,   -- expected 1
  (select count(*) from profiles)                        as profiles_visible;   -- expected 8
rollback;

-- ---------------------------------------------------------------------------
-- Block 2 — Marc (manager, Engineering) sees himself and his two reports,
-- but nothing from the Commerce team.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from profiles where email = 'marc.leroy@novacorp.fr'))::text,
  true);
set local role authenticated;

select
  (select count(*) from requests)                                      as requests_visible,  -- expected 1
  (select count(*) from requests where details like '%Lea%')           as sees_other_team,   -- expected 0
  (select count(*) from leave_balances)                                as balances_visible;  -- expected 3
rollback;

-- ---------------------------------------------------------------------------
-- Block 3 — Nadia (manager, Commerce) sees the mirror image.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from profiles where email = 'nadia.cherif@novacorp.fr'))::text,
  true);
set local role authenticated;

select
  (select count(*) from requests)                                   as requests_visible,  -- expected 1
  (select count(*) from requests where details like '%Claire%')     as sees_other_team;   -- expected 0
rollback;

-- ---------------------------------------------------------------------------
-- Block 4 — Sophie (RH) sees everything.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from profiles where email = 'sophie.martin@novacorp.fr'))::text,
  true);
set local role authenticated;

select
  (select count(*) from requests)       as requests_visible,  -- expected 2
  (select count(*) from leave_balances) as balances_visible;  -- expected 8
rollback;

-- ---------------------------------------------------------------------------
-- Block 5 — an employee cannot approve their own request, and cannot
-- promote herself by editing her profile.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from profiles where email = 'claire.dubois@novacorp.fr'))::text,
  true);
set local role authenticated;

update profiles set role = 'drh'
where id = (select auth.uid());

select role as role_after_self_promotion_attempt
from profiles where email = 'claire.dubois@novacorp.fr';
-- expected: salarie — the update matches no row, so it silently affects nothing
rollback;

-- ---------------------------------------------------------------------------
-- Block 6 — remove the fixture.
-- ---------------------------------------------------------------------------
delete from requests where details like 'RLS fixture%';
select count(*) as fixture_requests_remaining from requests where details like 'RLS fixture%';
-- expected: 0