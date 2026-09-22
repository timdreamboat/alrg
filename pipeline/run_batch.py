#!/usr/bin/env python3
"""
ALRG headless batch runner (mode B).
Requires env: ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY
Runs: next N queued metros -> extractor -> analyzer -> audit -> publish.

Claude Code executes the skill steps; this script is the thin orchestrator
that (a) picks work, (b) invokes claude -p per step, (c) updates state.
"""
import json, os, subprocess, sys, urllib.request

N_METROS = int(os.environ.get("BATCH_METROS", "2"))
SB_URL = os.environ["SUPABASE_URL"].rstrip("/")
SB_KEY = os.environ["SUPABASE_SERVICE_KEY"]

def sb(method, path, body=None):
    req = urllib.request.Request(
        f"{SB_URL}/rest/v1/{path}", method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"apikey": SB_KEY, "Authorization": f"Bearer {SB_KEY}",
                 "Content-Type": "application/json", "Prefer": "return=representation"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or "[]")

def claude(prompt):
    """Run one non-interactive Claude Code task and return its output."""
    out = subprocess.run(["claude", "-p", prompt, "--output-format", "text"],
                         capture_output=True, text=True, timeout=3600)
    if out.returncode != 0:
        raise RuntimeError(out.stderr[:2000])
    return out.stdout

def main():
    metros = sb("GET", f"metros?status=eq.queued&order=rank&limit={N_METROS}")
    if not metros:
        print("Metro queue empty — check the chains table or maintenance mode.")
        return
    for m in metros:
        name = f"{m['name']}, {m['state']}"
        print(f"=== {name} ===")
        sb("PATCH", f"metros?id=eq.{m['id']}", {"status": "in_progress"})
        result = claude(
            f"Process the metro {name} for ALRG. Follow CLAUDE.md's autonomous "
            f"priority order and standing conventions exactly. Steps: "
            f"1) use the restaurant-menu-extractor skill for this metro's core zips, "
            f"2) run allergen-analyzer on the output, "
            f"3) run the QA audit per skills/qa-allergen-auditor/SKILL.md, retrying "
            f"once on FAIL per that skill's rule, "
            f"4) publish on PASS or PASS WITH CORRECTIONS with no owner review — "
            f"only a second consecutive FAIL opens a needs-owner board card, "
            f"5) update the GitHub Projects board and write an ops_log entry. "
            f"Reply ONLY with the one-line completion summary.")
        print(result.strip())
        sb("PATCH", f"metros?id=eq.{m['id']}",
           {"status": "complete", "completed_at": "now()"})
    print("Batch complete.")

if __name__ == "__main__":
    sys.exit(main())
