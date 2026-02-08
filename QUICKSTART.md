# Quick Start (5 Minutes)

Get started with git-native-issue in 5 minutes. No theory, just commands.

## Install

### Homebrew (macOS/Linux)

```bash
brew install remenoscodes/git-native-issue/git-native-issue
```

### Install Script (Any POSIX System)

```bash
curl -sSL https://raw.githubusercontent.com/remenoscodes/git-native-issue/main/install.sh | sh
```

### Verify

```bash
git issue version
# git-issue version 1.0.2
```

## Your First Issue

### 1. Create an Issue

```bash
cd your-git-repo/
git issue create "Add dark mode support" -m "Users have requested this feature"
# Created issue a7f3b2c
```

### 2. List Issues

```bash
git issue ls
# a7f3b2c [open]  Add dark mode support
```

### 3. Show Details

```bash
git issue show a7f3b2c
```

### 4. Add a Comment

```bash
git issue comment a7f3b2c -m "Working on this now. Will have PR ready by Friday."
# Added comment to a7f3b2c
```

### 5. Close the Issue

```bash
git issue state a7f3b2c --close --fixed-by abc123
# Closed issue a7f3b2c
```

### 6. Push to Remote

```bash
git push origin 'refs/issues/*'
# Your issues now travel with your code
```

## Common Workflows

### Create Issue with Labels and Priority

```bash
git issue create "Fix login crash" \
  -l bug -l auth -l urgent \
  -p critical \
  -a alice@example.com
```

### Search Issues

```bash
git issue search "login"
# Searches titles, bodies, and comments
```

### Filter by State

```bash
git issue ls --state open    # Default
git issue ls --state closed
git issue ls --all           # Both open and closed
```

### Edit Issue Metadata

```bash
git issue edit a7f3b2c -p high --add-label security
```

### Sync with Remote

```bash
# Pull issues from remote
git fetch origin 'refs/issues/*:refs/issues/*'

# Push your issues
git push origin 'refs/issues/*'
```

## GitHub Bridge

### Import Issues from GitHub

```bash
# Requires: gh CLI and jq
brew install gh jq
gh auth login

# Import all open issues
git issue import github:owner/repo

# Import all issues (open + closed)
git issue import github:owner/repo --state all
```

### Export Issues to GitHub

```bash
git issue export github:owner/repo
```

### Two-Way Sync

```bash
git issue sync github:owner/repo --state all
```

## What's Next?

### Learn More

- **[README.md](README.md)** - Full documentation
- **[ISSUE-FORMAT.md](ISSUE-FORMAT.md)** - Format specification
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - How to contribute

### Try Advanced Features

```bash
# Distributed merge (resolve divergent issue updates)
git issue merge origin

# Validate data integrity
git issue fsck

# Custom sorting and filtering
git issue ls --sort priority --reverse
git issue ls --assignee alice@example.com
git issue ls --priority critical
```

### Get Help

```bash
git issue --help
git issue create --help
git issue ls --help
```

---

**That's it!** You're now tracking issues with Git. Issues travel with your code, sync with `git fetch/push`, and work completely offline.

Happy issue tracking! 🚀
