# Points to defend at the soutenance

Decisions where an alternative was available and the reasoning is worth stating
out loud, plus limitations better raised by us than found by the jury.

Deliberately short. A list where everything is interesting is a list where
nothing is.

## Architecture

**Routing is data, not workflow branches.** Thresholds and approval chains live
in `routing_rules`; `resolve_approver_chain()` is the only place the rule is
expressed. n8n never reimplements it, so the workflow and the database cannot
drift. Changing a threshold is a migration containing an `update`, not a
workflow edit.

**The approval chain is snapshotted at submission.** `requests.approver_chain`
is copied from `routing_rules` when the request is created. A policy change
never alters the path of a request already in flight, and an approved request
never retroactively looks like it skipped a step.

**Derived values are computed server-side.** Leave duration comes from the dates
via `working_days()`, ignoring whatever the client sent. Routing depends on
`value`, so a client able to set it freely could route a long holiday to a
manager-only chain.

**Deterministic checks in SQL, prose from the LLM.** Date coherence, balance and
overlaps are arithmetic — computed in SQL, testable, free, never wrong. The
model receives those findings and writes the synthesis. Lower token cost, and
the failure mode is bad phrasing rather than a miscalculated balance.

## Security and compliance

**The AI never decides.** It annotates; the human approves. GDPR Article 22
restricts decisions produced solely by automated processing that significantly
affect someone — refusing leave on a model's say-so would sit squarely there.

**History is written by a trigger, not by the application.** A status change
*is* an event; no code path can produce one without the other. Had logging been
the application's job, any missed call would leave a silent hole in the audit
trail and corrupt the DORA measurement.

**`request_events` is append-only via trigger, not via RLS.** n8n connects with
the service role, which bypasses RLS entirely. A policy would not have stopped
it rewriting history; a trigger does. General rule: RLS protects against users,
triggers and constraints protect against your own services.

**...but rows remain deletable by cascade.** An audit log that can never be
erased is itself a GDPR problem. Retention and erasure delete the parent
request; individual events cannot be quietly removed.

**RLS recursion is solved with `security definer` helpers.** A policy on
`profiles` that reads `profiles` recurses infinitely. The helpers break the
cycle, and are safe because each reads only the caller's own context —
`caller_manages(x)` answers "am I x's manager", never "who manages x".

**The manager check is the *direct* manager.** A role check alone would let any
of NovaCorp's managers approve any employee's leave. The two-team seed is what
makes that class of bug visible in testing.

**Secrets are in an RLS-enabled table with zero policies**, readable only by the
service role. Supabase Vault is the production upgrade.

## Known limitations

- **pg_net is fire-and-forget.** A notification is lost if n8n is down, with no
  error raised in the database. Mitigation: a scheduled sweep for requests with
  no `notification_sent` event.
- **Public holidays are seeded to 2027 only.** Beyond that, `working_days()`
  silently counts holidays as workdays. Alsace-Moselle's two extra days are not
  modelled.
- **Leave spanning 31 December** is attributed entirely to the year of
  `start_date`.
- **Email is sandboxed** in Mailtrap, so fictitious addresses cannot reach real
  people. Production needs a real provider on a company domain with SPF, DKIM
  and DMARC — the domain-authentication wall is why the sandbox was chosen.
- **Authentication is email and password** with seeded accounts. SSO via
  Microsoft Entra ID is the evolution path: no password management, automatic
  deprovisioning, hierarchy syncable from the directory. Rejected here because
  fictitious employees have no real identity provider accounts.
- **`<input type="date">` renders in the browser's locale**, which the page
  cannot override — an `en-US` browser shows `mm/dd/yyyy` and silently accepts a
  transposed date. Mitigation: the form echoes the interpreted period back in
  full French ("du lundi 12 octobre au jeudi 15 octobre — 4 jours ouvrés")
  before submission. Any app with international users needs this.
