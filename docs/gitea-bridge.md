# Gitea/Forgejo Bridge

Import and export issues from/to Gitea and Forgejo repositories. The Gitea/Forgejo bridge supports both hosted services and self-hosted instances.

## Table of Contents

- [Quick Start](#quick-start)
- [Authentication](#authentication)
- [Import](#import)
- [Export](#export)
- [Migration Guide](#migration-guide)
- [Self-Hosted Instances](#self-hosted-instances)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

## Quick Start

```bash
# Import all open issues from a Gitea/Forgejo repository
git issue import gitea:owner/repo

# Import from self-hosted instance
git issue import gitea:owner/repo --url https://gitea.company.com

# Export local issues to Gitea/Forgejo
git issue export gitea:owner/repo

# Two-way sync (import then export)
git issue sync gitea:owner/repo --state all
```

## Authentication

Unlike GitHub (which uses `gh` CLI) and GitLab (which uses `glab` CLI), Gitea and Forgejo don't have official CLI tools for authentication. Instead, the bridge uses **Personal Access Tokens (PATs)** directly.

### Creating a Personal Access Token

#### Gitea

1. Log in to your Gitea instance
2. Navigate to **Settings** → **Applications** → **Manage Access Tokens**
3. Click **Generate New Token**
4. Enter a descriptive name (e.g., "git-issue sync")
5. Select scopes:
   - **For import only:** `read:issue`, `read:repository`
   - **For import + export:** `read:issue`, `write:issue`, `read:repository`
6. Click **Generate Token**
7. **Copy the token immediately** -- it won't be shown again

#### Forgejo

1. Log in to your Forgejo instance (e.g., codeberg.org)
2. Navigate to **Settings** → **Applications** → **Manage Access Tokens**
3. Click **Generate New Token**
4. Enter a descriptive name (e.g., "git-issue sync")
5. Select scopes:
   - **For import only:** `read:issue`, `read:repository`
   - **For import + export:** `read:issue`, `write:issue`, `read:repository`
6. Click **Generate Token**
7. **Copy the token immediately** -- it won't be shown again

### Storing Your Token

There are three ways to provide your token:

#### Option 1: Environment Variable (Quick Testing)

```bash
export GITEA_TOKEN="your-token-here"
git issue import gitea:owner/repo
```

This is convenient for testing but the token is visible in shell history and environment.

#### Option 2: Config File (Recommended)

Store tokens securely in a config file:

```bash
# Create config directory
mkdir -p ~/.config/git-native-issue
chmod 700 ~/.config/git-native-issue

# Store token (Gitea)
echo "your-token-here" > ~/.config/git-native-issue/gitea-token
chmod 600 ~/.config/git-native-issue/gitea-token

# For Forgejo, use a separate file
echo "your-forgejo-token" > ~/.config/git-native-issue/forgejo-token
chmod 600 ~/.config/git-native-issue/forgejo-token
```

The bridge will automatically read from these files when you run import/export commands.

#### Option 3: Command-Line Flag (CI/CD)

Pass the token directly via the `--token` flag:

```bash
git issue import gitea:owner/repo --token "your-token-here"
```

This is useful for CI/CD pipelines where tokens are stored in secrets management systems.

### Verify Authentication

Test that authentication works:

```bash
# This will attempt to fetch issues and verify your token
git issue import gitea:owner/repo --dry-run
```

If authentication fails, you'll see:

```
error: Gitea API returned error: 401 Unauthorized
```

## Import

Import issues from a Gitea or Forgejo repository into local `refs/issues/`.

### Basic Usage

```bash
# Import all open issues (default)
git issue import gitea:owner/repo

# Import from Forgejo (same command, different provider)
git issue import forgejo:owner/repo

# Import all issues (open + closed)
git issue import gitea:owner/repo --state all

# Import only closed issues
git issue import gitea:owner/repo --state closed
```

### Provider Detection

The bridge automatically detects whether you're using Gitea or Forgejo:

- **`gitea:owner/repo`** - Reads from `~/.config/git-native-issue/gitea-token` or `$GITEA_TOKEN`
- **`forgejo:owner/repo`** - Reads from `~/.config/git-native-issue/forgejo-token` or `$FORGEJO_TOKEN`

Both use the same API (Forgejo is a Gitea fork), so the provider prefix is mainly for token selection and documentation clarity.

### Self-Hosted Instances

Specify the instance URL with `--url`:

```bash
# Self-hosted Gitea
git issue import gitea:owner/repo --url https://gitea.company.com

# Codeberg.org (Forgejo)
git issue import forgejo:owner/repo --url https://codeberg.org

# Custom port
git issue import gitea:owner/repo --url https://git.example.com:3000
```

**URL Format:**
- Must include protocol: `https://` or `http://`
- No trailing slash: Use `https://gitea.example.com`, not `https://gitea.example.com/`
- Custom ports supported: `https://gitea.example.com:8443`

### Preview Mode

Use `--dry-run` to preview what would be imported without making changes:

```bash
git issue import gitea:owner/repo --dry-run
```

This shows which issues and comments would be imported, useful for:
- Verifying authentication
- Checking issue count before import
- Testing filters before applying them

### What Gets Imported

For each Gitea/Forgejo issue, the import creates a local issue with:

- **Title** - From issue title
- **Description** - From issue body
- **State** - `open` or `closed`
- **Labels** - All labels as comma-separated list
- **Assignee** - First assignee (Gitea/Forgejo support multiple, git-issue supports one)
- **Comments** - All comments with original author and timestamp
- **Author** - Original issue author
- **Timestamps** - Preserves original creation date

Each imported issue receives a `Provider-ID` trailer to track its source:

```
Provider-ID: gitea:owner/repo#42
```

or

```
Provider-ID: forgejo:owner/repo#42
```

### Incremental Import

Re-importing is safe and efficient:

- **Already-imported issues** are skipped (based on `Provider-ID`)
- **New comments** on existing issues are appended to the issue chain
- **No duplicates** are created

This means you can run the same import command multiple times to fetch new comments without duplicating issues.

### Import Options

```bash
git issue import gitea:owner/repo [options]

Options:
  --state <state>   Filter by state: open, closed, all (default: open)
  --url <url>       Gitea/Forgejo instance URL (e.g., https://gitea.company.com)
  --token <token>   Access token (or use GITEA_TOKEN/FORGEJO_TOKEN env var)
  --dry-run         Show what would be imported without importing
  -h, --help        Show help
```

## Export

**Status:** Implemented in v1.2.0

Export creates Gitea/Forgejo issues from local issues, syncs state changes, and exports comments.

### Basic Usage

```bash
# Export local issues to Gitea
git issue export gitea:owner/repo

# Export to Forgejo
git issue export forgejo:owner/repo

# Export to self-hosted instance
git issue export gitea:owner/repo --url https://gitea.company.com
```

### What Gets Exported

For each local issue without a `Provider-ID` matching the target repository:

- **Title** - From commit subject line
- **Description** - From commit body
- **State** - `open` or `closed`
- **Labels** - Created if they don't exist on the remote
- **Comments** - All comments in the issue chain
- **Author** - Mapped to your Gitea/Forgejo account (API token owner)

After export, the issue receives a `Provider-ID` trailer:

```
Provider-ID: gitea:owner/repo#123
```

This prevents duplicate exports on subsequent syncs.

### Export Options

```bash
git issue export gitea:owner/repo [options]

Options:
  --url <url>       Gitea/Forgejo instance URL
  --token <token>   Access token
  --dry-run         Show what would be exported without exporting
  -h, --help        Show help
```

## Migration Guide

### Problem: GitHub/GitLab → Gitea/Forgejo Migration

When migrating repositories from GitHub or GitLab to Gitea or Forgejo, your code moves easily, but your issues don't. Gitea's built-in import only works if you migrate the entire project at once, and doesn't preserve original URLs.

`git-native-issue` solves this by using Git itself as the transfer medium.

### Migration Workflow

#### Scenario: Moving from GitHub to Gitea

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

**Step 2: Push issues to new Gitea remote**

```bash
# Add Gitea as new remote
git remote add gitea git@gitea.company.com:owner/repo.git

# Push issues alongside code
git push gitea 'refs/issues/*:refs/issues/*'
git push gitea main
```

Issues now travel with the code in the same Git repository.

**Step 3: Export to Gitea**

Create native Gitea issues from local issues:

```bash
git issue export gitea:owner/repo --url https://gitea.company.com
```

This creates Gitea issues with `Provider-ID` trailers linking back to the original GitHub issues.

#### Scenario: GitLab → Forgejo (e.g., Codeberg.org)

```bash
# Import from GitLab
git issue import gitlab:group/project --state all

# Push to new Forgejo remote
git remote add codeberg git@codeberg.org:user/repo.git
git push codeberg 'refs/issues/*:refs/issues/*'
git push codeberg main

# Export to Codeberg
git issue export forgejo:user/repo --url https://codeberg.org
```

### Bidirectional Sync

`git-native-issue` enables working across multiple platforms simultaneously:

```bash
# Keep GitHub and Gitea in sync via local git-issue refs
git issue import github:owner/repo --state all
git issue export gitea:owner/repo --url https://gitea.company.com

# Or use sync command (import + export)
git issue sync github:owner/repo --state all
git issue sync gitea:owner/repo --url https://gitea.company.com --state all
```

Issues remain under Git's version control, so you can:
- Work offline with both sets of issues
- Merge changes from both platforms
- Use Git's three-way merge to resolve conflicts
- Push issues to any remote (`origin`, `github`, `gitea`, `codeberg`)

### Why This Works Better Than Platform Migrations

| Traditional Migration | git-native-issue |
|----------------------|------------------|
| One-time snapshot | Continuous sync possible |
| Loses issue URLs | Preserves `Provider-ID` links |
| Requires API limits | Local-first, API only when syncing |
| No rollback | Git history tracks everything |
| Vendor lock-in | Platform-agnostic storage |

Your issues become as portable as your code.

## Self-Hosted Instances

Both Gitea and Forgejo are designed for self-hosting. The bridge fully supports custom instances.

### Gitea Self-Hosted

```bash
# Import from company Gitea
export GITEA_TOKEN="your-token-here"
git issue import gitea:engineering/backend \
  --url https://gitea.company.com \
  --state all

# Export to company Gitea
git issue export gitea:engineering/backend \
  --url https://gitea.company.com
```

### Forgejo Self-Hosted

```bash
# Import from Codeberg.org (public Forgejo instance)
export FORGEJO_TOKEN="your-codeberg-token"
git issue import forgejo:username/project \
  --url https://codeberg.org \
  --state all

# Or use config file
echo "your-codeberg-token" > ~/.config/git-native-issue/forgejo-token
chmod 600 ~/.config/git-native-issue/forgejo-token
git issue import forgejo:username/project --url https://codeberg.org
```

### API Compatibility

- **Gitea:** Requires Gitea 1.0+ (API v1 support)
- **Forgejo:** Requires Forgejo 1.18+ (API v1 compatible with Gitea)
- **API Endpoint:** Both use `/api/v1/*` endpoints

Forgejo is a soft fork of Gitea, maintaining API compatibility. This means:
- All Gitea API calls work on Forgejo
- Token scopes are identical
- Authentication methods are the same

### Troubleshooting Self-Hosted

**Self-signed certificates:**

If your instance uses self-signed SSL certificates, `curl` (used internally by the bridge) may reject the connection. Solutions:

1. **Add certificate to system trust store** (recommended):
   ```bash
   # macOS
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain cert.pem

   # Linux
   sudo cp cert.pem /usr/local/share/ca-certificates/gitea.crt
   sudo update-ca-certificates
   ```

2. **Temporary workaround** (not recommended for production):
   ```bash
   # Skip SSL verification (insecure!)
   export GIT_SSL_NO_VERIFY=true
   git issue import gitea:owner/repo --url https://gitea.company.com
   ```

**Firewall/VPN:**

If the instance is behind a corporate firewall, ensure your machine can reach it:

```bash
# Test connectivity
curl https://gitea.company.com/api/v1/version

# With authentication
curl -H "Authorization: token YOUR_TOKEN" \
  https://gitea.company.com/api/v1/user
```

**API v1:**

git-native-issue requires Gitea API v1 (`/api/v1/*`). Ensure your instance runs:
- **Gitea 1.0+** (released 2016)
- **Forgejo 1.18+** (released 2022)

Older versions are not supported.

## Examples

### Import All Issues from a Gitea Repository

```bash
git issue import gitea:go-gitea/gitea --state all
```

### Import from Codeberg.org (Forgejo)

```bash
export FORGEJO_TOKEN="your-codeberg-token"
git issue import forgejo:meissa/forgejo --url https://codeberg.org --state all
```

### Import from Self-Hosted Gitea

```bash
export GITEA_TOKEN="your-company-token"
git issue import gitea:company/product \
  --url https://gitea.company.com \
  --state all
```

### Preview Import Without Making Changes

```bash
git issue import gitea:owner/repo --dry-run
```

Output:
```
Fetching issues from owner/repo...
Found 42 issues
[DRY RUN] Would import issue #1: Fix login crash
[DRY RUN] Would import issue #2: Add dark mode
...
```

### Import Only Open Issues

```bash
git issue import gitea:owner/repo --state open
```

### Update Existing Issues with New Comments

```bash
# First import
git issue import gitea:owner/repo
# Imported 10 issues (0 skipped)

# Someone adds comments on Gitea...

# Second import (fetches new comments)
git issue import gitea:owner/repo
# Imported 0 issues, updated 3 issues (7 skipped)
```

### Import from Multiple Repositories

```bash
# Frontend issues (Gitea)
git issue import gitea:company/frontend --url https://gitea.company.com --state all

# Backend issues (Forgejo/Codeberg)
git issue import forgejo:company/backend --url https://codeberg.org --state all

# Both sets of issues coexist in refs/issues/
git issue ls
```

Each issue's `Provider-ID` tracks its source, so there's no confusion.

### Export to Gitea After Migration

```bash
# Import from GitHub
git issue import github:old-org/old-repo --state all

# Export to new Gitea instance
git issue export gitea:new-org/new-repo --url https://gitea.company.com
```

Issues now exist on both platforms with linked `Provider-ID` trailers.

### Scripted Import (CI/CD)

```bash
#!/bin/sh
# Import issues from Gitea nightly

set -e

export GITEA_TOKEN="$(cat /secrets/gitea-token)"

git issue import gitea:team/project \
  --url https://gitea.company.com \
  --state all || {
  echo "Import failed" >&2
  exit 1
}

git push origin 'refs/issues/*:refs/issues/*'
```

This keeps a Git remote in sync with Gitea issues automatically.

## Troubleshooting

### "error: GITEA_TOKEN or FORGEJO_TOKEN environment variable is required"

**Cause:** You haven't provided an access token.

**Solution:**

Create a token and provide it via environment variable or config file:

```bash
# Environment variable
export GITEA_TOKEN="your-token-here"

# Or config file
mkdir -p ~/.config/git-native-issue
echo "your-token-here" > ~/.config/git-native-issue/gitea-token
chmod 600 ~/.config/git-native-issue/gitea-token
```

### "error: Gitea API returned error: 401 Unauthorized"

**Cause:** Token is invalid, expired, or doesn't have required scopes.

**Solution:**

1. Verify token has correct scopes:
   - **Import:** `read:issue`, `read:repository`
   - **Export:** `read:issue`, `write:issue`, `read:repository`

2. Test token manually:
   ```bash
   curl -H "Authorization: token YOUR_TOKEN" \
     https://gitea.company.com/api/v1/user
   ```

3. Create a new token if the current one is invalid.

### "error: Gitea API returned error: 404 Not Found"

**Cause:** Repository doesn't exist, or you lack access.

**Solution:**

1. Verify repository path: `gitea:owner/repo` (not `gitea:user/project` for personal repos)
2. Check if repository is private - you must have access
3. For personal repositories, use your username: `gitea:username/repo`

Test repository access:

```bash
curl -H "Authorization: token YOUR_TOKEN" \
  https://gitea.company.com/api/v1/repos/owner/repo
```

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

### "error: 'curl' is required but not found"

**Cause:** `curl` is not installed (rare on modern systems).

**Solution:**

```bash
# Debian/Ubuntu
sudo apt install curl

# Fedora/RHEL
sudo dnf install curl

# macOS (should be pre-installed)
brew install curl
```

### Import Hangs or Times Out

**Cause:** Large repositories with 1000+ issues take time to paginate through the API.

**Solution:**

- Be patient - imports are paginated at 100 issues per request
- Use `--dry-run` first to see how many issues exist
- For very large repositories, import in stages:

```bash
# Import open issues first
git issue import gitea:owner/repo --state open

# Then closed issues (usually more numerous)
git issue import gitea:owner/repo --state closed
```

Gitea's default rate limit: 5000 requests/hour for authenticated users. The bridge respects rate limits automatically.

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

If comments exist on Gitea but aren't imported, try `--dry-run` to see what the bridge detects:

```bash
git issue import gitea:owner/repo --dry-run
```

### Self-Hosted Gitea/Forgejo SSL Errors

**Cause:** Self-signed certificates or corporate SSL interception.

**Solution:**

```bash
# Temporary workaround (insecure)
export GIT_SSL_NO_VERIFY=true

# Permanent fix: Add certificate to system trust store
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  /path/to/gitea.crt

# Linux
sudo cp /path/to/gitea.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### "error: Repository is archived and read-only"

**Cause:** The Gitea/Forgejo repository is archived, preventing exports.

**Solution:**

You can still import from archived repositories, but cannot export to them. Unarchive the repository in Gitea/Forgejo settings if you need write access.

## Limitations

### Current Limitations (v1.2.0)

1. **Single assignee** - Gitea and Forgejo support multiple assignees per issue. git-native-issue imports only the first assignee (matches Git's single-author model).

2. **No Gitea-specific metadata:**
   - **Projects/Boards** - Not imported (these are views, not issue metadata)
   - **Due dates** - Not imported (not in core git-issue spec)
   - **Dependencies** - Issue dependencies are not imported

3. **No live sync** - Import/export are batch operations. Changes made locally don't automatically reflect on Gitea/Forgejo until you run export again.

4. **Comment updates** - Gitea/Forgejo comments can be edited. git-issue imports the current version, but doesn't track edit history (immutable commit model).

5. **Pull request references** - Gitea/Forgejo issues can reference pull requests. These are imported as plain text, not linked entities.

### Design Trade-offs

These limitations are intentional design choices:

- **Single assignee** - Git's data model (one author per commit) naturally maps to single assignee. Multiple assignees would require synthetic representation.
- **No platform-specific features** - git-issue targets the common subset of GitHub/GitLab/Gitea/Forgejo. Platform-specific features don't generalize.
- **Batch operations** - Real-time sync requires webhooks and conflict resolution UI. Starting with batch import/export reduces complexity.

### Workarounds

**Multiple assignees:** Import preserves all assignees in the issue description. Manually edit the `Assignee` trailer if needed:

```bash
git issue edit abc123 -a primary@example.com
```

**Due dates:** Add as issue comment or in description:

```bash
git issue comment abc123 -m "Due date: 2026-03-01"
```

**Issue dependencies:** Add as issue comment:

```bash
git issue comment abc123 -m "Blocked by: #42, #57"
```

### Planned Features (Roadmap)

- **v1.3.0:** Bidirectional sync with conflict detection
- **v2.0.0:** Native multi-assignee support (requires format spec change)
- **v2.1.0:** Due date support in core specification

See [Issues](https://github.com/remenoscodes/git-native-issue/issues) for full roadmap.

## Gitea vs Forgejo: What's the Difference?

**Forgejo** is a soft fork of **Gitea**, created in 2022 to ensure community governance and prevent corporate capture. From an API perspective, they are nearly identical:

- **API Compatibility:** Forgejo maintains API v1 compatibility with Gitea
- **Token Scopes:** Identical scope names and permissions
- **Authentication:** Both use Personal Access Tokens via HTTP headers
- **Endpoints:** `/api/v1/*` endpoints are the same

**When to use which provider prefix:**

- Use `gitea:` for official Gitea instances (e.g., gitea.io)
- Use `forgejo:` for Forgejo instances (e.g., codeberg.org)
- Both work technically, but the prefix determines which token file is read

**Key differences:**

| Feature | Gitea | Forgejo |
|---------|-------|---------|
| Governance | Company-backed (Gitea Ltd) | Community-driven (Codeberg e.V.) |
| License | MIT | MIT (GPL-3.0+ for additions) |
| Public Instances | try.gitea.io | codeberg.org |
| CLI Tool | None (3rd party only) | None (3rd party only) |
| API Stability | Stable since 1.0 | Inherited from Gitea |

For git-native-issue purposes, they are functionally identical.

## See Also

- [README.md](../README.md) - Project overview and core concepts
- [GitHub Bridge](../README.md#github-bridge) - GitHub import/export documentation
- [GitLab Bridge](gitlab-bridge.md) - GitLab import/export documentation
- [Migration Guide](#migration-guide) - Cross-platform migration workflows
- [ISSUE-FORMAT.md](../ISSUE-FORMAT.md) - git-issue format specification
