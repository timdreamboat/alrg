# ALRG Setup — Your Only 30 Minutes

Everything in this repo is pre-built. These are the ONLY steps that must be you
(account creation requires your identity and your agreement to each service's terms).
Do them in order. After step 6, Claude Code does everything else.

---

## 1. GitHub account + repo (~5 min) — FREE
1. Go to github.com → Sign up (use your normal email).
2. Click "+" → "New repository" → name it `alrg` → Public → Create.
3. On the empty repo page choose "uploading an existing file" and drag the
   entire contents of this folder in → Commit.
   (Claude Code can also do this push for you in step 6.)

## 2. Supabase account + database (~10 min) — FREE
1. Go to supabase.com → Start your project → sign in with your GitHub account.
2. New project → name `alrg` → set a database password (save it) → region: US West → Create.
3. Left sidebar → SQL Editor → New query → paste the ENTIRE contents of
   `supabase/schema.sql` → Run. (Creates all tables + security + Denver sample data.)
4. Left sidebar → Project Settings → API. Copy two values:
   - Project URL   (looks like https://xxxx.supabase.co)
   - anon public key (long string)
5. Open `app/config.js` and paste those two values where marked.

## 3. Free hosting via GitHub Pages (~3 min) — FREE
1. In your GitHub repo → Settings → Pages.
2. Source: "Deploy from a branch" → Branch: main → folder: `/app` → Save.
3. Your app is live in ~1 minute at https://YOURUSERNAME.github.io/alrg/
   (Later: point alrgfree.com here from GoDaddy → Settings → Pages → Custom domain.)

## 4. Install Claude Code (~5 min) — included in your Claude subscription
1. Install Node.js from nodejs.org (LTS button, default options).
2. Open Terminal (Mac) or PowerShell (Windows) and run:
   npm install -g @anthropic-ai/claude-code
3. Run `claude` once and log in with your Claude account when prompted.

## 5. Give Claude Code the repo (~2 min)
In Terminal:
   git clone https://github.com/YOURUSERNAME/alrg
   cd alrg
   claude
Then type: "Read CLAUDE.md and confirm you understand the project."

## 6. From here on, you type sentences, not code
Examples of everything else being hands-off:
- "Finish any setup this repo needs and deploy."
- "Run tonight's data batch."            ← collects the next metros
- "Import the top 25 chains."            ← national footprint begins
- "Show me this week's ops report."

## 7. Full access: repos + browser (~5 min) — FREE
1. Install the GitHub CLI from cli.github.com (default options).
2. In Terminal: `gh auth login` → follow the prompts (choose GitHub.com,
   HTTPS, log in with a browser). This lets Claude Code create repos, issues,
   and PRs on your behalf — no tokens to copy.
3. Optional but recommended: install Claude for Chrome from the Chrome Web
   Store, sign in with your Claude account, pin it. First week, leave its
   permission mode on "Ask before acting."

## 8. Your project board — GitHub Projects, not a separate tool (~5 min) — FREE
No new account needed; it's a tab on the repo you already made.
1. In your `alrg` GitHub repo → "Projects" tab → "New project" → pick the
   "Board" template → name it `ALRG Build`.
2. Set up columns: Backlog · In Progress · In Review · Done (defaults are
   close — just rename/reorder).
3. Add labels if you want them color-coded: `pipeline`, `app`, `scoring`,
   `ops`, `audit-flag`, `needs-owner`.
That's it — Claude Code now keeps this board updated on its own (see
CLAUDE.md). Ask "show me the board" any time for a plain-English summary.

## 9. Make the batch pipeline fully autonomous — the default, not optional
This is Claude Code's own scheduling feature — no GitHub Actions, no API key,
runs on your subscription. In Claude Code:
1. Type: `/schedule every hour, follow CLAUDE.md's autonomous priority order
   for ALRG — chains first, then metros, then maintenance mode`
2. Claude confirms the repo and connectors (your Supabase connector should
   already be selected) and saves it.
3. On the routine's page (claude.ai/code/routines) → environment settings →
   widen network access beyond the default allowlist (Custom or Full) — the
   extractor and chain-importer both need to reach ordinary websites.
4. Click "Run now" once to watch a real run before trusting the hourly fire.
It validates and publishes on its own — you are not a per-batch approval
step. Your actual checkpoint is reviewing pending community verifications
in the app periodically (interim: the Supabase table editor). The only
things that ever wait for you are a repeated audit failure on the same
target or a safety-relevant user report — both show up as a `needs-owner`
card on the project board, nothing else does.
Keep an eye on usage at claude.ai/settings/usage for the first few days;
dial the interval back (e.g. every 4 hours) if hourly burns faster than
expected. Hourly is the ceiling this supports, not a fixed requirement.

## Optional fallback (only if Routines are ever unavailable)
- `.github/workflows/nightly.yml` does the same job via GitHub Actions, but
  bills separately per token instead of using your subscription. Add repo
  secrets ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY to enable it.
- App Store / Play Store: only when you outgrow the PWA (Apple charges $99/yr).

That's it. Nine steps, all free, and none of them repeat.
