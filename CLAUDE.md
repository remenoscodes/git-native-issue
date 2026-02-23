# git-native-issue

Distributed issue tracking using Git's native data model. Issues stored as commits under `refs/issues/`.

Inherits workspace conventions from `~/CLAUDE.md`.

## Status
- **Version**: 1.3.3
- **State**: active
- **Deploy**: Homebrew (`remenoscodes/git-native-issue/git-native-issue`), install script, Makefile

## Stack
POSIX shell (Bash-compatible), Git plumbing commands, `jq` for bridge JSON processing.
Platform bridges: `gh` (GitHub), `glab` (GitLab), REST API (Gitea/Forgejo).

## Key Commands
```bash
make test                           # Run all 282 tests
make install                        # Install system-wide (/usr/local)
git issue create "title" -l bug     # Create issue with label
git issue ls --format full          # List issues with metadata
git issue sync github:owner/repo    # Two-way sync with GitHub
git issue fsck                      # Validate issue data integrity
```

## Architecture
- `bin/` — CLI entrypoints (`git-issue`, `git-issue-create`, `git-issue-edit`, etc.)
- `bridge/` — Platform bridge scripts (GitHub, GitLab, Gitea/Forgejo import/export)
- `t/` — Test suite (core, bridge, merge/fsck, QoL, validation, quality, edge cases, concurrency)
- `ISSUE-FORMAT.md` — Standalone format specification (the primary deliverable)
- Data model: commits as events, refs as identity, Git trailers as metadata, merge commits for conflict resolution

## Related Projects
- `~/source/remenoscodes.claude-git-native-issue` — Claude Code plugin for autonomous git-issue integration
- `~/source/remenoscodes.claude-plugin-marketplace` — Central marketplace listing this plugin
