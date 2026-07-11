---
name: money-math-invariants
description: "Lint checklist for money fields in a billing subsystem. Activates on any edit to payment/billing modules, shared billing types, or pricing/checkout UI. Verifies 6 money-math invariants that a typecheck does not catch."
---
# Money Math Invariants

This skill codifies **6 money-math invariants** whose violation produces bugs like "profit shows $498,669", "'—' in the payment history", or "the AI tells the user they paid $9.90 instead of $990".

Each invariant is a **class of bug** that a typecheck does not catch, because the violation happens at a seam: name ↔ unit, Prisma ↔ JSON, frontend ↔ backend, seed ↔ schema.

> The convention below uses a currency suffix to encode the unit in the field name: `*Dollars` holds a major unit, `*Cents` holds a minor unit (1/100). Substitute your own currency, but keep the principle — **the name must not lie about the unit.**

## When to activate

Any edit to a file in one of these zones:

- payment / checkout service modules
- admin billing / billing-adjustment services
- LLM/agent data-source files that surface billing context
- shared billing/pricing type packages
- admin billing pages, organization/user detail pages
- account billing settings pages, public pricing page
- database seed scripts and one-off migration/update scripts

## The 6 invariants

### Invariant 1: "Field name = unit of its contents"

**Rule:** if a field is named `*Dollars` it stores dollars; if `*Cents` it stores cents. **The name must not lie about the unit.**

**Example violation:**
```ts
// schema.prisma
model Plan {
  priceMonthlyDollars  Int  // ← name says "Dollars", but it stored 499000 (cents) for $4990
}
```

**Check:** for every `*Dollars` field — contents × 1.0 = dollars (not × 0.01 = cents divided by 100).

**How to verify:** a runtime test with sample values + a grep for `*Cents` in any DTO that flows to the UI.

### Invariant 2: "Decimal does not go into JSON directly"

**Rule:** the Prisma `Decimal` type is a `Prisma.Decimal` object (a Decimal.js wrapper). When serialized to JSON it becomes `{d:[4990],e:3,s:1}` or a string `"4990"`, **not a number**. The frontend expects a number → gets garbage.

**Example violation:**
```ts
// billing.service.ts
return {
  amountDollars: p.amount,  // ← Decimal object, not number. Frontend receives {d:[4990]...}
};
```

**Correct:**
```ts
return {
  amountDollars: p.amount.toNumber(),  // ← number
};
```

**Check:** for every `prisma.X.findMany().select(...)` where the select contains a money field — the DTO map must call `.toNumber()` on it.

**Grep:**
```bash
# Find Decimal money fields without .toNumber():
grep -rn "amount\b\|priceMonthlyDollars\b\|unitPriceDollars\b\|amountDollars\b" \
  src --include="*.ts" | grep -v ".spec.ts" | grep -v ".toNumber()"
```

### Invariant 3: "No `/100` in the UI layer"

**Rule:** the frontend never divides by 100. The cents↔dollars conversion happens **only at the API boundary** (Prisma read/write in the backend). The UI receives dollars as a ready `number`.

**Example violation:**
```tsx
// organizations/[id]/page.tsx
Math.round(s.plan.priceMonthlyDollars / 100)  // ← /100 in UI, divides twice
```

**Correct:**
```tsx
s.plan.priceMonthlyDollars  // ← already dollars, no /100
```

**Check:** `grep -rn "/ 100\|/100\b" web/ --include="*.tsx" --include="*.ts" | grep -v ".next"` — results must not contain money-related variables (`amount`, `price`, `cost`, `*Dollars`, `*Cents`).

**Exception:** percentages (`discount / 100 * 100`) are OK.

### Invariant 4: "Frontend ↔ backend DTO names match"

**Rule:** the field name in the backend DTO interface = the field name in the frontend type. If the backend sends `amount`, the frontend must read `amount` (not `amountDollars`).

**Example violation:**
```ts
// backend: SerialisedPayment.amount: number
// frontend: BillingPortalState.payments[].amountDollars: number
// → frontend reads amountDollars → undefined → "—" in UI
```

**Check:** for every admin/account/public endpoint, diff the type in shared-types VS the type in the frontend API client VS the interface in the backend service.

A name mismatch is a BLOCKER, not cosmetic. Prefer converging on one name on either side (ideally `*Dollars` for money, with the unit in the name).

### Invariant 5: "Seed scripts use the same units as the schema"

**Rule:** values in seed and one-off migration scripts must match the current type in the schema. After a rename `Int (cents) → Decimal (dollars)`, seed values change `99000 → 990`.

**Example violation:**
```ts
// seed.ts (after the migration but without updating seed)
{ slug: "personal-start", priceMonthlyDollars: 99000 }  // ← now this is $99,000, not $990
```

**Correct:**
```ts
{ slug: "personal-start", priceMonthlyDollars: 990 }  // ← dollars, as in schema
```

**Check:** on any money-field rename in schema — `grep -rn "<fieldName>" prisma/` and walk every occurrence.

**Especially dangerous:** seed scripts are often **outside tsconfig** → typecheck does not see them. They only fail on `db:seed` against a clean DB, usually weeks after the schema change.

### Invariant 6: "LLM context = real units"

**Rule:** AI agents receive billing context through data-source schemas (zod). A field `amountCents` in zod must contain cents; a field `amountDollars` must contain dollars. Otherwise the LLM will lie by 100× in a chat with the user.

**Example violation:**
```ts
// billing.data-source.ts (after Payment.amount Int→Decimal-in-dollars migration)
recentPayments: payments.map((p) => ({
  amountCents: p.amount.toNumber(),  // ← amount=990 dollars, key "amountCents"
  // → LLM in the prompt: "the client paid 990 cents = $9.90"
}))
```

**Correct:** rename both key and value:
```ts
recentPayments: payments.map((p) => ({
  amountDollars: p.amount.toNumber(),
}))
```

**Check:** for every LLM data-source — the zod schema field name must match the unit of the actual data. After any Prisma rename — re-check the data-source.

## Pre-commit checklist (billing scope)

Run **in order**:

```bash
# 1. No legacy *Cents in the frontend DTO (it should receive *Dollars)
grep -rn "Cents\|cents" packages/shared-types/src/billing-* \
  web/ --include="*.ts" --include="*.tsx" | grep -v ".next"

# 2. No /100 in the UI near money variables
grep -rn "/ 100\|/100\b" web/ --include="*.tsx" --include="*.ts" | \
  grep -v ".next" | grep -E "amount|price|cost|Dollars|Cents"

# 3. Decimal fields have .toNumber() at the DTO boundary
grep -rn "amount\|priceMonthlyDollars\|unitPriceDollars" \
  src --include="*.ts" | grep -v ".spec.ts" | grep -v ".toNumber()" | \
  grep -E "return\s*{|map\(\(.*\)\s*=>|select|data:"

# 4. Frontend ↔ backend DTO names match (manual diff)
diff <(grep "interface Serialised\|amountDollars\|amountCents\|amount\s*:" src/) \
     <(grep "amountDollars\|amountCents\|amount\s*:" web/lib/api.ts)

# 5. Seed scripts in the right units (if the schema was renamed)
grep -E "priceMonthlyDollars: \d{4,}" prisma/*.ts | \
  awk -F: '{ if ($NF > 99999) print "WARN: ", $0 }'

# 6. LLM data-source keys match the real units
grep -A3 "recentPayments\|amountCents\|amountDollars" \
  src/**/data-sources/*.ts
```

## Anti-patterns

1. **"Typecheck is green — so it's done."** No: typecheck does not compare local DTO types front ↔ back, does not check name ↔ unit, and does not see seed scripts.
2. **A short-lived conversion helper.** A `dollarsToCents` helper added for one write can become dead weight a day later (once the DB migrates to Decimal). An extra helper = mental tax. Prefer keeping the DB unit consistent with the DTO.
3. **Backward compat for legacy `*Cents` strings.** Normalizing `BONUS_CREDIT_CENTS → BONUS_CREDIT_DOLLARS` at the boundary works, but **update UI dropdowns in parallel** — otherwise the frontend keeps sending the legacy value.
4. **"Data is stored in cents for precision."** Legitimate for financial systems, BUT the field name must explicitly say `*Cents` or `*MinorUnits`. Never `*Dollars` for cents.

## Related patterns

- A safe Prisma-rename recipe with in-transaction data conversion for money fields.
- A clean-build verification after a Prisma rename.
- A reviewer gate (security + QA) for any billing change — a green typecheck is not enough.
