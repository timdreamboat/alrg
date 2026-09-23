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

---

## 1. Map tiles — `app/index.html`, `initMap()`

**Now:** Esri World Light Gray Canvas (`services.arcgisonline.com`) —
free, no key, no usage cap found in testing.

**Upgrade to:** Mapbox GL (vector tiles, custom styling, better label
placement/decluttering than Esri's raster tiles — would help the pin-
label crowding already noted in the UI) or Google Maps JS API. Needs an
API key added to `app/config.js` (same pattern as the Supabase keys)
and the `L.tileLayer(...)` calls replaced with the new provider's tile
URL template + key.

## 2. Geocoding — `app/index.html` (`geocodeAndFly`, `onboardSearch`) and the one-off backfill scripts used for `pipeline/db-publisher`

**Now:** Nominatim (OpenStreetMap, free, no key) — usage-policy capped
at ~1 request/second, meant for light use, not guaranteed uptime/SLA.
Already the thing that made local geocoding attempts flaky during
setup (see git history around the restaurant lat/lng backfill).

**Upgrade to:** Google Geocoding API or Mapbox Geocoding — faster,
higher volume, an actual SLA. Needs a key in `app/config.js` for the
client-side calls, and the same key (or a server-side equivalent) for
whatever runs the next restaurant lat/lng backfill pass.

## 3. Restaurant/place discovery — `pipeline/README.md`, "Restaurant discovery in the cloud Routine"

**Now:** WebSearch + WebFetch per-restaurant, with Overpass (OSM) as a
first attempt when reachable. Explicitly chosen over Google Places
earlier in this project specifically because of cost — see
`pipeline/places_data_coverage` history. This is the slowest, lowest-
coverage part of the whole pipeline (one hourly firing might only add
1-2 restaurants this way) and the main reason metro coverage (e.g. New
York's 4 restaurants) is so thin.

**Upgrade to:** Google Places API (Nearby Search / Text Search) once
subscription funds exist — this is the highest-leverage upgrade on
this list, since it directly unblocks nationwide metro coverage
instead of the current one-restaurant-at-a-time web search grind. Note
Google Places' terms restrict caching/redistributing place data
long-term — keep using `place_id` as a join key only (already how
`restaurants.place_id` is defined), don't cache descriptions/photos/
reviews, consistent with the data-licensing rule already in CLAUDE.md.

## 4. JS-rendered / bot-blocked chain allergen pages — `pipeline/BLOCKED_SOURCES.md`

**Now:** `pipeline/fetch_rendered.js` (Playwright through the sandbox's
own proxy) — works for plain JS-rendering issues, but can't get past a
real WAF/bot-detection block like McDonald's Akamai "Access Denied,"
which is an IP-reputation problem a config fix can't solve.

**Upgrade to:** A paid scraping-proxy/headless-browser service
(Browserless, ScrapingBee, Bright Data, etc.) with residential or
higher-reputation IPs. Would very likely unblock McDonald's and any
other chain in `BLOCKED_SOURCES.md`'s "Confirmed hard blocks" section.
Lower priority than #3 — this affects a handful of specific chains,
not the whole metros pipeline.

## 5. Phone number / website per restaurant — not collected at all today

**Now:** Nothing. The "About this place" card in the app explicitly
tells the user phone/website aren't tracked yet rather than showing
nothing silently. Free path forward would be capturing these from the
same chain store-locator pages already scraped for addresses (they
usually list a phone number right next to the address) — doable
without a paid API, just needs the import step to grab one more field.

**Upgrade to:** A paid Places API (see #3) would give this more
reliably and consistently than scraping locator pages one chain at a
time, especially for independent restaurants where there's no locator
page to scrape at all.

---

## How to use this when the day comes

1. Search the codebase for `PAID-UPGRADE:` to find every exact spot.
2. Work through this list roughly in priority order — #3 (places
   discovery) has by far the biggest impact on actual coverage; #1/#2
   are UI/reliability polish; #4/#5 are narrower, real but smaller.
3. Update this file's "Now" section to "Done — see commit X" as each
   one gets upgraded, rather than deleting the entry — keeps the
   history of what changed and why.
