# Cost log

Filled as the project progresses. Feeds the "coûts d'exploitation prévisionnels"
section of the dossier. Two columns matter: what the platform costs to run, and
what the manual process it replaces costs today.

## Current manual process

Loaded hourly cost assumed at €35/h (gross salary + employer charges), stated as
an assumption rather than a company figure.

| Item | Time / month | Cost / month |
|---|---|---|
| HR transcription and follow-up (13.3 h) | 13.3 h | €466 |
| Manager handling (6.7 h) | 6.7 h | €235 |
| **Total** | 20 h | **€701** |

Not costed: the indirect cost of 3-day lead times and lost requests.

## Platform running cost

| Component | Plan | Cost / month | Notes |
|---|---|---|---|
| Supabase | Free | €0 | 500 MB DB, 2 projects, pauses after 7 days idle |
| n8n | Self-hosted, Docker | €0 | runs on existing hardware; a VPS would be ~€5 |
| ngrok | Free | €0 | one static domain, for webhook ingress |
| Brevo | Free | €0 | 300 emails/day — well above 40 requests/month |
| LLM API | TBD | TBD | measure at séance 6 |
| **Total** | | **TBD** | |

## LLM cost measurement (séance 6)

Measured per request from the `ai_checks` table, which stores the token counts
returned by the API.

| Field | Value |
|---|---|
| Provider / model | TBD |
| Input tokens per request | TBD |
| Output tokens per request | TBD |
| Price per 1M input / output tokens | TBD |
| Cost per request | TBD |
| Cost at 40 requests/month | TBD |

## What a realistic production setup would cost

The free tiers above are credible for a 40-request/month internal tool, but the
dossier should state what changes if NovaCorp actually adopted it:

| Component | Realistic plan | Cost / month |
|---|---|---|
| Supabase | Pro (no pausing, daily backups) | $25 |
| n8n | VPS or n8n Cloud starter | €5–€20 |
| LLM API | as measured | TBD |

## Bonus features

Each bonus gets a costed entry before it is built, per the brief.

| Bonus | User benefit | Build cost | Running cost | Decision |
|---|---|---|---|---|
| | | | | |
