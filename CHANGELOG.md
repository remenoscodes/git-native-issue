# Changelog

All notable changes to git-native-issue will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **GitLab bridge** - Import, export, and sync issues with GitLab
  - `git issue import gitlab:group/project` - Import issues from GitLab
  - `git issue export gitlab:group/project` - Export issues to GitLab
  - `git issue sync gitlab:group/project` - Bidirectional synchronization
  - Support for gitlab.com and self-hosted GitLab instances
  - GitLab PAT authentication via ~/.config/git-native-issue/gitlab-token or GITLAB_TOKEN env var
  - Provider-ID format: `gitlab:group/project#123`
  - Idempotent operations with Exported-Commit tracking (no duplicates)

### Testing
- GitLab bridge test suite (t/test-gitlab-bridge.sh)
- Migration test: GitHub → Git → GitLab roundtrip validation
- Idempotency verification (multiple syncs produce identical results)

### Documentation
- GitLab bridge setup guide (docs/gitlab-bridge.md)
- Platform migration guide (GitHub ↔ GitLab)
- Updated README with GitLab examples

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

[1.0.3]: https://github.com/remenoscodes/git-native-issue/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/remenoscodes/git-native-issue/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/remenoscodes/git-native-issue/releases/tag/v1.0.1
