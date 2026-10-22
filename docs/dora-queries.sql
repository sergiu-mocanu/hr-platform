-- Post-automation figures for the comparison in docs/dora-baseline.md.
-- Run in the Supabase SQL editor.

-- Lead time: submission to final decision.
select
  count(*)                                                              as decided_requests,
  round(avg(days)::numeric, 2)                                          as avg_days,
  round((percentile_cont(0.5) within group (order by days))::numeric, 2) as median_days,
  round((percentile_cont(0.9) within group (order by days))::numeric, 2) as p90_days
from (
  select
    extract(epoch from
      min(occurred_at) filter (where event_type in ('approved','rejected'))
      - min(occurred_at) filter (where event_type = 'submitted')
    ) / 86400 as days
  from request_events
  group by request_id
) t
where days is not null;

-- Lead time broken down by request type, to show where the routing depth costs time.
select
  r.request_type,
  count(*)                                                               as decided,
  round((percentile_cont(0.5) within group (order by e.days))::numeric, 2) as median_days
from (
  select
    request_id,
    extract(epoch from
      min(occurred_at) filter (where event_type in ('approved','rejected'))
      - min(occurred_at) filter (where event_type = 'submitted')
    ) / 86400 as days
  from request_events
  group by request_id
) e
join requests r on r.id = e.request_id
where e.days is not null
group by r.request_type
order by median_days desc;

-- Traceability: share of requests with a complete event history.
-- Expected to be 100% by construction, which is itself the point.
select
  count(*)                                                      as total,
  count(*) filter (where ev > 0)                                as with_history,
  round(100.0 * count(*) filter (where ev > 0) / count(*), 1)   as pct
from (
  select r.id, count(e.id) as ev
  from requests r left join request_events e on e.request_id = r.id
  group by r.id
) t;

-- Throughput: decisions per week.
select
  date_trunc('week', occurred_at)::date as week,
  count(*)                              as decisions
from request_events
where event_type in ('approved','rejected')
group by 1 order by 1;