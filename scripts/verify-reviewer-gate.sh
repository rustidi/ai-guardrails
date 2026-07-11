#!/usr/bin/env bash
# =============================================================
# verify-reviewer-gate.sh  —  the machine review gate
#
# WHAT IT DOES
#   Looks at the code that changed in a repo, works out which specialist
#   reviewers that blast radius requires, scans the changed lines for a few
#   concrete anti-patterns, and refuses to pass (exit 2) unless:
#     (a) no hard finding remains in the diff, AND
#     (b) every required reviewer has a PASS verdict in REVIEW_LOG.md.
#
# WHY IT EXISTS
#   "Please review the auth change carefully" is a wish. A green typecheck is
#   not proof of correctness. This turns review into something the pipeline
#   enforces: the risky change does not ship until the right specialist signs
#   off — and a hardcoded secret never ships at all.
#
# ENFORCEMENT IS OPT-IN
#   The gate only enforces when a REVIEW_LOG.md exists at the repo root. A repo
#   without one passes untouched, so wiring this as a hook never surprises a
#   user who has not adopted the workflow.
#
# USAGE
#   scripts/verify-reviewer-gate.sh [REPO_DIR]     # default: $CLAUDE_PROJECT_DIR or .
#
# ESCAPE HATCH (explicit, logged)
#   REVIEWER_GATE_BYPASS=1 scripts/verify-reviewer-gate.sh
# =============================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
say()  { printf '%b\n' "$1"; }
err()  { printf '%b\n' "$1" >&2; }

REPO="${1:-${CLAUDE_PROJECT_DIR:-.}}"

if [ "${REVIEWER_GATE_BYPASS:-0}" = "1" ]; then
  err "${YELLOW}[gate] BYPASS=1 — gate skipped, explicitly, on your responsibility.${NC}"
  exit 0
fi

if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  say "${YELLOW}[gate] $REPO is not a git repo — nothing to gate.${NC}"
  exit 0
fi

REVIEW_LOG="$REPO/REVIEW_LOG.md"
if [ ! -f "$REVIEW_LOG" ]; then
  say "${YELLOW}[gate] no REVIEW_LOG.md in $REPO — enforcement is opt-in, passing.${NC}"
  exit 0
fi

# --- 1. What changed (uncommitted diff vs HEAD, plus untracked files) ---
if git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
  tracked=$(git -C "$REPO" diff --name-only HEAD 2>/dev/null)
else
  tracked=$(git -C "$REPO" diff --cached --name-only 2>/dev/null)
fi
untracked=$(git -C "$REPO" ls-files --others --exclude-standard 2>/dev/null)
CHANGED=$(printf '%s\n%s\n' "$tracked" "$untracked" | sed '/^$/d' | sort -u)

if [ -z "$CHANGED" ]; then
  say "${GREEN}[gate] no changes to review.${NC}"
  exit 0
fi

# --- 2. Blast radius: changed paths -> required reviewers ---
require=""
add_req() { case " $require " in *" $1 "*) ;; *) require="$require $1" ;; esac; }
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *[Aa]uth*|*[Ll]ogin*|*[Rr]efresh*|*[Ss]ession*|*[Uu]nlock*|*[Tt]oken*) add_req auth-flow-reviewer ;;
  esac
  case "$f" in
    *payment*|*billing*|*pricing*|*charge*|*checkout*|*invoice*) add_req security-reviewer; add_req money-math-invariants ;;
  esac
  case "$f" in
    *[Aa]pi*|*route*|*controller*|*endpoint*|*handler*) add_req security-reviewer ;;
  esac
done <<EOF
$CHANGED
EOF

# --- 3. Content tripwires: scan the changed files for concrete anti-patterns ---
# HARD findings block unconditionally (a sign-off cannot clear them).
# SOFT findings raise a reviewer requirement that a sign-off can clear.
hard_findings=""
soft_findings=""
scan_file() {
  local f="$1" full="$REPO/$1"
  [ -f "$full" ] || return 0
  # binary guard
  if LC_ALL=C grep -qI . "$full" 2>/dev/null; then :; else return 0; fi

  # HARD: hardcoded secret / credential literal
  # (a) an identifier ending in KEY/SECRET/TOKEN/PASSWORD assigned a long quoted literal
  local sec
  sec=$(grep -nEi '[A-Za-z_][A-Za-z0-9_]*(key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}["'"'"']' "$full" 2>/dev/null)
  # (b) recognizable provider token shapes (allow _ and - inside the token)
  sec="$sec
$(grep -nE '(sk|pk|rk)[_-](live|test)[_-][A-Za-z0-9]{10,}|sk[_-][A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|ghp_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$full" 2>/dev/null)"
  sec=$(printf '%s\n' "$sec" | sed '/^$/d' | sort -u)
  if [ -n "$sec" ]; then
    while IFS= read -r ln; do
      hard_findings="$hard_findings
$f:$ln|security-reviewer|hardcoded secret / credential in source"
    done <<EOF
$sec
EOF
    add_req security-reviewer
  fi

  # SOFT: swallowed error — empty catch block, or bare except: pass
  local swallow
  swallow=$(grep -nE 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}' "$full" 2>/dev/null)
  swallow="$swallow
$(grep -nE 'except[^:]*:[[:space:]]*pass[[:space:]]*$' "$full" 2>/dev/null)"
  swallow=$(printf '%s\n' "$swallow" | sed '/^$/d')
  if [ -n "$swallow" ]; then
    while IFS= read -r ln; do
      soft_findings="$soft_findings
$f:$ln|silent-failure-hunter|swallowed error (empty catch / bare except pass)"
    done <<EOF
$swallow
EOF
    add_req silent-failure-hunter
  fi

  # SOFT: money divided by 100 in a UI/view file (unit bug)
  case "$f" in
    *ui*|*web*|*frontend*|*component*|*view*|*.tsx|*.jsx)
      local money
      money=$(grep -nEi '(amount|price|total|charge|cents|balance)[A-Za-z]*[[:space:]]*/[[:space:]]*100\b' "$full" 2>/dev/null | sed '/^$/d')
      if [ -n "$money" ]; then
        while IFS= read -r ln; do
          soft_findings="$soft_findings
$f:$ln|money-math-invariants|money divided by 100 in a view (probable unit bug)"
        done <<EOF
$money
EOF
        add_req money-math-invariants
      fi ;;
  esac
}
while IFS= read -r f; do
  [ -z "$f" ] && continue
  scan_file "$f"
done <<EOF
$CHANGED
EOF

require="$(printf '%s' "$require" | xargs 2>/dev/null)"
hard_findings=$(printf '%s\n' "$hard_findings" | sed '/^$/d')
soft_findings=$(printf '%s\n' "$soft_findings" | sed '/^$/d')

# --- 4. Report findings ---
if [ -n "$hard_findings" ] || [ -n "$soft_findings" ]; then
  err "${BOLD}[gate] findings in the changed code:${NC}"
  if [ -n "$hard_findings" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      loc="${line%%|*}"; rest="${line#*|}"; who="${rest%%|*}"; msg="${rest#*|}"
      err "  ${RED}HARD${NC}  $loc  ($who) — $msg"
    done <<EOF
$hard_findings
EOF
  fi
  if [ -n "$soft_findings" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      loc="${line%%|*}"; rest="${line#*|}"; who="${rest%%|*}"; msg="${rest#*|}"
      err "  ${YELLOW}SOFT${NC}  $loc  ($who) — $msg"
    done <<EOF
$soft_findings
EOF
  fi
fi

# --- 5. Hard findings block unconditionally ---
if [ -n "$hard_findings" ]; then
  err ""
  err "${RED}${BOLD}[gate] BLOCKED — a hard finding is present in the diff.${NC}"
  err "${RED}  A hardcoded secret never ships. Remove it (read from the environment) and re-run.${NC}"
  exit 2
fi

if [ -z "$require" ]; then
  say "${GREEN}[gate] the changed scope needs no mandatory reviewers.${NC}"
  exit 0
fi

# --- 6. Require a PASS verdict in REVIEW_LOG.md for each required reviewer ---
PASS_RE='CLEAR|SAFE|APPROVE|APPROVED|PASS|SIGNED-OFF|SIGNED OFF'
missing=""
for r in $require; do
  if grep -iF -- "$r" "$REVIEW_LOG" 2>/dev/null | grep -qiE "$PASS_RE"; then :; else
    missing="$missing $r"
  fi
done
missing="$(printf '%s' "$missing" | xargs 2>/dev/null)"

if [ -n "$missing" ]; then
  err ""
  err "${RED}${BOLD}[gate] COMMIT BLOCKED.${NC}"
  err "${RED}  The changed scope requires review, but REVIEW_LOG.md has no PASS verdict from:${NC}"
  for m in $missing; do err "${RED}    - $m${NC}"; done
  err "${YELLOW}  Run those reviewers, then add a line to REVIEW_LOG.md such as:${NC}"
  err "${YELLOW}    - security-reviewer: CLEAR — no injection, secret now read from env${NC}"
  exit 2
fi

say "${GREEN}${BOLD}[gate] PASS — all mandatory reviewers signed off:${NC} ${GREEN}$require${NC}"
exit 0
