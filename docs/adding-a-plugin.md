# Adding a plugin

1. Pick a name: lowercase, hyphenated, named for what it does, not starting with `claude-` (see AGENTS.md).
2. Create the folder:

   ```
   plugins/<name>/
   ├── .claude-plugin/plugin.json
   ├── README.md
   ├── CHANGELOG.md
   ├── skills/<skill>/SKILL.md        # and/or hooks/, agents/, commands/
   └── tests/run.sh
   ```

   `plugin.json` needs at least `name`, `description`, `version`, `author`, `license`. Point `homepage` at
   `https://github.com/negadras/negadras-kit/tree/main/plugins/<name>`.
3. Add an entry to `.claude-plugin/marketplace.json` with `"source": "./plugins/<name>"`.
4. Add a row to the Contents table in the root `README.md`.
5. Write the offline tests first and watch them fail, then build until they pass.
6. Run `scripts/validate.sh`.

A skill that is not worth a plugin of its own still goes in one: a plugin with a single skill is the unit people
install. Files that are copied rather than installed go in `configs/<topic>/` with a short README.
