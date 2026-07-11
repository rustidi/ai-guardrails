#!/usr/bin/env bash
# =============================================================
# demo.sh — the 60-second proof.
#
# Builds a throwaway git repo, introduces a deliberately bad payments change
# (a hardcoded secret + a swallowed error), and runs the reviewer gate:
#
#   1. BAD change  -> gate BLOCKS  (non-zero exit, names the findings)
#   2. Fixed change -> gate PASSES (exit 0)
#
# Runs on plain bash + git. No install, no network, no exotic deps.
# =============================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/scripts/verify-reviewer-gate.sh"
BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
rule() { printf '%b\n' "${DIM}------------------------------------------------------------${NC}"; }
step() { printf '\n%b\n' "${BOLD}${CYAN}$1${NC}"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/guardrails-demo.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

REPO="$WORK/sample-app"
cp -R "$HERE/demo/sample-app" "$REPO"

step "① Setting up a tiny sample repo"
git -C "$REPO" init -q
git -C "$REPO" config user.email demo@example.com
git -C "$REPO" config user.name "Demo"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "baseline: clean payments module"
printf '%b\n' "   ${DIM}$REPO (clean, committed)${NC}"

step "② Introducing a BAD change to src/payments/charge.js"
cp "$HERE/demo/bad/charge.js" "$REPO/src/payments/charge.js"
git -C "$REPO" add -A
printf '%b\n' "   ${DIM}+ hardcoded Stripe secret${NC}"
printf '%b\n' "   ${DIM}+ swallowed error (empty catch)${NC}"

step "③ Running the reviewer gate on the bad change"
rule
"$GATE" "$REPO"
BAD_EXIT=$?
rule
if [ "$BAD_EXIT" -ne 0 ]; then
  printf '%b\n' "   ${GREEN}✓ gate exited ${BAD_EXIT} (non-zero) — the bad commit is BLOCKED.${NC}"
else
  printf '%b\n' "   ${RED}✗ expected a block but the gate passed (exit 0).${NC}"
fi

step "④ Applying the fix (env secret + propagated error + reviewer sign-offs)"
cp "$HERE/demo/fixed/charge.js" "$REPO/src/payments/charge.js"
cp "$HERE/demo/fixed/REVIEW_LOG.md" "$REPO/REVIEW_LOG.md"
git -C "$REPO" add -A

step "⑤ Running the reviewer gate again"
rule
"$GATE" "$REPO"
FIX_EXIT=$?
rule
if [ "$FIX_EXIT" -eq 0 ]; then
  printf '%b\n' "   ${GREEN}✓ gate exited 0 — the fixed change is allowed to ship.${NC}"
else
  printf '%b\n' "   ${RED}✗ expected a pass but the gate blocked (exit ${FIX_EXIT}).${NC}"
fi

step "Result"
if [ "$BAD_EXIT" -ne 0 ] && [ "$FIX_EXIT" -eq 0 ]; then
  printf '%b\n' "${GREEN}${BOLD}DEMO PASSED — the gate blocked the bad change and allowed the fix.${NC}"
  exit 0
else
  printf '%b\n' "${RED}${BOLD}DEMO FAILED — see the exit codes above.${NC}"
  exit 1
fi
