# Pipeline — how ALRG data gets collected

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
on top, each needing its own handling rather than one generic fix:
- **Chipotle** — rendered real page content successfully.
- **Starbucks** — rendered a real page, but landed on a cookie-consent
  interstitial instead of the allergen content. Next step: have the
  script detect a consent/cookie overlay and click through it (common
  button text: "Agree", "Accept", "Accept All") before extracting text.
- **Burger King** — rendered but visible text came back empty; not yet
  diagnosed, don't assume it's the same issue as Starbucks.
- **Taco Bell, Domino's** — `net::ERR_TOO_MANY_RETRIES`. Possibly the
  sandbox's shared proxy IP getting rate-limited/blocked after repeated
  hits in a short window (both domains had also been hit by earlier
  plain WebFetch attempts in the same session) — try spacing out
  repeated attempts at the same domain within one run, or treat a
  second `ERR_TOO_MANY_RETRIES` on the same domain within a run as a
  sign to stop retrying that domain this pass.
- **McDonald's** — still "Access Denied" (Akamai WAF), even through the
  proxy with a real rendered browser. This looks like real bot/IP-
  reputation detection, not a config problem — likely not fixable
  without a residential-style egress IP, which is out of scope for now.
  Don't keep re-attempting McDonald's every single pass once it's been
  logged blocked; retry only occasionally (e.g. once every several
  passes) in case Akamai's rules change.

If a chain's allergen page still comes back genuinely empty/blocked
after a real attempt, treat it as blocked for that pass — don't
retry-loop indefinitely, log the specific failure mode to `ops_log` (not
just "blocked" — note which of the above patterns it was, so the next
pass doesn't have to rediscover it), and move on. Never fall back to
guessing chain allergen data from third-party aggregators — that
remains a hard no per `chain-menu-importer`.
