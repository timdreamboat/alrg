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

**Status: DB ready (`restaurants.phone`, `.website`, `.place_id` exist
and are null until populated — no `.rating`/`.rating_count`, see below),
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
instead of the current one-restaurant-at-a-time web search grind.

**Owner decision, 2026-09-23 — checked Google's actual current terms
before writing this, they're stricter than the original plan assumed.**
Only `place_id` may be stored indefinitely; coordinates may be cached
30 days; name, formatted address, rating, phone, and photos must be
requested live and displayed with attribution on every view, not
warehoused — see the sources below. That rules out "copy Places'
fields straight into `restaurants`, serve from Supabase forever," which
is how every other field in this table works. The pattern that stays
compliant and still ships:
- **Places is a discovery lead, not a stored data source.** A Nearby/
  Text Search call gives the pipeline a `place_id` and an approximate
  name/location — "a restaurant exists here, go look."
- **The pipeline independently re-verifies and collects** name,
  address, phone, website from the restaurant's own site, the same way
  it already does for menus — that's our own independently-collected
  data at that point, not Places content, so it's ours to store freely.
  `place_id` is kept as the join key (already how `restaurants.place_id`
  is defined); coordinates get refreshed at least every 30 days if
  sourced via Places/Geocoding, not populated once.
- **`rating`/`rating_count` don't survive this pattern** — a star
  rating is inherently Google's own proprietary aggregate, there's no
  independent way to re-derive it from the restaurant's own site. See
  #5.
- **The allergen side is untouched:** our existing
  restaurant-menu-extractor → allergen-analyzer → qa-allergen-auditor →
  db-publisher chain still runs on every restaurant Places surfaces,
  unchanged. Google is never the allergen source; it doesn't offer that
  data for arbitrary restaurants anyway.
- Full detail and the reasoning is in `pipeline/README.md` under
  "Restaurant discovery in the cloud Routine" and
  `pipeline/COVERAGE_PLAN.md`, which are the docs to actually build
  from when this lands.

Sources checked 2026-09-23: [Policies and attributions for Places API
(New)](https://developers.google.com/maps/documentation/places/web-service/policies),
[Google Maps Platform Service Specific Terms](https://cloud.google.com/maps-platform/terms/maps-service-terms).

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

## 5. Phone number / website per restaurant (no rating — dropped 2026-09-23)

**Status: DB and UI fully ready** — `restaurants.phone`/`.website`. The
"About this place" card shows a real `tel:` link and a real external
website link the moment either is non-null, and quietly keeps showing
the honest "not tracked yet" note only for whichever is still missing.
Populated the same way as #3: Places surfaces the lead, the pipeline
independently re-verifies phone/website from the restaurant's own site
and stores that — never copied straight from a Places response field.

**No rating field, on purpose.** `restaurants.rating`/`.rating_count`
were built 2026-09-23 and dropped the same day once Google's actual
terms were checked: a Places-sourced rating must be requested live and
displayed with attribution on every view, not stored — incompatible
with how this table works (populate once, serve from Supabase). Rather
than build a feature that can't actually ship under the free-tier-then-
paid plan, it was removed — schema, UI, and sort logic. Distance
remains the real, honest sort signal (see `app/index.html`
`renderList()`). If a genuine popularity signal is ever wanted, it
would need a source whose terms allow storage (e.g. a licensed reviews
API with its own storage terms), not Google Places.

---

## How to use this when the day comes

1. Search the codebase for `PAID-UPGRADE:` to find every exact spot.
2. #1/#2 (map + geocoding): paste a real `MAPBOX_TOKEN` into
   `app/config.js`. Done — nothing else to change.
3. #3/#5 (places discovery + phone/website): the bigger lift — wire
   Google Places (or equivalent) into the restaurant-discovery step in
   `pipeline/README.md` as a discovery lead, then independently
   re-verify and store name/address/phone/website from each discovered
   restaurant's own site (never copy Places' fields straight in — see
   #3 for why). This is the highest-impact upgrade on this list for
   actual coverage.
4. #4 (bot-blocked chains): swap `fetch_rendered.js`'s plain Playwright
   call for a paid scraping-proxy service where `BLOCKED_SOURCES.md`
   lists a confirmed hard block.
5. Update this file's "Status" line to "Done — see commit X" as each
   one gets upgraded, rather than deleting the entry — keeps the
   history of what changed and why.
