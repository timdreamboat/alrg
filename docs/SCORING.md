# ALRG Confidence Score — Spec v1

Input: a restaurant's menu items with per-allergen flags
(contains | shared | may; absent = clear) and the user's allergen profile.

Per item: worst status across the profile's allergens.

Score:
  base     = 100 * (clear_items + 0.45 * caution_items) / total_items
             (caution = may or shared)
  penalty  = (contains_items / total_items) * 22     # allergen density
  verified = +6 if restaurant-verified OR official chain allergen matrix,
             else -3                                  # data certainty
  score    = clamp(round(base - penalty + verified), 4, 99)

Tiers: 80–100 High Confidence · 50–79 Proceed with Care · 0–49 High Risk.

Rules for changes:
- Never let any restaurant reach 100 (we are not a guarantee).
- Any change = version bump here + re-score note in ops_log + user-facing
  changelog entry. The score must remain explainable in one sentence.
