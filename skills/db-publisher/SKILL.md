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
    `peanut`, `treenut` (no underscore), `dairy`, `egg`, `wheat`, `soy`,
    `fish`, `shellfish`, `sesame`. Upstream skills (allergen-analyzer,
    chain-menu-importer) may use their own internal naming (e.g.
    `tree_nuts`, `crustacean`/`mollusk` for shellfish) — normalize every
    key to this exact list before insert. A misnamed key is a silent
    false-CLEAR for that allergen (the app simply won't match it), found
    and fixed once already (2026-09-22, 409 rows had `tree_nut` instead of
    `treenut`) — don't reintroduce it.
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
