# Nationwide coverage plan — 50 unique restaurants per state

Owner decision, 2026-09-23. Two intentional pivots from how the pipeline
ran before this file existed:

**2026-09-23 update — independents lead, chains are a light supplement,
not the main lever.** Chain locations are useful (real coverage, real
audited data) but low-differentiation — a McDonald's in one state is
essentially the same restaurant as a McDonald's in another, and the
owner's own experience (living with someone with food allergies) is
that chain restaurants are lower-risk and less of a concern day to day
precisely because they're standardized and already publish allergen
info. The actual gap — and the thing ALRG adds real value on — is
independent restaurants, which aren't handled at scale anywhere else.
Chasing down every real address of every chain in every state is a lot
of pipeline effort for restaurants that are "almost always the same,"
so that effort now goes to independents first. See the reordered
priority list below — Track B (independents) runs before Track A
(chain expansion) for any under-50 state, and Track A is capped per
chain per state so it tops states up rather than dominating them.

1. **APIs stay off until user adoption is real.** Map/geocoding
   (Mapbox) and place discovery/contact data (Google Places) remain on
   their free substitutes — see `pipeline/PAID_UPGRADE_POINTS.md`. That
   file's whole job is making the eventual switch a paste-a-key /
   wire-in-one-place change with no other code touched; nothing in this
   plan should make that switch harder. Don't wire in a paid key on
   your own initiative — same standing rule as before.
2. **Chains no longer get a fresh menu search per location.** A
   chain's menu is the same everywhere. Once `chain-menu-importer` has
   analyzed and audited a chain **once**, every physical location of
   that chain reuses that exact menu/allergen data — no
   restaurant-menu-extractor, no allergen-analyzer, no
   qa-allergen-auditor re-run per location. The only work left for a
   known chain is finding where its real locations are and copying the
   already-audited data in. This is the highest-leverage change in this
   plan: it turns "one restaurant per pipeline pass" into "dozens of
   real locations per pass" for every chain already analyzed.

## The target

**Every one of the 50 US states reaches at least 50 unique restaurants**
(rows in `restaurants`, chains and independents both count — each row
is a distinct real place). Check progress with:

```sql
select state, count(*) from restaurants group by state order by count(*) asc;
```

A state "passes" once its count is >= 50. DC and any US territory are
bonus coverage, not part of the 50-state target (DC is already seeded
in `metros` from earlier work; no other territory is seeded, none
required).

`metros` was expanded 2026-09-23 to include at least one city in
every state that had zero coverage, largest city in that state, so the
independent-restaurant pipeline has a starting point everywhere. Rank
is a rough population-order hint, not authoritative. If a state's
seeded city plus its chain locations still don't reach 50, the Routine
should add a second city in that state to `metros` rather than
stalling — do not treat one metro row as the ceiling for a state.

## Two tracks — independents lead, chain expansion tops up

### Track B — independent restaurants (primary lever, run first)

For any state under 50, work it with the existing
restaurant-menu-extractor -> allergen-analyzer -> qa-allergen-auditor ->
db-publisher flow, same as it's always worked, using that state's
`metros` row(s) as the search starting point. This is where real
pipeline effort should go — independents are the restaurants nobody
else is covering at scale, and they're the higher-uncertainty case
allergy-conscious diners most need a second opinion on.

**2026-09-23 — candidate list now comes from `pipeline/discover_places.py`
first, not cold WebSearch guessing.** This script queries Overture
Maps' open Places dataset (free, no key or account needed, CDLA
Permissive 2.0 license — see `pipeline/PAID_UPGRADE_POINTS.md`) for
real restaurants near a city and prints them as JSONL:

```
python3 pipeline/discover_places.py "Wichita, KS" 12 0.7
```

(city/state query, radius in miles, minimum confidence 0-1 — defaults
15 miles / 0.6 if omitted). A single run against one metro city
routinely returns 1,000+ real candidates (name, category, address,
phone, website, confidence) — far more than one state needs.

**This is a discovery lead, same rule as Google Places will be once
that's wired in (see `pipeline/PAID_UPGRADE_POINTS.md` #3) — never
store an Overture field directly.** The flow per state:
1. Run `discover_places.py` against that state's `metros` city/cities.
2. Filter out anything already in `restaurants` (match on address or
   lat/lng proximity) and anything that's actually a chain already
   handled by Track A (name matches a row in `chains`) — Overture mixes
   both in, this script doesn't distinguish them.
3. Pick real independent candidates from what's left, prioritizing
   higher `confidence` and skipping anything that looks like a data
   artifact (duplicated city name in the `name` field, null address,
   confidence well under 0.7).
4. For each one, run the full restaurant-menu-extractor ->
   allergen-analyzer -> qa-allergen-auditor -> db-publisher flow as
   normal — Overture's `phone`/`website` are a starting point to check,
   not a value to copy in; independently confirm from the restaurant's
   own site before storing anything, same discipline as the menu data
   itself.
5. Only fall back to cold WebSearch discovery (the original method,
   still described below) if a metro's Overture pull comes back thin
   or a state still needs more cities than are seeded in `metros`.

This doesn't change the audit/publish rules at all — it only replaces
"guess what might exist" with "here are 1,000 real candidates," so the
slow part (menu/allergen analysis) has real leads to work through
immediately instead of spending pipeline time on discovery guesswork.

### Track A — chain location expansion (supplement only, capped)

Chains are lower-value to expand exhaustively — they're standardized,
already publish their own allergen info, and one McDonald's is a lot
like the next. Use Track A to **top up** a state that's still short of
50 after a real independent-discovery attempt, not as the first move.

**Cap: at most ~8 locations per chain per state.** The goal is
covering the chain's real presence in that state, not enumerating
every address — 8 real locations of a chain already say "this chain
operates here" as well as 30 do, and the saved effort goes to
independents instead. If a state is still short of 50 after topping up
with several different chains (each capped at ~8), that's a signal to
add another independent-discovery pass, not to lift the chain cap.

For each chain with `analyzed_at is not null` (currently: check
`select name from chains where analyzed_at is not null`), find its
real physical locations and copy the existing menu into a new
`restaurants` row per location — prioritize states currently under 50,
stop at ~8 per chain per state.

**How to find real locations without a paid places API:**
1. Overpass (OSM) query by brand tag first — this is the cleanest free
   source and usually gives lat/lng + address in one shot:
   ```
   [out:json][timeout:25];
   area["ISO3166-2"="US-{STATE}"]->.a;
   (
     node["brand"="{Chain Name}"](area.a);
     way["brand"="{Chain Name}"](area.a);
   );
   out center tags;
   ```
   Fall back to `name` instead of `brand` if a chain isn't tagged that
   way in OSM (common for smaller/regional chains). Retry 2-3x on a
   transient Overpass failure before falling back — same guidance
   already in `pipeline/README.md`'s discovery section.
2. If Overpass has nothing for that state/chain, fall back to the
   chain's own public store-locator page via WebFetch — most chains
   publish one (often backed by a readable JSON endpoint in the page),
   e.g. `mcdonalds.com/us/en-us/restaurant-locator.html`. Extract
   address/city/state/zip; lat/lng isn't required if address is solid,
   the app can geocode display-side only if needed later.
3. Dedupe against existing `restaurants` rows (same chain_id + same
   address, or lat/lng within ~50m) before inserting.

**For each new location found:**
- Insert one `restaurants` row: name, address, city, state, zip,
  lat/lng (if known), `chain_id` set, `data_source = 'chain_matrix'`,
  `verified = true` (matches existing practice for every chain_matrix
  row already in the database — `verified` here means "sourced from an
  audited official chain matrix," not restaurant-staff confirmation;
  the app must never imply per-location confirmation from this flag
  alone, see the UI disclaimer requirement below), `source_document`
  left null (the citation lives on `chains.source_document` for this
  chain already — don't duplicate it per location).
- Copy that chain's existing `menu_items` rows (name, note, flags,
  `audited = true`, inherited — the content is identical, it already
  passed audit once) onto the new `restaurant_id`. This is a literal
  copy, not a fresh analysis. Never run allergen-analyzer or
  qa-allergen-auditor on a copied location.
- Write one `ops_log` entry per chain-expansion batch (not per
  location) summarizing state, chain, locations added.

Within a state, prefer adding a chain **not yet represented there**
over piling more locations of one already-present chain, and stop at
the ~8-per-chain cap above — the goal is topping a state up with a
little variety, not maximizing any one chain's footprint.

**UI requirement (owner decision, 2026-09-23):** because a chain
location's data is copied from corporate's matrix rather than
confirmed at that specific address, every chain restaurant's detail
card must carry a visible disclaimer — something like: "Based on
[Chain]'s official corporate allergen guide. Individual locations can
vary slightly in ingredients, suppliers, or prep — confirm with the
restaurant before you visit." This is implemented in `app/index.html`
(see the detail-drawer rendering) and applies to every restaurant with
a `chain_id` set, regardless of `verified`.

## Updated hourly priority order

Supersedes the plain chains-then-metros order in `CLAUDE.md` — full
detail lives here, `CLAUDE.md` should point at this file:

1. Any chain with `analyzed_at is null` -> chain-menu-importer (unchanged,
   still highest leverage as a one-time investment — a chain not yet
   analyzed can't be expanded later, but this step does NOT chase
   location addresses, just the one-time menu analysis).
2. Any state with `count(restaurants) < 50` -> Track B (independent
   restaurants) first, via that state's `metros` row(s).
3. Any state still `< 50` after a real independent-discovery attempt
   -> Track A (chain location expansion), capped at ~8 locations per
   chain per state, spread across chains not yet represented there
   rather than piling onto one.
4. All 50 states >= 50 and chains backlog empty -> maintenance mode
   (freshness sweep), same as before. Report "coverage complete"
   once, same rule as before.

## What doesn't change

- Publishing, audit, and provenance rules are untouched — Track A
  locations are marked `data_source='chain_matrix'` precisely so
  they're never confused with a fresh independent analysis.
- The two genuine escalation triggers (repeated audit fail, safety
  community report) are unchanged and don't apply to Track A at all
  (nothing new is being audited there — it's a copy of already-audited
  data).
- The GitHub Projects board conventions are unchanged: one issue per
  batch, closed with a one-line summary.
