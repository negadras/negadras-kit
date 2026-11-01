# warp-handoff

A Claude Code skill that starts and supervises separate Claude Code sessions: unattended with a fixed tool
allowlist, or driven by you in a new [Warp](https://www.warp.dev) tab. The guardrails live in the script, so the
calling agent cannot loosen them.

Unofficial. Not affiliated with Warp or Anthropic.

## Why

Skills that drive other Claude sessions by typing into their terminal let the parent agent answer the child's
permission prompts, including "always allow" and "switch to auto mode". warp-handoff has no way to type into a
session. It builds on Claude Code's own background sessions (`claude --bg`, `claude agents`) and headless mode
(`claude -p`), and uses Warp only as a place for you to watch.

## Two modes

| | `launch` | `handoff` |
|---|---|---|
| Runs | `claude -p` in the background | `claude --bg`, attached in a new Warp tab |
| Permission prompts | never shown: tools outside `-t` are refused (`dontAsk`, `--permission-prompts none`) | shown in the Warp tab; only you answer them (`manual`) |
| The calling agent reads | the final answer, capped and marked as data | the state only (`waiting`, `idle`, ...) |

## Requirements

- Claude Code with `--bg`, `claude agents --json`, `--permission-prompts` and the `dontAsk` mode. Tested with
  2.1.309. The script checks for these and refuses to run without them.
- bash 3.2 or later, `jq`.
- macOS. Linux paths for Warp are in place but untested.
- Warp is optional (stable or Preview). Without it, `handoff` prints `claude attach <id>` instead of opening a tab.

## Install

As a plugin:

```
/plugin marketplace add negadras/negadras-kit
/plugin install warp-handoff@negadras-kit
```

Or copy `skills/warp-handoff/` (in this folder) to `~/.claude/skills/`. Then check your setup:

```bash
skills/warp-handoff/scripts/warp-handoff.sh doctor
```

## Use

Ask Claude, for example "use warp-handoff to list the TODOs in src/", or run the script yourself:

```bash
ch=skills/warp-handoff/scripts/warp-handoff.sh

id=$($ch launch -t "Read,Grep,Glob" -- "List every TODO under src/ with file and line.")
$ch wait "$id"          # 0 done, 11 error/budget/timeout
$ch result "$id"

id=$($ch handoff --split -- "Upgrade the eslint config and run the tests.")
$ch wait "$id"          # 10 = waiting for you in the Warp tab
$ch stop "$id"
```

Warp opens tabs from a Tab Config, so `handoff` writes `warp-handoff-<id>.toml` into Warp's `tab_configs`
folder, opens it with `warp://tab_config/...` without bringing Warp to the front, and deletes it 15 seconds later.

## Configuration

`~/.config/warp-handoff/config` holds `KEY=value` lines. It is parsed, never executed.

| Key | Default | Meaning |
|---|---|---|
| `TRUSTED_DIRS` | empty | Colon-separated. Sessions under these load project settings and hooks; elsewhere only your user settings load. |
| `PROTECTED_DIRS` | empty | No write tools and no `handoff` under these. |
| `BUDGET_USD` | `1.00` | Per-session cap. `--budget` can only lower it. |
| `MAX_SESSIONS` | `3` | Running sessions started by this script. |
| `TIMEOUT_SECS` | `1800` | A `launch` session is stopped after this. `--timeout` can only lower it. |
| `DEFAULT_TOOLS` | `Read,Grep,Glob` | Tools for `launch` when `-t` is not given. |
| `DENY_TOOLS` | `git push`, `gh` PR, issue and release writes | Always passed to `launch` as `--disallowedTools`. |
| `MCP_CONFIG` | empty | An MCP config file for sessions. Empty means no MCP servers. |
| `WARP_CHANNEL` | `stable` | `stable` or `preview`. |

Environment overrides: `WARP_HANDOFF_CONFIG`, `WARP_HANDOFF_STATE`, `WARP_HANDOFF_WARP_TAB_DIR`,
`WARP_HANDOFF_OPEN`, `WARP_HANDOFF_TAB_TTL`.

## What it protects against

- **The parent answering the child's prompts.** There is no command that types into a session, and `launch`
  sessions never show a prompt.
- **An inherited permission mode.** Every session gets an explicit mode, whatever your default is (it may be `auto`).
- **Project hooks from folders you have not vetted.** `claude -p` runs a folder's project hooks without any trust
  check. Outside `TRUSTED_DIRS`, sessions load only your user settings. `claude --bg` refuses folders Claude has not
  trusted, but trust is inherited: trusting your home folder trusts every clone under it.
- **MCP tools you did not choose.** Sessions get no MCP servers unless `MCP_CONFIG` names some.
- **Runaway cost.** Budget, session count and timeout; flags can only lower them.
- **Instructions smuggled in a result.** `result` caps the text and wraps it in data markers, and the skill tells the
  agent not to act on it.

## What it does not protect against

- In `handoff`, you can still choose "always allow" or "switch to auto mode" yourself.
- Sessions run as you. Your user settings, allow rules and hooks apply, and an allow rule in your user settings still
  pre-approves matching calls for any tool in `-t`.
- Approving a `launch` whose `-t` includes `Bash` approves whatever that session runs within the deny list. Read the
  tool list before you approve, and do not add the script to your allow rules or to the skill's `allowed-tools`.
- The budget is checked after each turn, so a session can overshoot by one turn. A $0.0001 cap stopped at $0.12.
- An agent that can write files in your home folder can edit the config. The guardrails stop casual widening, not a
  determined agent with that access.
- The states read from `claude agents --json` are observed, not documented. Unknown values are treated as
  "waiting for you".
- `CLAUDE.md` files in the session's folder still load.

## Tests

```bash
bash tests/run.sh                                     # offline, stub claude, no tokens
LIVE_TRUSTED_DIR=<a folder claude trusts> bash tests/live.sh   # real claude, a few cents on Sonnet
```

The Warp tab itself needs your eyes: run `handoff --split` and check that the left pane shows the session.

## License

MIT
