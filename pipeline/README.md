# Pipeline — how ALRG data gets collected

The service validates and publishes on its own. The owner is not a
per-batch approval gate — see CLAUDE.md's "Standing conventions" for the
exact (short) list of things that still escalate. The owner's real
checkpoint is the live app's community verifications, reviewed periodically
— not this pipeline.

Priority order, every time the pipeline runs (manually or via the Routine):
1. Chains first — one unanalyzed row in `chains` covers every location of
   that chain. Highest leverage for reaching "nationwide" fast.
   Flow: chain-menu-importer → qa-allergen-auditor → db-publisher.
2. Then metros — the next queued metro by rank.
   Flow: restaurant-menu-extractor → allergen-analyzer →
   qa-allergen-auditor → db-publisher.
3. Both empty → maintenance mode: freshness sweep on the oldest data.

A PASS or PASS WITH CORRECTIONS audit publishes immediately, no owner
review. Only a second consecutive FAIL on the same target opens a
needs-owner board card — see qa-allergen-auditor's retry rule.

## Running it

A) INTERACTIVE: owner types "Run tonight's data batch" in Claude Code and
   it works through the priority order above once.

B) CLOUD ROUTINE — the default, since the owner has a Pro/Max plan. A saved
   Claude Code cloud config (this repo + the Supabase connector) that fires
   on a schedule from Anthropic's infrastructure, laptop closed or not, and
   draws on normal subscription usage rather than separate API billing.
   Create with `/schedule` in Claude Code, or at claude.ai/code/routines.
   Suggested setup — schedule at the minimum interval (hourly) so the queue
   clears as fast as the audit pipeline can sustain:
     "Every hour, follow CLAUDE.md's autonomous priority order exactly:
      chains first, then metros, then maintenance mode once both are
      empty. Publish on PASS or PASS WITH CORRECTIONS with no owner
      review. Only open a needs-owner card on a second consecutive audit
      fail for the same target, or a safety-relevant community report.
      Update the GitHub Projects board per CLAUDE.md."
   One-time setup in the routine's environment settings: widen network
   access beyond the default "Trusted" allowlist (Custom or Full) — the
   extractor and chain-importer both need to reach ordinary restaurant and
   chain websites, not just package registries. Test with "Run now" before
   trusting the hourly fire. Watch subscription usage at
   claude.ai/settings/usage for the first few days at this cadence and dial
   the interval back (e.g. every 4 hours) if it's burning faster than
   expected — hourly is the ceiling, not a fixed requirement.

C) GITHUB ACTIONS (fallback only, not the default): use only if Routines
   are ever unavailable. Enable .github/workflows/nightly.yml and add repo
   secrets ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY. Bills
   separately per token instead of using the subscription.

State lives in the database (`metros`, `chains`, `ops_log`), not in chat,
so all three modes are interchangeable — switch freely without losing
progress. run_batch.py documents mode C's exact orchestration.
