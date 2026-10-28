# Workflows n8n

Exported with `n8n export:workflow --all --separate`. One file per workflow.

Credentials are **not** included — n8n stores them encrypted, separately.
After importing on a new instance, each HTTP and email node needs its
credential reattached by hand; the ids in these files refer to the instance
they were exported from and will not resolve elsewhere.

Credentials to recreate:

- **Supabase API** — host + service_role key (used by three nodes)
- **SMTP** — Mailpit, host `mailpit`, port 1025, no auth, SSL/TLS off

After importing, set each workflow's production webhook URL in `app_settings`
(see the main README) and publish it.