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
| Denny's | dennys.com/sites/default/files/.../Core_MENU_NutritionGuide.pdf (multiple dated URLs) | Cloudflare "Just a moment..." JS-challenge interstitial via plain curl/WebFetch. Via `fetch_rendered.js`, the real PDF download actually started (`page.goto: Download is starting`) but a companion diagnostic attempt (scripted download-capture via Playwright) failed because the sandbox's own egress proxy explicitly **denies** the CONNECT to `brunhild.challenges.cloudflare.com` (`connect_rejected — organization policy`), which is the domain Cloudflare's JS challenge needs to load to pass a headless browser through. | 2026-09-23, first attempt. **Important, not just a per-chain finding:** this means any Cloudflare-protected chain (this row, IHOP above) is structurally unsolvable via `fetch_rendered.js` in this sandbox specifically because the proxy policy blocks Cloudflare's own challenge domain — no amount of retrying or waiting will fix it from here. A human-in-the-browser seed (this file's whole purpose) or a sandbox network-policy change are the only real fixes. Worth flagging to the owner if Cloudflare-gated chains keep piling up. |
| Cracker Barrel | crackerbarrel.com/-/media/.../AllergenGuide.pdf and crackerbarrel.com/nutrition | Plain curl/WebFetch on the PDF got HTTP 429; `fetch_rendered.js` on the nutrition page landed on a **Vercel Security Checkpoint** ("We're verifying your browser") — a different bot-mitigation vendor than the Akamai/Cloudflare rows above, same category of block. | 2026-09-23, first attempt. |
| Red Lobster | redlobster.com/nutrition | WebFetch 302-redirects to a `validate.perfdrive.com` URL — a PerimeterX/ShieldSquare bot-mitigation validation endpoint (`ssk=support@shieldsquare.com` in the query string), not real page content. Did not follow the redirect (it's a bot-check flow, not content). | 2026-09-23, first attempt. Third distinct bot-mitigation vendor seen this pass (Akamai/Cloudflare/Vercel/PerimeterX all now represented across this file). |
| Applebee's | applebees.com/en/nutrition | `fetch_rendered.js` hit `net::ERR_CERT_AUTHORITY_INVALID` — ambiguous signature, could be a real TLS/cert issue on the site or a proxy MITM interaction, not clearly a deliberate bot wall like the rows above. | 2026-09-23, first attempt. Needs a second attempt (maybe plain WebFetch instead of rendered Chromium) before concluding anything. |
| Dairy Queen | dairyqueen.com/en-us/nutrition/ | Plain WebFetch: HTTP 403. Not yet tried via `fetch_rendered.js`. | 2026-09-23, first attempt. |
| Panda Express | pandaexpress.com/nutritioninformation | Plain WebFetch: HTTP 403. `fetch_rendered.js`: page renders but visible text comes back empty (Burger King-style signature, not diagnosed further). | 2026-09-23, first attempt. |
| Texas Roadhouse | texasroadhouse.com/pdfs/texas-roadhouse-nutritional-guide.pdf | Plain curl returned an HTML "Security Check" / CAPTCHA interstitial (title: "Security Check - Texas Roadhouse") instead of the PDF, not a network error | 2026-09-23, first attempt. Bot-check wall on the direct PDF URL; not yet tried through `fetch_rendered.js` with cookie-consent/interactive handling, which might get further — worth one more attempt before confirming. |
| Outback Steakhouse | outback.com/allergens | `fetch_rendered.js` hit an Akamai "Access Denied" page (errors.edgesuite.net reference code) — same signature format as the already-confirmed McDonald's block, different domain. Plain curl to the same URL got a normal HTTP 200 (page shell only, no embedded allergen data — client-side fetched), so the block appears specific to the rendered-browser path, not the domain generally. | 2026-09-23, first attempt. Strong match to a known hard-block signature but only tried once here; needs one more confirming attempt before moving to "Confirmed hard blocks." |
| Pizza Hut | pizzahut.com/menu/ingredients-and-allergens | Plain curl: `HTTP/2 stream 1 was not closed cleanly: INTERNAL_ERROR` (connection killed mid-handshake). WebFetch: HTTP 503. `fetch_rendered.js`: "upstream request failed." Three different fetch paths, three different failure modes, same domain. | 2026-09-23, first attempt. Ambiguous signature (could be proxy-layer interference rather than a deliberate bot wall) — needs a clean retry before drawing conclusions either way. |
| Wendy's | wendys.com/nutrition-allergens; order.wendys.com/us/en/national/menu | Not a bot block — a structural gap. The official allergen page has no downloadable matrix at all: it directs users to click into each item individually on the ordering site/app for a per-item "Nutrition & Allergens" link, no bulk export. The one PDF linked in the site footer ("Core Menu.pdf") is actually the **Wendy's UK menu** (UK-specific items, UK 14-allergen scheme with Celery/Mustard/Gluten(Barley)/Gluten(Rye) instead of US FDA Big 9) — `www.wendys.com` silently defaults to UK region content. Rendering `order.wendys.com/us/en/national/menu` (both plain `fetch_rendered.js` and a network-sniffing Playwright pass capturing every JSON XHR) surfaced only category names, no item content and no bulk JSON API to read from. | 2026-09-23, second attempt (first attempt logged in `ops_log` only, same conclusion: "no consolidated matrix found"). A real per-item crawl (dozens of individual order.wendys.com item pages) would be needed — treat as a bigger job than a normal chain import, not a quick retry candidate. |

Move a row from "Watching" to "Confirmed hard blocks" only after it repeats
with the same signature on a clean attempt (not immediately after another
attempt against the same domain, which can trigger throttling on its own).

**PAID-UPGRADE:** the manual-drop-in workflow above is the free
fallback. A paid scraping-proxy/headless-browser service (residential
or high-reputation IPs) would very likely get past Akamai-class blocks
like McDonald's programmatically instead of needing a human each time
— see `pipeline/PAID_UPGRADE_POINTS.md` #4.
