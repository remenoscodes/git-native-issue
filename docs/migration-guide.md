# Platform Migration Guide

How to migrate issues between GitHub, GitLab, and other platforms using git-native-issue as the transfer medium.

## Table of Contents

- [Overview](#overview)
- [GitHub to GitLab Migration](#github-to-gitlab-migration)
- [GitLab to GitHub Migration](#gitlab-to-github-migration)
- [Multi-Platform Sync](#multi-platform-sync)
- [Disaster Recovery](#disaster-recovery)
- [Rollback Strategy](#rollback-strategy)
- [Best Practices](#best-practices)

## Overview

### The Problem

Traditional Git hosting platform migrations face these issues:

1. **Code migrates, issues don't** - `git remote set-url` moves code instantly, but issues require platform-specific export/import
2. **Vendor lock-in** - Issues are trapped in proprietary APIs and databases
3. **Migration is one-time** - No way to keep both platforms in sync during transition
4. **Broken references** - Issue numbers change, links break, history is lost
5. **No rollback** - Once migrated, going back means starting over

### The Solution

`git-native-issue` treats Git itself as the single source of truth:

```
GitHub Issues ←→ refs/issues/* ←→ GitLab Issues
                      ↓
                  (Git remotes)
```

Instead of direct platform-to-platform migration, issues flow through Git refs:

1. **Import** from source platform (GitHub, GitLab, etc.) into `refs/issues/*`
2. **Push** issue refs to any Git remote (same as code)
3. **Export** from `refs/issues/*` to target platform

This architecture provides:

- ✅ **Bidirectional sync** - Keep both platforms synchronized during migration
- ✅ **Version control** - Full Git history of issue changes
- ✅ **Rollback** - Revert to any previous state
- ✅ **Offline work** - Modify issues locally without API access
- ✅ **Multi-remote** - Push issues to multiple platforms simultaneously
- ✅ **Platform independence** - Issues outlive any single hosting service

## GitHub to GitLab Migration

**Scenario:** Your company is moving from GitHub Enterprise to GitLab (common in enterprises adopting DevOps platforms or moving to GitLab's CI/CD features).

### Phase 1: Preparation

**1. Install git-native-issue on your machine:**

```bash
brew install remenoscodes/git-native-issue/git-native-issue
git issue version
# git-issue version 1.1.0
```

**2. Set up authentication for both platforms:**

```bash
# GitHub
gh auth login

# GitLab
mkdir -p ~/.config/git-native-issue
echo "glpat-your-gitlab-token" > ~/.config/git-native-issue/gitlab-token
chmod 600 ~/.config/git-native-issue/gitlab-token
```

**3. Create the GitLab project (if not already done):**

```bash
# Via GitLab web UI or API
# Make sure the project exists before exporting
```

### Phase 2: Initial Migration

**1. Import all issues from GitHub:**

```bash
cd your-project/
git issue import github:your-org/your-repo --state all
```

This creates `refs/issues/*` for all GitHub issues, preserving:
- Complete comment history
- Original authors and timestamps
- Labels, assignees, milestones
- Issue numbers (tracked via `Provider-ID`)

Verify the import:

```bash
git issue ls --all
# Should show all imported issues

git issue show a7f3b2c
# Shows full issue details
```

**2. Push issue refs to GitLab remote:**

```bash
# Add GitLab remote (if not already added)
git remote add gitlab git@gitlab.company.com:your-org/your-repo.git

# Push code
git push gitlab main

# Push issues
git push gitlab 'refs/issues/*:refs/issues/*'
```

Now issues travel with the code in the Git repository.

**3. Export to GitLab (creates native GitLab issues):**

```bash
# Coming in v1.2.0
git issue export gitlab:your-org/your-repo
```

**Note:** Export is not yet implemented in v1.1.0. Until then, issues exist only as Git refs, which team members can query with `git issue` commands.

### Phase 3: Transition Period

During the migration, keep both platforms in sync:

**Option A: Manual sync (current v1.1.0):**

```bash
# Pull new GitHub issues
git issue import github:your-org/your-repo --state all

# Push to GitLab remote
git push gitlab 'refs/issues/*:refs/issues/*'
```

**Option B: Automated sync (v1.2.0+):**

```bash
# Two-way sync with both platforms
git issue sync github:your-org/your-repo --state all
git issue sync gitlab:your-org/your-repo --state all
```

This allows:
- Creating issues on GitHub (old workflow)
- Creating issues on GitLab (new workflow)
- Both sets synchronized via `refs/issues/*`

### Phase 4: Cut-Over

**1. Announce the cut-over date:**

"As of 2026-03-01, all new issues should be created on GitLab. GitHub issues are read-only."

**2. Final sync before cut-over:**

```bash
# Import any last-minute GitHub issues
git issue import github:your-org/your-repo --state all

# Export everything to GitLab
git issue export gitlab:your-org/your-repo
```

**3. Mark GitHub repository as read-only:**

In GitHub settings, archive the repository or update the README with a migration notice.

**4. Update team documentation:**

- Update issue templates to point to GitLab
- Update CI/CD references (if any)
- Update onboarding docs

### Phase 5: Post-Migration

**1. Verify GitLab issue count matches GitHub:**

```bash
# Count issues in Git refs
git for-each-ref refs/issues/ | wc -l

# Compare to GitHub issue count (via web UI)
# Compare to GitLab issue count (via web UI)
```

**2. Spot-check a few issues for completeness:**

```bash
# Compare GitHub issue #42 to GitLab equivalent
git issue show <uuid>
# Check that comments, labels, and metadata match
```

**3. Keep GitHub import available for 30 days:**

In case you need to re-import issues that were modified during migration:

```bash
git issue import github:your-org/your-repo --state all
# Updates existing issues with any new comments
```

### Migration Checklist

- [ ] Install git-native-issue
- [ ] Authenticate with GitHub (`gh auth login`)
- [ ] Authenticate with GitLab (create PAT, store in config)
- [ ] Import all GitHub issues (`git issue import github:org/repo --state all`)
- [ ] Verify import (`git issue ls --all`)
- [ ] Create GitLab project
- [ ] Add GitLab as Git remote
- [ ] Push code to GitLab (`git push gitlab main`)
- [ ] Push issue refs to GitLab (`git push gitlab 'refs/issues/*:refs/issues/*'`)
- [ ] Export to GitLab (when available: `git issue export gitlab:org/repo`)
- [ ] Test issue sync during transition period
- [ ] Announce cut-over date to team
- [ ] Final sync before cut-over
- [ ] Mark GitHub repository as read-only
- [ ] Update documentation and links
- [ ] Spot-check migrated issues
- [ ] Monitor for 30 days, re-import if needed

## GitLab to GitHub Migration

**Scenario:** Moving from GitLab to GitHub (less common but possible, e.g., open-sourcing a private project).

### Process (v1.2.0+)

Same as GitHub → GitLab, but reversed:

```bash
# 1. Import from GitLab
git issue import gitlab:your-org/your-repo --state all

# 2. Push to GitHub remote
git remote add github git@github.com:your-org/your-repo.git
git push github main
git push github 'refs/issues/*:refs/issues/*'

# 3. Export to GitHub
git issue export github:your-org/your-repo
```

### Current Workaround (v1.1.0)

Since GitLab export is not yet implemented, use GitLab's native export/import:

1. Use GitLab's "Export project" feature (Settings → General → Advanced → Export)
2. Import the `.tar.gz` into a GitHub repository
3. Use git-native-issue to pull GitHub issues into `refs/issues/*` for version control

This is a temporary limitation until GitLab export lands in v1.2.0.

## Multi-Platform Sync

**Scenario:** Keep issues synchronized across multiple platforms simultaneously (e.g., GitHub for public contributors, GitLab for internal work).

### Architecture

```
          ┌─────────────┐
          │   GitHub    │ ← Public issues
          └──────┬──────┘
                 │
            import/export
                 │
    ┌────────────▼────────────┐
    │    refs/issues/*        │ ← Source of truth (Git)
    │  (local + git remote)   │
    └────────────┬────────────┘
                 │
            import/export
                 │
          ┌──────▼──────┐
          │   GitLab    │ ← Private issues + CI/CD
          └─────────────┘
```

### Workflow

**1. Set up both bridges:**

```bash
# GitHub authentication
gh auth login

# GitLab authentication
export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
```

**2. Sync from both platforms:**

```bash
# Pull from GitHub (public)
git issue sync github:your-org/your-repo --state all

# Pull from GitLab (private)
git issue sync gitlab:your-org/your-repo --state all
```

**3. Push to shared Git remote:**

```bash
# All team members see both sets of issues
git push origin 'refs/issues/*:refs/issues/*'
```

### Conflict Resolution

If the same issue exists on both platforms:

- `Provider-ID` trailers distinguish them: `github:org/repo#42` vs `gitlab:org/repo#42`
- They appear as separate issues locally (different UUIDs)
- Use `git issue merge` to reconcile divergent updates

Example:

```bash
# Issue created on GitHub
git issue import github:org/repo
# Creates refs/issues/abc123 with Provider-ID: github:org/repo#1

# Same issue manually created on GitLab
git issue import gitlab:org/repo
# Creates refs/issues/def456 with Provider-ID: gitlab:org/repo#1

# These are TWO SEPARATE ISSUES in git-issue
# To unify them, close one and reference the other:
git issue state def456 --close -m "Duplicate of github:org/repo#1 (local: abc123)"
```

**Better approach:** Pick one platform as the primary source, and export from `refs/issues/*` to the secondary platform. This prevents duplicates.

### Use Case: Public + Private Issues

**Public (GitHub):**
- Bug reports from users
- Feature requests
- Security disclosures (after fix)

**Private (GitLab):**
- Internal sprint planning
- Security issues (before fix)
- Commercial feature development

**Workflow:**

```bash
# Sync public issues
git issue import github:org/repo --state all

# Sync private issues
git issue import gitlab:org/repo --state all --token "$PRIVATE_GITLAB_TOKEN"

# Filter when listing
git issue ls  # Shows all issues

# Tag them differently for filtering
git issue edit abc123 --add-label github --add-label public
git issue edit def456 --add-label gitlab --add-label private

# List by platform
git issue ls -l github
git issue ls -l gitlab
```

## Disaster Recovery

**Scenario:** GitHub/GitLab experiences an outage, data loss, or account suspension.

### Why git-issue Helps

Because issues live in `refs/issues/*`, they're backed up wherever your Git repository is:

1. **Developer machines** - Every developer with a clone has a full copy
2. **CI/CD systems** - Build agents that clone the repo have issues
3. **Backup remotes** - `git push backup 'refs/issues/*'` creates an off-platform backup

### Recovery Workflow

**1. Set up new platform (e.g., GitHub → self-hosted GitLab):**

```bash
# Add new remote
git remote add recovery git@gitlab.backup.com:org/repo.git

# Push code + issues
git push recovery main
git push recovery 'refs/issues/*:refs/issues/*'
```

**2. Export to new platform:**

```bash
git issue export gitlab:org/repo --url https://gitlab.backup.com
```

**3. Team continues working:**

All developers update their remote URLs and continue as if nothing happened. No issues are lost because they were already in Git.

### Backup Strategy

**Recommended:** Push issues to multiple remotes:

```bash
# Primary remote (GitHub/GitLab)
git push origin 'refs/issues/*:refs/issues/*'

# Backup remote (self-hosted or different platform)
git push backup 'refs/issues/*:refs/issues/*'

# Personal remote (your own server)
git push personal 'refs/issues/*:refs/issues/*'
```

Issues are now stored in 4 places:
1. Your local machine
2. Primary remote
3. Backup remote
4. Personal remote

If any one fails, you can restore from the others.

## Rollback Strategy

**Scenario:** Migration went wrong, need to revert.

### Git Provides Built-in Rollback

Because issues are Git refs, you can revert them like code:

**1. Find the commit before migration:**

```bash
# Show issue history
git log refs/issues/abc123

# Find commit before problematic import
git show <commit-hash>
```

**2. Reset issue refs to previous state:**

```bash
# Revert single issue
git update-ref refs/issues/abc123 <old-commit-hash>

# Revert all issues (nuclear option)
git for-each-ref --format='%(refname)' refs/issues/ | while read ref; do
  git update-ref "$ref" <old-commit-hash>
done
```

**3. Force-push to remote (if already pushed):**

```bash
git push origin 'refs/issues/*:refs/issues/*' --force
```

**Warning:** Force-pushing issue refs can cause divergence for other team members. Communicate before doing this.

### Safe Rollback: Create a Branch

Instead of force-pushing, create a rollback branch:

```bash
# Save current state
git branch issues-backup refs/issues/*

# Reset to previous state
git update-ref refs/issues/abc123 <old-commit-hash>

# If rollback was a mistake, restore:
git update-ref refs/issues/abc123 issues-backup
```

## Best Practices

### 1. Import Before Export

Always import issues from the source platform BEFORE exporting to the target:

```bash
# ✅ Correct
git issue import github:org/repo --state all
git issue export gitlab:org/repo

# ❌ Wrong
git issue export gitlab:org/repo
# (exports empty issue set)
```

### 2. Use Dry-Run First

Test migrations without side effects:

```bash
git issue import github:org/repo --dry-run
git issue export gitlab:org/repo --dry-run  # (when available)
```

This shows what WOULD happen without making changes.

### 3. Migrate During Low Activity

Pick a time when:
- Few issues are being created
- Developers aren't actively commenting
- CI/CD isn't heavily running

This minimizes the chance of issues being modified during migration.

### 4. Keep Provider-ID Trailers

Never manually remove `Provider-ID` trailers:

```
Provider-ID: github:org/repo#42
```

These are the only way to prevent duplicates on re-import/re-export.

### 5. Test on a Small Repo First

Before migrating a 5000-issue production repository, test on a small repo:

```bash
# Test repo with 10 issues
git issue import github:test-org/test-repo --state all
git issue export gitlab:test-org/test-repo
```

Verify the process works before scaling to production.

### 6. Communicate with the Team

Before migration:
- Announce the plan and timeline
- Share this migration guide
- Set expectations (e.g., "issues read-only for 2 hours during migration")

During migration:
- Post status updates
- Share rollback plan if something breaks

After migration:
- Confirm successful migration
- Update documentation and links
- Provide support for team members with questions

### 7. Archive Old Platform Issues

After successful migration, mark the old platform as read-only:

- **GitHub:** Archive the repository (Settings → General → Archive)
- **GitLab:** Make the project read-only (Settings → General → Permissions)

Add a prominent README notice:

```markdown
# ⚠️ This repository has been migrated

Issues have moved to: https://gitlab.company.com/org/repo

This repository is **read-only**. Please do not create new issues here.
```

### 8. Monitor for 30 Days

Keep the old platform accessible for a grace period:

- Re-import if someone accidentally creates an issue there
- Spot-check migrated issues for missing data
- Collect feedback from team members

After 30 days, you can fully deprecate the old platform.

## Troubleshooting

### "Migrated issues are missing comments"

**Cause:** Re-import skips already-imported issues unless they have new comments.

**Solution:**

```bash
# Force re-import by deleting local issue first
git update-ref -d refs/issues/abc123

# Re-import
git issue import github:org/repo --state all
```

Only do this if you're certain the local issue is incomplete.

### "Issue numbers changed after migration"

**Expected behavior:** Issue numbers are platform-specific. git-issue uses UUIDs.

**Solution:**

Use `Provider-ID` trailers to map between platforms:

```bash
# Find issue by GitHub number
git issue search "Provider-ID: github:org/repo#42"

# Show issue
git issue show abc123

# Check GitLab issue number (after export)
git log refs/issues/abc123 --format='%(trailers:key=Provider-ID,valueonly)'
# github:org/repo#42
# gitlab:org/repo#89
```

The issue has TWO platform IDs (one from GitHub, one from GitLab).

### "Import is slow for large repos"

**Cause:** Importing 1000+ issues requires many API calls.

**Solution:**

```bash
# Import in stages
git issue import github:org/repo --state opened
git issue import github:org/repo --state closed
```

Or use `--dry-run` to estimate time before committing:

```bash
git issue import github:org/repo --dry-run
# Found 2000 issues
# (estimate: ~10 minutes at 100 issues/page)
```

### "Team members don't see migrated issues"

**Cause:** Issue refs not pushed to remote, or not fetched locally.

**Solution:**

```bash
# Push from migration machine
git push origin 'refs/issues/*:refs/issues/*'

# Fetch on team machines
git fetch origin 'refs/issues/*:refs/issues/*'

# Verify
git issue ls --all
```

Add to `.git/config` for automatic fetch:

```ini
[remote "origin"]
    url = git@github.com:org/repo.git
    fetch = +refs/heads/*:refs/remotes/origin/*
    fetch = +refs/issues/*:refs/issues/*
```

## See Also

- [docs/gitlab-bridge.md](gitlab-bridge.md) - GitLab-specific documentation
- [README.md](../README.md#github-bridge) - GitHub bridge documentation
- [ISSUE-FORMAT.md](../ISSUE-FORMAT.md) - git-issue format specification
- [Git documentation on refs](https://git-scm.com/book/en/v2/Git-Internals-Git-References)
