# git-native-issue v1.1.0 Release Notes

## 🎉 Major Feature: GitLab Bridge

v1.1.0 adds full GitLab support, completing the core promise of **seamless cross-platform issue migration**.

### What's New

#### GitLab Bridge (Import/Export/Sync)

- **`git issue import gitlab:group/project`** - Import issues from GitLab
- **`git issue export gitlab:group/project`** - Export issues to GitLab
- **`git issue sync gitlab:group/project`** - Bidirectional synchronization

**Key Features:**
- ✅ Uses `glab` CLI (official GitLab CLI) for authentication
- ✅ Consistent authentication pattern: `glab auth login` (same as GitHub's `gh auth login`)
- ✅ Support for gitlab.com and self-hosted GitLab instances
- ✅ Bidirectional comment sync with Provider-Comment-ID tracking
- ✅ Idempotent operations - re-syncing is safe, no duplicates
- ✅ Full unicode and markdown preservation

#### Cross-Platform Migration

The killer feature - migrate issues between platforms in 2 commands:

```bash
# GitHub → GitLab migration
git issue import github:oldorg/oldrepo --state all
git issue export gitlab:neworg/newrepo

# GitLab → GitHub migration
git issue import gitlab:oldgroup/oldproject --state all
git issue export github:newowner/newrepo
```

**Use Cases:**
- Enterprise platform migrations (GitHub Enterprise → GitLab self-hosted)
- Cost optimization (GitHub Teams → GitLab CE/Gitea)
- Vendor independence (backup issues in Git, portable across any platform)
- Multi-platform workflows (sync issues between GitHub + GitLab)

### Architecture Improvements

**Refactored Bridge Architecture:**
- Provider-specific scripts for better maintainability
- Clean router pattern for extensibility
- Consistent authentication and API patterns
- Ready for future providers (Gitea, Forgejo)

### Testing & Quality

- **76 core tests** passing (all existing functionality validated)
- **6 integration tests** with real GitHub/GitLab repositories
- **Cross-platform migration** validated end-to-end
- **Idempotency stress testing** - multiple syncs produce identical results
- **Unicode, emoji, markdown** preservation verified

### Critical Bug Fixes

**CRITICAL FIX**: GitLab import UUID generation
- **Problem**: Non-unique UUIDs caused duplicate refs and idempotency failures
- **Impact**: Re-syncing caused exponential growth (3→4→5 refs)
- **Fix**: Use proper UUID generation (caught during pre-release testing!)

**Other Fixes:**
- git commit-tree syntax (use environment variables)
- Router dry-run parameter expansion

### Documentation

- **docs/gitlab-bridge.md** - Comprehensive GitLab bridge guide
- **docs/migration-guide.md** - Enterprise migration workflows
  - GitHub ↔ GitLab migration recipes
  - Multi-platform sync strategies
  - Disaster recovery scenarios
- **README.md** - Updated with GitLab examples

## Upgrade Guide

### Prerequisites

Install the GitLab CLI if not already installed:

```bash
# macOS
brew install glab

# Linux
# See: https://gitlab.com/gitlab-org/cli#installation
```

Authenticate with GitLab:

```bash
# GitLab.com
glab auth login

# Self-hosted GitLab
glab auth login --hostname gitlab.company.com
```

### Upgrade from v1.0.x

```bash
# Homebrew
brew upgrade remenoscodes/git-native-issue/git-native-issue

# Or from source
git pull
make install
```

Verify the version:

```bash
git issue version
# git-issue version 1.1.0
```

## Breaking Changes

**None!** This release is 100% backward compatible with v1.0.x.

## What's Next (v1.2.0+)

- Gitea/Forgejo bridge
- Shell completion (bash/zsh)
- Performance optimizations
- Additional QoL improvements

## Contributors

This release was developed with comprehensive testing and validation before launch, catching critical bugs that would have been catastrophic in production.

Special thanks to the testing process that discovered and fixed the UUID generation bug!

---

**Full Changelog**: https://github.com/remenoscodes/git-native-issue/compare/v1.0.3...v1.1.0

**Installation**: https://github.com/remenoscodes/git-native-issue#installation

**Documentation**: https://github.com/remenoscodes/git-native-issue/tree/main/docs
