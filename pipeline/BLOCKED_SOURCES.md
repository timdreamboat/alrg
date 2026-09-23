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
| Starbucks | starbucks.com/menu/nutrition/top-allergens | `fetch_rendered.js` renders a real page (HTTP 200, ~180-200KB HTML, cookie-consent overlay dismissed successfully) but `document.body.innerText` comes back empty even after a 20s settle wait — real content sits in the DOM (confirmed via a direct `page.content()` check) but never becomes visible text, unlike the Burger King pattern where text is simply absent. A same-session repeat diagnostic attempt then hit `net::ERR_TOO_MANY_RETRIES`, which could be proxy throttling from the repeated same-domain hits rather than a real block. | 2026-09-23, first attempt (two same-session tries, second may have been self-inflicted throttling — needs a clean single attempt on a future pass, ideally checking whether the content is gated behind a `visibility:hidden` class (e.g. a `fonts-loading` pattern) that a longer wait or a forced class removal would clear, before concluding it's a harder block. |
| Jersey Mike's | jerseymikes.com/menu/food-allergy | `fetch_rendered.js` renders the page (HTTP 200) but `document.body.innerText` comes back empty/near-empty, same signature as the Starbucks and Burger King rows above — content likely present in the DOM but not surfacing as visible text (hidden behind a loading class, or gated by a client-side toggle like Chick-fil-A's Allergens tab). Not diagnosed further this pass (no screenshot or raw-HTML-length check taken). | 2026-09-23, first attempt. WebFetch on the same URL also returned empty content. Needs a diagnostic pass (screenshot / HTML length / DOM inspection) before a second clean attempt, per the "diagnose before confirming" rule above. |
| IHOP | ihop.com/en/nutrition/allergen-info | `fetch_rendered.js` (real Chromium through the sandbox proxy) hit a Cloudflare interstitial: "Sorry, you have been blocked" / "This website is using a security service to protect itself from online attacks", with a Cloudflare Ray ID. Plain curl on the known allergen-handout PDF URL also got a 403. | 2026-09-23, first attempt. Clean, deliberate bot-block signature (same category as McDonald's Akamai block, different vendor — Cloudflare here), but only tried once so filed as Watching per the two-clean-attempts rule, not moved straight to confirmed. |
| Texas Roadhouse | texasroadhouse.com/pdfs/texas-roadhouse-nutritional-guide.pdf | Plain curl returned an HTML "Security Check" / CAPTCHA interstitial (title: "Security Check - Texas Roadhouse") instead of the PDF, not a network error | 2026-09-23, first attempt. Bot-check wall on the direct PDF URL; not yet tried through `fetch_rendered.js` with cookie-consent/interactive handling, which might get further — worth one more attempt before confirming. |
| Outback Steakhouse | outback.com/allergens | `fetch_rendered.js` hit an Akamai "Access Denied" page (errors.edgesuite.net reference code) — same signature format as the already-confirmed McDonald's block, different domain. Plain curl to the same URL got a normal HTTP 200 (page shell only, no embedded allergen data — client-side fetched), so the block appears specific to the rendered-browser path, not the domain generally. | 2026-09-23, first attempt. Strong match to a known hard-block signature but only tried once here; needs one more confirming attempt before moving to "Confirmed hard blocks." |
| Pizza Hut | pizzahut.com/menu/ingredients-and-allergens | Plain curl: `HTTP/2 stream 1 was not closed cleanly: INTERNAL_ERROR` (connection killed mid-handshake). WebFetch: HTTP 503. `fetch_rendered.js`: "upstream request failed." Three different fetch paths, three different failure modes, same domain. | 2026-09-23, first attempt. Ambiguous signature (could be proxy-layer interference rather than a deliberate bot wall) — needs a clean retry before drawing conclusions either way. |

Move a row from "Watching" to "Confirmed hard blocks" only after it repeats
with the same signature on a clean attempt (not immediately after another
attempt against the same domain, which can trigger throttling on its own).

**PAID-UPGRADE:** the manual-drop-in workflow above is the free
fallback. A paid scraping-proxy/headless-browser service (residential
or high-reputation IPs) would very likely get past Akamai-class blocks
like McDonald's programmatically instead of needing a human each time
— see `pipeline/PAID_UPGRADE_POINTS.md` #4.
