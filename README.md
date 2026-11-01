# negadras-kit

Skills, plugins and configs for working with coding agents, Claude Code first.

Unofficial. Not affiliated with Anthropic or any tool named here.

## Contents

| Name | Kind | What it does |
|---|---|---|
| [warp-handoff](plugins/warp-handoff) | plugin (skill) | Start and supervise separate Claude Code sessions with guardrails the calling agent cannot loosen; watch them in Warp tabs. |

## Install

Plugins install through this repo's marketplace:

```
/plugin marketplace add negadras/negadras-kit
/plugin install <name>@negadras-kit
```

Or copy a skill folder (`plugins/<name>/skills/<skill>/`) to `~/.claude/skills/`. Each plugin's README lists its
requirements.

## Layout

```
.claude-plugin/marketplace.json   lists every plugin
plugins/<name>/                   one installable plugin: skills, hooks, agents, commands, MCP config
configs/<topic>/                  copy-in files that are not plugins (settings snippets, statusline, tab configs)
docs/                             guides for working on this repo
scripts/validate.sh               checks manifests, shell scripts and every plugin's offline tests
```

Conventions are in [AGENTS.md](AGENTS.md); adding something new is in [docs/adding-a-plugin.md](docs/adding-a-plugin.md).

## License

MIT
