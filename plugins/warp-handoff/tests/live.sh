#!/usr/bin/env bash
# Live checks against the real claude CLI. Spends tokens (a few cents on Sonnet); no Warp needed.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SCRIPT="$ROOT/skills/warp-handoff/scripts/warp-handoff.sh"
MODEL=${LIVE_MODEL:-sonnet}
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/warp-handoff-live.XXXXXX")" && pwd -P)
export WARP_HANDOFF_STATE="$WORK/state" WARP_HANDOFF_CONFIG="$WORK/config"
: >"$WORK/config"
pass=0
fail=0
HANDOFF_ID=""

cleanup() {
  [ -z "$HANDOFF_ID" ] || { claude stop "$HANDOFF_ID" >/dev/null 2>&1; claude rm "$HANDOFF_ID" >/dev/null 2>&1; }
  cd /
  rm -rf "$WORK"
}
trap cleanup EXIT

ch() { OUT=$(bash "$SCRIPT" "$@" 2>"$WORK/err"); RC=$?; ERR=$(cat "$WORK/err"); }
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n     rc=%s out=%.400s\n     err=%.300s\n' "$1" "${RC:-}" "${OUT:-}" "${ERR:-}"; }
expect() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
rc_is() { [ "$RC" = "$1" ]; }
out_has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }

# A folder this machine has never trusted, with a project hook that leaves a marker if it runs.
untrusted() {
  local d="$WORK/$1"
  mkdir -p "$d/.claude"
  jq -n --arg m "$d/hook-ran" '{hooks: {SessionStart: [{hooks: [{type: "command", command: ("touch " + $m)}]}]}}' \
    >"$d/.claude/settings.json"
  printf '%s' "$d"
}

ch doctor
expect "doctor passes on this machine" rc_is 0

echo "# launch: prompt on stdin, project hooks skipped"
D=$(untrusted l1)
ch launch -d "$D" --model "$MODEL" "Reply with exactly the word PINEAPPLE and nothing else."
ID=$OUT
ch wait "$ID" --timeout 180
expect "finishes" rc_is 0
ch result "$ID"
expect "the prompt arrived on stdin" out_has "PINEAPPLE"
expect "the untrusted project hook did not run" test ! -e "$D/hook-ran"

echo "# launch: a tool outside the allowlist is refused, not prompted"
D=$(untrusted l2)
ch launch -d "$D" --model "$MODEL" -t "Read,Bash(echo:*)" \
  "Use the Bash tool to run exactly: touch $D/should-not-exist  If it is refused, reply REFUSED."
ID=$OUT
ch wait "$ID" --timeout 180
expect "finishes without waiting for anyone" rc_is 0
ch result "$ID"
expect "the refusal is reported" out_has "denied: Bash: touch"
expect "the command did not run" test ! -e "$D/should-not-exist"

echo "# launch: budget cap"
D=$(untrusted l3)
ch launch -d "$D" --model "$MODEL" --budget 0.0001 "Reply OK."
ID=$OUT
ch wait "$ID" --timeout 180
expect "budget stop exits 11" rc_is 11
expect "and is named budget" out_has "budget"

echo "# launch: timeout"
printf 'TIMEOUT_SECS=3\n' >"$WORK/config"
D=$(untrusted l4)
ch launch -d "$D" --model "$MODEL" "Count from 1 to 500, one number per line."
ID=$OUT
ch wait "$ID" --timeout 60
expect "timeout exits 11" rc_is 11
expect "and is named timeout" out_has "timeout"
: >"$WORK/config"

echo "# handoff: claude itself refuses a folder it has not trusted"
D=$(untrusted h0)
ch handoff --no-tab -d "$D" "Reply OK."
expect "refused (exit 2)" rc_is 2
expect "with claude's reason" test -n "$(printf '%s' "$ERR" | grep -i 'not trusted')"

echo "# handoff: waits for a human; project hooks skipped in a trusted folder not in TRUSTED_DIRS"
if [ -z "${LIVE_TRUSTED_DIR:-}" ]; then
  echo "skip: set LIVE_TRUSTED_DIR to a folder claude already trusts (a parent you accepted counts)"
else
  D=$(mktemp -d "$LIVE_TRUSTED_DIR/warp-handoff-live.XXXXXX")
  mkdir -p "$D/.claude"
  jq -n --arg m "$D/hook-ran" '{hooks: {SessionStart: [{hooks: [{type: "command", command: ("touch " + $m)}]}]}}' \
    >"$D/.claude/settings.json"
  ch handoff --no-tab -d "$D" "Use the Bash tool to run exactly: touch $D/needs-approval  Then reply DONE."
  HANDOFF_ID=$OUT
  ch wait "$HANDOFF_ID" --timeout 120
  expect "stops at the permission prompt (exit 10)" rc_is 10
  expect "the command waits for approval" test ! -e "$D/needs-approval"
  expect "the project hook did not run" test ! -e "$D/hook-ran"
  ch stop "$HANDOFF_ID"
  ch wait "$HANDOFF_ID" --timeout 10
  expect "stopped" rc_is 12
  echo "left for you to inspect or delete: $D"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
