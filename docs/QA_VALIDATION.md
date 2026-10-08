# QA validation — menu completeness and allergen-flag integrity

Owner request, 2026-10-08: get prepared to validate, state by state once
nationwide coverage is reached, that (1) every restaurant has a full menu
and (2) every menu item actually has a usable allergen score. This file is
that preparation — a tested toolkit, not a one-off report.

**Two categories that need very different treatment:**
- **Flag integrity** (Category A) — is the stored data even shaped
  correctly? These are mechanical, unambiguous, SQL-fixable bugs. Safe to
  run anytime, not gated on coverage — in fact running them *now*, early
  and often, is strictly better than waiting, per the 2026-10-08 findings
  below.
- **Menu/flag completeness** (Categories B and C) — is the data
  *honest and sufficient*, not just well-formed? These need human/audit
  judgment, not a mechanical fix, and are naturally the "QA each state"
  pass the owner is preparing for.

## How the flags column actually works (read this before writing any query)

`menu_items.flags` is a **sparse** JSONB object: **only non-`clear` values
are ever written**. An allergen key that's absent means `clear`, exactly
matching `app/index.html`'s own fallback (`(it.flags||{})[a]||"clear"`).
This has been the convention since the very first seed data (2026-09-22)
through the most recent batch — confirmed by spot-checking both ends of
the timeline on 2026-10-08. **Do not treat a missing key as a bug** — an
earlier draft of this validation effort did, and it was wrong; see the
2026-10-08 log below. The ONLY valid values are `clear`, `may`, `shared`,
`contains`; the ONLY valid keys are `peanut`, `treenut`, `dairy`, `egg`,
`wheat`, `soy`, `fish`, `shellfish`, `sesame`.

## Category A — flag integrity (run anytime, zero judgment needed)

```sql
-- A1: non-canonical keys (same bug class as the 2026-09-22/23 tree_nut/milk
-- incidents in skills/db-publisher/SKILL.md 2a — a misnamed key holds a
-- real flag value the app will never read, which is a silent false-CLEAR)
select key, count(*) from menu_items, jsonb_object_keys(flags) as key
where key not in ('peanut','treenut','dairy','egg','wheat','soy','fish','shellfish','sesame')
group by key order by count(*) desc;

-- A2: non-canonical values (same bug class as the 2026-10-01 may_contain
-- incident — RANK[] in app/index.html doesn't recognize it, and an
-- unrecognized value compares as LESS than clear, so it silently renders
-- as fully clear)
select v, count(*) from menu_items, jsonb_each_text(flags) as kv(k,v)
where v not in ('clear','may','shared','contains')
group by v order by count(*) desc;

-- A3: zero-item restaurants (shouldn't exist; a real gap if found)
select r.id, r.name, r.state from restaurants r
where not exists (select 1 from menu_items mi where mi.restaurant_id=r.id);
```

Both A1 and A2 should return **zero rows**. If they don't, fix by
rebuilding the affected rows' `flags` object (rename bad keys / remap bad
values, preserving the real value underneath) — see the 2026-10-08 fix
below for the exact pattern. Never backfill a missing key with a guessed
value; the sparse convention already means "missing = clear," so there's
nothing to backfill.

## Category B — thin menus (needs a human read, not a mechanical fix)

```sql
-- Item count per restaurant, flagged under 15 (adjust threshold as the
-- dataset's own distribution becomes clearer with more coverage)
select r.id, r.name, r.state, r.city, r.data_source, r.source_document,
       count(mi.id) n
from restaurants r left join menu_items mi on mi.restaurant_id=r.id
group by r.id, r.name, r.state, r.city, r.data_source, r.source_document
having count(mi.id) < 15
order by r.state, n asc;
```

**Before treating a hit as a bug, read `source_document` first.** As of
2026-10-08, every thin-menu restaurant checked had already honestly
disclosed the limitation there (per the project's own source-quality
convention) — e.g. "Menu detail is genuinely thin — this stand effectively
sells one burrito," "only 3 items could be verified," "RECOMMEND STAFF
VERIFICATION." These are known, transparent, low-confidence sources, not
silent failures — the pipeline is working as designed. The real QA
question per state is narrower than "is anything thin": **does every thin
entry have an honest `source_document`, and does the app surface that
text clearly enough that a user would see it before trusting a score?**
A thin entry with no explanation in `source_document` is the actual bug to
chase.

116 restaurants were under 15 items as of 2026-10-08 (out of 1,653 — about
7%), all independents, all with a disclosed weak-source note on spot check.

## Category C — empty-flags items (`flags = '{}'`) — a real review queue

```sql
-- C1: chain-level first — one chain fix corrects every copied location
select c.name chain, count(distinct mi.id) empty_items, count(distinct r.id) locations
from menu_items mi
join restaurants r on r.id=mi.restaurant_id
join chains c on c.id=r.chain_id
where mi.flags='{}'::jsonb
group by c.name order by empty_items desc;

-- C2: independent restaurants with empty-flags items (lower priority —
-- one restaurant each, not copied anywhere)
select r.id, r.name, r.state, count(mi.id) n
from menu_items mi join restaurants r on r.id=mi.restaurant_id
where mi.flags='{}'::jsonb and r.chain_id is null
group by r.id, r.name, r.state order by n desc;
```

`{}` is valid under the sparse convention (a genuinely allergen-free item,
e.g. a plain soda or black coffee) — but it's also indistinguishable from
"the extraction never actually found this item's row in the source," so
unlike Category A this needs a real read, not a blanket fix. **As of
2026-10-08: 6,203 items across 14 chains (1,558 at Chili's alone, 19
locations; also Sonic, Dunkin', Subway, Chick-fil-A, IHOP, Arby's,
Chipotle, Panera, Jimmy John's, Five Guys, Crackin' Crab, Olive Garden,
Domino's)** — all `official_matrix=true` sources, so the right fix is
re-reading each chain's actual official document for exactly these items,
not guessing. Spot-checked example: Arby's "Steak Nuggets" (breaded,
fried) with zero flags at all — plausible the extraction missed that
row in the matrix, not plausible the item is genuinely free of all 9
allergens. **Prioritize this list first** when the real QA pass starts —
each chain fix is one `chain-menu-importer` re-check, not 5–30 separate
restaurant fixes. 3,679 more empty-flags items sit on independent
restaurants, lower priority since each only affects one location.

## Suggested per-state QA procedure (once nationwide coverage is reached)

1. Re-run Category A globally first (should already be clean if run
   periodically — don't let it silently regress).
2. Work the Category C chain list to zero before touching any state's
   independents — it's the highest-leverage fix per hour spent.
3. Per state: run Category B's query filtered to that state. For each hit,
   confirm `source_document` discloses the limitation; if not, that's the
   real finding — re-extract or flag for a fresh pass, don't just accept it.
4. Record sign-off somewhere durable (an `ops_log` row, `event:
   'qa_signoff'`, `detail: {state, checked_at, findings}` fits the existing
   pattern better than a new table).
5. Any fix found needs a menu *replace* (delete old items, insert new) —
   do this interactively, not via the Routine; see
   `skills/db-publisher/SKILL.md` 3a/3b for why DELETE and git-staged fixes
   don't work from an unattended firing.

## 2026-10-08 — first real run of this toolkit, what it actually found

Ran Category A for the first time against the full live dataset (136,594
items). Found and fixed three real, unambiguous bugs, all live in
production until today:
- **2,452 items** across ~70+ restaurants using non-canonical keys
  (`milk`, `tree_nut`, `tree_nuts`, `treenuts`, `peanuts`) — same bug class
  as the 2026-09-22/23 incidents, recurring in later batches despite the
  documented rule.
- **6,597 items** (16 restaurants, most concentrated in one — "Fishnet
  Seafood") stored flags as JSON booleans (`true`/`false`) instead of the
  four-value string convention — an entirely different ingestion format
  that slipped through, collapsing `may`/`shared` nuance into a binary
  signal. Mapped `true`->`contains` (the cautious reading — never map a
  bare positive signal to anything softer) and `false`->`clear`.
- **627 items** (7 restaurants) using `may_contain` again — the exact
  value already fixed project-wide on 2026-10-01 (see
  `skills/db-publisher/SKILL.md` 1b), recurring in batches run since that
  fix, same instruction-following gap seen with the git-commit habit.

All three fixed in one combined UPDATE (rename bad keys, remap bad values,
single pass, zero collisions). Re-ran Category A after: zero bad keys,
zero bad values, confirmed clean. The original draft of this check also
flagged "missing canonical key" (65,744 items) as a bug — spot-checking
the earliest (2026-09-22) and most recent (2026-10-08) batches showed
identical behavior, proving it's the sparse-storage convention working as
designed, not a defect; corrected this file's own understanding before
it caused a bad backfill.
