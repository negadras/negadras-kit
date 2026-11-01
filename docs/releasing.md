# Releasing a plugin

Merging to `main` is the release. The marketplace serves each plugin from `main`, and users get a new copy only when
the plugin's `version` changes, through `claude plugin update` or auto-update. Tags record what shipped; they do not
ship anything.

## In the PR

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json`, and any copy of it the plugin keeps (warp-handoff's
   script has `VERSION`; its tests check that the two match).
2. Add a `## <version>` entry to the plugin's `CHANGELOG.md`.
3. Run `scripts/validate.sh`. Its `versions` step fails when:
   - `plugin.json` has no `x.y.z` version, or `CHANGELOG.md` has no entry for it;
   - files users receive changed but the version did not (`tests/`, `README.md` and `CHANGELOG.md` may change
     without a bump);
   - the version is already tagged and the plugin's files differ from that tag.

   It compares against `origin/main`, or the commit in `VALIDATE_BASE`, so fetch first.
4. `scripts/release.sh --dry-run` prints the tag and notes the merge would publish.

## After the merge

`.github/workflows/release.yml` runs on every push to `main`. It runs `validate.sh`, then `scripts/release.sh`,
which for each plugin whose version has no tag creates `<name>--v<version>` on the merged commit and a GitHub
Release whose notes are that version's CHANGELOG entry. Versions that already have a tag are skipped, so re-running
the workflow is safe.

The `<name>--v<version>` form is the one Claude Code matches plugin dependency version ranges against.
