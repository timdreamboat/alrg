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

**2026-09-28 update — Track A gate tightened, and it's now nationwide,
not per-state.** Original wording above ("any under-50 state... after
a real independent-discovery attempt") let Track A fire for a state
after just one independent pass came up short. Owner decision
2026-09-28: that's too early — chain-location copying should not
start ANYWHERE until independent discovery has genuinely been
exhausted, state by state, everywhere it's going to be tried. A single
thin pass isn't exhaustion. See the redefined trigger in "Track A —
chain location expansion" below and the updated priority order — step
3 (Track A) is now gated on a state's independent well being **run
dry**, not merely attempted, and this applies across all 50 states
before Track A does any real volume of work, not state-by-state in
isolation. Until then, a state under 50 with independent candidates
still available just... stays under 50 and gets worked again next
pass. That's expected, not a bug.

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

**Found 2026-09-25 — that query has a blind spot, don't use it alone to
pick "lowest coverage state."** A plain `group by state` silently omits
any state with zero restaurants (no row = absent from the result, not a
zero row) — several hourly passes on 2026-09-25 picked NM (2) and CA (3)
as "the lowest-coverage state" this way while 14 states (ID, IA, NE, CT,
AR, DE, NH, ME, SD, ND, MT, VT, WY, WV) sat at a true zero the whole
time, invisible to that query. Always left-join from `metros` instead,
so a state with nothing yet still sorts to the front:

```sql
select m.state, m.name, m.rank, coalesce(r.cnt,0) as restaurant_count
from metros m
left join (select state, count(*) cnt from restaurants group by state) r
  on r.state = m.state
where m.state <> 'DC'
order by coalesce(r.cnt,0) asc, m.rank asc nulls last;
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
phone, website, confidence, source_dataset, source_updated) — far more
than one state needs.

**`source_updated` is per-candidate, not a dataset-wide freshness
date.** Tested against Wichita, KS (2026-09-23): most candidates were
from within weeks of the current release, but one real record was last
updated **2021-10-13** — nearly 5 years old. This is how stale that
specific lead might be, not how stale Overture is in general. Weight it
when picking candidates and when re-verifying (see step 3) — an old
record is still worth checking, just with more skepticism that the
place still exists as described.

**This is a discovery lead, same rule as Google Places will be once
that's wired in (see `pipeline/PAID_UPGRADE_POINTS.md` #3) — never
store an Overture field directly.** The flow per state:
1. Run `discover_places.py` against that state's `metros` city/cities.
2. Filter out anything already in `restaurants` **or already in
   `discovery_candidates`** (match on address or lat/lng proximity) and
   anything that's actually a chain already handled by Track A (name
   matches a row in `chains`) — Overture mixes both in, this script
   doesn't distinguish them.
3. Pick real independent candidates from what's left, prioritizing
   higher `confidence` and more recent `source_updated`, and skipping
   anything that looks like a data artifact (duplicated city name in
   the `name` field, null address, confidence well under 0.7).

   **Also skip ghost-kitchen / virtual-brand concepts — found
   2026-09-24, not caught by the chains-table name filter above.**
   "The Meltdown," "Banda Burrito," and "The Burger Den" all appeared
   as apparently-independent Overture candidates in AK and HI, but are
   Denny's Corporation delivery-only virtual brands operated out of
   existing Denny's kitchens, not independent restaurants — confirmed
   via The Meltdown's own Allergen Guide PDF, copyright-marked "© 2022
   DFO, LLC" (a Denny's corporate entity) and explicitly scoped to "the
   contiguous United States only" (so it doesn't even cover the HI
   location it was being considered for). These aren't in the `chains`
   table, so the existing name-match filter misses them. If a
   "restaurant" candidate's own site reads like a shared corporate
   ghost-kitchen doc (generic multi-brand-style allergen PDF, another
   chain's name showing up in an ingredient/seasoning line, explicit
   regional scoping that excludes the state being worked), treat it
   like a chain for filtering purposes — don't source it as an
   independent, and don't treat its document as that location's own
   data.

   **Related but distinct — found 2026-09-29, a real small multi-location
   family group, not a ghost kitchen.** An OR Track B candidate ("Puerto
   Mazatlan," King City) turned out to be one of 5 sibling restaurants
   under different local names (Puerto Mazatlan in Ashland OR, El Indio de
   Oro and Indio Mexican Restaurant in Portland OR, Hacienda Tequila in
   Buckley WA, and the King City location itself branded "Mazatlan
   Mexican Restaurant") sharing one standardized menu document, run by one
   family. Unlike the Denny's virtual-brand case, this is a genuine small
   independent restaurant group — just not a single-name chain the
   name-match filter would catch, and not yet a `chains` row. Rejected
   this candidate from Track B (a shared standardized menu across
   locations is the same red flag as the ghost-kitchen case, so it
   shouldn't be extracted/audited as if it were one-off independent data)
   — logged in `discovery_candidates` (id 829, status `rejected`) with
   full detail. **Not yet actioned further**: this family is a plausible
   future `chains` table candidate (chain-menu-importer flow: one
   analysis + audit of the shared menu, then location-copy same as any
   other chain) but that's a separate, bigger unit of work than a Track B
   pass and wasn't started this pass. If this pattern recurs — a
   candidate whose own site reveals sibling locations under different
   names sharing one menu — treat it the same way: reject from Track B,
   log the sibling list, and flag as a chain-menu-importer candidate
   rather than silently publishing it as an independent or silently
   dropping it.

   **Confirmed recurring, not a one-off — IL pass, 2026-09-29.** 3 of 6
   IL/Chicago Track B candidates this pass turned out to be exactly this
   pattern (50%, unusually high but a real signal that independent
   subagents are now catching this reliably before publishing bad data):
   - **El Gallo Bravo** (3714 W Lawrence Ave) — official Chicago DPH
     business-license DBA on file is "El Gallo Bravo #6," a numbered
     multi-location designation. Sibling addresses (#1-#5, #7+) not
     found this pass.
   - **Ba Le Sandwiches** (5014 N Broadway) — real, actively-expanding
     3-location group (Chicago + Schaumburg IL, Rockville MD; Naperville
     IL and Rolling Meadows IL opening 2027), one shared site
     (balesandwich.com) and one shared `/menu` page across all locations.
   - **KFire Korean BBQ** (2528 N Milwaukee Ave) — real 2-location group
     (Logan Square + Old Town), one unified menu confirmed identical at
     both locations via kfire.com and both locations' Toast pages.

   All 3 were rejected from Track B (`discovery_candidates.fetch_notes`
   has the full finding) rather than published as independents, and all
   3 are flagged as future `chains` table candidates — not actioned this
   pass, same as Puerto Mazatlan above. Worth a dedicated pass at some
   point to work through this small backlog (Puerto Mazatlan's family,
   Ba Le, KFire) through chain-menu-importer once there's room — each is
   a one-time analysis that then covers multiple real locations, same
   leverage as any other chain.

   **Four more instances, IN/Indianapolis pass, 2026-10-01 — a near-50%
   reject rate on this pass's 12 parallel subagents (5 of 12), all
   caught before publish, none leaked through as false independents:**
   - **"Juicy Seafood" franchise** (candidate: "Snow Crab Juicy Seafood,"
     8340 Kelly Ln) — a documented multi-state Midwest chain
     (Chinese-owned, 10+ locations) operating under rotating storefront
     names per location (Blue Crab/Snow Crab/Mr. & Mrs. Crab Juicy
     Seafood, The Juicy Seafood, Juicy Crab) — same address was "Blue
     Crab Juicy Seafood" per a 2019 article, renamed since, same
     standardized build-your-own seafood-boil menu structure confirmed
     recurring across differently-named locations.
   - **Indiana State Park Inns** (candidate: "Garrison," actually
     Garrison Restaurant at Fort Harrison State Park Inn) — a state
     government-operated group of 7 inns/restaurants (Abe Martin Lodge,
     Canyon Inn, Clifty Inn, Fort Harrison, Potawatomi Inn, Spring Mill
     Inn, Turkey Run Inn) sharing one standardized core menu document
     (verbatim items/descriptions/prices confirmed) — the first
     government-operated instance of this pattern seen so far.
   - **Murphy's Pubhouse/Craft House** (candidate: "Murphy's Pubhouse
     South") — a confirmed 3-location Stonebraker-family group (Fishers,
     Thompson Rd/"South", Geist) sharing signature menu items across
     differently-branded locations.
   - **Hoaglin To Go** (candidate: "Stardust Terrace Cafe," operated by
     Hoaglin To Go at the Indiana History Center) — a smaller, purely
     local 2-location group (this + a Mass Ave location) with the same
     dishes renamed cosmetically per location; flagged as the same
     pattern but likely too small on its own to justify a dedicated
     `chains` row — owner's call.

   All 4 flagged as future chain-menu-importer candidates (full detail
   in each `discovery_candidates.fetch_notes`), not actioned this pass —
   growing the same backlog as Puerto Mazatlan/Ba Le/KFire/El Gallo
   Bravo/Rosie's Coffee Cafe above. The State Park Inns case in
   particular is worth prioritizing if this backlog is ever worked: one
   analysis would cover 7 real, already-standardized locations across
   multiple states' worth of coverage pressure (Indiana specifically,
   but the same multi-state-inn-system pattern likely recurs elsewhere).

   **Fourth instance, GA/Atlanta pass, 2026-09-29 — Rosie's (Coffee)
   Cafe.** A candidate at 48 Northside Dr SW, Atlanta (Castleberry Hill)
   turned out to be one of 3-4 locations of "Rosie's Coffee Cafe," a
   family-owned group (Platt Restaurant Group, owner Ericka Platt) —
   Castleberry Hill, East Point (2330 Sylvan Rd), Carrollton, and a
   planned 4th location (Roosevelt Hall, University of West Georgia
   campus) — all trading under the identical name and the same Southern
   breakfast/brunch + coffee concept. The same-name signal here is even
   stronger than Puerto Mazatlan's (different names per location) and
   closer to the Ba Le/El Gallo Bravo pattern. Rejected from Track B
   (`discovery_candidates` id 1114, status `rejected`, full detail in
   `fetch_notes`) rather than extracted as a one-off independent. Add to
   the same chain-menu-importer backlog as the three above — still not
   actioned, a growing list worth a dedicated pass.

   **Separate recurring issue, not a chain/group problem — PA pass,
   2026-09-29: Overture's `website` field is wrong at a meaningfully high
   rate, not just occasionally stale.** 3 of 6 PA/Philadelphia candidates
   this pass had a `website` value that was flat-out wrong, not just
   outdated:
   - **Crab Shack** (4800 N 16th St) — Overture's website
     (theoriginalcrabshack.com) belongs to an unrelated, well-known
     restaurant of the same generic name on Tybee Island, GA. The real
     restaurant's actual first-party source was its Toast ordering page,
     found independently, not via the Overture field.
   - **City Line Diner and Deli** (7547 Haverford Ave) — Overture's
     website (franksdeliandcatering.com) is a different, related-but-distinct
     business (a catering-only operation a few doors down, different
     address/phone) — plausibly a family connection, but not the same
     restaurant.
   - **New Mandarin House** (3 W Girard Ave) — Overture's website
     (phillymandarinpalace.com) belongs to an entirely unrelated Center
     City restaurant ("Mandarin Palace").
   All 3 were still worked and published (menu sourced from the
   restaurant's own first-party ordering platform, or a third-party
   aggregator when that failed) — this is a **verify-before-trust**
   finding, not a fetch failure: don't skip a candidate just because its
   Overture website is dead/wrong, but also never publish a `website`
   value straight from Overture without independently confirming it
   resolves to the same business at the same address first (same
   discipline already applied to menu content, just extended to the
   website field itself). When a mismatch is found, set `website` to the
   independently-confirmed correct URL, or `null` if none can be found
   (never leave the wrong Overture URL in place).

   **Confirmed again, not PA-specific — MA/Lynn pass, 2026-09-29.**
   Charlie's Seafood (188 Essex St, Lynn) had an Overture `website`
   (charlieseafood.com) that turned out to belong to an entirely
   unrelated San Francisco seafood wholesaler, different state and
   industry — not just a different restaurant of the same name. No
   working first-party site or social page could be found after an
   extensive search, so `website` was set to `null` rather than carrying
   the wrong domain forward or the PA pass's fallback (a working
   secondary source still existed there; here the menu itself came from
   the restaurant's own live Uber Eats/Postmates ordering catalog
   instead, honestly noted as a secondary/aggregator source in
   `source_document`).

   **New distinction worth recording — same pass: a multi-concept
   restaurateur is NOT the same red flag as a shared-menu chain/group.**
   The Blue Ox (191 Oxford St, Lynn) surfaced two things that looked like
   they might trigger the multi-location rejection above but didn't: (1)
   Overture separately listed "Safra Restaurant Group LLC" at the same
   address — plausibly just the restaurant's own legal entity filing, not
   a second business (no second restaurant at that address was found
   anywhere); (2) the proprietor also owns two other named restaurants
   elsewhere (Prezza, Tonno) — but those are distinct concepts with their
   own separate, unshared menus, not sibling locations serving the same
   standardized menu under different names (the actual pattern that made
   Puerto Mazatlan/Ba Le/KFire/El Gallo Bravo real rejects above). One
   owner running several different restaurants is normal small-business
   structure, not a chain — the test stays "do multiple locations share
   one standardized menu," not "does this person/LLC touch more than one
   restaurant." Published as an independent.
4. **Insert picked candidates into `discovery_candidates`**
   (`status='pending'`) — this is what makes them show up on the map as
   a distinct "coming soon" pin (see `app/index.html`
   `candidatePinIcon`/`openCandidateDrawer`) before they're analyzed.
5. For each one, run the full restaurant-menu-extractor ->
   allergen-analyzer -> qa-allergen-auditor -> db-publisher flow as
   normal — Overture's `phone`/`website` are a starting point to check,
   not a value to copy in; independently confirm from the restaurant's
   own site before storing anything, same discipline as the menu data
   itself.
6. **When db-publisher actually publishes the restaurant**, update its
   `discovery_candidates` row: `status='promoted'`,
   `promoted_restaurant_id=<the new restaurants.id>`. This is what
   turns the dashed "coming soon" pin into the real scored one — the
   app's map query is `discovery_candidates?status=eq.pending`, so a
   promoted row simply stops appearing there once the real restaurant
   (with its real score) is live. If a candidate turns out not viable
   (permanently closed, a duplicate, no real menu found anywhere) set
   `status='rejected'` instead — same effect, it drops off the map
   without ever being confused for a real entry either way.
6a. **If a candidate hits a block, dead domain, structural gap, or
   anything else worth remembering for next time (and isn't ready to
   promote or reject yet)**, write it to that row's `fetch_notes`
   (text), incrementing `fetch_attempts` and setting
   `last_attempted_at = now()` — NOT to `pipeline/BLOCKED_SOURCES.md`,
   which is chains-only as of 2026-09-28 (see that file's own
   "Independent-restaurant attempt notes now live in the database"
   section). Check `fetch_notes` before re-attempting a `pending`
   candidate, same spirit as checking `BLOCKED_SOURCES.md` before
   re-attempting a chain.
7. Only fall back to cold WebSearch discovery (the original method,
   still described below) if a metro's Overture pull comes back thin
   or a state still needs more cities than are seeded in `metros`.

This doesn't change the audit/publish rules at all — it only replaces
"guess what might exist" with "here are 1,000 real candidates," so the
slow part (menu/allergen analysis) has real leads to work through
immediately instead of spending pipeline time on discovery guesswork.

### Track A — chain location expansion (supplement only, capped, gated)

Chains are lower-value to expand exhaustively — they're standardized,
already publish their own allergen info, and one McDonald's is a lot
like the next. Use Track A to **top up** a state that's still short of
50 — but only once that state's independent well has genuinely **run
dry**, not just after one attempt.

**"Run dry" — the operational test (owner decision, 2026-09-28):**
a state's independent well counts as dry only when, in the same or a
recent pass:
1. `discover_places.py` has been run against every `metros` row
   currently seeded for that state (adding a second/third city per
   `COVERAGE_PLAN.md`'s existing "don't stall on one metro" guidance
   if the seeded city's radius is clearly exhausted), AND
2. After filtering out chains, existing `restaurants` rows, and
   already-`rejected` candidates, the pull returns **zero new viable
   pending candidates** for that state — nothing left to insert into
   `discovery_candidates`, AND
3. `discovery_candidates` has no remaining `pending` rows for that
   state either (they've all been worked to published/promoted or
   rejected).

Log this with an `ops_log` entry (`event: independent_well_dry`,
`detail: {state, metros_tried, last_checked}`) the first time a state
hits this — same spirit as `pipeline/BLOCKED_SOURCES.md` for chains.
Once logged, don't re-run the full check on that state every single
pass (Overture data does refresh, so recheck occasionally — e.g. once
every couple weeks — rather than never again, same retry cadence
already used for blocked chain sources). Only states with a logged
`independent_well_dry` entry (or a fresh recheck confirming it's still
dry) are eligible for Track A. A state that's merely under 50 with
candidates still sitting in `discovery_candidates` is NOT eligible —
keep working it with Track B.

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

   **Fifth cluster, IA/Des Moines pass, 2026-10-02 — three instances in one
   12-candidate batch (25% reject rate, all caught before publish):**
   - **Teriyaki House Japanese Grill** (candidate: 9250 University Ave Ste
     106, West Des Moines) — Overture's listed website (teriyakihouse.co)
     actually belongs to a *different* Teriyaki House location (1014 E
     14th St, Des Moines, different phone). A third same-named location
     (1802 SE Delaware Ste 108, Ankeny) has an identical menu
     structure/protein lineup, and a fourth, differently-named sibling
     concept ("Teriyaki Eats Japanese Grill," Windsor Heights) uses
     word-for-word identical business-model description — a standardized
     build-your-own-teriyaki-bowl concept recurring under slightly
     different storefront names across the metro, the same rotating-name
     shape as "Juicy Seafood" (IN, 2026-10-01).
   - **Tavern Pizza & Pasta Grill** (candidate: 1755 50th St, West Des
     Moines) — independent sources explicitly describe this address as
     "a second location" of The Tavern (205 Fifth St, Historic Valley
     Junction, est. 1945). A third location (1106 Army Post Rd, Des
     Moines) shares a verbatim-identical grinder lineup ("The Italian
     Grinder," "The Special Grinder," "The Sting") plus shared staples
     (onion rings, Fettuccine Alfredo, Lasagna, Chicken Parmesan) — a real
     3-location local group, not a one-off independent.
   - **El Toreado Restaurant Bar & Grill** (candidate: 3751 EP True Pkwy,
     West Des Moines) — the restaurant's own site lists a second location
     under the identical brand (4521 Fleur Dr, Des Moines, "the Airport
     location") with one shared menu/ordering flow and no
     location-specific variation.

   All 3 flagged as future chain-menu-importer candidates (full detail in
   each `discovery_candidates.fetch_notes`, ids 1179-1181), not actioned
   this pass — growing the same backlog as Puerto Mazatlan/Ba Le/KFire/El
   Gallo Bravo/Rosie's Coffee Cafe/Juicy Seafood/Indiana State Park
   Inns/Murphy's Pubhouse above. Des Moines in particular is shaping up as
   a metro with an unusually high density of small local restaurant
   groups — worth keeping in mind if a dedicated chain-menu-importer pass
   through this backlog is ever scheduled, since 3 of the ~15 candidates
   found there so far are groups, not one-offs.

## Sixth cluster, SD/Sioux Falls pass, 2026-10-04 — three more chain/group
rejects in one 12-candidate batch (25% reject rate):

- **Pizza Shop** (candidate: "Pizzashop Sioux Falls," 4104 W 41st St) — a
  multi-state chain (owner Josiah Urban, NJ-origin) with confirmed MS and TX
  locations also expanding under the same brand/menu as of this pass. Full
  menu already extracted from the site's own menu images (directly read,
  not guessed) and saved in `discovery_candidates` fetch_notes (id 762) for
  reuse — a real chain-menu-importer pass still needs to audit it properly,
  not just copy the preliminary read.
- **Tinners Public House / Tinners North** — confirmed 2-location Sioux
  Falls group (Kirby Muilenburg/Bryant Soberg), same standardized menu
  carried through a 2023 rebrand (Northstar Grill & Pub → Tinners North).
  Same ownership group also owns Tavern 180 and part of Wileys — watch for
  those names surfacing as separate candidates with the same issue.
- **Jacky's Restaurant** — confirmed 2-location Sioux Falls group (3101 W
  41st St + 3308 E 10th St) via the restaurant's own homepage copy ("two
  convenient locations"), one shared jackysrestaurants.com/menu. Guatemalan/
  Mexican-influenced menu plus Chinese and breakfast/lunch/dinner items,
  founded 2009 by Jacky Vanloh.

All 3 flagged as future chain-menu-importer candidates (full detail in each
`discovery_candidates.fetch_notes`, ids 762/764/1611, and in `ops_log`
`pipeline_note` events from this pass), not actioned this pass — growing the
same backlog as the IA/Des Moines, IL, IN, GA, and OR clusters above. 6 of
this pass's 12 candidates did publish cleanly (Boki European Street Food,
Swamp Daddy's Cajun Kitchen, Fuji Sushi & Hibachi Grill, The Rush Bar &
Grill, Szechwan Chinese Restaurant, and Ninja Ramen & Thai — the last one
found under a stale "Pad Thai" discovery-candidate name but confirmed via
the site's own banner/footer to be a dual Thai/ramen concept actually
trading as Ninja Ramen & Thai); one (Intoxibakes) was rejected as defunct
(closed storefront, 2+ years stale at the candidate's address); two
(Lao Szechuan, Pilot Mike's Roadhouse) stayed `pending` — both real,
current, single businesses with no extractable ingredient-level menu found
yet (Lao Szechuan's site is Vercel-bot-walled; Pilot Mike's Roadhouse has no
website/social/delivery presence found at all, just one weak press mention
naming 5 unidentified items with no ingredient detail — correctly not
fabricated). SD restaurant count: 12 → 18.

## Updated hourly priority order

Supersedes the plain chains-then-metros order in `CLAUDE.md` — full
detail lives here, `CLAUDE.md` should point at this file:

1. Any chain with `analyzed_at is null` -> chain-menu-importer (unchanged,
   still highest leverage as a one-time investment — a chain not yet
   analyzed can't be expanded later, but this step does NOT chase
   location addresses, just the one-time menu analysis).
2. Any state with `count(restaurants) < 50` AND independent candidates
   still available (no logged `independent_well_dry`, or pending rows
   still sit in `discovery_candidates`) -> Track B (independent
   restaurants), via that state's `metros` row(s).
3. Any state still `< 50` **with a logged `independent_well_dry`**
   (2026-09-28: genuinely exhausted, not just attempted once — see
   Track A above) -> Track A (chain location expansion), capped at ~8
   locations per chain per state, spread across chains not yet
   represented there rather than piling onto one. A state under 50
   without a dry well is NOT eligible yet — falls back to step 2.
4. All 50 states >= 50 and chains backlog empty -> maintenance mode
   (freshness sweep), same as before. Report "coverage complete"
   once, same rule as before.

Note: because step 3 now requires a dry well, it's realistic that
Track A does close to nothing for a long stretch while Track B still
has candidates everywhere — that's the intended effect of the
2026-09-28 decision, not a sign something's broken.

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
