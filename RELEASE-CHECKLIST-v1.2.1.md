# Release Checklist for v1.2.1

## ✅ Completed Steps

- [x] Fixed all 10 bugs discovered during integration testing
- [x] Updated CHANGELOG.md with v1.2.1 entry
- [x] Created RELEASE-NOTES-v1.2.1.md
- [x] Updated version to 1.2.1 in bin/git-issue
- [x] Committed all changes (commit: eeba1c5)
- [x] Created git tag v1.2.1
- [x] Comprehensive testing: 111/111 tests passing

## 🚀 Next Steps

### 1. Push to GitHub

```bash
cd /Users/emersonsoares/source/remenoscodes.git-native-issue

# Push commits
git push origin main

# Push tag
git push origin v1.2.1
```

### 2. Create GitHub Release

Go to: https://github.com/remenoscodes/git-native-issue/releases/new

**Tag:** v1.2.1
**Title:** v1.2.1 - Critical Bug Fixes for Gitea/Forgejo Bridge
**Description:** Copy from RELEASE-NOTES-v1.2.1.md

**Release highlights:**
```markdown
## 🐛 Critical Bug Fix Release

v1.2.1 fixes **10 critical bugs** discovered during comprehensive integration testing.

### What's Fixed

- ✅ Import/export router argument passing
- ✅ Gitea label auto-creation with smart colors
- ✅ GitLab comment sync
- ✅ Optional authentication for public repos
- ✅ Better error messages
- ✅ Dry-run mode improvements

### Testing
- **111/111 tests passing**
- All platforms validated: GitHub, GitLab, Gitea

**Recommendation:** All v1.2.0 users should upgrade immediately.

[See full release notes](./RELEASE-NOTES-v1.2.1.md)
```

### 3. Update Homebrew Formula

**Repository:** https://github.com/remenoscodes/homebrew-git-native-issue
**Formula:** Formula/git-native-issue.rb

**Changes needed:**
1. Update `url` to point to v1.2.1 tarball
2. Update `sha256` hash
3. Update `version` to "1.2.1"

**Steps:**
```bash
# Get the tarball SHA256
curl -L https://github.com/remenoscodes/git-native-issue/archive/refs/tags/v1.2.1.tar.gz | shasum -a 256

# Edit the formula
cd /path/to/homebrew-git-native-issue
edit Formula/git-native-issue.rb

# Update these lines:
  url "https://github.com/remenoscodes/git-native-issue/archive/refs/tags/v1.2.1.tar.gz"
  sha256 "NEW_SHA256_HERE"
  version "1.2.1"

# Test the formula
brew install --build-from-source ./Formula/git-native-issue.rb
git issue version  # Should show 1.2.1

# Commit and push
git add Formula/git-native-issue.rb
git commit -m "Update git-native-issue to v1.2.1

Critical bug fixes:
- Import/export router argument passing
- Gitea label auto-creation
- GitLab comment sync
- Better error handling
- Dry-run improvements

Testing: 111/111 tests passing"

git push origin main
```

### 4. Test Installation

```bash
# Uninstall current version
brew uninstall git-native-issue

# Update brew
brew update

# Install new version
brew install remenoscodes/git-native-issue/git-native-issue

# Verify version
git issue version  # Should show 1.2.1

# Test basic functionality
git issue create "Test v1.2.1" -m "Testing new release"
git issue ls
```

### 5. Announce Release

**Platforms to announce on:**
- [ ] GitHub Discussions (if enabled)
- [ ] Project README.md (update badge if showing version)
- [ ] Social media (if applicable)

**Announcement template:**
```
🎉 git-native-issue v1.2.1 released!

Critical bug fixes for Gitea/Forgejo bridge:
✅ 10 bugs fixed
✅ Smart label auto-creation
✅ Better error messages
✅ 111/111 tests passing

Upgrade: brew upgrade git-native-issue

Details: https://github.com/remenoscodes/git-native-issue/releases/tag/v1.2.1
```

## 📊 Release Statistics

**Version:** 1.2.1
**Release Date:** 2026-02-09
**Bugs Fixed:** 10
**Files Changed:** 8 (560 insertions, 143 deletions)
**Test Coverage:** 111/111 tests passing (100%)
**Platforms Validated:** GitHub, GitLab, Gitea
**Testing Duration:** ~2 hours comprehensive integration testing

## 🔗 Important Links

- **GitHub Repo:** https://github.com/remenoscodes/git-native-issue
- **Homebrew Tap:** https://github.com/remenoscodes/homebrew-git-native-issue
- **v1.2.1 Release:** https://github.com/remenoscodes/git-native-issue/releases/tag/v1.2.1
- **Changelog:** CHANGELOG.md
- **Release Notes:** RELEASE-NOTES-v1.2.1.md

## 📝 Notes

- This is a **patch release** addressing critical bugs from v1.2.0
- **No breaking changes** - existing workflows continue to work
- **Recommended for all users** - especially those using Gitea/Forgejo
- Next release (v1.3.0) could focus on additional platform support or features
