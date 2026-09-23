# CLAUDE.md — ALRG project context for Claude Code

Read this first in every session. The owner (Tim) is non-technical for this
project and works by giving plain-English instructions. Your job is to do the
work end-to-end and explain outcomes in one or two sentences, not code detail.

## What ALRG is
Allergen Lifestyle Restaurant Guide (alrgfree.com). Analyzes restaurant menus
and gives each restaurant a 0–100 confidence score per user allergen profile.
Tiers: 80–100 High Confidence / 50–79 Proceed with Care / 0–49 High Risk.
Positioning is ALWAYS "discovery tool, not a safety guarantee" — never remove
disclaimers, never overstate certainty. This is a safety-adjacent product:
false "CLEAR" flags are the dangerous error class. When in doubt, flag more
cautiously.

## Architecture (v2 — fresh start Sept 2026; ignore any pre-2026 build)
- Database: Supabase (Postgres). Schema in `supabase/schema.sql`. Public reads
  via RLS + anon key; ALL writes via service role only.
- Consumer app: `app/` — no-build static PWA (vanilla JS + Leaflet/OSM),
  hosted on GitHub Pages. `app/config.js` holds the Supabase URL + anon key
  and is the only file the owner edits.
- Scoring: client-side, spec v1 (see `docs/SCORING.md`). If you change scoring,
  bump the version, update the doc, and note it in ops_log.
- Pipeline: `pipeline/` — batch collection using the owner's Claude skills
  (restaurant-menu-extractor → allergen-analyzer → qa audit → publish).
- Data licensing rule: store external place_id as join key only. Do NOT cache
  or redistribute proprietary map-vendor content. Base place data comes from
  open sources (Overture/OSM) or the owner's own collection. Menus + allergen
  analysis are our own derived work and are the proprietary core.
- Two-part data model (owner decision, 2026-09-22): once Google Places is
  paid and wired in, Google is the source for map/location/contact metadata
  (geocoding, place discovery, phone, website, rating) and ALRG's own
  pipeline stays the sole source for menu + allergen data, always — Google
  has no per-item allergen data to offer anyway. Combined per restaurant via
  place_id, never per field; neither source originates the other's columns.
  See `pipeline/README.md` ("Restaurant discovery in the cloud Routine") and
  `pipeline/PAID_UPGRADE_POINTS.md` #3 for the full design.

## Standing conventions
- Everything free-tier for now, with one exception: the plan is for
  ALRG to run on a paid subscription once it goes live (2026-09-23
  owner decision) — the database (Supabase) is the one thing meant to
  stay free either way. Every place currently working around a paid
  API with a free substitute (map tiles, geocoding, restaurant/places
  discovery, JS-render-blocked chain sourcing) is deliberately marked
  `PAID-UPGRADE:` in code/docs and tracked in full in
  `pipeline/PAID_UPGRADE_POINTS.md` — check that file before adding a
  new free-tier workaround, and swap the real thing in there once a
  subscription actually exists. Until then, still don't add a new paid
  API on your own initiative outside what's already tracked — flag it
  the same way instead.
- All data writes go through the publisher path with provenance + ops_log entry.
- The service validates and publishes autonomously — the owner is NOT a
  per-batch approval gate. A qa-allergen-auditor PASS or PASS WITH
  CORRECTIONS auto-publishes with no owner review. This is the operating
  mode until nationwide coverage, not a temporary shortcut.
- The owner's actual checkpoint is the live app: users submit community
  verifications (`verifications` table), and the owner reviews the pending
  queue periodically — today via the Supabase table editor, with an
  owner-only in-app review view as a near-term build (see Current phase).
  Don't wait on the owner for anything short of a genuine exception below.
- Exactly two things escalate and wait for the owner — everything else is
  autonomous:
  (1) qa-allergen-auditor FAILs twice in a row on the same restaurant/chain
      after one automatic retry (see that skill for the retry rule) — this
      signals a systemic problem worth a human look, not routine caution.
  (2) Any safety-relevant community report (`reaction_reported`) — never
      auto-resolved, ever.
  Everything else — ordinary PASS/PASS-WITH-CORRECTIONS batches, a single
  audit fail that a retry clears, routine ops_log entries — proceeds without
  waiting, because requiring approval on those would just recreate the
  manual bottleneck automation is supposed to remove.
- Commit style: small commits, plain-English messages. Open a PR for
  anything touching scoring or schema (those two genuinely need owner eyes);
  published restaurant/menu data does not need a PR, it needs to pass audit.

## Scheduling — how the ongoing rhythm actually runs
The batch pipeline runs as a Claude Code **Routine** (Anthropic cloud, fires
on a schedule, works with the laptop closed) — the owner has a Pro/Max plan,
so this is simply available, not something to gate on. Schedule it at the
minimum interval (hourly) so the queue clears as fast as the audit/publish
pipeline can sustain — "as automated as possible" means cadence, not just
unattended-ness. Full detail and the exact routine prompt: `pipeline/README.md`.
GitHub Actions (`.github/workflows/nightly.yml`) exists only as a fallback
if Routines are ever unavailable; don't mention it otherwise.

Each firing, in priority order (superseded in full detail by
`pipeline/COVERAGE_PLAN.md`, owner decision 2026-09-23 — read that file,
this is just the summary):
1. Any chain in `chains` with `analyzed_at IS NULL`? Run chain-menu-importer
   on it — highest leverage for nationwide presence (one import covers every
   location of that chain).
2. Else, any US state with `count(restaurants) < 50` that has an already-
   analyzed chain not yet expanded into it? Find that chain's real
   locations there (Overpass brand-tag query first, chain's own store
   locator as fallback) and copy its already-audited menu into a new
   `restaurants` row per location — no fresh menu/allergen analysis, ever,
   for a chain location; the chain's one-time analysis already covers
   every location of it nationwide.
3. Else, any US state still under 50 after chain expansion is exhausted
   for it? Run the restaurant-menu-extractor → allergen-analyzer →
   qa-allergen-auditor → db-publisher flow on independents there, using
   that state's `metros` row(s) as the starting point.
4. Else — every state at 50+ and the chains backlog empty, nationwide
   coverage reached for the current target — switch to maintenance mode:
   a freshness sweep on the oldest-`last_reviewed` restaurants. Report
   "coverage complete, entering maintenance mode" once; don't repeat that
   report every subsequent firing.

A Routine run has no local files and no interactive permission prompts, so
everything it needs — schema, skills, this file — must already be committed
to the repo, and its Supabase writes go through the connector/service key,
not a locally-typed one.

## Common owner commands and what they mean
- "Run tonight's data batch" → manual trigger of the same priority order the
  Routine uses (chains, then metros, then maintenance). Update statuses,
  write ops_log, summarize: "[work done]. X restaurants, Y items added. Z
  audit exceptions (list, if any)."
- "Show me the ops report" → query Supabase for coverage by state, freshness,
  audit stats, pending verification count; present a short readable summary.
- "Show me pending verifications" → read the `verifications` table where
  status='pending' and summarize for owner review; apply the owner's
  approve/reject decision back to the row when told.
- "Deploy" → push to main; GitHub Pages serves `app/` automatically.

## The project board (GitHub Projects — single source of truth)
The owner tracks "everything being built" on a GitHub Projects board in this
repo (created once by hand; see SETUP.md Part E). No separate task tool.
You (Claude Code) are responsible for keeping it current using the `gh` CLI
— the owner should rarely need to touch it directly.

Columns: Backlog · In Progress · In Review · Done.
Labels: `pipeline`, `app`, `scoring`, `ops`, `audit-flag`, `needs-owner`.

Conventions — do these without being asked:
- Starting any multi-step task → `gh issue create` with a short title, add to
  the board, move to "In Progress". Close it (moves to "Done") when finished
  — this includes ordinary autonomous batches; "autonomous" means no owner
  approval needed, not that the board goes dark.
- The two genuine exceptions from Standing Conventions (repeated audit fail,
  safety-relevant community report) → open an issue labeled `audit-flag` or
  `needs-owner` and leave it in "In Progress" — never close these yourself.
  Nothing else gets this label; routine audit corrections are not exceptions.
- End of a batch run → update or close the relevant issue with the one-line
  summary (chains/metros done, restaurants/items added, audit stats) instead
  of only printing it to the terminal, so the board reflects reality even if
  the owner wasn't watching.
- Useful commands: `gh issue create -t "..." -b "..." -l pipeline`,
  `gh issue list`, `gh project item-list <number> --owner <user>`,
  `gh issue close <n> -c "done: ..."`.
- If the owner asks "show me the board" or "what's in progress", run the
  `gh` list commands and summarize in plain English — don't just dump raw
  output.

## Repo & browser access (owner's local machine)
- The owner authenticates the GitHub CLI once (`gh auth login`) so you can
  create repos, issues, PRs, and manage the project board without any
  copy-pasted tokens.
- Claude for Chrome (separate browser extension, not this CLI) may be
  available to the owner for browser-side tasks (checking the live app,
  filling out store-listing forms later). It is independent of you; don't
  assume it's active unless the owner says so.

## Current phase
Phase 0/1: foundation + factory, now running autonomously. Denver seed data
is live. Next milestones:
(1) chain-menu-importer built and chains backlog seeded (done this pass),
(2) Routine scheduled hourly and proven for a day unattended,
(3) owner-only in-app view for reviewing pending verifications (interim:
    Supabase table editor) — this is the owner's real checkpoint, prioritize it,
(4) restaurant portal,
(5) nationwide coverage — every US state at 50+ unique restaurants, see
    `pipeline/COVERAGE_PLAN.md` (added 2026-09-23; metros seeded for all
    50 states this pass),
(6) once every state is at 50+ and chains queue is empty: freshness-sweep
    maintenance mode.
