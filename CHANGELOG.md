# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-11

Initial public release as an installable Claude Code plugin.

### Added
- **14 reusable skills** covering LLM cost control, eval-driven development,
  output-coverage assertions, money-math invariants, clean-build verification,
  API-contract audits, regex-vs-LLM parsing, content-hash caching, anti-bug
  prevention, and research-before-code.
- **6 adversarial review agents**: `silent-failure-hunter`, `auth-flow-reviewer`,
  `security-reviewer`, `typescript-reviewer`, `code-reviewer`, `qa-engineer`.
- **The machine review gate** (`scripts/verify-reviewer-gate.sh`): maps a change's
  blast radius to the specialist reviewers it requires, scans the diff for
  hardcoded secrets (hard block) and swallowed errors (soft block), and refuses
  to pass until `REVIEW_LOG.md` carries a PASS verdict from each required reviewer.
- The gate is wired two ways: a `PreToolUse` **hook** (fires before `git commit` /
  `git push` / `deploy`) and a manual **`reviewer-gate` skill**.
- **`demo.sh`** — a self-contained 60-second proof that runs on plain bash + git:
  it blocks a deliberately bad payments change, then passes the fix.
- **CI** (`.github/workflows/validate-plugin.yml`): structural validation, the
  real `claude plugin validate --strict`, and an end-to-end run of the demo.
- Self-hosting `marketplace.json` so the repo installs via `/plugin marketplace add`.

[0.1.0]: https://github.com/rustidi/ai-guardrails/releases/tag/v0.1.0
