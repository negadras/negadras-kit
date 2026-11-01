#!/usr/bin/env bash
# Checks the marketplace, every plugin's manifest, version and shell scripts, and runs every plugin's offline tests.
# VALIDATE_BASE is the commit to compare versions against; it defaults to origin/main.
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

step "versions"
# Merging to main is the release, and users only receive a plugin's files when its version changes.
shipped_changes() {
  git -C "$ROOT" diff --name-only "$1" -- "$2" ":(exclude)$2/tests" ":(exclude)$2/README.md" ":(exclude)$2/CHANGELOG.md" |
    tr '\n' ' '
}
base=${VALIDATE_BASE:-}
if [ -z "$base" ] && git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1; then base=origin/main; fi
if [ -n "$base" ]; then
  base=$(git -C "$ROOT" merge-base "$base" HEAD 2>/dev/null) || { echo "skip unbumped-change check: no merge base"; base=""; }
fi
semver='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
while IFS=$'\t' read -r name source; do
  dir=${source#./}
  manifest="$ROOT/$dir/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || continue
  version=$(jq -r '.version // empty' "$manifest")
  if ! [[ $version =~ $semver ]]; then fail "$name: version '$version' in plugin.json is not x.y.z"; continue; fi
  grep -qxF "## $version" "$ROOT/$dir/CHANGELOG.md" || fail "$name: CHANGELOG.md has no '## $version' entry"
  old=""
  [ -z "$base" ] || old=$(git -C "$ROOT" show "$base:$dir/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
  if [ "$old" = "$version" ]; then
    changed=$(shipped_changes "$base" "$dir")
    [ -z "$changed" ] || fail "$name: files users receive changed but version is still $version: $changed"
  fi
  tag="refs/tags/$name--v$version"
  if git -C "$ROOT" rev-parse -q --verify "$tag" >/dev/null 2>&1; then
    changed=$(shipped_changes "$tag" "$dir")
    [ -z "$changed" ] || fail "$name: $version is already released as ${tag#refs/tags/} and these files differ from it: $changed"
  fi
  pass "$name $version"
done < <(jq -r '.plugins[] | [.name, .source] | @tsv' "$MARKET")

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
