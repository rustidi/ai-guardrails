#!/usr/bin/env bash
# Structural validation for the agent-guardrails plugin.
# Pure bash + python3 (for JSON). Mirrors what `claude plugin validate` checks,
# plus repo-specific invariants. Exits non-zero on the first failure.
set -u
cd "$(dirname "$0")/.." || exit 2
FAIL=0
ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[0;31m✗ %s\033[0m\n' "$1"; FAIL=1; }

echo "1. plugin.json + marketplace.json are valid JSON"
python3 -c "import json,sys; json.load(open('.claude-plugin/plugin.json'))" 2>/dev/null \
  && ok ".claude-plugin/plugin.json" || bad "plugin.json is not valid JSON"
python3 -c "import json,sys; json.load(open('.claude-plugin/marketplace.json'))" 2>/dev/null \
  && ok ".claude-plugin/marketplace.json" || bad "marketplace.json is not valid JSON"

echo "2. plugin.json has a name"
python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); assert d.get('name'), 'no name'" 2>/dev/null \
  && ok "name present" || bad "plugin.json missing required 'name'"

echo "3. every skill is a directory with SKILL.md + a description"
for d in skills/*/; do
  n="$(basename "$d")"
  if [ ! -f "$d/SKILL.md" ]; then bad "$n: missing SKILL.md"; continue; fi
  head -1 "$d/SKILL.md" | grep -q '^---' || { bad "$n: SKILL.md missing YAML frontmatter"; continue; }
  grep -qE '^description:[[:space:]]*\S' "$d/SKILL.md" || { bad "$n: SKILL.md missing description"; continue; }
  ok "skills/$n/SKILL.md"
done

echo "4. every agent has name + description in frontmatter"
for f in agents/*.md; do
  [ -e "$f" ] || continue
  grep -qE '^name:[[:space:]]*\S' "$f"        || { bad "$f: missing name"; continue; }
  grep -qE '^description:[[:space:]]*\S' "$f"  || { bad "$f: missing description"; continue; }
  ok "$f"
done

echo "5. agents declare no plugin-forbidden frontmatter (hooks/mcpServers/permissionMode)"
for f in agents/*.md; do
  [ -e "$f" ] || continue
  fm="$(awk '/^---/{c++} c==1{print} c==2{exit}' "$f")"
  if printf '%s' "$fm" | grep -qE '^(hooks|mcpServers|permissionMode):'; then
    bad "$f: uses a frontmatter field not allowed for plugin agents"
  fi
done
[ "$FAIL" -eq 0 ] && ok "no forbidden agent frontmatter"

echo "6. no duplicate skill/agent names"
DUPES="$( { for d in skills/*/; do basename "$d"; done; \
            for f in agents/*.md; do grep -m1 -E '^name:' "$f" | sed 's/^name:[[:space:]]*//'; done; } \
          | sort | uniq -d )"
if [ -n "$DUPES" ]; then bad "duplicate names: $DUPES"; else ok "all names unique"; fi

echo "7. gate + demo scripts are executable"
for s in scripts/verify-reviewer-gate.sh scripts/reviewer-gate-hook.sh demo.sh; do
  [ -x "$s" ] && ok "$s executable" || bad "$s not executable"
done

echo "8. no product-specific names leaked into shipped files"
LEAK="$(grep -rniE '\b(signalo|prizmatika|призматик|amocrm|selectel|runpod|gigaam)\b' skills agents hooks 2>/dev/null || true)"
if [ -n "$LEAK" ]; then bad "product name leak:"; printf '%s\n' "$LEAK"; else ok "no product names"; fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[0;32mSTRUCTURE OK\033[0m\n'; exit 0
else
  printf '\033[0;31mSTRUCTURE VALIDATION FAILED\033[0m\n'; exit 1
fi
