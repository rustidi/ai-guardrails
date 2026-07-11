---
name: reviewer-gate
description: "Run the machine review gate over the current repo — map changed files to the specialist reviewers they require, scan the diff for hardcoded secrets and swallowed errors, and block until REVIEW_LOG.md carries a PASS verdict from each required reviewer. Invoke before committing, pushing, or deploying."
disable-model-invocation: true
---

# Reviewer Gate

Run the machine gate that decides whether the current change is allowed to ship.

## What it checks

1. **Blast radius → required reviewers.** Changed files map to mandatory specialists
   (auth/session/token → `auth-flow-reviewer`; payments/billing/pricing → `security-reviewer`
   + `money-math-invariants`; api/route/handler → `security-reviewer`).
2. **Diff tripwires.** The changed lines are scanned for concrete anti-patterns:
   - a **hardcoded secret** (HARD — blocks unconditionally, no sign-off clears it),
   - a **swallowed error** (empty `catch {}` / bare `except: pass`),
   - **money divided by 100 in a view** (probable unit bug).
3. **Sign-off.** Each required reviewer must have a PASS line in `REVIEW_LOG.md`
   (e.g. `- security-reviewer: CLEAR — secret now read from env`).

If a hard finding remains, or any required reviewer is missing a PASS, the gate exits
non-zero and the commit/deploy is blocked.

## Run it

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/verify-reviewer-gate.sh
```

Run against a specific repo directory:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/verify-reviewer-gate.sh /path/to/repo
```

## Escape hatch (explicit, logged)

```bash
REVIEWER_GATE_BYPASS=1 "${CLAUDE_PLUGIN_ROOT}"/scripts/verify-reviewer-gate.sh
```

## Notes

- Enforcement is **opt-in**: a repo with no `REVIEW_LOG.md` passes untouched, so the
  bundled `PreToolUse` hook never surprises a repo that has not adopted the workflow.
- The same script backs the automatic hook (fires before `git commit` / `git push` /
  `deploy` in Bash) and this manual skill.
