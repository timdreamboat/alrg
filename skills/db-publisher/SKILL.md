---
name: db-publisher
description: Publish a validated, audited ALRG batch (restaurants + menu items with allergen flags) into the Supabase database with provenance and ops logging. Use after qa-allergen-auditor passes a batch, or when the user asks to publish, load, or upsert pipeline data to the database. Never use on unaudited data.
---

# DB Publisher

Precondition: the batch has a PASS or PASS-WITH-CORRECTIONS audit verdict.
Refuse to publish otherwise and say why.

## Procedure
1. Env needed: SUPABASE_URL, SUPABASE_SERVICE_KEY (service role — writes are
   blocked for anon by RLS). Never embed the service key in any client file.
1a. Canonical allergen flag keys — the ONLY keys `app/index.html` filters on:
    `peanut`, `treenut` (no underscore), `dairy` (not `milk`), `egg`,
    `wheat`, `soy`, `fish`, `shellfish` (never combined as
    `fish_shellfish`), `sesame`. Upstream skills (allergen-analyzer,
    chain-menu-importer) may use their own internal naming (e.g.
    `tree_nuts`, `crustacean`/`mollusk` for shellfish) — normalize every
    key to this exact list before insert. A misnamed key is a silent
    false-CLEAR for that allergen (the app simply won't match it). Found
    and fixed twice now: 2026-09-22, 409 rows had `tree_nut` instead of
    `treenut`; 2026-09-23, a second instance of the exact same bug class
    was found confined to Panera Bread's 30 restaurants — 680 rows used
    `milk` instead of `dairy`, and 35 rows (7 distinct items) used a
    merged `fish_shellfish` key instead of the correct single canonical
    key, in both cases silently reading as allergen-CLEAR to any user
    with that allergen selected. Fixed by key rename (`milk`->`dairy`,
    value preserved) and by deriving the correct single key per item from
    its actual ingredient (Caesar dressing/Tuna Salad -> `fish`;
    Shrimply Baja Salad -> `shellfish`) rather than guessing. Don't
    reintroduce either pattern — always normalize to this exact key list
    before insert, never a synonym and never a merged category.
1b. **Canonical allergen flag VALUES — the same rule applies to values, not
    just keys:** the ONLY values `app/index.html` recognizes are `clear`,
    `may`, `shared`, `contains` (its `RANK` object maps exactly these four;
    anything else is `undefined` there, which a plain `>` comparison always
    treats as *less than* `clear` — so an unrecognized value doesn't just
    fail to render, it silently renders as fully CLEAR, the worst possible
    failure mode for a safety-adjacent product). Found 2026-10-01: 314
    rows across 5 already-published restaurants used `may_contain` instead
    of `may` — a natural synonym to type, never caught because the
    normalization note above only ever called out keys. Fixed by replacing
    the value in place (`may_contain`->`may`, nothing else touched).
    Before inserting, normalize every flag value to this exact four-value
    list the same way key normalization already works — never a synonym
    like `may_contain`, `possible`, or `cross_contact` for `may`/`shared`.
2. Upsert restaurants on place_id (or name+zip when no place_id):
   POST /rest/v1/restaurants with Prefer: resolution=merge-duplicates.
   Set data_source, last_reviewed=now.
2a. **No unique DB constraint actually backs this** — place_id is always
    null for chain locations (no places API available), so Postgres has
    nothing to merge-duplicates against and every insert lands as a new
    row. Before inserting, explicitly query for an existing restaurant at
    the same `address` + `city` + `state` (case-insensitive, trimmed) —
    if found, skip re-inserting and update that row instead. Two chain
    imports of the same two Five Guys locations under slightly different
    name strings ("Five Guys" vs "Five Guys - Denver") slipped through
    this exact gap once already (2026-09-22, fixed by deleting the
    duplicate rows) — the fix is checking by address, not by name.
    **Happened again 2026-10-02/04, different cause: two overlapping
    firings, not a name mismatch.** 4 real duplicate pairs found (Waffle
    Rush/AK, Abuela's Tacos/NV, E & S Bakery/TX, Ming's Chinese/VA), each
    pair created minutes to ~2 days apart — the address-dedup check above
    is correct but only ever checks at one point in time; it can't see
    an insert from a different firing that's in flight (or that happened
    after a stale discovery_candidates read) at the moment it checks.
    Found and fixed by an interactive session (duplicates can't be
    cleaned up by the Routine itself — see the DELETE note at 3a).
    Rather than trying to make the check perfectly race-proof, watch for
    it periodically with
    `select lower(trim(address)), city, state, array_agg(id) from
    restaurants group by 1,2,3 having count(*)>1` and clean up any real
    hits (as opposed to genuine same-address ghost-kitchen/virtual-brand
    pairs — different names at one address is normal, check names before
    assuming a match is a bug).
2b. **Geocode every restaurant before insert.** The map is useless without
    lat/lng, and 85 of 91 published restaurants had none as of 2026-09-22
    (every chain import skipped this). Use Nominatim (free, no key,
    already this project's preferred geocoder):
    `https://nominatim.openstreetmap.org/search?q=<address>,<city>,<state>
    <zip>&format=json&limit=1&countrycodes=us`, with a descriptive
    `User-Agent` header (required by Nominatim's usage policy) and **no
    more than 1 request/second** — that policy is enforced, don't try to
    parallelize or you'll get blocked. If a specific address fails to
    geocode, don't fabricate coordinates or silently skip forever — leave
    lat/lng null on that one row, note it in the batch's ops_log entry,
    and it'll show up in a `select * from restaurants where lat is null`
    sweep for a later retry.
3. Replace that restaurant's menu_items (delete by restaurant_id, insert new)
   so removed dishes disappear. Set audited=true only per the audit report.
3a. **DELETE hangs indefinitely from an unattended Routine firing — confirmed
    repeatedly (GitHub issue #216, 2026-10-03/04): every DELETE attempt
    timed out at 60s+ regardless of row count, including a would-match-
    zero-rows case, while INSERT/UPDATE/SELECT against the exact same rows
    worked fine throughout.** Root cause: this tool's own "destructive
    statements may require the user to confirm" gate has no one to answer
    it in a scheduled session — same shape as the git-push wall. This only
    bites the *replace* path above (a fresh restaurant's first publish is
    insert-only, unaffected). Until this is resolved: a *new* restaurant
    publishes normally; *re-publishing/updating an existing restaurant's
    menu* (freshness-sweep maintenance mode, Step 4 of the priority order,
    is the main place this would come up) should NOT attempt the
    delete-then-insert replace from an unattended firing — stage it (same
    pattern as `pipeline/pending_publish/` for the Supabase-outage case)
    for a human/interactive session to run instead, or skip re-publishing
    that restaurant this pass and log why via `ops_log` `pipeline_note`.
    This hasn't blocked real work yet because maintenance mode hasn't
    started (no state has reached 50 restaurants) — flagging now so it's
    not a surprise when it does.
4. Update metros status if this completes a metro.
4a. **If this restaurant came from `discovery_candidates`** (its address
    matches a `pending` row there — check before every publish, see
    `pipeline/COVERAGE_PLAN.md`), update that row: `status='promoted'`,
    `promoted_restaurant_id=<the restaurants.id just inserted>`. This is
    what turns the map's dashed "coming soon" pin into the real scored
    pin — the app only queries `status=eq.pending`, so skipping this
    step leaves a stale duplicate-looking pin sitting on the map forever
    next to the real one. If a candidate turns out not viable during
    this pass (closed, duplicate, no real menu anywhere), set
    `status='rejected'` on it instead of leaving it pending.
5. Insert ops_log entry: event=batch_published, detail={metro, restaurants,
   items, audit_stats}.
6. Report to the user in one line:
   "[Metro] published. X restaurants, Y items. Audit: Z corrections."

## Hard rules
- Licensing: store external place_id as a join key only; never store cached
  proprietary map-vendor content (descriptions, photos, reviews).
- All-or-nothing per restaurant: if any insert fails, roll that restaurant
  back and report it; do not leave partial menus.
