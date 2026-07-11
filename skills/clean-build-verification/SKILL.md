---
name: clean-build-verification
description: "Before committing changes that touch workspace deps, DB schema, or >500 LOC — verify a real clean build. A green typecheck is not proof of correctness."
---
# Clean-build verification

> Sanitized example skill.

## The trap this exists to prevent

`npm run typecheck` passing feels like "it works." It isn't. Typecheck validates types; it does **not**
prove that:

- a fresh `npm install` resolves the same dependency tree (a stale `node_modules` can hide a missing dep,
  or silently ignore an `overrides` entry that only applies on a clean install)
- the production build actually compiles (a build step can fail where a per-file typecheck passes)
- a workspace dependency you bumped is consistent across all apps that consume it

"Typecheck green ≠ correctness" is the whole point.

## When to run this

Before committing, if the change touches any of:
- **workspace dependencies** (a shared package version bump, a new dep)
- **the DB schema** (generated client can drift from the schema)
- **more than ~500 lines** (large diffs hide integration breaks)

## What it does

1. Clean the dependency tree and reinstall from the lockfile — no stale cache.
2. Regenerate any code-gen artifacts (ORM client, shared types).
3. Run the **production build**, not just the typecheck.
4. Confirm the lockfile is included in the commit (a scoped commit that drops the lockfile ships a build
   that only works on your machine).

## The lesson

Two real failure modes this caught:
- An `overrides` entry that silently did nothing because it was applied against a stale `node_modules` —
  the vulnerable transitive dep was still there after "the fix."
- A scoped commit (`git commit -- path/to/files`) that captured the code change but **not** the lockfile,
  so CI built a different dependency tree than the author tested.

The discipline: a diff is not verified until a clean, from-lockfile production build is green — and the
commit that carries it also carries the lockfile.
