# NovaCorp — HR Request Platform

Internal platform standardising and automating NovaCorp's HR request lifecycle
(leave, remote work, equipment, training).

Academic project — M1 DFS, Ingénierie de l'automatisation.
**All data is fictitious.** No real personal data is ever loaded into this project.

## Stack

| Layer | Technology |
|---|---|
| Database + API + auth | Supabase (hosted, EU region) |
| Frontend | Static HTML + `supabase-js` (no build step) |
| Workflows | n8n (self-hosted, Docker, WSL2) |
| AI agent | LLM via API, called from n8n |
| Email | Brevo (SMTP) |

## Repository layout

```
docs/                 working notes feeding the final dossier
supabase/
  migrations/         schema as code — the single source of truth
  seed.sql            fictitious users and reference data
web/                  frontend (from séance 3)
n8n/                  exported workflow JSON (from séance 4)
```

## Conventions

- **Language**: code, identifiers, comments and `docs/` in English.
  The UI and the final dossier are in French.
- **Schema changes go through migrations only.** Nothing is created by hand in
  the Supabase dashboard. The free tier has zero backup retention, so
  `supabase db push` + `seed.sql` must be able to rebuild the project from
  scratch.
- n8n workflows are exported to `n8n/` after each working session.

## Common commands

```bash
supabase migration new <name>   # create an empty timestamped migration
supabase db push                # apply pending migrations to the linked project
supabase migration list         # compare local and remote migration state
```

## Free-tier constraints

- Projects pause after 7 days of low activity. Open the dashboard weekly.
- No automatic backups. The repository is the backup.
