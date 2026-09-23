# Ingredient backfill — tracked backlog

As of 2026-09-22, `menu_items.note` for almost every chain-sourced item is
either empty, a bare category label ("Donuts - Strawberry Frosted Donut"),
or a source citation ("From Subway official U.S. Allergy and Sensitivity
Information, January 2026") — none of that is a real ingredient list. The
owner wants menu items in the app to expand and show actual ingredients,
not just allergen flags. That UI work is intentionally on hold (owner's
call, 2026-09-22) until this backfill makes real progress.

**Why this is a separate document from the allergen matrix, not just a
re-read of what we already fetched:** the "allergen guide" / "nutrition &
allergen chart" PDFs already used for every chain in this repo are
compliance tables (item × allergen columns), not ingredient statements.
Most chains publish those as a **separate** document. Confirmed so far:

- **Subway** — has a real ingredient PDF, distinct from the allergen doc:
  `https://media.subway.com/dam/urn:aaid:aem:aa3ade30-7496-41bd-a7e1-4964bebb89de/original/as/us-ingredients-en.pdf`
  ("US Product Ingredient Guide, January 2026"). Not yet fetched — my
  local session's network couldn't reach this specific asset path
  (connection reset/timeout on the exact DAM URL, even though
  subway.com and media.subway.com's root both load fine locally) while
  the cloud Routine's sandbox has already proven it can reach
  media.subway.com for the allergen PDF, so this needs to run there.
- **Five Guys** — strong evidence of a real ingredient breakdown
  (component-level, e.g. "Buns contain: Water, Salt, Sugar, Vegetable
  Shortening (Contains Soy), Milk, Eggs, Bleached Bread Flour, Yeast,
  Sesame Seeds") in their nutrition/allergen guide PDF at
  `fiveguys.com/wp-content/uploads/2026/08/Five-Guys-US-Nutrition-Allergen-Guide-English-June-2026.pdf`
  — worth re-checking whether the version already fetched for allergens
  has this detail before treating it as a separate fetch.
- **Chick-fil-A** — no single ingredient-statement PDF found; ingredients
  are published per menu item on individual product pages
  (chick-fil-a.com/menu/entrees/...) via an "Ingredients" dropdown. Real
  data, but ~156 pages to visit instead of one document — much higher
  effort per item than the others. Lowest priority until the cheaper
  chains are done.
- **Panera, Olive Garden, Jimmy John's, Arby's, Dunkin'** — not yet
  researched for a genuine ingredient-statement document. Don't assume
  one exists; confirm the same way as above (search for "ingredient
  statement" / "ingredient guide" / "product ingredients" specifically,
  not just the allergen chart) before spending fetch effort.

## Hard rule

Never fabricate ingredient text from menu item names or general
knowledge ("Caesar Salad" → guessed ingredients) — same standard as
allergen flags. If a chain has no publicly available real ingredient
statement, leave `note` as-is and mark it here as "no source found"
rather than inventing one. This is consumer-facing allergen-adjacent
data; a fabricated ingredient list is worse than an honest gap.

## Progress

| Chain | Status | Source | Items |
|---|---|---|---|
| Subway | done (2026-09-23) | `us-ingredients-en.pdf` fetched, parsed (pypdf + pdfplumber, cffi reinstall needed), matched by item name and written to `menu_items.note` for all 31 Denver locations. 62 of 64 distinct items got real ingredient text (1,922 rows updated). 2 items — "Chicken, Grilled (Buffalo sauce)" and "Spicy Italian Meats (pepperoni, salami)" — have no matching entry in the PDF (not real distinct Subway products in this document) and were left with their original citation note per the no-fabrication rule. | 1,984 (1,922 updated, 62 left as-is) |
| Five Guys | not started | check existing fetched PDF for component ingredients first | 253 |
| Chick-fil-A | not started | per-item pages, no single doc found yet | 1,248 |
| Panera Bread | not started | needs research | 985 |
| Olive Garden | not started | needs research | 525 |
| Arby's | not started | needs research | 1,044 |
| Jimmy John's | not started | needs research | 396 |
| Dunkin' | not started | needs research | 4,068 |
| Independent restaurants | partial | `note` already has real short descriptions from original menu extraction for most; 10 of 124 items have none | 124 |
| Texas Roadhouse | no source found (2026-09-23) | Checked at chain-import time: the official allergen source (Special Diets Wizard on nutritionix.com) is a per-item allergen filter tool, not an ingredient-statement document — no separate "ingredient guide" found on texasroadhouse.com or nutritionix.com. `note` left null per the no-fabrication rule. | 258 |

Update this table (status + a one-line note on what was found/done) as
each chain gets worked — don't just update `menu_items` silently and
leave this file stale, it's the at-a-glance progress record for the
owner.
