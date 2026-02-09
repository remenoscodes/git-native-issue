# Release Notes: git-native-issue v1.2.2

**Release Date:** 2026-02-09
**Type:** Patch Release (Bug Fix)

---

## 🎯 What's Fixed

### The Problem (Discovered via Dogfooding)

When using `git-native-issue` in a **local-only repository** (no remote configured), users encountered confusing errors:

```
$ git issue init
error: remote 'origin' does not exist
       available remotes:
```

This contradicted git-native-issue's **distributed/offline-first philosophy** — core commands should work perfectly without any remote configuration.

### Root Causes

1. **Hardcoded "origin" assumption** in `git issue init`
   - Failed immediately if no "origin" remote existed
   - Didn't handle repos with non-standard remote names (upstream, fork, etc.)

2. **Unclear messaging** about init being optional
   - Users might assume init is required
   - No documentation explaining core commands work without init

3. **Coupling appeared to exist** between core functionality and remotes
   - Actually, core commands were fine!
   - But init failures blocked workflow

---

## ✨ What's New

### 1. Intelligent Remote Auto-Detection

`git issue init` now auto-detects remotes intelligently:

| Scenario | Behavior |
|----------|----------|
| **No remotes** | Explains init is optional, exits gracefully (exit 0) |
| **1 remote (any name)** | Auto-detects and uses it |
| **Multiple remotes + "origin"** | Prefers "origin" (common convention) |
| **Multiple remotes, no "origin"** | Lists options, asks user to specify |
| **Explicit: `init <remote>`** | Always respects user choice |

**Before:**
```sh
$ git issue init
error: remote 'origin' does not exist
       available remotes: upstream,fork
```

**After:**
```sh
$ git issue init
git-issue: Multiple remotes found. Please specify which one to use:
  - fork
  - upstream

Usage:
  git issue init <remote-name>

Example:
  git issue init fork
```

### 2. Local-Only Repository Support

**No remotes?** No problem!

```sh
$ git issue init
git-issue: No remotes configured.

Note: git issue init is OPTIONAL. You can use git-issue without any remote:
  - All core commands (create, ls, show, comment, edit, state) work locally
  - To sync with a remote later, use manual push/fetch:
    git push <remote> 'refs/issues/*'
    git fetch <remote> 'refs/issues/*:refs/issues/*'

To configure automatic fetch when you add a remote, run:
  git issue init <remote-name>
```

### 3. Comprehensive Test Coverage

**30 new tests** validating local-only workflows:

- **t/test-local-only-repo.sh** (17 tests)
  - Core commands work 100% without remote
  - Init handles no-remote gracefully
  - Bridge commands fail clearly (as expected)
  - Issues stored correctly in refs/issues/*

- **t/test-init-auto-detect.sh** (13 tests)
  - All auto-detection scenarios
  - Error message clarity
  - Remote preference logic

**Test Results:** 106/106 tests passing (76 core + 30 new)

---

## 🔍 Technical Details

### What `git issue init` Actually Does

**ONLY adds convenience for automatic fetch:**

```ini
# Without init - manual fetch required:
git fetch origin 'refs/issues/*:refs/issues/*'

# With init - adds to .git/config:
[remote "origin"]
    fetch = +refs/issues/*:refs/issues/*

# Then you can just:
git fetch origin  # issues fetched automatically
```

**Init is 100% OPTIONAL** — all core commands work without it.

### Changes Made

**Modified files:**
- `bin/git-issue-init` (+64 lines) - Auto-detection logic
- `bin/git-issue` (VERSION bump to 1.2.2)
- `t/test-issue.sh` (version test updated)

**New files:**
- `t/test-local-only-repo.sh` (+315 lines)
- `t/test-init-auto-detect.sh` (+270 lines)

**Total:** 3 files changed, 649 insertions(+), 3 deletions(-)

---

## 📦 Installation

### Upgrade via Homebrew

```bash
brew update
brew upgrade git-native-issue
```

### Install from Source

```bash
git clone https://github.com/remenoscodes/git-native-issue.git
cd git-native-issue
git checkout v1.2.2
make install
```

### Verify Installation

```bash
git issue version
# git-issue version 1.2.2
```

---

## ✅ Validation

**Tested scenarios:**
- ✅ Local-only repos (no remote)
- ✅ Repos with single non-origin remote
- ✅ Repos with multiple remotes (with/without origin)
- ✅ Explicit remote specification
- ✅ All core commands work independently

**Backwards compatibility:**
- ✅ Existing workflows unchanged
- ✅ Explicit `git issue init origin` still works
- ✅ No breaking changes

---

## 🙏 Credits

**Discovered by:** Emerson Soares (dogfooding in production)
**Root cause analysis:** Complete investigation of coupling between core and bridges
**Fix:** Intelligent auto-detection + comprehensive test coverage

---

## 📚 Documentation

- [README.md](README.md) - Full documentation
- [CHANGELOG.md](CHANGELOG.md) - Complete changelog
- [ISSUE-FORMAT.md](ISSUE-FORMAT.md) - Format specification

---

## 🐛 Reporting Issues

Found a bug? Please report it:
- GitHub: https://github.com/remenoscodes/git-native-issue/issues
- Use git-native-issue itself: `git issue create "Bug: ..." -l bug`

---

**Previous release:** [v1.2.1 - Gitea/Forgejo bridge fixes](RELEASE-NOTES-v1.2.1.md)
**Next release:** TBD

---

🚀 **Happy distributed issue tracking!**
