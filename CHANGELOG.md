# Changelog

All notable changes to git-native-issue will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.1] - 2026-02-15

### Fixed

- **GitHub assignee resolution for private emails** — users with non-public email addresses can now be resolved to their GitHub username via commit history
  - Upgraded from three-tier to five-tier lookup: cache → noreply pattern → repo commits API → search commits API → search users API
  - Tiers 2-3 use GitHub's Commits API which resolves private emails (linked via account settings)
  - Noreply pattern moved earlier (free, no API call needed)
  - Search users API demoted to last resort (only works for public emails)
- **Auto-seed user cache on GitHub export** — the authenticated `gh` user's email→username mapping is cached at startup, removing the need for a prior import to populate the cache

## [1.3.0] - 2026-02-15

### Added

- **Bidirectional assignee sync** across all platform bridges (GitHub, GitLab, Gitea/Forgejo)
  - Import bridges resolve platform usernames to canonical email addresses
  - Export bridges resolve canonical emails back to platform identities
  - Three-tier reverse lookup: persistent cache → platform search API → noreply pattern extraction
  - Auto-seed cache from authenticated CLI user on export (no manual setup needed)
  - Unassign support: clearing assignee locally (`-a ""`) propagates to platforms
- **Persistent user cache** (`git-issue-lib`) for email ↔ platform identity mapping
  - Stored in `.git/issue-user-cache.<platform>` (per-repo, per-platform)
  - Functions: `cache_platform_user`, `lookup_cached_login`, `lookup_cached_user_id`
  - Populated during import, used during export for reverse lookup
- **Assignee email validation** in `git-issue-create` and `git-issue-edit`
  - Validates basic email format: `user@domain.tld`
  - Helpful error messages guide users to correct format
- **Label validation and normalization** (`normalize_labels()` in git-issue-lib)
  - Labels containing commas rejected with clear error
  - Duplicate labels automatically deduplicated
  - Whitespace normalized consistently
- **Concurrency retry mechanism** (`update_ref_with_retry()` in git-issue-lib)
  - Optimistic locking with CAS (Compare-And-Swap) for ref updates
  - Retries up to 3 times with exponential backoff (100ms, 200ms)
  - Clear error messages distinguish CAS failures from other errors
- **Git identity validation** (`validate_git_identity()` in git-issue-lib)
  - Checks `user.name` and `user.email` before any git operations
  - Exits early with helpful error messages if missing
- New test suites:
  - `t/test-assignee-validation.sh` — 22 tests (email validation, cache, filters, unassign)
  - `t/test-labels-validation.sh` — 12 tests (comma rejection, dedup, normalization)
  - `t/test-concurrency.sh` — 8 tests (CAS retry, identity validation)

### Fixed

- **git-issue-edit**: Could not unassign with `-a ""` — added `has_assignee_set` flag to distinguish "not provided" from "empty value"
- **git-issue-show**: Empty assignee/priority/milestone values were skipped by `sed '/^$/d'`, causing stale values to show through
- **git-issue-show**: Trailer parsing failed when commit body contained only trailers (no description) — fixed by prepending newline before `git interpret-trailers --parse`
- **git-issue-ls**: Empty assignee/priority/milestone values overwritten by older non-empty values in awk — added `has_*` flags
- **git-issue-export-github**: `head -1` on `%(trailers:key=Assignee,valueonly)` captured empty line from Provider-ID commit (no Assignee trailer), causing active unassign on every re-export — switched to full trailer format with `has_assignee` flag

### Changed

- All platform bridge imports now resolve usernames to canonical emails and populate persistent cache
- All platform bridge exports now resolve canonical emails to platform identities for assignee assignment
- `git-issue-edit`, `git-issue-state`, `git-issue-comment` now use `update_ref_with_retry()` for ref updates
- `git-issue-edit`, `git-issue-state`, `git-issue-comment` now validate git identity before operations

## [1.2.2] - 2026-02-09

### Fixed
- **git-issue-init remote coupling**: Fixed hardcoded "origin" assumption that failed in repos without remotes or with non-standard remote names
- **Intelligent remote auto-detection**: Init now auto-detects remotes intelligently (single remote, prefers origin if multiple, asks user if ambiguous)
- **Local-only repository support**: Clarified that `git issue init` is OPTIONAL - all core commands work perfectly without any remote configuration

### Added
- Comprehensive test coverage for local-only workflows (t/test-local-only-repo.sh - 17 tests)
- Remote auto-detection test suite (t/test-init-auto-detect.sh - 13 tests)
- Improved error messages explaining init is optional and showing manual push/fetch alternatives

### Changed
- `git issue init` now exits gracefully (exit 0) when no remotes exist, with helpful message
- Updated documentation to clarify distributed/offline-first philosophy

## [1.2.1] - 2026-02-09

### Fixed

**Critical bug fixes for Gitea/Forgejo bridge** (10 bugs found during integration testing):

1. **Import router argument passing** - Router scripts (git-issue-import, git-issue-export) weren't passing --url and --token flags to provider-specific scripts. Fixed by passing all arguments via "$@".

2. **Import pagination integer validation** - Missing validation before integer arithmetic caused "integer expression expected" errors when API returned invalid responses. Added proper validation with error messages.

3. **Import authentication requirements** - Hard requirement for API token prevented importing from public repositories. Changed to optional with warning message for private repo access.

4. **Import error handling with curl -f** - The -f flag caused curl to fail silently on HTTP errors, hiding actual API error messages. Removed -f flag and added JSON validation instead.

5. **Import empty author names** - Some Gitea users have empty full_name field, causing "empty ident name not allowed" git errors. Added fallback to username when full_name is empty.

6. **Export router argument passing** - Same issue as import router, fixed by passing all arguments via "$@".

7. **Export label handling for Gitea** - Gitea API expects label IDs (integers) but we were sending label names (strings), causing "cannot unmarshal number into Go struct field" errors. Implemented smart label resolution:
   - Fetches all existing labels from target repository
   - Auto-creates missing labels with smart color defaults:
     - bug/fix → red (#d73a4a)
     - enhancement/feature → light blue (#a2eeef)
     - documentation/docs → blue (#0075ca)
     - question → purple (#d876e3)
     - duplicate → gray (#cfd3d7)
     - help* → green (#008672)
     - default → blue (#84b6eb)
   - Returns label IDs for API calls
   - Caches labels for performance

8. **Export token verification** - Token check with curl -f blocked dry-run mode. Removed -f flag, added JSON validation, and skipped verification in dry-run mode.

9. **Export dry-run improvements** - Dry-run mode now works without valid credentials, skipping all API calls.

10. **GitLab comment sync** - glab issue view --output json doesn't include notes/comments (glab CLI limitation). Changed to use direct API call: glab api "projects/{encoded_path}/issues/{iid}/notes".

### Testing

- **Full integration testing across all 3 platforms** (GitHub, GitLab, Gitea):
  - ✅ Import: 4 issues from 3 different platforms into single repository
  - ✅ Export: Local issues exported to GitLab and Gitea with label auto-creation
  - ✅ Bidirectional sync: Comments added on all 3 platforms synced successfully
  - ✅ Unicode & emoji: 你好 🚀 🌍 🔧 preserved across all platforms
  - ✅ Smart duplicate prevention: Issues with Provider-ID correctly skipped
  - ✅ Cross-platform migration: GitHub→Local→GitLab/Gitea workflows verified
- **Test suite results**: 97/97 tests passing (76 core + 21 QoL)
- **Real-world validation**: Tested with gitea.com, gitlab.com, and github.com

### Changed

- bin/git-issue-import: Pass all arguments to provider scripts
- bin/git-issue-export: Pass all arguments to provider scripts
- bin/git-issue-import-gitea: Fixed 5 bugs (pagination, auth, errors, authors, token check)
- bin/git-issue-export-gitea: Fixed 3 bugs (labels, token check, dry-run) + added label auto-creation
- bin/git-issue-import-gitlab: Fixed comment sync (use direct API instead of glab issue view)

## [1.2.0] - 2026-02-08

### Added
- **Gitea/Forgejo bridge** - Import, export, and sync issues with Gitea and Forgejo
  - `git issue import gitea:owner/repo` - Import issues from Gitea
  - `git issue import forgejo:owner/repo` - Import issues from Forgejo (Codeberg.org, etc.)
  - `git issue export gitea:owner/repo` - Export issues to Gitea
  - `git issue export forgejo:owner/repo` - Export issues to Forgejo
  - `git issue sync gitea:owner/repo` - Bidirectional synchronization
  - Uses direct API calls (curl + jq) - NO CLI tool required
  - Token authentication via GITEA_TOKEN/FORGEJO_TOKEN env vars or config files
  - Self-hosted instance support via --url flag
  - Provider-ID format: `gitea:owner/repo#123` or `forgejo:owner/repo#123`
  - Auto-detect platform (Gitea vs Forgejo) via /api/v1/version endpoint
  - Default URLs: https://gitea.com (Gitea), https://codeberg.org (Forgejo)
  - Idempotent operations with Provider-Comment-ID tracking
  - Bidirectional comment sync

### Changed
- **Bridge architecture extended** - Added Gitea/Forgejo provider-specific scripts
  - bin/git-issue-import-gitea: Gitea/Forgejo import implementation (467 lines)
  - bin/git-issue-export-gitea: Gitea/Forgejo export implementation (506 lines)
  - bin/git-issue-{import,export,sync}: Updated routers for gitea:/forgejo: prefixes
- **Documentation updates**
  - Fixed GitLab bridge docs to correctly reference glab CLI (not curl/PAT)
  - Updated authentication instructions for GitLab bridge

### Testing
- Gitea/Forgejo bridge test suite: 40 comprehensive tests
  - t/test-gitea-bridge.sh: 30 mock tests with fixtures
  - t/test-integration-gitea.sh: 10 real instance tests
  - Mock curl implementation for isolated testing
  - JSON fixtures for Gitea API responses
- Test documentation: t/TEST-GITEA-BRIDGE.md

### Documentation
- Gitea/Forgejo bridge setup guide (docs/gitea-bridge.md) - 700+ lines
  - Authentication setup (Personal Access Tokens)
  - Import/export/sync examples
  - Self-hosted instance configuration
  - API compatibility notes (Gitea 1.0+, Forgejo 1.18+)
  - Troubleshooting guide
  - Migration workflows (GitHub→Gitea, GitLab→Forgejo)
- Updated README.md with Gitea/Forgejo bridge section
- Updated QUICKSTART.md with Gitea/Forgejo examples

## [1.1.0] - 2026-02-08

### Added
- **GitLab bridge** - Import, export, and sync issues with GitLab
  - `git issue import gitlab:group/project` - Import issues from GitLab
  - `git issue export gitlab:group/project` - Export issues to GitLab
  - `git issue sync gitlab:group/project` - Bidirectional synchronization
  - Uses `glab` CLI (official GitLab CLI) for authentication and API access
  - Authentication via `glab auth login` (consistent with GitHub bridge)
  - Support for gitlab.com and self-hosted GitLab instances
  - Provider-ID format: `gitlab:group/project#iid`
  - Idempotent operations with Exported-Commit tracking (no duplicates)
  - Bidirectional comment sync with Provider-Comment-ID tracking

### Changed
- **Refactored bridge architecture** - Provider-specific scripts for maintainability
  - bin/git-issue-import-github: GitHub import implementation
  - bin/git-issue-import-gitlab: GitLab import implementation
  - bin/git-issue-export-github: GitHub export implementation
  - bin/git-issue-export-gitlab: GitLab export implementation
  - bin/git-issue-{import,export,sync}: Routers delegate to provider scripts

### Testing
- GitLab bridge test suite: 30+ comprehensive tests (t/test-gitlab-bridge.sh)
- Migration test: GitHub → Git → GitLab roundtrip validation
- Idempotency verification (multiple syncs produce identical results)
- Unicode, edge cases, dry-run, error handling coverage
- Mock glab CLI for isolated testing

### Documentation
- GitLab bridge setup guide (docs/gitlab-bridge.md)
- Platform migration guide (docs/migration-guide.md)
  - GitHub ↔ GitLab enterprise migration workflows
  - Multi-platform sync strategies
  - Disaster recovery scenarios
- Updated README with GitLab bridge section

### Fixed
- **CRITICAL**: GitLab import UUID generation (caused duplicate refs and idempotency failures)
  - Root cause: Used static value for UUID generation, creating identical UUIDs
  - Impact: Re-syncing caused exponential growth of refs (3→4→5...)
  - Fix: Use proper UUID generation (uuidgen) like GitHub import
- git commit-tree syntax: Use environment variables (GIT_AUTHOR_*) instead of --author/--date flags
- Router dry-run parameter expansion bug

## [1.0.3] - 2026-02-11

### Changed
- **CI/CD Refactored** - Homebrew tap updates now fully automated
  - Removed Formula/ directory from main repository
  - Tap formula now lives exclusively in homebrew-git-native-issue repository
  - Release workflow triggers automated formula updates via repository_dispatch
  - Follows official Homebrew tap best practices
- **Documentation improvements**
  - Comprehensive README for Homebrew tap with CI/CD architecture
  - Removed tool-specific references, keeping documentation generic
  - Platform migration use case highlighted in announcement

### Infrastructure
- Automated tap update workflow in homebrew-git-native-issue
- PAT token integration for cross-repository workflow triggers
- Zero-downtime formula updates (users get new version within minutes)

## [1.0.2] - 2026-02-11

### Added
- **Bidirectional comment synchronization** for GitHub bridge
  - Comments added on GitHub are now imported to local issues
  - Comments added locally are exported to existing GitHub issues
  - Fully idempotent: running sync multiple times is safe
- **Provider-Comment-ID tracking** to prevent duplicate comments
- **Exported-Commit trailer** links metadata to original commit SHAs
- **Edge case test suite** (11 tests covering unicode, long comments, special chars, state conflicts, rapid syncs, concurrent operations, markdown)
- Platform migration use case documentation in ANNOUNCEMENT.md

### Fixed
- **Critical bug**: Comments were duplicated on each sync (#7481188)
  - Root cause: Export didn't track which commits were already exported
  - Solution: Exported-Commit trailer associates metadata with original commits
  - Impact: sync is now fully idempotent with zero duplication
- GitHub bridge now handles deleted/closed issues gracefully
- State conflicts resolved correctly (local wins on simultaneous changes)
- Markdown code blocks preserved during export/import

### Changed
- Export now creates metadata commits with both Provider-Comment-ID and Exported-Commit trailers
- Sync detection logic uses commit SHA list instead of timestamp comparison
- Test suite expanded from 153 to 160 tests (7 new bidirectional sync tests)

### Testing
- 160/160 tests passing (76 core + 36 bridge + 20 merge + 21 QoL + 7 comment-sync)
- Edge cases validated: unicode, emojis, special characters, long comments (5000+ chars)
- Idempotency verified: 3 consecutive syncs produce identical results
- State conflict resolution tested and validated

### Documentation
- Added migration use case (GitHub ↔ GitLab) to announcement
- Updated roadmap: C/Rust implementation → contrib/git-issue/ → git builtin
- Created GitLab bridge specification for v1.1.0

## [1.0.1] - 2026-02-07

### Added
- Initial public release
- Core commands: create, ls, show, comment, edit, state
- GitHub bridge: import, export, sync
- Distributed merge with field-specific rules
- POSIX shell implementation
- 153 comprehensive tests
- Multiple installation methods (Homebrew, asdf, install.sh)

### Security
- Trailer injection protection
- Command injection prevention
- Input sanitization for all user-provided data

### Performance
- Tested with 10,000+ issues
- Optimized for large repositories
- Efficient Git plumbing usage

[1.3.1]: https://github.com/remenoscodes/git-native-issue/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/remenoscodes/git-native-issue/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/remenoscodes/git-native-issue/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/remenoscodes/git-native-issue/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/remenoscodes/git-native-issue/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/remenoscodes/git-native-issue/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/remenoscodes/git-native-issue/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/remenoscodes/git-native-issue/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/remenoscodes/git-native-issue/releases/tag/v1.0.1
