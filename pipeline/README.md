# Pipeline — how ALRG data gets collected

## `chains.source_document` — set this for every chain import, one time

Schema addition (2026-09-23): `chains.source_document` (text) holds the
real document/page the allergen data was transcribed from — e.g.
"Official Allergen Guide PDF on media.olivegarden.com
(media.olivegarden.com/en_us/pdf/allergen_guide.pdf, doc code
US_083126)". The app's "About this place" card shows this to the user
as the actual source of the allergen information, per the owner's
request that this be visible, not just a generic category badge.

**Why chain-level, not per-item:** the obvious place to put a citation
is `menu_items.note`, and that's where it lived originally — but
`note` is also where the ingredient backfill (see
`INGREDIENT_BACKFILL.md`) writes real per-item ingredient text. Those
two uses collide: as soon as a chain's items get real ingredients, any
citation that was sitting in `note` gets overwritten and the source
becomes unrecoverable. A chain's source document is the same for every
item and every location anyway, so it belongs on `chains`, set once,
immune to what happens in `menu_items.note` afterward.

**When importing or re-analyzing a chain**, set
`chains.source_document` to a one-line description of the real
document/page used — the same detail already captured in the
`chain_imported` ops_log entry's `source` field, just copied up to a
queryable column instead of buried in a JSON blob. Backfilled for all
9 already-analyzed chains from their existing ops_log entries
(2026-09-23) — this is a real record of what was actually fetched, not
guessed after the fact. Do the same for every future chain at import
time, not as a later backfill pass.

**Independent (non-chain) restaurants get the same field on
`restaurants` instead** — `restaurants.source_document`, since there's
no `chains` row to attach it to. Set this at extraction time for every
independent restaurant, and **be honest about source quality, not just
presence**: a restaurant's own menu page is strong; press coverage
(Michelin Guide, food blogs) or a third-party listing (allmenus.com,
Yelp, etc.) used because the restaurant's own site was unreachable is
real but weaker, and the citation should say so explicitly (e.g. "the
restaurant's own site returned errors when fetched; compiled from
press coverage instead — verify with staff") rather than reading the
same as a restaurant-published source.

**Known issue found 2026-09-23, fixed but worth knowing about:** the
original repo setup seeded 4 Denver restaurants (Copper Kettle
Kitchen, Maria's Taqueria, Golden Lotus, Verde Bowl Co. — restaurant
ids 1–4) as hardcoded placeholder data ("1 Demo St" etc.) to make the
app demoable before the pipeline existed. They were never touched by
real extraction but carried `data_source=ai_pipeline` and
`verified=true` (3 of 4), presenting fabricated menu/allergen data
with the same authority as real, audited chains. Corrected 2026-09-23:
`verified` set to false and `source_document` set to an explicit
"this is placeholder demo data, not real" label on all 4 — full
removal vs. keeping them clearly labeled as demo content is the
owner's call, not made here. If you ever see a restaurant with a
"Demo St" address or similarly obviously-fake data, treat it the same
way — flag it honestly, don't silently publish over it.

---

## Override: highly-refined frying oil is not an allergen trigger

The account-level `allergen-analyzer` skill's ingredient-matching table
lists "peanut oil" as a `peanuts` trigger with no exception. That's wrong
for frying/cooking oil specifically: highly refined peanut oil has the
allergenic protein removed and is exempt from major-allergen labeling
under FDA/FALCPA (21 CFR 101.100(a)(3)) — this is exactly why chains that
fry everything in peanut oil (Chick-fil-A, Five Guys) still publish
peanut-free menus, and why our own Chick-fil-A data (sourced from their
official PDF) correctly has zero `peanut` flags despite frying in it.

**When running allergen-analyzer for ALRG, override that one table
entry:** do not flag `peanuts` on a menu item just because it's noted as
fried/cooked in peanut oil. Only flag `peanuts` if the source indicates
unrefined/cold-pressed/gourmet peanut oil specifically, a genuine peanut
ingredient (butter, pieces, sauce) is present, or the restaurant's own
official source explicitly calls out peanut for that item anyway (trust
an explicit official source over this default). The same logic applies
to sesame oil if it ever comes up — refined sesame oil is a closer call
(less universally exempt than peanut oil) so default to the cautious
flag there unless the source is explicit either way.

This was found 2026-09-22 during an owner UI review, before it caused any
actual bad data (audited the full menu_items table — no published item
was mis-flagged from this specific pattern yet). It's a latent-bug fix,
not a data correction. The account skill itself can't be edited from
here (this repo has no access to claude.ai skill storage) — this note is
the durable fix for ALRG's pipeline specifically, since the Routine
already reads this file every run regardless of what the account skill
says.

---

## Capture real ingredients, not just allergen flags

The owner wants menu items in the app to expand and show real ingredient
text (2026-09-22 request), not just the allergen flag badges. Right now
`menu_items.note` is mostly empty or a bare category/citation label — see
`pipeline/INGREDIENT_BACKFILL.md` for the full tracked backlog, per-chain
source status, and the hard rule against fabricating ingredient text.

**For every chain or restaurant worked from now on** (new imports AND
whenever `INGREDIENT_BACKFILL.md` still lists a chain as not started):
look for a genuine ingredient-statement document — often called
"ingredient guide," "ingredient statement," or "product ingredients" —
**separate from the allergen matrix PDF**. Most chains publish these as
two different documents; the allergen chart alone usually isn't enough
(it's a compliance table, item × allergen columns, not prose ingredient
text). If found, set `note` to the real ingredient text for that item
(trimmed, not the whole document dumped in). If no such document exists
publicly after a real search, leave `note` as whatever's already there
and update the backlog table with "no source found" — never invent
ingredients from the item name or general knowledge.

Priority: work this backlog interleaved with (not necessarily before)
the normal chains → metros → maintenance order — an hourly pass with
nothing new to import in either queue is a good time to pick the next
"not started" row in `INGREDIENT_BACKFILL.md`. Start with Subway (real
ingredient PDF already confirmed to exist, URL in that file) since it's
the cheapest proven win.

---

The service validates and publishes on its own. The owner is not a
per-batch approval gate — see CLAUDE.md's "Standing conventions" for the
exact (short) list of things that still escalate. The owner's real
checkpoint is the live app's community verifications, reviewed periodically
— not this pipeline.

Priority order, every time the pipeline runs (manually or via the Routine):
1. Chains first — one unanalyzed row in `chains` covers every location of
   that chain. Highest leverage for reaching "nationwide" fast.
   Flow: chain-menu-importer → qa-allergen-auditor → db-publisher.
2. Then metros — the next queued metro by rank.
   Flow: restaurant-menu-extractor → allergen-analyzer →
   qa-allergen-auditor → db-publisher.
3. Both empty → maintenance mode: freshness sweep on the oldest data.

A PASS or PASS WITH CORRECTIONS audit publishes immediately, no owner
review. Only a second consecutive FAIL on the same target opens a
needs-owner board card — see qa-allergen-auditor's retry rule.

## Running it

A) INTERACTIVE: owner types "Run tonight's data batch" in Claude Code and
   it works through the priority order above once.

B) CLOUD ROUTINE — the default, since the owner has a Pro/Max plan. A saved
   Claude Code cloud config (this repo + the Supabase connector) that fires
   on a schedule from Anthropic's infrastructure, laptop closed or not, and
   draws on normal subscription usage rather than separate API billing.
   Create with `/schedule` in Claude Code, or at claude.ai/code/routines.
   Suggested setup — schedule at the minimum interval (hourly) so the queue
   clears as fast as the audit pipeline can sustain:
     "Every hour, follow CLAUDE.md's autonomous priority order exactly:
      chains first, then metros, then maintenance mode once both are
      empty. Publish on PASS or PASS WITH CORRECTIONS with no owner
      review. Only open a needs-owner card on a second consecutive audit
      fail for the same target, or a safety-relevant community report.
      Update the GitHub Projects board per CLAUDE.md."
   One-time setup in the routine's environment settings: widen network
   access beyond the default "Trusted" allowlist (Custom or Full) — the
   extractor and chain-importer both need to reach ordinary restaurant and
   chain websites, not just package registries. Test with "Run now" before
   trusting the hourly fire. Watch subscription usage at
   claude.ai/settings/usage for the first few days at this cadence and dial
   the interval back (e.g. every 4 hours) if it's burning faster than
   expected — hourly is the ceiling, not a fixed requirement.

C) GITHUB ACTIONS (fallback only, not the default): use only if Routines
   are ever unavailable. Enable .github/workflows/nightly.yml and add repo
   secrets ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY. Bills
   separately per token instead of using the subscription.

State lives in the database (`metros`, `chains`, `ops_log`), not in chat,
so all three modes are interchangeable — switch freely without losing
progress. run_batch.py documents mode C's exact orchestration.

## Restaurant discovery in the cloud Routine — known gap (as of 2026-09-22)

The Routine's cloud sandbox does not have the `places_search` /
`places_map_display_v0` tools that `restaurant-menu-extractor` normally
uses, and a single Overpass (OSM) call to `overpass-api.de` failed at the
network-proxy layer on the first hourly run — not a hard block (other
domains worked fine), so it's worth retrying rather than skipping straight
to WebSearch. Priority order for restaurant discovery until this is
properly fixed:
1. Overpass API, `overpass-api.de` first (freshest data) — retry 2-3x
   with a short backoff before giving up on it; a single transient proxy
   failure isn't grounds to abandon the run's primary source.
2. Only if Overpass fails outright — fall back to WebSearch + WebFetch
   per-restaurant (what the first run did). This works but is slow and
   caps how many restaurants one hourly firing can cover.
Do not add a paid places API (Google Places, Foursquare, etc.) without
the owner's explicit approval — see "Standing conventions" in CLAUDE.md
("everything free-tier unless the owner explicitly approves a cost").
Google Places' terms also restrict caching/redistributing place data,
which cuts against this project's own data-licensing rule; if this ever
gets revisited, Overture Maps' open static dataset (no key, no per-call
cost, explicitly the kind of source CLAUDE.md already prefers) is the
better fit than a paid vendor API, but needs real engineering work
(DuckDB + spatial queries against Overture's S3/Azure release) that
hasn't been built yet.

## Chain allergen pages that are JS-rendered SPAs — use fetch_rendered.js

Most big chains (McDonald's, Starbucks, Taco Bell, Burger King,
Chick-fil-A, Domino's, and likely most of the remaining unanalyzed
`chains` rows) publish their real per-item allergen matrix through a
React/JS nutrition tool, not static HTML — plain WebFetch/curl only see
an empty app shell, which reads as "blocked" but isn't actually a hard
wall. **This is not a missing-tool problem.** The Routine's cloud sandbox
already has Chromium + Playwright preinstalled at `/opt/pw-browsers`; the
first attempt to use it (2026-09-22 run) failed only because Playwright
doesn't automatically route through the sandbox's egress proxy the way
curl/WebFetch do, so Chromium tried to connect directly and hit TLS/
timeout errors.

Use `pipeline/fetch_rendered.js` instead of hand-rolling a fetch script
each run:
```
PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers NODE_PATH=/opt/node22/lib/node_modules node pipeline/fetch_rendered.js "<url>" [extraWaitMs]
```
(Playwright is installed globally in the sandbox, not as a repo
dependency — `NODE_PATH` is required or `require('playwright')` fails.
Confirmed working 2026-09-22; if a future sandbox image changes this,
`npm root -g` finds the real path.)

It launches Chromium pointed at the sandbox's proxy (`$HTTPS_PROXY`, or
`http://127.0.0.1:37265` if unset — the port changes between sandbox
instances, check `curl -s "$HTTPS_PROXY/__agentproxy/status"` if the
env var is somehow unset), trusts the proxy's MITM cert
(`ignoreHTTPSErrors`), waits for DOM content plus a fixed settle window
(SPAs keep background XHR alive forever, so waiting for `networkidle`
usually just times out), and prints the page's rendered *visible text*
(not raw HTML) to stdout.

**Validated 2026-09-22 against 6 previously-blocked chains** — the
proxy-routing fix works (Chromium now actually reaches and renders these
pages), but real-world sites still throw a mix of *different* obstacles
on top:
- **Chipotle** — rendered real page content successfully, no extra work
  needed.
- **Starbucks** — rendered a real page, but landed on a cookie-consent
  interstitial instead of the allergen content.
- **Burger King** — rendered but visible text came back empty; not yet
  diagnosed, don't assume it's the same issue as Starbucks.
- **Taco Bell, Domino's** — `net::ERR_TOO_MANY_RETRIES`. Looked like the
  sandbox's shared proxy IP getting rate-limited after repeated hits in a
  short window (both domains had also been hit by earlier plain WebFetch
  attempts in the same session).
- **McDonald's** — "Access Denied" (Akamai WAF), even through the proxy
  with a real rendered browser. This looks like real bot/IP-reputation
  detection, not a config problem — likely not fixable without a
  residential-style egress IP, which is out of scope for now. Don't keep
  re-attempting McDonald's every single pass once it's been logged
  blocked; retry only occasionally (e.g. once every several passes) in
  case Akamai's rules change.

**Fixed 2026-09-22, same day** — `fetch_rendered.js` now handles two of
those automatically, no caller changes needed:
- **Cookie-consent overlays** (the Starbucks pattern): after the settle
  wait, it checks a short list of known consent-platform selectors
  (OneTrust, Cookiebot, TrustArc, Quantcast) plus a text-based fallback
  (button labeled "Accept"/"Agree"/"Allow All"/etc.), clicks through if
  found, waits briefly, and re-reads the page. A stderr line
  (`dismissed a cookie-consent overlay...`) confirms when this fired.
- **Transient network errors** (the Taco Bell/Domino's pattern): `goto`
  now retries up to 3 times with backoff (0s, 3s, 8s) specifically for
  the error codes seen in practice (`ERR_TOO_MANY_RETRIES`,
  `ERR_CONNECTION_RESET`, `ERR_CONNECTION_CLOSED`, etc.) before giving
  up on that URL for the pass. A genuinely non-retryable error (like
  McDonald's "Access Denied", which is an HTTP 403 page, not a network
  failure) is not retried — it fails fast instead of wasting time.

Not yet fixed, still needs live diagnosis in the sandbox: **Burger
King's empty-text result** — unclear if it's a slower-loading SPA (needs
a longer settle wait), a different consent platform not in the known
list, or something else. Next run that tries Burger King should capture
more diagnostic detail (e.g. a screenshot or the raw HTML length) rather
than just re-logging "still empty."

If a chain's allergen page still comes back genuinely empty/blocked
after a real attempt, treat it as blocked for that pass — don't
retry-loop indefinitely, log the specific failure mode to `ops_log` (not
just "blocked" — note which of the above patterns it was, so the next
pass doesn't have to rediscover it), and move on. Never fall back to
guessing chain allergen data from third-party aggregators — that
remains a hard no per `chain-menu-importer`.

## Hard blocks that need a human — pipeline/BLOCKED_SOURCES.md

Some blocks (McDonald's Akamai WAF "Access Denied" is the confirmed case
so far) are not a rendering or retry problem — no amount of proxy/consent/
backoff tuning gets past them, because the site is deliberately refusing
automated traffic before content ever loads. For those, the only real fix
is a human opening the page in their own browser once and handing Claude
Code the PDF/page to seed manually — not an ongoing scraping arms race.

`pipeline/BLOCKED_SOURCES.md` is the durable record of these. Read it
before re-attempting a chain that's blocked before (skip chains already
listed under "Confirmed hard blocks" — don't burn a pass re-proving what's
already known; only retry those occasionally, e.g. once every several
passes, in case the site's rules changed). When a chain hits the *same*
block signature on a second separate pass (not immediately after a prior
attempt against the same domain in the same session, which can be
throttling rather than a real block), move it from "Watching" to
"Confirmed hard blocks" in that file — append the row, commit, and push.
This is a repo file specifically so it's easy for the owner to glance at
and act on, not just another `ops_log` row.
