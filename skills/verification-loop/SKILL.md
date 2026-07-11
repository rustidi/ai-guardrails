---
name: verification-loop
description: "Run a practical quality gate before closing work — typecheck, sync/consistency check, and task-specific validation. Scale the checks to the size of the change."
---
# Verification Loop

Use this before considering a meaningful task complete.

## Baseline Checks

Run the smallest complete set that matches the task.

### Default

- run the repo's sync/consistency check

### Code Changes

- run the type checker
- run the repo's sync/consistency check

### Larger or Cross-Package Changes

- run the full verify pipeline (typecheck + sync check + build)

## Task-Specific Additions

- Prisma/schema work:
  - regenerate the ORM client
  - run the migration
- package-local build checks:
  - build the affected workspace package(s) individually

## Final Review Questions

- Did we update delivery docs?
- Did we preserve the API contract, or change it intentionally?
- Did we introduce new env vars, migrations, or storage assumptions?
- Did we leave debug logging or incomplete TODOs behind?
