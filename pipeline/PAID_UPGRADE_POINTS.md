# Paid upgrade points — swap these in once a subscription exists

Owner decision, 2026-09-23: ALRG runs on a paid subscription once it
goes live. The database (Supabase) is the one thing meant to stay free
regardless. Everything below is a place where the app or pipeline
currently uses a free substitute *specifically because* the real thing
costs money — each is tagged `PAID-UPGRADE:` in the actual code/docs so
it's easy to find by search, and listed here with what to actually do
once billing exists.

**Don't wire in a paid key speculatively.** These stay on their free
substitute until the owner says the subscription is in place. This file
is the map for that day, not a green light to act now.

**2026-09-23 update — DB schema and UI are now built to match what
these upgrades would deliver**, so the *only* remaining step for most
of these is pasting a real key into `app/config.js` (#1/#2) or running
a pipeline enrichment pass (#3/#5). No further schema or template
changes should be needed. Every new column is null for every row
today, on purpose — that's the honest state until real data exists.

---

## 1. Map tiles — `app/index.html`, `initMap()`

**Status: code ready, gated on a key.** `initMap()` checks
`C.MAPBOX_TOKEN` (in `app/config.js`) and uses real Mapbox raster tiles
(`mapbox/light-v11`) when set, Esri's free tiles otherwise. Paste a
real token from a paid Mapbox account into `app/config.js` and the map
switches automatically — no other code change.

## 2. Geocoding — `app/index.html` (`geocodeQuery`, used by `onboardSearch` and `geocodeAndFly`)

**Status: code ready, gated on the same key.** Both onboarding search
and the sidebar location search now go through one shared
`geocodeQuery()` function, which uses Mapbox Geocoding when
`C.MAPBOX_TOKEN` is set, Nominatim otherwise. Same token as #1 covers
both — no separate geocoding key needed if using Mapbox.

## 3. Restaurant/place discovery — `pipeline/README.md`, "Restaurant discovery in the cloud Routine"

**Status: DB ready (`restaurants.phone`, `.website`, `.rating`,
`.rating_count`, `.place_id` all exist and are null until populated),
pipeline work not started.** Currently WebSearch + WebFetch per-
restaurant, with Overpass (OSM) as a first attempt when reachable —
explicitly chosen over Google Places earlier in this project because
of cost. This is the slowest, lowest-coverage part of the whole
pipeline (one hourly firing might only add 1-2 restaurants this way)
and the main reason metro coverage (e.g. New York's 4 restaurants) is
so thin.

**Upgrade to:** Google Places API (Nearby Search / Text Search) once
subscription funds exist — this is the highest-leverage upgrade on
this list, since it directly unblocks nationwide metro coverage
instead of the current one-restaurant-at-a-time web search grind. When
wiring this in, populate the four new columns from the Places response
(`formatted_phone_number`→phone, `website`→website, `rating`→rating,
`user_ratings_total`→rating_count) — the app already reads and
displays all four the moment they're non-null, including using
`rating` as the real popularity sort (see `app/index.html`
`renderList()`) in place of the distance fallback it uses today. Note
Google Places' terms restrict caching/redistributing place data
long-term — keep using `place_id` as a join key only (already how
`restaurants.place_id` is defined), don't cache descriptions/photos/
reviews, consistent with the data-licensing rule already in CLAUDE.md.

**Owner decision, 2026-09-22 — the exact division of labor, not just a
swap.** Google is never the allergen source; it doesn't offer that data
for arbitrary restaurants anyway. The two-part model is:
- Google Places → discovery + the identity/contact row: `place_id`,
  name, address, lat/lng, phone, website, rating, rating_count. Live
  lookup only, per the licensing rule above.
- Our existing restaurant-menu-extractor → allergen-analyzer →
  qa-allergen-auditor → db-publisher chain → menu_items, flags,
  source_document, for every restaurant Places discovers, unchanged
  from how it works today.
- Combined per restaurant (same row), not per field — one source never
  originates the other's columns. Full detail and the reasoning is in
  `pipeline/README.md` under "Restaurant discovery in the cloud
  Routine," which is the doc to actually build from when this lands.

## 4. JS-rendered / bot-blocked chain allergen pages — `pipeline/BLOCKED_SOURCES.md`

**Status: not started, no DB/UI change needed for this one** — it's a
pipeline-tooling upgrade only. `pipeline/fetch_rendered.js` (Playwright
through the sandbox's own proxy) works for plain JS-rendering issues,
but can't get past a real WAF/bot-detection block like McDonald's
Akamai "Access Denied," which is an IP-reputation problem a config fix
can't solve.

**Upgrade to:** A paid scraping-proxy/headless-browser service
(Browserless, ScrapingBee, Bright Data, etc.) with residential or
higher-reputation IPs. Would very likely unblock McDonald's and any
other chain in `BLOCKED_SOURCES.md`'s "Confirmed hard blocks" section.
Lower priority than #3 — this affects a handful of specific chains,
not the whole metros pipeline.

## 5. Phone number / website / rating per restaurant

**Status: DB and UI fully ready, same columns as #3** —
`restaurants.phone`/`.website`/`.rating`/`.rating_count`. The "About
this place" card shows a real `tel:` link, a real external website
link, and a ★ rating with review count the moment any of these are
non-null, and quietly keeps showing the honest "not tracked yet" note
only for whichever of phone/website is still missing. This is the same
upgrade as #3 (Google Places gives all of it in one response) — no
separate work needed once that's wired in.

---

## How to use this when the day comes

1. Search the codebase for `PAID-UPGRADE:` to find every exact spot.
2. #1/#2 (map + geocoding): paste a real `MAPBOX_TOKEN` into
   `app/config.js`. Done — nothing else to change.
3. #3/#5 (places discovery + phone/website/rating): the bigger lift —
   wire Google Places (or equivalent) into the restaurant-discovery
   step in `pipeline/README.md`, populate the four new `restaurants`
   columns from the response. This is the highest-impact upgrade on
   this list for actual coverage.
4. #4 (bot-blocked chains): swap `fetch_rendered.js`'s plain Playwright
   call for a paid scraping-proxy service where `BLOCKED_SOURCES.md`
   lists a confirmed hard block.
5. Update this file's "Status" line to "Done — see commit X" as each
   one gets upgraded, rather than deleting the entry — keeps the
   history of what changed and why.
