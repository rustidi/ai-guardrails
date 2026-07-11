---
name: api-contract-audit
description: "Inventory every API endpoint that surfaces a field to clients BEFORE dropping, renaming, or semantically changing it. Runs in the planning phase whenever a schema change touches a field the frontend reads, or drops/renames any field. Without it, a field quietly stays in the shape of only some endpoints and the client breaks on one page you forgot to check."
---
# API Contract Audit

> Sanitized example skill.

When a Prisma model field is dropped/renamed/semantically changed:
- TypeScript catches places where code **reads** the field from a Prisma row
- Tests catch units that expect specific values
- **Nobody** catches places where the field is **returned to the client** in a response shape

Real incident that motivated this skill: `User.role` was dropped (role now lives only on `Membership.role`). A legacy mapping (OWNER+ADMIN→"ADMIN") was added in `/auth/me` and in `/admin/users`. Reviewers approved. But `team.service.ts` (`presentMember`) still returned the raw `Membership.role` ("OWNER") — so the web app rendered "User" instead of "Administrator." That endpoint was never inventoried; the reviewer never requested an inventory. It was found in production.

## When to activate

**MANDATORY, in the planning phase**, BEFORE writing code, if:

- A migration drops a column/enum
- A migration renames a column
- A field changes semantics (JSON shape, enum values, nullable→required)
- The web/desktop client consumes that field directly via an API response

## 3-step Audit Protocol

### Step 1: Inventory every endpoint that returns the field

```bash
# Find all mentions of the field in API source (including select/include/return statements)
FIELD="role"  # or another
grep -rn "\b$FIELD\b" src \
  --include="*.ts" \
  | grep -vE "\.(test|spec)\." \
  | grep -E "(return|select:|include:|: true|res\.json|response\.|res\.send)" \
  > /tmp/field-surface-inventory.txt

wc -l /tmp/field-surface-inventory.txt
```

Plus — grep for shape transforms (DTO functions, presentXxx helpers, etc):

```bash
# Find presenter / serializer / DTO shape functions
grep -rn "function present\|function shape\|serialize\|toDto\|toResponse" \
  src --include="*.ts" \
  | head -30
```

### Step 2: Classify each location

For each line in the inventory, determine:

**Class A: "Read-then-throw"** — the field is read but not returned to the client (internal logic, audit log, etc). Refactor freely.

**Class B: "API response"** — the field appears in the client's JSON. Each of these must be handled explicitly in the migration (legacy mapping OR canonical type OR removal).

**Class C: "JWT payload"** — a sub-category of Class B (via token). If a new endpoint issues a JWT without the mapping → bug.

### Step 3: Output → spec

Create an audit doc for the sprint:

```markdown
# API contract audit for dropping User.role

## Class B endpoints (need mapping)

| Endpoint | File:line | Field shape | Action |
|----------|-----------|-------------|--------|
| GET /auth/me | auth.service.ts getCurrentUser | role: UserRole → mapped to "ADMIN" | shapeUserDto helper |
| GET /admin/users | admin-users.service.ts findAll | role: UserRole → mapped | shapeUserDto |
| GET /team/members | team.service.ts presentMember | role: MembershipRole | mapping needed |
| POST /oauth/userinfo | oauth.service.ts verifyAccessToken | role: MembershipRole.role | check |

## Class C (JWT)

- signAccessToken — already maps

## Coverage

15 endpoints touched. Each has an explicit handling decision. Legacy mapping consolidated into a single utility function (not duplicated across services).
```

Then this document is handed to implementation as a pre-spec, and in review the reviewers use it as a checklist.

## What this skill does NOT do

- Does not replace planning / architecture review
- Does not replace the TypeScript reviewer (it catches compile errors, not shape regressions)
- Does not cover a separate desktop client — handle that separately when shared types change

## Related skills

- `database-migrations` — migration safety
- `prisma-rename-recipe` — the SQL template
