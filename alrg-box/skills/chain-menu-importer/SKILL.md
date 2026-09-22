---
name: chain-menu-importer
description: Ingest a national or regional restaurant chain's published menu and official allergen information once, then apply the analyzed result to every US location of that chain. Use when the user asks to import a chain, when CLAUDE.md's autonomous priority order points at an unanalyzed row in the chains table, or when nationwide coverage speed matters more than independent-restaurant depth. One import can cover hundreds or thousands of locations, which is why chains run before metros in the autonomous priority order.
---

# Chain Menu Importer

Chains are the fast path to nationwide presence: one analysis run, applied
everywhere that chain operates. Still passes through qa-allergen-auditor —
"published by corporate" reduces uncertainty, it doesn't exempt data from
the same validity bar every other row meets.

## Procedure
1. Input: a row in `chains` with `analyzed_at IS NULL`. Take its `name`.
2. Find the chain's own published menu and allergen information — the
   official nutrition/allergen page on the chain's own domain is the target;
   third-party aggregators are a fallback only, never the source of record.
   Note whether what you found is a true allergen matrix (explicit per-item
   flags for the Big 9) or just an ingredient list you must infer from
   (same hidden-source reasoning as restaurant-menu-extractor/allergen-
   analyzer — treat ingredient-list-only chains as ordinary analysis, not
   as "official_matrix").
3. Build the same structure allergen-analyzer produces: items with flags.
4. Run qa-allergen-auditor on the result exactly as for any other batch —
   same thresholds, same retry-then-escalate rule. A chain's own published
   matrix can still contain a transcription slip; audit it anyway.
5. On PASS or PASS WITH CORRECTIONS: find US locations of the chain (web/
   places search — as many as reasonably enumerable; it's fine to add more
   in a later pass rather than block on finding every single one now).
   For each location, upsert a restaurant row with data_source='chain_matrix',
   chain_id set, and the SAME analyzed menu_items attached to every location
   (menus are near-identical across a chain's locations; note in `note` if
   a specific location's menu is known to differ and skip that one for a
   human/later pass rather than guessing).
6. Set the chain's `analyzed_at = now()`. Set `official_matrix = true` only
   if step 2 found a genuine per-item allergen matrix, not an inferred one.
7. Certainty bonus: locations from a genuine `official_matrix` chain earn
   the same scoring certainty bonus as `verified=true` (set verified=true
   for these) — a corporate-published matrix is at least as reliable as one
   restaurant confirming its own listing. Ordinary chain menus without a
   real matrix (official_matrix=false) do NOT get this bonus; they're
   `data_source='chain_matrix'` but `verified=false`, same as any other
   AI-analyzed restaurant.
8. ops_log entry: event=chain_imported, detail={chain, locations, audit_stats}.
9. GitHub Projects card per CLAUDE.md's board conventions — same as any
   autonomous batch; only a repeated audit fail escalates to needs-owner.

## Hard rules
- Never fabricate or guess a chain's allergen data because a page is hard to
  find — search harder, or leave the row unanalyzed for a later attempt.
  A missing analysis is honest; a guessed one is exactly the false-CLEAR
  risk this whole product exists to avoid.
- Same licensing rule as everywhere else: place_id as join key only, no
  cached third-party map content.
