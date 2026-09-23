# Blocked sources — need a manual PDF/page drop-in

Chains or restaurants where automated fetching (WebFetch, `fetch_rendered.js`
with retries + consent-dismissal) has hit a **genuine, repeatable hard
block** — not a transient network error, not an unattempted chain, an actual
"we don't want bots here" wall confirmed across multiple real attempts.

These are one-time asks for the owner: open the page yourself in a real
browser, save the PDF or the page, and hand it to Claude Code to seed into
the database. Once seeded, treat it exactly like the chains solved via
official PDF (`official_matrix=true`) — same trust tier, just sourced by a
human instead of the pipeline.

**Do NOT add a row here for:**
- A chain not yet reached in the priority queue.
- A transient network error (`ERR_TOO_MANY_RETRIES` etc.) that hasn't been
  retried across at least 2 separate pipeline passes — could just be
  temporary proxy throttling, not a real block.
- An "empty text" result from `fetch_rendered.js` that hasn't been diagnosed
  (could be a slow SPA needing a longer settle wait, an undiscovered consent
  platform, etc.) — diagnose first, only log here once it's a confirmed dead
  end.

**When adding a row:** append it, commit (`git commit -m "..."`), and push —
this file is the durable record, not `ops_log` alone (ops_log is easy to
lose track of; this file is meant to be glanced at).

## Confirmed hard blocks — need a human-provided seed

| Chain | URL attempted | Block signature | First confirmed | Attempts |
|---|---|---|---|---|
| McDonald's | mcdonalds.com/us/en-us/full-menu/nutrition-explorer.html | Akamai WAF — "Access Denied" (errors.edgesuite.net reference code), not a JS-rendering issue — same result via plain WebFetch, curl, and `fetch_rendered.js` with a real rendered Chromium through the sandbox's own proxy | 2026-09-22 | 4 separate pipeline passes (16:53, 17:40, 19:41, 19:58 UTC) |

## Watching — not yet confirmed hard-blocked, still auto-retrying

| Chain | URL attempted | What happened | Notes |
|---|---|---|---|
| Taco Bell | tacobell.com/nutrition/allergen-info | `net::ERR_TOO_MANY_RETRIES` | Only tried once with the retry-backoff fix live; could be proxy throttling from repeated same-domain hits in one session rather than a real block. Needs a clean single-attempt pass to confirm either way. |
| Domino's | dominos.com/en/pages/content/nutritional/allergen-info | `net::ERR_TOO_MANY_RETRIES` | Same as Taco Bell — also hit by an earlier plain-WebFetch attempt in the same session, which may have tripped the throttling itself. |
| Burger King | bk.com/allergen | Page renders but visible text comes back empty | Undiagnosed — not yet known whether this is a consent overlay the known-selector list doesn't cover, a slower-loading SPA, or something else. Needs a screenshot or raw-HTML-length check on the next attempt, not just a re-log of "still empty." |
| Popeyes (location locator only — allergen PDF itself works fine) | locations.popeyes.com/co/denver and individual location pages | HTTP 503 on every attempt (directory listing and individual store pages alike), via both plain WebFetch and `fetch_rendered.js` | 2026-09-23, first attempt. This is the RBI-shared store-locator platform (same corporate family as Burger King, also on this list) — worth watching whether it's the same underlying block as bk.com/allergen. Fell back to a third-party directory (yellowpages.com) for addresses this pass, cross-reference not yet independently verified. Only tried once; needs a second clean attempt before drawing conclusions. |

Move a row from "Watching" to "Confirmed hard blocks" only after it repeats
with the same signature on a clean attempt (not immediately after another
attempt against the same domain, which can trigger throttling on its own).

**PAID-UPGRADE:** the manual-drop-in workflow above is the free
fallback. A paid scraping-proxy/headless-browser service (residential
or high-reputation IPs) would very likely get past Akamai-class blocks
like McDonald's programmatically instead of needing a human each time
— see `pipeline/PAID_UPGRADE_POINTS.md` #4.
