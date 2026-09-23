# Nationwide coverage plan — 50 unique restaurants per state

Owner decision, 2026-09-23. Two intentional pivots from how the pipeline
ran before this file existed:

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

## Two tracks, run in this order

### Track A — chain location expansion (fast, cheap, do this first for every already-analyzed chain)

For each chain with `analyzed_at is not null` (currently: check
`select name from chains where analyzed_at is not null`), find its
real physical locations and copy the existing menu into a new
`restaurants` row per location — prioritize states currently under 50.

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
  `verified = false` (still not restaurant-confirmed — that's a
  separate signal from "sourced from an audited chain matrix"),
  `source_document` left null (the citation lives on `chains.source_document`
  for this chain already — don't duplicate it per location).
- Copy that chain's existing `menu_items` rows (name, note, flags,
  `audited = true`, inherited — the content is identical, it already
  passed audit once) onto the new `restaurant_id`. This is a literal
  copy, not a fresh analysis. Never run allergen-analyzer or
  qa-allergen-auditor on a copied location.
- Write one `ops_log` entry per chain-expansion batch (not per
  location) summarizing state, chain, locations added.

Within a state, prefer adding a chain **not yet represented there**
over piling more locations of one already-present chain — the goal is
50 real, at-least-somewhat-varied restaurants, not 50 McDonald's.

### Track B — independent restaurants (slower, still needed for real variety)

Once chain expansion has been tried for a state and it's still under
50 (common in smaller/rural states with thin chain footprints), or
once chain expansion alone would make a state's list too
one-note, fall back to the existing restaurant-menu-extractor ->
allergen-analyzer -> qa-allergen-auditor -> db-publisher flow, same as
it's always worked, using that state's `metros` row(s) as the search
starting point. This is unchanged from before — it's just no longer
the only lever for reaching the 50 floor, so it doesn't need to carry
the entire nationwide push alone.

## Updated hourly priority order

Supersedes the plain chains-then-metros order in `CLAUDE.md` — full
detail lives here, `CLAUDE.md` should point at this file:

1. Any chain with `analyzed_at is null` -> chain-menu-importer (unchanged,
   still highest leverage — a chain not yet analyzed can't be expanded).
2. Any state with `count(restaurants) < 50` that has an analyzed chain
   not yet expanded into it -> Track A (chain location expansion).
3. Any state still `< 50` after Track A is exhausted for it -> Track B
   (independent-restaurant pipeline via that state's `metros` rows).
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
