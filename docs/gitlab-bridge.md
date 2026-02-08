# GitLab Bridge

Import and export issues from/to GitLab projects. The GitLab bridge supports both GitLab.com and self-hosted GitLab instances.

## Table of Contents

- [Quick Start](#quick-start)
- [Authentication](#authentication)
- [Import](#import)
- [Export](#export)
- [Migration Guide](#migration-guide)
- [Self-Hosted GitLab](#self-hosted-gitlab)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

## Quick Start

```bash
# Import all open issues from a GitLab project
git issue import gitlab:group/project

# Export local issues to GitLab
git issue export gitlab:group/project

# Two-way sync (import then export)
git issue sync gitlab:group/project --state all
```

## Authentication

GitLab bridge uses the **`glab` CLI** (official GitLab CLI) for authentication, providing a consistent experience with the GitHub bridge (`gh`).

### Prerequisites

Install the GitLab CLI if not already installed:

```bash
# macOS
brew install glab

# Linux (Debian/Ubuntu)
sudo apt install glab

# Linux (Fedora/RHEL)
sudo dnf install glab

# Linux (manual install)
# See: https://gitlab.com/gitlab-org/cli#installation
```

### Authenticate with GitLab

Run the authentication flow once per GitLab instance:

#### GitLab.com (default)

```bash
glab auth login
```

This will:
1. Open your browser to GitLab.com
2. Prompt you to authorize the CLI
3. Save credentials securely in your system keychain

#### Self-Hosted GitLab

```bash
glab auth login --hostname gitlab.company.com
```

Replace `gitlab.company.com` with your GitLab instance URL.

### Verify Authentication

Check that authentication succeeded:

```bash
glab auth status
```

You should see:
```
✓ Logged in to gitlab.com as username (PRIVATE-TOKEN)
✓ Active account: true
```

### Multiple GitLab Instances

You can authenticate to multiple GitLab instances (e.g., GitLab.com + self-hosted):

```bash
glab auth login                                    # GitLab.com
glab auth login --hostname gitlab.company.com      # Self-hosted instance
```

When using git-native-issue, it will automatically use the correct credentials based on the project URL.

## Import

Import issues from a GitLab project into local `refs/issues/`.

### Basic Usage

```bash
# Import all open issues (default)
git issue import gitlab:group/project

# Import all issues (open + closed)
git issue import gitlab:group/project --state all

# Import only closed issues
git issue import gitlab:group/project --state closed
```

### Preview Mode

Use `--dry-run` to preview what would be imported without making changes:

```bash
git issue import gitlab:group/project --dry-run
```

This shows which issues and comments would be imported, useful for:
- Verifying authentication
- Checking issue count before import
- Testing filters before applying them

### What Gets Imported

For each GitLab issue, the import creates a local issue with:

- **Title** - From GitLab issue title
- **Description** - From GitLab issue body
- **State** - `open` or `closed` (mapped from GitLab's `opened`/`closed`)
- **Labels** - All GitLab labels as comma-separated list
- **Assignee** - First assignee (GitLab supports multiple, git-issue supports one)
- **Comments** - All notes (GitLab's term for comments) with original author and timestamp
- **Author** - Original GitLab issue author
- **Timestamps** - Preserves original creation date

Each imported issue receives a `Provider-ID` trailer to track its source:

```
Provider-ID: gitlab:group/project#42
```

### Incremental Import

Re-importing is safe and efficient:

- **Already-imported issues** are skipped (based on `Provider-ID`)
- **New comments** on existing issues are appended to the issue chain
- **No duplicates** are created

This means you can run the same import command multiple times to fetch new comments without duplicating issues.

### Import Options

```bash
git issue import gitlab:group/project [options]

Options:
  --state <state>   Filter by state: opened, closed, all (default: opened)
  --url <url>       GitLab instance URL (default: https://gitlab.com)
  --token <token>   GitLab PAT (or use GITLAB_TOKEN env var)
  --dry-run         Show what would be imported without importing
  -h, --help        Show help
```

## Export

**Status:** Not yet implemented (planned for v1.2.0)

Export will create GitLab issues from local issues, sync state changes, and export comments. The export script will use the same authentication mechanism as import.

Expected usage:

```bash
# Export local issues to GitLab (coming soon)
git issue export gitlab:group/project
```

See [Task #2 and #4](../../README.md#roadmap) for implementation status.

## Migration Guide

### Problem: GitHub → GitLab Migration

When migrating repositories from GitHub to GitLab, your code moves easily (`git remote set-url`), but your issues don't. GitLab's built-in import only works if you migrate the entire project, and doesn't preserve GitHub URLs.

`git-native-issue` solves this by using Git itself as the transfer medium.

### Migration Workflow

#### Scenario: Moving from GitHub to GitLab

**Step 1: Import from GitHub**

```bash
cd my-project/
git issue import github:owner/repo --state all
```

This creates local `refs/issues/*` for all GitHub issues, preserving:
- Complete history (creation, comments, state changes)
- Author information
- Labels, assignees, milestones
- GitHub issue numbers (tracked via `Provider-ID: github:owner/repo#123`)

**Step 2: Push issues to new GitLab remote**

```bash
# Add GitLab as new remote
git remote add gitlab git@gitlab.com:group/project.git

# Push issues alongside code
git push gitlab 'refs/issues/*:refs/issues/*'
git push gitlab main
```

Issues now travel with the code in the same Git repository.

**Step 3: Export to GitLab (optional)**

When export is implemented (v1.2.0), you'll be able to create native GitLab issues:

```bash
git issue export gitlab:group/project
```

This creates GitLab issues with `Provider-ID` trailers linking back to the original GitHub issues.

### Bidirectional Sync

`git-native-issue` enables working across both platforms simultaneously:

```bash
# Keep GitHub and GitLab in sync via local git-issue refs
git issue import github:owner/repo --state all
git issue export gitlab:group/project  # (when available)

# Or use sync command (import + export)
git issue sync github:owner/repo --state all
git issue sync gitlab:group/project --state all
```

Issues remain under Git's version control, so you can:
- Work offline with both sets of issues
- Merge changes from both platforms
- Use Git's three-way merge to resolve conflicts
- Push issues to any remote (`origin`, `github`, `gitlab`, `backup`)

### Why This Works Better Than Platform Migrations

| Traditional Migration | git-native-issue |
|----------------------|------------------|
| One-time snapshot | Continuous sync possible |
| Loses issue URLs | Preserves `Provider-ID` links |
| Requires API limits | Local-first, API only when syncing |
| No rollback | Git history tracks everything |
| Vendor lock-in | Platform-agnostic storage |

Your issues become as portable as your code.

## Self-Hosted GitLab

The GitLab bridge supports self-hosted GitLab instances via the `--url` flag.

### Configuration

```bash
# Import from self-hosted GitLab
git issue import gitlab:group/project \
  --url https://gitlab.company.com

# With authentication
export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
git issue import gitlab:group/project \
  --url https://gitlab.company.com
```

### URL Format

- **Must include protocol:** `https://` or `http://`
- **No trailing slash:** Use `https://gitlab.example.com`, not `https://gitlab.example.com/`
- **Custom ports:** `https://gitlab.example.com:8443` is supported

### Authentication for Self-Hosted

Self-hosted instances use the same PAT mechanism as GitLab.com:

1. Go to your instance's user settings: `https://gitlab.company.com/-/profile/personal_access_tokens`
2. Create token with `read_api` (import) or `api` (import + export) scope
3. Provide via `--token`, `GITLAB_TOKEN`, or config file

### Example: Company GitLab Instance

```bash
# Create a dedicated token for automation
mkdir -p ~/.config/git-native-issue
echo "glpat-company-token-here" > ~/.config/git-native-issue/gitlab-token
chmod 600 ~/.config/git-native-issue/gitlab-token

# Import from company GitLab
git issue import gitlab:engineering/backend \
  --url https://gitlab.company.com \
  --state all

# Import succeeds if token has read_api scope
```

### Troubleshooting Self-Hosted

**Self-signed certificates:**

If your instance uses self-signed SSL certificates, `glab` may reject the connection. Solutions:

1. **Add certificate to system trust store** (recommended):
   ```bash
   # macOS
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain cert.pem

   # Linux
   sudo cp cert.pem /usr/local/share/ca-certificates/gitlab.crt
   sudo update-ca-certificates
   ```

2. **Temporary workaround** (not recommended for production):
   ```bash
   # Skip SSL verification (insecure!)
   export GIT_SSL_NO_VERIFY=true
   glab auth login --hostname gitlab.company.com
   ```

**Firewall/VPN:**

If the instance is behind a corporate firewall, ensure your machine can reach it:

```bash
# Test connectivity
glab auth status

# Or test the API directly
glab api version
```

**API v4:**

git-native-issue uses GitLab's REST API v4 (`/api/v4/...`). Ensure your instance runs GitLab 9.0+ (released 2017). Older versions are not supported.

## Examples

### Import All Issues from a GitLab Project

```bash
git issue import gitlab:gnome/gtk --state all
```

### Import from Self-Hosted GitLab

```bash
export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
git issue import gitlab:company/product \
  --url https://gitlab.company.com \
  --state all
```

### Preview Import Without Making Changes

```bash
git issue import gitlab:group/project --dry-run
```

Output:
```
Fetching issues from group/project...
Found 42 issues
[DRY RUN] Would import issue #1: Fix login crash
[DRY RUN] Would import issue #2: Add dark mode
...
```

### Import Only Open Issues

```bash
git issue import gitlab:group/project --state opened
```

GitLab uses `opened` (not `open`) for active issues. The import command accepts both `open` and `opened` but passes `opened` to the API.

### Update Existing Issues with New Comments

```bash
# First import
git issue import gitlab:group/project
# Imported 10 issues (0 skipped)

# Someone adds comments on GitLab...

# Second import (fetches new comments)
git issue import gitlab:group/project
# Imported 0 issues, updated 3 issues (7 skipped)
```

### Import from Multiple Projects

```bash
# Frontend issues
git issue import gitlab:company/frontend --state all

# Backend issues
git issue import gitlab:company/backend --state all

# Both sets of issues coexist in refs/issues/
git issue ls
```

Each issue's `Provider-ID` tracks its source, so there's no confusion.

### Scripted Import (CI/CD)

```bash
#!/bin/sh
# Import issues from GitLab nightly

set -e

export GITLAB_TOKEN="$(cat /secrets/gitlab-token)"

git issue import gitlab:team/project --state all || {
  echo "Import failed" >&2
  exit 1
}

git push origin 'refs/issues/*:refs/issues/*'
```

This keeps a Git remote in sync with GitLab issues automatically.

## Troubleshooting

### "error: 'glab' is not authenticated. Run 'glab auth login' first."

**Cause:** You haven't authenticated with GitLab yet.

**Solution:**

Authenticate with the GitLab CLI:

```bash
# For GitLab.com
glab auth login

# For self-hosted GitLab
glab auth login --hostname gitlab.company.com
```

Verify authentication:

```bash
glab auth status
```

### "error: GitLab API returned error: 401 Unauthorized"

**Cause:** Authentication expired or was revoked.

**Solution:**

Re-authenticate with GitLab:

```bash
glab auth login
```

If the issue persists, check your GitLab access tokens in **Settings** → **Access Tokens** and revoke any that look suspicious, then re-authenticate.

### "error: GitLab API returned error: 404 Not Found"

**Cause:** Project doesn't exist, or you lack access.

**Solution:**

1. Verify project path: `gitlab:group/project` (not `gitlab:user/project` for personal repos)
2. Check if project is private - you must be a member
3. For personal projects, use your username: `gitlab:username/repo`

Test project access:

```bash
# List your accessible projects
glab repo list

# View specific project
glab repo view group/project
```

Note the URL encoding: `group/project` becomes `group%2Fproject` in the API URL.

### "error: 'jq' is required but not found"

**Cause:** `jq` (JSON processor) is not installed.

**Solution:**

```bash
# macOS
brew install jq

# Debian/Ubuntu
sudo apt install jq

# Fedora/RHEL
sudo dnf install jq

# Arch
sudo pacman -S jq
```

### "error: 'glab' (GitLab CLI) is required but not found"

**Cause:** `glab` is not installed.

**Solution:**

Install the GitLab CLI:

```bash
# macOS
brew install glab

# Debian/Ubuntu
sudo apt install glab

# Fedora/RHEL
sudo dnf install glab

# Manual installation
# See: https://gitlab.com/gitlab-org/cli#installation
```

After installation, authenticate:

```bash
glab auth login
```

### Import Hangs or Times Out

**Cause:** Large projects with 1000+ issues take time to paginate through GitLab's API.

**Solution:**

- Be patient - imports are paginated at 100 issues per request
- Use `--dry-run` first to see how many issues exist
- For very large projects, import in stages:

```bash
# Import open issues first
git issue import gitlab:group/project --state opened

# Then closed issues (usually more numerous)
git issue import gitlab:group/project --state closed
```

GitLab's API rate limit: 5 requests/second for authenticated users. The script doesn't implement backoff, so extremely large imports (10,000+ issues) may hit rate limits.

### Comments Not Imported

**Cause:** Re-importing an existing issue without new comments shows "skipped".

**Expected behavior:** This is correct - already-imported comments are not duplicated.

**Verification:**

```bash
# Show issue with all comments
git issue show a7f3b2c

# Check for Provider-Comment-ID trailers
git log refs/issues/a7f3b2c --format='%B' | grep Provider-Comment-ID
```

If comments exist on GitLab but aren't imported, try `--dry-run` to see what the script detects:

```bash
git issue import gitlab:group/project --dry-run
```

### Self-Hosted GitLab SSL Errors

**Cause:** Self-signed certificates or corporate SSL interception.

**Solution:**

```bash
# Temporary workaround (insecure)
export GIT_SSL_NO_VERIFY=true

# Permanent fix: Add certificate to system trust store
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  /path/to/gitlab.crt

# Linux
sudo cp /path/to/gitlab.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

## Limitations

### Current Limitations (v1.1.0)

1. **Export not implemented** - Only import works in v1.1.0. Export coming in v1.2.0 (see Task #2).

2. **Single assignee** - GitLab supports multiple assignees per issue. git-native-issue imports only the first assignee (matches Git's single-author model).

3. **No GitLab-specific metadata:**
   - **Time tracking** (estimates, time spent) - not imported
   - **Epics** - not supported (GitLab Premium feature)
   - **Boards** - not imported (this is a view, not issue metadata)
   - **Health status** - not imported

4. **No live sync** - Import is one-way batch operation. Changes made locally don't automatically reflect on GitLab until export is implemented.

5. **Comment updates** - GitLab notes can be edited. git-issue imports the current version, but doesn't track edit history (immutable commit model).

6. **Merge request references** - GitLab issues can reference merge requests. These are imported as plain text, not linked entities.

### Design Trade-offs

These limitations are intentional design choices:

- **Import-only v1** - Export requires write operations and conflict resolution. Starting with read-only operations reduces risk.
- **Single assignee** - Git's data model (one author per commit) naturally maps to single assignee. Multiple assignees would require synthetic representation.
- **No GitLab-specific features** - git-issue targets the common subset of GitHub/GitLab/Forgejo. Platform-specific features (epics, boards) don't generalize.

### Workarounds

**Multiple assignees:** Import preserves all assignees in the issue description. Manually edit the `Assignee` trailer if needed:

```bash
git issue edit abc123 -a primary@example.com
```

**Time tracking:** Add as issue comment:

```bash
git issue comment abc123 -m "Estimated: 4h, Spent: 2h 30m"
```

**Merge request links:** These are preserved as text in comments (e.g., "See !123"). When you migrate to GitLab via export, the links will work if MR numbers are preserved.

### Planned Features (Roadmap)

- **v1.2.0:** GitLab export (Task #2, #4)
- **v1.3.0:** Bidirectional sync with conflict detection
- **v2.0.0:** Native multi-assignee support (requires format spec change)

See [Issues](https://github.com/remenoscodes/git-native-issue/issues) for full roadmap.

## See Also

- [README.md](../README.md) - Project overview and core concepts
- [GitHub Bridge](../README.md#github-bridge) - GitHub import/export documentation
- [Migration Guide](#migration-guide) - Cross-platform migration workflows
- [ISSUE-FORMAT.md](../ISSUE-FORMAT.md) - git-issue format specification
