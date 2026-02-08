# git-native-issue v1.2.0 Release Notes

## 🎉 Major Feature: Gitea/Forgejo Bridge

v1.2.0 adds full Gitea and Forgejo support, completing coverage of the major open-source Git hosting platforms.

### What's New

#### Gitea/Forgejo Bridge (Import/Export/Sync)

- **`git issue import gitea:owner/repo`** - Import issues from Gitea
- **`git issue import forgejo:owner/repo`** - Import issues from Forgejo
- **`git issue export gitea:owner/repo`** - Export issues to Gitea/Forgejo
- **`git issue sync gitea:owner/repo`** - Bidirectional synchronization

**Key Features:**
- ✅ NO CLI tool required - uses direct API calls (curl + jq)
- ✅ Token authentication: `GITEA_TOKEN` / `FORGEJO_TOKEN` env vars or config files
- ✅ Auto-detect platform (Gitea vs Forgejo) via API
- ✅ Support for gitea.com, codeberg.org, and self-hosted instances
- ✅ Bidirectional comment sync with Provider-Comment-ID tracking
- ✅ Idempotent operations - re-syncing is safe, no duplicates
- ✅ Full unicode and markdown preservation

#### Cross-Platform Migration

The killer feature - migrate issues between ANY supported platforms in 2 commands:

```bash
# GitHub → Gitea migration
git issue import github:oldorg/oldrepo --state all
git issue export gitea:neworg/newrepo --url https://gitea.company.com

# GitLab → Forgejo migration
git issue import gitlab:oldgroup/oldproject --state all
git issue export forgejo:username/project

# Forgejo → GitHub migration
git issue import forgejo:username/oldproject --state all
git issue export github:username/newrepo
```

**Use Cases:**
- Platform independence (backup issues in Git, portable across any platform)
- Cost optimization (GitHub Teams → Gitea/Forgejo self-hosted)
- Open-source alignment (move to Codeberg.org/Forgejo for non-profit governance)
- Self-hosted for compliance (GDPR, data sovereignty)

### Platform Support Matrix

| Platform | Status | Method | CLI Required? |
|----------|--------|--------|---------------|
| GitHub | ✅ v1.0 | gh CLI | Yes |
| GitLab | ✅ v1.1 | glab CLI | Yes |
| **Gitea** | ✅ **v1.2** | **Direct API** | **No** |
| **Forgejo** | ✅ **v1.2** | **Direct API** | **No** |

### Architecture Improvements

**Direct API Approach:**
- Gitea/Forgejo bridges use curl + jq (NO CLI dependency)
- Simpler authentication (just set token env var or config file)
- Works everywhere POSIX shell is available
- No rate limiting concerns (unlike GitHub's 5000 req/hour)

**Provider-Specific Scripts:**
- bin/git-issue-import-gitea (467 lines)
- bin/git-issue-export-gitea (506 lines)
- Clean router pattern for extensibility
- Ready for future providers (Bitbucket, Azure DevOps)

### Testing & Quality

- **40 comprehensive tests** for Gitea/Forgejo bridge
  - 30 mock tests with fixture-based API responses
  - 10 integration tests with real instances
- **All platform tests passing** (GitHub, GitLab, Gitea/Forgejo)
- **Cross-platform migration** validated end-to-end
- **Idempotency stress testing** - multiple syncs produce identical results
- **Unicode, emoji, markdown** preservation verified

### Documentation

- **docs/gitea-bridge.md** - Comprehensive Gitea/Forgejo bridge guide (700+ lines)
  - Authentication setup (Personal Access Tokens)
  - Import/export/sync examples
  - Self-hosted instance configuration
  - API compatibility notes (Gitea 1.0+, Forgejo 1.18+)
  - Troubleshooting guide
  - Migration workflows
- **docs/gitlab-bridge.md** - Fixed to correctly reference glab CLI
- **README.md** - Updated with Gitea/Forgejo examples
- **QUICKSTART.md** - Added Gitea/Forgejo quickstart

## Upgrade Guide

### Prerequisites

No additional CLI tools needed! Just `curl` and `jq` (usually pre-installed).

```bash
# Verify you have the tools
command -v curl && command -v jq
```

### Authentication Setup

#### Gitea

1. Go to your Gitea instance → **Settings** → **Applications** → **Manage Access Tokens**
2. Generate new token with `read:issue` and `write:issue` scopes
3. Save token:

```bash
# Via environment variable
export GITEA_TOKEN="your-token-here"

# Or via config file (recommended)
mkdir -p ~/.config/git-native-issue
echo "your-token-here" > ~/.config/git-native-issue/gitea-token
chmod 600 ~/.config/git-native-issue/gitea-token
```

#### Forgejo (e.g., Codeberg.org)

Same process as Gitea, but use `FORGEJO_TOKEN`:

```bash
export FORGEJO_TOKEN="your-forgejo-token"

# Or config file
echo "your-forgejo-token" > ~/.config/git-native-issue/forgejo-token
chmod 600 ~/.config/git-native-issue/forgejo-token
```

### Upgrade from v1.1.x

```bash
# Homebrew
brew upgrade remenoscodes/git-native-issue/git-native-issue

# Or from source
cd ~/source/remenoscodes.git-native-issue
git pull
make install
```

Verify the version:

```bash
git issue version
# git-issue version 1.2.0
```

## Breaking Changes

**None!** This release is 100% backward compatible with v1.1.x.

## What's Next (v1.3.0+)

Based on market research, the next bridges in priority order:

1. **Bitbucket** (21-30% market share, Atlassian ecosystem)
2. **Azure DevOps** (13.62% DevOps services, Fortune 500 presence)
3. **Forgejo Federation (ForgeFed)** - Distributed issue tracking across federated instances

Other roadmap items:
- Shell completion (bash/zsh)
- Performance optimizations
- Additional QoL improvements

## Contributors

This release was developed using parallel team development with specialized agents:
- **implementation-lead**: Import/export bridge implementation
- **test-specialist**: Comprehensive 40-test suite
- **doc-writer**: 700+ line documentation and API research

---

**Full Changelog**: https://github.com/remenoscodes/git-native-issue/compare/v1.1.0...v1.2.0

**Installation**: https://github.com/remenoscodes/git-native-issue#installation

**Documentation**: https://github.com/remenoscodes/git-native-issue/tree/main/docs
