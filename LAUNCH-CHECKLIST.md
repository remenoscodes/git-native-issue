# Launch Checklist - Tuesday 2026-02-11

## ✅ Completed (All 7 Blockers Fixed)

1. ✅ CI workflow updated with new repo names
2. ✅ Shellcheck linting added to CI
3. ✅ CI added to Homebrew tap repo
4. ✅ CI added to asdf plugin repo
5. ✅ GPG signing added to workflow (optional, can enable later)

## ✅ Testing & Validation (COMPLETED 2026-02-08)

### 1. ✅ Create v1.0.2 Release
- ✅ Updated VERSION in bin/git-issue to 1.0.2
- ✅ Created and pushed v1.0.2 tag
- ✅ Release workflow completed successfully
- ✅ Tarball created: `git-native-issue-v1.0.2.tar.gz`
- ✅ Homebrew formula auto-updated

### 2. ✅ Update PKGBUILD SHA256
- ✅ PKGBUILD updated with v1.0.2 SHA256
- ✅ Committed and pushed

### 3. ✅ CI Validation - All Tests Passing (9/9)
- ✅ Homebrew formula
- ✅ asdf plugin
- ✅ macOS installation
- ✅ Ubuntu 20.04, 22.04
- ✅ Debian 11, 12
- ✅ Alpine Linux
- ✅ Arch Linux (PKGBUILD)

## 📋 Remaining Tasks for Tuesday Launch

### 1. ✅ Documentation Review (COMPLETED 2026-02-08)
- ✅ README URLs all correct (version updated to 1.0.2)
- ✅ Test suite version checks fixed (all 3 files updated)
- ✅ Launch post ready (LAUNCH-POST.md created)
- ✅ HN title fits (78 chars, under 80 limit)
- ✅ Reddit formatting tested

### 2. ✅ Final Pre-Launch Checks (COMPLETED 2026-02-08)
- ✅ Test one installation method locally (install.sh tested)
- ✅ Verify GitHub Actions all green (all tests passing)
- ✅ Verify latest commit signed with new GPG key (87084B5FE22026BE)

## 📋 Launch Day (Tuesday Morning)

### Pre-Launch (30 min before)
- [ ] Final smoke test all installation methods
- [ ] Check GitHub Actions all green
- [ ] Verify latest commit is signed
- [ ] Test HN link formatting

### Launch (9:00 AM PT - optimal time)
- [ ] Post to Hacker News (Show HN)
- [ ] Monitor for first 2 hours (quick responses help)
- [ ] Have answers ready for common questions

### Post-Launch (Same Day)
- [ ] Wait 24 hours, then Reddit (r/programming, r/git)
- [ ] Lobsters if accepted
- [ ] Dev.to/Hashnode blog post

## 🎯 Success Metrics (Week 1)

- GitHub stars: 50+
- Homebrew installs: 20+
- HN front page (top 30)
- Zero critical bugs reported

## 📝 Notes

GPG Signing:
- Workflow supports it but currently disabled
- Can enable post-launch by adding secrets
- Not critical for initial launch

Time to Launch: ~1.5 hours remaining work
Confidence: HIGH ✅
