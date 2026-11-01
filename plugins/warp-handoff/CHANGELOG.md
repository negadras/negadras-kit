# Changelog

## 0.1.2

- Under `PROTECTED_DIRS`, only `Read`, `Grep` and `Glob` are allowed; `WebFetch` and `WebSearch` are refused because
  they can send out what `Read` saw.
- Config values may end with a comment: a `#` after whitespace, after a quoted value too. A `#` anywhere else stays
  part of the value, so `"/repo"#1` or `#/repo` is a bad folder entry, not `/repo` or an empty list.
- `doctor` checks `PROTECTED_DIRS` (a bad entry fails it) and reports bad `TRUSTED_DIRS` entries as ignored.
- The skill description names new tabs, split panes and parallel sessions, so Claude picks it for those requests; a
  split opens in a new tab, because Warp cannot split the current one.

## 0.1.1

- Removed the internal `_run` command, which started claude with flags read from any folder named on the command line.
- `PROTECTED_DIRS` matches folders by identity, so a different letter case on macOS or `/` itself no longer slips past.
  An entry that is not an existing absolute folder is now an error instead of being skipped.
- Under `PROTECTED_DIRS`, only `Read`, `Grep`, `Glob`, `WebSearch` and `WebFetch` count as read-only; every other
  tool counts as a write tool.
- Config lines may use CRLF endings, spaces around `=` and single or double quotes.
- `--model` refuses a name that starts with `-`.
- `result` markers carry a random tag, so session output cannot fake the end of the data block.

## 0.1.0

- `launch`: unattended `claude -p` session with a fixed tool allowlist, budget, timeout and session limit.
- `handoff`: `claude --bg` session in manual mode, opened in a new Warp tab; only the user answers its prompts.
- `wait`, `status`, `result`, `ls`, `stop`, `follow`, `doctor`.
- Tested with Claude Code 2.1.309 and Warp 0.2026.10.21 on macOS.
