#!/usr/bin/env bash
# Checks the marketplace, every plugin's manifest and shell scripts, and runs every plugin's offline tests.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
MARKET="$ROOT/.claude-plugin/marketplace.json"
status=0

step() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; status=1; }
pass() { printf 'ok   %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }

step "marketplace and plugin folders agree"
listed=""
while IFS=$'\t' read -r name source; do
  listed="$listed $name"
  dir="$ROOT/${source#./}"
  manifest="$dir/.claude-plugin/plugin.json"
  if [ ! -f "$manifest" ]; then fail "$name: no $source/.claude-plugin/plugin.json"; continue; fi
  [ "$(jq -r .name "$manifest")" = "$name" ] || fail "$name: plugin.json name differs from the marketplace entry"
  for f in README.md CHANGELOG.md tests/run.sh; do
    [ -f "$dir/$f" ] || fail "$name: missing $f"
  done
  case "$name" in claude-* | anthropic-* | anthropics-* | cc-plugin-*) fail "$name: reserved name prefix" ;; esac
  pass "$name"
done < <(jq -r '.plugins[] | [.name, .source] | @tsv' "$MARKET")
for dir in "$ROOT"/plugins/*/; do
  [ -d "$dir" ] || continue
  case " $listed " in *" $(basename "$dir") "*) ;; *) fail "plugins/$(basename "$dir") is not in marketplace.json" ;; esac
done

step "claude plugin validate"
if command -v claude >/dev/null 2>&1; then
  if out=$(claude plugin validate "$MARKET" 2>&1); then pass "marketplace"; else fail "marketplace"; printf '%s\n' "$out"; fi
  for dir in "$ROOT"/plugins/*/; do
    [ -d "$dir" ] || continue
    if out=$(claude plugin validate "$dir" 2>&1); then pass "$(basename "$dir")"; else fail "$(basename "$dir")"; printf '%s\n' "$out"; fi
  done
else
  echo "skip: claude is not installed"
fi

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  scripts=()
  while IFS= read -r f; do scripts+=("$f"); done < <(
    find "$ROOT/scripts" "$ROOT/plugins" -type f \( -name '*.sh' -o -path '*/tests/stub/*' \) | sort
  )
  if shellcheck -s bash -S warning "${scripts[@]}"; then pass "${#scripts[@]} scripts"; else fail "shellcheck"; fi
else
  echo "skip: shellcheck is not installed"
fi

step "offline tests"
for t in "$ROOT"/plugins/*/tests/run.sh; do
  [ -f "$t" ] || continue
  name=$(basename "$(dirname "$(dirname "$t")")")
  if out=$(bash "$t" 2>&1); then pass "$name: $(printf '%s\n' "$out" | tail -n 1)"; else fail "$name"; printf '%s\n' "$out" | grep -v '^ok '; fi
done

printf '\n'
if [ "$status" -eq 0 ]; then echo "all checks passed"; else echo "some checks failed"; fi
exit "$status"
