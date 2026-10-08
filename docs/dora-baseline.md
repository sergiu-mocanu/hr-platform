# Baseline — manual process (before automation)

## Status of these figures

NovaCorp's current process has **no instrumentation**: requests live in email
threads and a shared spreadsheet, so no historical data exists to measure.

The figures below are therefore **declared working estimates**, derived from the
process described in the brief, not measurements. They are stated here at the
start of the project so that the "after" comparison is honest: the post-automation
figures will be real queries against `request_events`, compared to a hypothesis
that was fixed in advance rather than retrofitted to flatter the result.

Estimates are deliberately conservative — understating the current pain means
the measured improvement cannot be accused of being inflated.

## Volume hypothesis

120 employees, ~40 HR requests per month:

| Type | Requests / month |
|---|---|
| Leave (congés) | 26 |
| Remote work (télétravail) | 8 |
| Equipment (matériel) | 4 |
| Training (formation) | 2 |

## DORA metrics, adapted to a business process

DORA was defined for software delivery. The mapping used here treats a single
HR request as the unit of work flowing through the system.

| DORA metric | Equivalent here | Baseline |
|---|---|---|
| Lead time for changes | Submission → decision communicated to the employee | median 3.2 days, P90 9 days |
| Deployment frequency | Requests reaching a final decision | ~9 per week |
| Change failure rate | Requests needing rework: lost, re-keyed incorrectly, sent to the wrong approver, or duplicated | 12% |
| Time to restore service | Time to notice and correct a mishandled request | 4.5 days |

### Where each number comes from

- **Lead time** — email arrives, HR transcribes it when they next process the
  inbox (0.5–1 day), the manager replies when they notice it (1–3 days), the
  employee is told when someone remembers (0.5–2 days).
- **Change failure rate** — the brief states lines are sometimes forgotten
  during transcription, and there is no routing rule, so wrong-approver cases
  are structural. 12% assumes roughly 1 in 8 requests needs human rework.
- **Time to restore** — nothing detects a lost request; it surfaces when the
  employee chases it, typically after a week minus a couple of days.

## Non-DORA baseline

| Indicator | Baseline |
|---|---|
| Traceability (requests with an auditable decision history) | 0% |
| Guaranteed response time (SLA) | none |
| HR manual handling | ~20 min/request (12 min transcription + 8 min follow-up) = **13.3 h/month** |
| Manager time per request | ~10 min = 6.7 h/month across all managers |

## Targets after automation

| Indicator | Target |
|---|---|
| Lead time, median | < 1 day |
| Lead time, P90 | < 3 days |
| Failure rate | < 2% |
| Traceability | 100% |
| HR manual handling | < 2 h/month |

## How the "after" figures will be measured

From `request_events`, which records every status transition with a timestamp
and an actor. Lead time is the interval between the `submitted` event and the
final `approved` / `rejected` event for the same request. The query will live in
`docs/dora-queries.sql` once the schema exists.
