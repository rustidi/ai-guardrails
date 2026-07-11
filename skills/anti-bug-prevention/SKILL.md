---
name: anti-bug-prevention
description: "Production deploy safety pipeline. Six patterns for catching production failures before they ship — re-review your own fixes, an anti-bug catalogue at design phase, atomic days vs safe rollback points, surprise zones with ENV fallbacks, idempotent SQL migrations by default, and excluding test files from the production tsconfig. Applies to any multi-day sprint, any migration, any change with tests."
---
# Anti-bug prevention pipeline

> Sanitized example skill. Each pattern below cost a real production incident or a near-miss.

Apply this on any change larger than a single working day — not "when I remember."

## Pattern 1 — Re-review your own fixes is a separate step

**Problem:** "Fixed per review" ≠ "Reviewed." Your own fixes can contain fresh bugs. In one real case, review round 1 found 6 blockers; after applying the fixes, round 2 (same reviewers, focused on the fixes) found **2 more CRITICAL + 4 HIGH — inside the fixes**. Deploying after round 1 would have been a production failure.

**Rule:**
1. Round 1 review (type reviewer / DB reviewer / QA / prompt engineer)
2. Apply fixes
3. **Round 2 review** — same agents, explicit focus "check my fixes"
4. Only after round 2 — deploy

**When mandatory:**
- Any review found ≥ 2 CRITICAL/HIGH blockers → re-review required
- Migration / DB schema / threading-related fixes → re-review even on 1 blocker
- Multi-agent review (3+ agents found different things) → re-review required — fixes can conflict with each other

**Anti-pattern:** "typecheck green after my fixes = ready to deploy." Typecheck catches syntax, not semantics. Re-review catches semantics.

## Pattern 2 — Anti-bug catalogue at design phase, not in code

**Problem:** "Tests will catch bugs" — no. Tests catch what you predicted. Categories of bugs you didn't foresee are the mine under the floor.

**Rule:** before writing code, ask a design agent (architect / board) an explicit question: "find 10 potential bugs in this plan." Each bug → assigned to a specific sprint day + a defensive recipe in code from day one.

**Template:**
```
| # | Bug | Mitigation |
|---|---|---|
| B1 | CVPixelBuffer use-after-free (Vision async) | Day 2: pixelBuffer.deepCopy(via: pool) as the first line |
| B2 | Priority inversion: audio thread waits on vision queue lock | Day 3: os_unfair_lock_trylock or an SPSC ring-buffer |
| ... | ... | ... |
```

**When mandatory:**
- Sprint > 3 days
- Touches threading / memory ownership / IPC / migrations
- Extends a hot-path module (audio engine, video encoder, ML inference)

**Anti-pattern:** "we'll solve it if it comes up." In production "comes up" = an incident with an emergency hotfix.

## Pattern 3 — Quality gates between days: atomic vs safe-rollback

**Problem:** "On day 5 something broke" in a sprint without gates = roll back all 5 days at once. An atomic block for days 1-4 plus safe stops after days 5/7 gives you two rollback points instead of one all-or-nothing.

**Rule:** for a sprint > 5 days:

1. **Atomic block** — a sequence of days that CANNOT be stopped mid-way. Usually: DB migration + code-wide rename + critical refactor. If you stop, old code + new DB = production crash.

2. **Safe rollback points** — points where you can stop the sprint and ship a smaller version. Usually: after Phase A (without Phase B), after core-feature (without UI polish).

3. **Quality gate after each day** — a specific grep / SQL / unit-test that is green and BLOCKS the start of the next day.

**Template:**
```
| Day | Quality gate (blocker for next day) | Checkpoint |
|---|---|---|
| 1 | grep "OldTableName" = 0 matches in src/, integration test green | — |
| 2 | unit tests green + audio invariant manual check | — |
| 3 | AudioMixerNoObserverTest green (regression FIRST) | ⚠️ checkpoint #1 |
```

**Anti-pattern:** "we'll check everything on day 10." By day 10 it's unclear when what broke. Gates localize it.

## Pattern 4 — Surprise zones with ENV fallbacks

**Problem:** confidence in new patterns is rarely 100%. Active-speaker-detection accuracy may be 70% on your data instead of 85% in the research paper. Without a fallback = redeploy.

**Rule:** every zone of uncertainty (new ML threshold, performance assumption, third-party API behavior) → an ENV switch in code from day one. Default = your hypothesis. If there's a problem — `ENV=value` in one minute, no redeploy.

**Template:**
```
- ACTIVE_SPEAKER_HEURISTIC_DISABLED=true  → fall back to a simple rule
- SCREEN_FACE_MATCH_THRESHOLD=0.92        → tune threshold for screen
- VOICE_MATCH_THRESHOLD=0.85              → tune voice threshold
- FUSION_FEATURE_ENABLED=false            → kill-switch the whole feature without a code rollback
```

**Document in the sprint file** under a "Surprise zones" section — which zones, which ENV for each, and the trigger to activate it (e.g. "if accuracy < 70% on the first 5 records").

**Anti-pattern:** hardcoded magic numbers. In production you'll learn that 0.7 is too high / too low — and have nothing to tune.

## Pattern 5 — Idempotent SQL migrations = default

**Problem:** a hotfix once exposed two historical migrations that fail on a clean DB (`column "isPersonal" does not exist`, `relation "MediaAsset" does not exist`). Cause: `prisma db push` created columns/tables without migrations; it survived on prod but failed on a fresh dev/staging DB.

**Rule:** all DDL operations are idempotent by default.

```sql
-- ALWAYS:
ALTER TABLE "X" ADD COLUMN IF NOT EXISTS "y" TEXT;
CREATE TABLE IF NOT EXISTS "Z" (...);
CREATE INDEX IF NOT EXISTS "X_idx" ON "X"(...);

-- FK constraints via DO-block (no native IF NOT EXISTS):
DO $$ BEGIN
  ALTER TABLE "X" ADD CONSTRAINT "X_y_fkey" FOREIGN KEY ...;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
```

**Cost on prod:** zero (no-op if it already exists).
**Benefit on dev/staging:** works from any DB snapshot, safe to re-run.

**Anti-pattern:** `ALTER TABLE x ADD COLUMN y` without `IF NOT EXISTS`. It passes once; the second time = `column already exists` → migration failed, and downstream migrations too.

## Pattern 6 — Test files → exclude from production tsconfig

**Problem:** a production build once failed on the deploy host with `Cannot find module 'vitest'` from `src/foo.test.ts`. Cause: the host doesn't install devDependencies, `tsc` tries to compile ALL `.ts` under src/ including tests, and vitest is unresolved.

**Rule:** in every `tsconfig.json` that compiles for production:

```json
{
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.test.ts", "src/**/*.integration.test.ts"]
}
```

Applies to every production-compiled workspace (API, web, workers). Vitest still runs tests directly (bypassing tsc). The production build never sees them.

**Anti-pattern:** "tests live in `src/` next to the code, vitest will find them" — yes it will, but so will `tsc`. Prod deploy fails.

## Operating discipline

At the start of any sprint > 1 day:

1. **Before code:**
   - Anti-bug catalogue (pattern 2) — design agent gives 5-10 predicted bugs
   - Surprise zones (pattern 4) — which ENV switches to add up front
   - Quality gates (pattern 3) — atomic days vs safe stops

2. **During code:**
   - Idempotent migrations (pattern 5) by default
   - Test-file excludes (pattern 6) as the first line when adding new tests

3. **After applying review fixes:**
   - Re-review (pattern 1) mandatory if round 1 found ≥ 2 CRITICAL/HIGH
   - Re-review even on 1 blocker for migration / threading / DB

4. **Before deploy:**
   - All quality gates green
   - Re-review (if any) confirmed the fixes introduced no new bugs
   - ENV fallbacks documented

## When NOT to apply the whole pipeline

- A 1-2 line hotfix (typo / log message) — overkill
- Pure docs / README / sprint files — not code
- A config change like a `package.json` script — no quality gates needed

But even in a hotfix, apply pattern 6 (test exclude) if a tsconfig is touched, and pattern 5 (idempotent SQL) if a migration is touched.
