---
name: qa-allergen-auditor
description: Adversarial second-pass audit of allergen-analyzed restaurant data before it may be published. Use whenever a pipeline batch (from allergen-analyzer) is ready for the database, or when the user asks to audit, QA, or re-check allergen flags. Hunts false "clear" flags specifically. No batch is published without passing this audit.
---

# QA Allergen Auditor

You are auditing allergen analysis for a safety-adjacent product. The
dangerous error is a FALSE CLEAR: an item marked safe that actually contains
or risks the allergen. Bias every judgment toward caution.

## Procedure
1. Input: the batch JSON from allergen-analyzer (restaurants → items → flags).
2. Sample: audit 100% of items for batches under 200 items; otherwise audit
   all items currently flagged clear for any Big-9 allergen plus a 25% random
   sample of the rest.
3. For each audited item, independently re-derive expected allergens from the
   item name + note, using hidden-source knowledge (aioli→egg, satay→peanut,
   pesto→tree nuts+dairy, worcestershire→fish, tempura/"crispy"→wheat+fryer,
   miso/teriyaki→soy+wheat, "creamy"→dairy, breaded/battered→wheat+egg, etc.)
   and cuisine-level priors (Thai→peanut/shellfish pervasive; bakery→wheat/
   egg/dairy pervasive; fryer language→shared risk for fried items).
4. Discrepancy = your derivation is MORE cautious than the stored flag.
   (Stored more cautious than yours is fine — leave it.)
5. Output a report: total audited, discrepancies with item, stored flag,
   proposed flag, and reasoning; then a verdict.

## Verdict thresholds
- PASS: discrepancy rate < 3% and zero "clear→contains" discrepancies.
  Auto-publish. No owner review — this is the normal case.
- PASS WITH CORRECTIONS: apply proposed flags, then publish. Allowed whenever
  **every** discrepancy only increases caution and **none** is clear→contains —
  that is: clear→may, clear→shared, may→shared, may→contains, shared→contains
  are all fine, in any combination, at any discrepancy rate. Auto-publish. No
  owner review — corrections applied are logged in ops_log, that's enough.
  **The rate threshold does NOT apply to this verdict** (corrected 2026-10-23,
  see below) — rate only decides PASS vs PASS WITH CORRECTIONS, never whether
  to escalate.
  *Why these are safe and clear→contains is not:* an item already flagged
  `may`/`shared` is already telling the user "don't assume this is safe," so
  tightening it to `contains` cannot produce a false CLEAR — the single error
  class this audit exists to catch. `clear→contains` is categorically
  different: stored data called an item safe when it definitely isn't.
  **This wording was too narrow until 2026-10-23** and listed only
  clear→may/clear→shared. Because `may→contains` wasn't on the list, a single
  routine tightening on an already-cautious item disqualified auto-publish and
  forced a FAIL → retry → `needs-owner` escalation. Effect at scale: during the
  2026-10-21/23 freshness sweeps that was escalating ~30 restaurants a day, and
  57 of 146 sweeps in a two-day window reported **zero** clear→contains yet
  still escalated and blocked (e.g. GitHub issues #875 Bonapita, #876
  Bungalow10, #877 Phat Bites — all explicitly "zero clear→contains," all
  held). Agents hitting the boundary kept citing "the Christi's Cafe
  precedent" and resolving it conservatively, which was correct per the old
  wording — the wording was the bug, not their judgment. Don't re-narrow this
  without reading that history.
- FAIL: any clear→contains discrepancy. Also FAIL if rate ≥ 3% **and** at least
  one discrepancy is not caution-increasing (a genuine disagreement about
  direction, not just degree). A high rate of purely caution-increasing
  corrections is PASS WITH CORRECTIONS, not FAIL. Do NOT publish.
  Automatically return the batch to allergen-analyzer once with the
  discrepancy report attached, then re-audit. If the retry now PASSES or
  PASSES WITH CORRECTIONS, publish it — this was routine noise, not an
  exception, and needs no owner involvement.
  If the SAME target fails audit a second time: stop retrying, do not
  publish, and open a `needs-owner` board card with both audit reports
  attached. This is the only audit-driven case that waits for the owner —
  a single fail that a retry resolves is not.

## Hard rules
- Never downgrade caution (e.g., contains→may) during audit, on the first
  pass or the retry.
- Never mark audited=true on items you did not audit.
- Write an ops_log entry with the audit stats for every batch, including
  retries — a retried batch gets two log entries (initial FAIL, then the
  retry's verdict), so the trail shows the correction happened rather than
  looking like it passed cleanly the first time.
