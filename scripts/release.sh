#!/usr/bin/env bash
# Tags <plugin>--v<version> and publishes a GitHub Release for every plugin whose version has no tag yet.
# Run by .github/workflows/release.yml on main; --dry-run prints what it would release from any checkout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
MARKET="$ROOT/.claude-plugin/marketplace.json"

dry=0
case "${1:-}" in
  --dry-run) dry=1 ;;
  "") ;;
  *) echo "usage: release.sh [--dry-run]" >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

head=$(git -C "$ROOT" rev-parse HEAD)
if [ "$dry" = 0 ]; then
  command -v gh >/dev/null 2>&1 || { echo "gh is required" >&2; exit 2; }
  git -C "$ROOT" merge-base --is-ancestor "$head" origin/main || { echo "HEAD is not on origin/main; refusing to release" >&2; exit 2; }
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "the checkout has uncommitted changes; refusing to release" >&2; exit 2; }
fi

notes=$(mktemp "${TMPDIR:-/tmp}/release-notes.XXXXXX")
trap 'rm -f "$notes"' EXIT
while IFS=$'\t' read -r name source; do
  dir="$ROOT/${source#./}"
  version=$(jq -r '.version // empty' "$dir/.claude-plugin/plugin.json")
  [ -n "$version" ] || { echo "$name: plugin.json has no version" >&2; exit 1; }
  tag="$name--v$version"
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "skip $tag: already tagged"
    continue
  fi
  awk -v h="## $version" '$0 == h { on = 1; next } on && /^## / { exit } on' "$dir/CHANGELOG.md" >"$notes"
  grep -q '[^[:space:]]' "$notes" || { echo "$name: CHANGELOG.md has no '## $version' entry" >&2; exit 1; }
  if [ "$dry" = 1 ]; then
    printf 'would release %s at %s with notes:\n' "$tag" "$head"
    cat "$notes"
    continue
  fi
  gh release create "$tag" --target "$head" --title "$name $version" --notes-file "$notes"
  echo "released $tag"
done < <(jq -r '.plugins[] | [.name, .source] | @tsv' "$MARKET")
