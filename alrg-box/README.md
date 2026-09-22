# ALRG — Allergen Lifestyle Restaurant Guide (v2, fresh start)

Everything needed to run ALRG free: a live PWA on GitHub Pages, a Supabase
database, and a Claude-powered data pipeline.

Start here → SETUP.md (your only ~30 minutes of clicking, ever).
Then Claude Code takes over → CLAUDE.md is its briefing.

Layout:
- app/        the consumer app (static PWA; config.js is the only hand-edited file)
- supabase/   schema.sql — full database, security, Denver seed data
- pipeline/   batch collection: free interactive mode + optional paid unattended mode
- skills/     qa-allergen-auditor + db-publisher (pair with your existing
              restaurant-menu-extractor and allergen-analyzer skills)
- docs/       SCORING.md — the confidence score spec v1
