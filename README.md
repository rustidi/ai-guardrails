# Agent Guardrails

[![Validate Plugin](https://github.com/rustidi98/agent-guardrails/actions/workflows/validate-plugin.yml/badge.svg)](https://github.com/rustidi98/agent-guardrails/actions/workflows/validate-plugin.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

An installable [Claude Code](https://code.claude.com/docs/en/plugins) plugin that puts **guardrails around AI-generated code**: reusable skills, a team of adversarial review agents, and a machine gate that **blocks a risky commit until the right specialist has signed off** — and never lets a hardcoded secret ship.

## See it work in 60 seconds

No install required — plain `bash` + `git`:

```bash
git clone https://github.com/rustidi98/agent-guardrails
cd agent-guardrails
./demo.sh
```

The demo spins up a throwaway repo, makes a **bad payments change** (a hardcoded Stripe key + a swallowed error), and runs the gate:

```
③ Running the reviewer gate on the bad change
  HARD  src/payments/charge.js:5   (security-reviewer) — hardcoded secret / credential in source
  SOFT  src/payments/charge.js:18  (silent-failure-hunter) — swallowed error (empty catch)
  [gate] BLOCKED — a hard finding is present in the diff.        ← exit 2, commit refused

⑤ Running the reviewer gate again  (secret moved to env, error propagated, reviewers signed off)
  [gate] PASS — all mandatory reviewers signed off               ← exit 0, allowed to ship
```

## Install as a plugin

```bash
# 1. add this repo as a marketplace, then install the plugin
/plugin marketplace add rustidi98/agent-guardrails
/plugin install agent-guardrails@guardrails
```

Or load it locally without a marketplace (development):

```bash
claude --plugin-dir ./agent-guardrails
```

Once enabled you get:

```
/agent-guardrails:reviewer-gate        # run the machine gate on the current repo
/agent-guardrails:eval-harness         # any of the 14 skills, namespaced
@agent-guardrails:silent-failure-hunter  # any of the 6 review agents, @-mentioned
```

The gate also wires in automatically as a `PreToolUse` hook: before Claude runs `git commit`, `git push`, or a `deploy` in Bash, the gate runs. Enforcement is **opt-in per repo** — a repo with no `REVIEW_LOG.md` passes untouched, so the hook never surprises a project that hasn't adopted the workflow.

## What's inside

| Component | Count | Examples |
|---|---|---|
| **Skills** | 14 | `reviewer-gate`, `eval-harness`, `cost-aware-llm-pipeline`, `money-math-invariants`, `output-coverage-assertion`, `clean-build-verification`, `api-contract-audit`, `anti-bug-prevention` |
| **Review agents** | 6 | `silent-failure-hunter`, `auth-flow-reviewer`, `security-reviewer`, `typescript-reviewer`, `code-reviewer`, `qa-engineer` |
| **Machine gate** | 1 | `scripts/verify-reviewer-gate.sh` — blast-radius → required reviewers + diff tripwires |

## Why

> **An agent is a scar, codified.**

Each review agent exists because a specific class of bug cost real time and real trust. Instead of *"try to remember to check for X,"* the check becomes a standing specialist that is **mandatory whenever code in its blast radius changes**, enforced by a gate rather than by good intentions.

- `silent-failure-hunter` — born from pipelines that swallowed an error and rendered "0 results" as success. *"Couldn't verify" must never look like "nothing there."*
- `auth-flow-reviewer` — born after a "false logout" bug recurred **eight times**. Reviews on a presumption of guilt.
- `money-math-invariants` — six billing-math invariants a typecheck can't catch (the unit lives in the variable name; never divide by 100 in the UI).

For AI-first teams the differentiator isn't *"can it write a function."* It's **designing a system where AI agents produce reliable, reviewable, production work at scale — with guardrails that keep it honest.** This plugin is that system, generalized from a real production codebase (the product's own code stays private; what's public here is the method, shown with clean examples).

## Repo layout

```
agent-guardrails/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # self-hosting marketplace (installs this same repo)
├── skills/<name>/SKILL.md   # 14 skills, one directory each
├── agents/*.md              # 6 review agents
├── hooks/hooks.json         # PreToolUse wiring for the gate
├── scripts/
│   ├── verify-reviewer-gate.sh   # the gate
│   ├── reviewer-gate-hook.sh     # hook wrapper
│   └── validate-structure.sh     # CI structural checks
├── demo/                    # the sample repo + bad/fixed change used by demo.sh
├── demo.sh                  # the 60-second proof
└── .github/workflows/validate-plugin.yml
```

## Requirements

- **Demo:** `bash` + `git` only.
- **Plugin install:** Claude Code with plugin support (`/plugin` available; update if not).

## License

MIT — see [LICENSE](./LICENSE).

*— Rustem Idiiatullin. Building AI products for healthcare.*
