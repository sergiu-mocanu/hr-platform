-- Fictitious NovaCorp team. Run after scripts/create_users.py, which creates
-- the auth accounts (and, by trigger, the profile rows this script updates).
--
-- Re-runnable: every statement is an update or an upsert.

update public.profiles set role = 'drh',     department = 'Direction'   where email = 'hugo.bernard@novacorp.fr';
update public.profiles set role = 'rh',      department = 'RH'          where email = 'sophie.martin@novacorp.fr';
update public.profiles set role = 'manager', department = 'Engineering' where email = 'marc.leroy@novacorp.fr';
update public.profiles set role = 'manager', department = 'Commerce'    where email = 'nadia.cherif@novacorp.fr';
update public.profiles set role = 'salarie', department = 'Engineering' where email = 'claire.dubois@novacorp.fr';
update public.profiles set role = 'salarie', department = 'Engineering' where email = 'thomas.roux@novacorp.fr';
update public.profiles set role = 'salarie', department = 'Commerce'    where email = 'lea.moreau@novacorp.fr';
update public.profiles set role = 'salarie', department = 'Commerce'    where email = 'karim.benali@novacorp.fr';

-- Hierarchy: two teams under two managers, both reporting to the DRH.
update public.profiles p set manager_id = m.id
from public.profiles m
where m.email = 'hugo.bernard@novacorp.fr'
  and p.email in ('sophie.martin@novacorp.fr', 'marc.leroy@novacorp.fr', 'nadia.cherif@novacorp.fr');

update public.profiles p set manager_id = m.id
from public.profiles m
where m.email = 'marc.leroy@novacorp.fr'
  and p.email in ('claire.dubois@novacorp.fr', 'thomas.roux@novacorp.fr');

update public.profiles p set manager_id = m.id
from public.profiles m
where m.email = 'nadia.cherif@novacorp.fr'
  and p.email in ('lea.moreau@novacorp.fr', 'karim.benali@novacorp.fr');

-- Leave entitlement for the current year. Carried-over days vary so the
-- balance check at séance 6 has more than one shape to look at.
insert into public.leave_balances (employee_id, year, entitled_days, carried_over_days)
select p.id, 2026, 25,
  case p.email
    when 'claire.dubois@novacorp.fr' then 3
    when 'lea.moreau@novacorp.fr'    then 5
    else 0
  end
from public.profiles p
where p.email like '%@novacorp.fr'
on conflict (employee_id, year) do update
  set entitled_days     = excluded.entitled_days,
      carried_over_days = excluded.carried_over_days;
