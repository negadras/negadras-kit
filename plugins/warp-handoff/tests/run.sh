#!/usr/bin/env bash
# Offline tests: a stub claude on PATH, no tokens spent, no Warp needed.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SCRIPT="$ROOT/skills/warp-handoff/scripts/warp-handoff.sh"
ORIG_PATH=$PATH
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/warp-handoff-test.XXXXXX")" && pwd -P)
trap 'cd /; rm -rf "$WORK"' EXIT
pass=0
fail=0

setup() {
  T="$WORK/$1"
  mkdir -p "$T/state" "$T/tabs" "$T/proj"
  : >"$T/config"
  export WARP_HANDOFF_STATE="$T/state" WARP_HANDOFF_CONFIG="$T/config"
  export WARP_HANDOFF_WARP_TAB_DIR="$T/tabs" WARP_HANDOFF_OPEN="$ROOT/tests/stub/fake-open"
  export WARP_HANDOFF_TAB_TTL=1
  export STUB_LOG="$T/argv.log" STUB_OPEN_LOG="$T/open.log" STUB_STDIN_LOG="$T/stdin.log"
  export PATH="$ROOT/tests/stub:$ORIG_PATH"
  unset STUB_OLD STUB_RESULT STUB_SLEEP STUB_AGENTS
  : >"$T/argv.log"
  cd "$T/proj" || exit 1
}

ch() { OUT=$(bash "$SCRIPT" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n     rc=%s out=%.300s\n     err=%.300s\n' "$1" "${RC:-}" "${OUT:-}" "${ERR:-}"
}
expect() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

rc_is() { [ "$RC" = "$1" ]; }
out_has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
err_has() { case "$ERR" in *"$1"*) return 0 ;; esac; return 1; }
line_has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
line_lacks() { ! line_has "$@"; }
is_id() { local re='^[0-9a-f]{8}$'; [[ $1 =~ $re ]]; }
launch_line() { grep -F '[-p]' "$T/argv.log" | tail -n 1; }
handoff_line() { grep -F '[--bg]' "$T/argv.log" | tail -n 1; }
launch_and_wait() { ch launch "$@"; ID=$OUT; ch wait "$ID" --timeout 10; }

echo "# feature gate"
setup gate
ch doctor
expect "doctor passes with a capable claude" rc_is 0
ch --version
expect "--version matches plugin.json" test "$OUT" = "$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
export STUB_OLD=1
ch doctor
expect "doctor fails when claude lacks required flags" test "$RC" -ne 0
ch launch "hello"
expect "launch refuses an old claude" rc_is 2
expect "the refusal names what is missing" err_has "--bg"

echo "# launch defaults"
setup launch
ch launch "do the thing"
ID=$OUT
expect "launch prints an 8-hex id" is_id "$ID"
ch wait "$ID" --timeout 10
expect "wait reports done" rc_is 0
L=$(launch_line)
expect "pins dontAsk" line_has "$L" "[--permission-mode] [dontAsk]"
expect "nobody answers prompts" line_has "$L" "[--permission-prompts] [none]"
expect "no MCP servers" line_has "$L" "[--strict-mcp-config]"
expect "default budget" line_has "$L" "[--max-budget-usd] [1.00]"
expect "tools limited to read-only" line_has "$L" "[--tools] [Read,Grep,Glob]"
expect "read-only tools approved" line_has "$L" "[--allowedTools] [Read,Grep,Glob]"
expect "default deny list" line_has "$L" "[--disallowedTools] [Bash(git push:*),"
expect "untrusted dir: user settings only" line_has "$L" "[--setting-sources] [user]"
expect "never bypassPermissions" line_lacks "$L" "bypassPermissions"
expect "never auto mode" line_lacks "$L" "[auto]"
expect "prompt not in argv" line_lacks "$L" "do the thing"
expect "prompt sent on stdin" test "$(cat "$T/stdin.log")" = "do the thing"

echo "# trusted dirs"
setup trusted
echo "TRUSTED_DIRS=$T" >"$T/config"
launch_and_wait "x"
expect "trusted dir loads project settings" line_lacks "$(launch_line)" "[--setting-sources]"
setup trusted-tilde
echo "TRUSTED_DIRS=~/proj" >"$T/config"
OUT=$(HOME="$T" bash "$SCRIPT" launch "x" 2>"$T/err")
ch wait "$OUT" --timeout 10
expect "~ in TRUSTED_DIRS expands to HOME" line_lacks "$(launch_line)" "[--setting-sources]"

echo "# tools"
setup tools
launch_and_wait -t "Read, Bash(npm test:*)" "x"
expect "--tools gets base names" line_has "$(launch_line)" "[--tools] [Read,Bash]"
expect "--allowedTools keeps patterns" line_has "$(launch_line)" "[--allowedTools] [Read,Bash(npm test:*)]"

echo "# rejections"
setup reject
ch launch -t "Read;rm -rf /" "x"
expect "rejects a malformed tool" rc_is 2
ch launch --model "x y" "x"
expect "rejects a malformed model" rc_is 2
ch launch --dangerously-skip-permissions "x"
expect "no pass-through of claude flags" rc_is 2
ch launch --permission-mode bypassPermissions "x"
expect "no permission-mode override" rc_is 2
ch handoff -- "-x"
expect "handoff rejects a prompt starting with -" rc_is 2
ch launch
expect "launch needs a prompt" rc_is 2
expect "nothing reached claude" test -z "$(launch_line)$(handoff_line)"

echo "# limits"
setup limits
printf 'BUDGET_USD=1.00\nTIMEOUT_SECS=60\n' >"$T/config"
ch launch --budget 5 "x"
expect "cannot raise the budget" rc_is 2
ch launch --timeout 600 "x"
expect "cannot raise the timeout" rc_is 2
launch_and_wait --budget 0.5 "x"
expect "can lower the budget" line_has "$(launch_line)" "[--max-budget-usd] [0.5]"

echo "# protected dirs"
setup protected
echo "PROTECTED_DIRS=$T/proj" >"$T/config"
ch launch -t "Read,Edit" "x"
expect "write tools refused" rc_is 2
ch launch -t "Read,Bash(git status:*)" "x"
expect "Bash counts as a write tool" rc_is 2
ch handoff "x"
expect "handoff refused" rc_is 2
launch_and_wait -t "Read,Grep" "x"
expect "read-only tools allowed" rc_is 0

echo "# session limit and stop"
setup limit
echo "MAX_SESSIONS=1" >"$T/config"
export STUB_SLEEP=5
ch launch "first"
FIRST=$OUT
expect "first session starts" rc_is 0
ch launch "second"
expect "second refused at the limit" rc_is 3
ch stop "$FIRST"
expect "stop succeeds" rc_is 0
ch status "$FIRST"
expect "stopped session reports stopped" out_has "stopped"
ch launch "third"
expect "a slot frees up after stop" rc_is 0
ch stop "$OUT"

echo "# result"
setup result
LONG=$(printf 'a%.0s' $(seq 1 5000))
jq -nc --arg r "$LONG" '{type:"result",subtype:"success",is_error:false,result:$r,total_cost_usd:0.02,num_turns:3,
  permission_denials:[{tool_name:"Bash",tool_input:{command:"touch x"}}]}' >"$T/r.jsonl"
export STUB_RESULT="$T/r.jsonl"
launch_and_wait "x"
ch result "$ID" --max-chars 100
expect "opens a data block" out_has "BEGIN SESSION OUTPUT"
expect "closes the data block" out_has "END SESSION OUTPUT"
expect "counts denials" out_has "denied: 1"
expect "names the denied tool" out_has "Bash: touch x"
expect "says it truncated" out_has "truncated"
expect "body is capped" test "$(printf '%s\n' "$OUT" | grep -c 'a\{101\}')" -eq 0

echo "# budget stop"
setup budget
echo '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":0.12,"errors":["Reached maximum budget"]}' >"$T/r.jsonl"
export STUB_RESULT="$T/r.jsonl"
launch_and_wait "x"
expect "budget stop exits 11" rc_is 11
expect "budget stop is named" out_has "budget"

echo "# handoff"
setup handoff
export WARP_HANDOFF_TAB_TTL=2
ch handoff "fix it"
expect "prints the session id" test "$OUT" = deadbeef
H=$(handoff_line)
expect "pins manual mode" line_has "$H" "[--permission-mode] [manual]"
expect "no MCP servers" line_has "$H" "[--strict-mcp-config]"
expect "untrusted dir: user settings only" line_has "$H" "[--setting-sources] [user]"
expect "prompt passed" line_has "$H" "[fix it]"
TAB="$T/tabs/warp-handoff-deadbeef.toml"
expect "tab config written" test -f "$TAB"
expect "tab attaches the session" grep -qF 'commands = ["claude attach deadbeef"]' "$TAB"
expect "opened by URI" grep -qF 'warp://tab_config/warp-handoff-deadbeef' "$T/open.log"
sleep 3
expect "tab config removed after the TTL" test ! -e "$TAB"
export STUB_AGENTS="$T/agents.json"
echo '[{"sessionId":"deadbeef-0000","status":"waiting"}]' >"$STUB_AGENTS"
ch wait deadbeef --timeout 5
expect "waiting exits 10" rc_is 10
echo '[{"sessionId":"deadbeef-0000","status":"idle"}]' >"$STUB_AGENTS"
ch wait deadbeef --timeout 5
expect "idle exits 0" rc_is 0
echo '[{"sessionId":"deadbeef-0000","status":"weird"}]' >"$STUB_AGENTS"
ch wait deadbeef --timeout 5
expect "unknown status goes to the human (10)" rc_is 10
echo '[]' >"$STUB_AGENTS"
ch wait deadbeef --timeout 5
expect "gone exits 12" rc_is 12
ch result deadbeef
expect "handoff result never reads the transcript" out_has "claude attach deadbeef"

echo "# tab layout and escaping"
setup layout
export WARP_HANDOFF_TAB_TTL=10
mkdir -p "$T/we\"ird dir"
ch handoff --split -d "$T/we\"ird dir" "x"
TAB="$T/tabs/warp-handoff-deadbeef.toml"
expect "quotes in paths are escaped" grep -qF 'we\"ird dir"' "$TAB"
expect "split node" grep -qF 'split = "horizontal"' "$TAB"
expect "two panes" test "$(grep -c 'type = "terminal"' "$TAB")" -eq 2

echo "# no Warp"
setup notab
ch handoff --no-tab "x"
expect "--no-tab writes nothing" test ! -e "$T/tabs/warp-handoff-deadbeef.toml"
expect "--no-tab says how to attach" err_has "claude attach deadbeef"
setup nowarp
export WARP_HANDOFF_WARP_TAB_DIR="$T/missing"
ch handoff "x"
expect "handoff works without Warp" rc_is 0
expect "and says how to attach" err_has "claude attach deadbeef"

echo "# preview channel"
setup preview
echo "WARP_CHANNEL=preview" >"$T/config"
ch handoff "x"
expect "uses warppreview://" grep -qF 'warppreview://tab_config/' "$T/open.log"

echo "# config safety"
setup config
printf 'BUDGET_USD=$(touch %s/pwned)\n' "$T" >"$T/config"
ch launch "x"
expect "non-numeric budget refused" rc_is 2
expect "config values never executed" test ! -e "$T/pwned"
printf 'NOPE=1\n' >"$T/config"
launch_and_wait "x"
expect "unknown keys ignored" rc_is 0

echo "# ids"
setup ids
ch wait "../etc"
expect "malformed id refused" rc_is 2
ch status "deadbeef"
expect "unknown id is an error" rc_is 2

echo "# no keystroke path"
expect "script never sends keys to a terminal" \
  bash -c '! grep -nE "send-key|send-text|osascript|keystroke|xdotool" "$1"' _ "$SCRIPT"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
