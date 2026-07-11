# Review log

Reviewers add a PASS line here after signing off on a change. The gate
(`scripts/verify-reviewer-gate.sh`) reads this file to decide whether the
changed blast radius has been reviewed.

Format:

    - <reviewer-name>: CLEAR — short summary

## Sign-offs

- security-reviewer: CLEAR — secret removed; STRIPE_SECRET_KEY now read from process.env.
- money-math-invariants: CLEAR — amount stays in minor units (amountCents) end to end; no /100 in a view.
