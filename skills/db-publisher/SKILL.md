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
3. Replace that restaurant's menu_items (delete by restaurant_id, insert new)
   so removed dishes disappear. Set audited=true only per the audit report.
4. Update metros status if this completes a metro.
5. Insert ops_log entry: event=batch_published, detail={metro, restaurants,
   items, audit_stats}.
6. Report to the user in one line:
   "[Metro] published. X restaurants, Y items. Audit: Z corrections."

## Hard rules
- Licensing: store external place_id as a join key only; never store cached
  proprietary map-vendor content (descriptions, photos, reviews).
- All-or-nothing per restaurant: if any insert fails, roll that restaurant
  back and report it; do not leave partial menus.
