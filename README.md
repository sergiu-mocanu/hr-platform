# NovaCorp — Plateforme de gestion des demandes RH

Internal platform covering the lifecycle of an HR request — leave, remote work,
equipment, training — from submission to decision, with routing, notifications
and AI pre-qualification.

Academic project, M1 DFS "Ingénierie de l'automatisation", MyDigitalSchool.

**All data is fictitious.** No real personal data is ever loaded. The email
layer is a local sandbox that delivers nothing, so fictitious addresses cannot
reach real people.

## What it does

An employee submits a request. The database computes its duration in working
days, resolves the approval chain from configurable thresholds, and fires a
webhook. n8n emails the right approver — copying HR when the amount warrants
it — while a second workflow runs four deterministic checks and has a model
write a French summary for the approver. The approver decides in the app; the
request advances to the next step or closes, the employee is notified, the
leave balance updates, and every transition is recorded in an append-only log.

## Stack

| Layer | Technology |
|---|---|
| Database, API, auth, realtime | Supabase (hosted, EU region) |
| Front-end | Static HTML + `supabase-js`, no build step |
| Workflows | n8n, self-hosted in Docker |
| Public URL for webhooks | ngrok (free static domain) |
| Email | Mailpit (local sandbox) |
| LLM | Mistral (`mistral-small-latest`) |

## Repository layout

```
docs/                 working notes and measurement queries
n8n/                  exported workflows, one file each
scripts/              create_users.py — seeds the auth accounts
supabase/
  migrations/         the schema, in order
  seed.sql            roles, hierarchy, leave balances
web/                  the application (index.html + config.js)
```

---

# Setup from scratch

Tested on Ubuntu 24.04. Allow about forty minutes.

## 1. Repository

```bash
git clone <repo-url> ~/projects/hr-platform
cd ~/projects/hr-platform
cp .env.example .env     # then fill in SUPABASE_SERVICE_ROLE_KEY
```

Check `web/config.js` holds the project URL and the **anon** key (not the
service_role key — that one never goes in the front-end).

## 2. Supabase CLI

```bash
curl -fsSL https://raw.githubusercontent.com/supabase/cli/main/install | bash
exec $SHELL -l
supabase login
supabase link --project-ref <your-project-ref>
supabase migration list
```

The last command should show every migration present both locally and
remotely. If the project is new, `supabase db push` applies them all.

> Free-tier projects **pause after 7 days of inactivity** and have no backups.
> The repository is the backup: migrations plus `seed.sql` rebuild everything.

## 3. Fictitious accounts

Only needed on a fresh Supabase project — the accounts already exist otherwise.

```bash
conda create -n hr-platform python=3.12 -y
conda activate hr-platform
pip install requests python-dotenv
python scripts/create_users.py
supabase db push --include-seed
```

`db push` alone does **not** run the seed; the flag is required.

Eight accounts, all with password `NovaCorp2026!`:

| | |
|---|---|
| Hugo Bernard | DRH |
| Sophie Martin | RH |
| Marc Leroy | manager, Engineering |
| Nadia Cherif | manager, Commerce |
| Claire Dubois, Thomas Roux | Engineering |
| Léa Moreau, Karim Benali | Commerce |

Two teams on purpose: with one, "a manager sees their team" and "a manager sees
everything" produce identical results, and the cross-team leak stays invisible.

## 4. Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
sudo systemctl enable --now docker
newgrp docker
docker run hello-world
```

> Group membership does not apply to shells opened before `usermod`. Run
> `newgrp docker` in any terminal that reports *permission denied while trying
> to connect to the Docker API*, or log out and back in once.

## 5. n8n and Mailpit

```bash
newgrp docker
docker network create hr-net
docker volume create n8n_data

docker run -d --name mailpit --network hr-net \
  -p 8025:8025 -p 1025:1025 axllent/mailpit

docker run -d --name n8n --network hr-net -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e GENERIC_TIMEZONE=Europe/Paris -e TZ=Europe/Paris \
  -e WEBHOOK_URL=https://<your-static-domain> \
  docker.n8n.io/n8nio/n8n
```

> `WEBHOOK_URL` is the **domain only** — no path, no trailing slash. n8n appends
> `/webhook/<path>` itself; giving it a full webhook address produces a doubled
> URL that silently fails.

n8n at `http://localhost:5678`, Mailpit inbox at `http://localhost:8025`.

## 6. ngrok

```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok
ngrok config add-authtoken <your-token>
```

The free plan provides one static domain — claim it in the dashboard so the
URL survives restarts and `app_settings` never needs updating.

## 7. Import the workflows

In n8n: **Workflows → Import from File**, once per file in `n8n/`.

Then create the two credentials, under **Credentials → Add credential**:

- **Supabase API** — host `https://<ref>.supabase.co`, service_role key
- **SMTP** — host `mailpit`, port `1025`, user and password empty,
  **SSL/TLS off**

> Port 587 and 1025 use STARTTLS; the SSL/TLS toggle means implicit TLS from
> the first byte and belongs to port 465. Leaving it on gives
> `wrong version number`.

> Host is `mailpit`, not `localhost` — n8n resolves it by container name over
> `hr-net`. Inside the n8n container, `localhost` is n8n itself.

Then **reattach the credential on every node that needs one** — three Supabase
nodes and one email node. Imported workflows carry credential ids from the
instance they were exported from, which resolve to nothing here.

Finally, publish each workflow and register its production URL:

```sql
select key, value from app_settings where key like '%_url';
```

```sql
update app_settings set value = '<production URL>' where key = 'n8n_request_created_url';
```

> Each Webhook node must be set to **POST**, and the URL stored here must be
> the **production** one (`/webhook/...`), not the test one
> (`/webhook-test/...`), which only listens while you are watching it.

## 8. Realtime

Enable replication on `requests`, or the HR dashboard will never update by
itself:

```sql
alter publication supabase_realtime add table public.requests;
```

## 9. Front-end

```bash
cd ~/projects/hr-platform/web
python -m http.server 5500
```

Open `http://localhost:5500`.

> Serve from `web/`, never from the repository root — the root contains `.env`,
> and a static server will happily hand it out over HTTP.

---

# Running it day to day

Three terminals:

```bash
newgrp docker && docker start mailpit n8n       # 1
ngrok http --url=<your-static-domain> 5678      # 2 — leave running
cd ~/projects/hr-platform/web && python -m http.server 5500   # 3 — leave running
```

Then confirm each workflow still shows as published in n8n.

| Check | Expected |
|---|---|
| `docker ps` | `n8n` and `mailpit` up |
| `https://<static-domain>` | the n8n interface |
| `http://localhost:8025` | the Mailpit inbox |
| `http://localhost:5500` | the login page |

## When a request goes in and nothing happens

The webhooks are asynchronous: no error surfaces in the SQL editor. The
response log is the only window.

```sql
select id, status_code, error_msg, created
from net._http_response order by id desc limit 5;
```

| Result | Meaning |
|---|---|
| `404` | n8n reached, nothing listening — workflow unpublished, wrong path, or the Webhook node is not POST |
| `200` | n8n accepted it — look at **Executions** in n8n |
| connection or DNS error | ngrok is not running |
| no new row | the trigger did not fire — check `pg_trigger` on `requests` |

---

# Conventions

- **Language**: code, identifiers, comments and `docs/` in English; the UI and
  the dossier in French.
- **Schema changes go through migrations only.** Nothing is created by hand in
  the dashboard.
- **Save the file before `supabase db push`** — it reads from disk, and an
  unsaved migration is recorded as applied while doing nothing. Recover with
  `supabase migration repair --status reverted <timestamp>`.
- **Business configuration lives in migrations** (request types, routing
  thresholds); **fictitious data lives in `seed.sql`**.
- Workflows are re-exported to `n8n/` after any change.

## Common commands

```bash
supabase migration new <name>      # create a timestamped empty migration
supabase db push                   # apply pending migrations
supabase db push --include-seed    # ...and reload the fictitious data
```

# Documentation

| File | Contents |
|---|---|
| `docs/defence-notes.md` | Design decisions worth defending, and known limitations |
| `docs/dora-baseline.md` | The declared "before" figures and how they were derived |
| `docs/dora-queries.sql` | The "after" measurement queries |
| `docs/rls-tests.sql` | Policy tests, one block per persona |
| `docs/cost-log.md` | Running cost tracking |
| `n8n/README.md` | What the exported workflows do and don't contain |

# Known limitations

Fully listed in `docs/defence-notes.md`. The ones that affect running the
project:

- Public holidays are seeded to **2027** only; beyond that, working-day counts
  silently treat holidays as workdays.
- Leave spanning 31 December is attributed entirely to the year of its start
  date.
- Supabase webhooks are fire-and-forget: if n8n is down, the notification is
  lost with no error raised.
- n8n runs locally behind a tunnel, so the workflows are only reachable while
  that machine is up.
