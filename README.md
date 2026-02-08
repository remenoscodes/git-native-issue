# git-native-issue

Distributed issue tracking using Git's native data model.

**Command:** `git issue` (simple to use, despite the project name)

## The Problem

Your source code travels with `git clone`. Your issues don't.

Migrate from GitHub to GitLab? Your code comes with you. Your issues
stay behind, trapped in a proprietary API. Work offline on code? Sure.
Work offline on issues? Not without a web browser and internet
connection. Linus Torvalds called this out in 2007:

> "A 'git for bugs', where you can track bugs locally and without a
> web interface."
>
> -- Linus Torvalds, [LKML 2007](https://yarchive.net/comp/linux/bug_tracking.html)

Nearly two decades later, this problem remains unsolved.

## The Solution: Issues Are Just Git

Here's the insight: **issues are append-only event logs, and Git is a
distributed append-only content-addressable database**. The data model
fits perfectly.

`git-issue` stores issues as Git commits under `refs/issues/`. No
external database. No JSON files in the working tree. No custom merge
algorithms. Just commits, trailers, and refs -- Git's own primitives:

- **Commits** = issue events (creation, comments, state changes)
- **Refs** = issue identity (one ref per issue, named by UUID)
- **Trailers** = structured metadata (State, Labels, Assignee, Priority)
- **Merge commits** = distributed conflict resolution (built into Git)
- **Fetch/push** = synchronization (no custom protocol needed)

Git already solved distributed synchronization, content addressing,
cryptographic integrity, and three-way merging. Why rebuild all that
for issue tracking?

```
$ git issue create "Fix login crash with special characters"
Created issue a7f3b2c

$ git issue ls
a7f3b2c [open]  Fix login crash with special characters
b3e9d1a [open]  Add dark mode support

$ git issue comment a7f3b2c -m "Reproduced on Firefox 120 and Chrome 119"
Added comment to a7f3b2c

$ git issue state a7f3b2c --close --fixed-by abc123
Closed issue a7f3b2c
```

Push issues to any remote. Fetch them back. They travel with the code:

```
$ git push origin 'refs/issues/*'
$ git fetch origin 'refs/issues/*:refs/issues/*'
```

## Why Git's Data Model Fits Perfectly

Most issue trackers bolt a database onto version control. `git-issue`
realizes that **Git already is a distributed database** -- one that's
designed exactly for this problem.

### The Mapping

| Issue Tracking Concept | Git Primitive | Why It Works |
|------------------------|---------------|--------------|
| **Issue identity** | `refs/issues/<uuid>` | Unique, immutable, collision-free in distributed systems |
| **Issue events** | Commits in a chain | Append-only, content-addressed, cryptographically verified |
| **Metadata** | Git trailers | Parseable by standard Git tools (`interpret-trailers`) |
| **Comments** | Commit messages | Full-text searchable with `git log --grep` |
| **State history** | Commit ancestry | `git log refs/issues/<id>` shows the full timeline |
| **Distributed sync** | `git fetch/push` | Zero custom protocol needed |
| **Conflict resolution** | Three-way merge | Merge commits resolve divergent issue updates |
| **Data integrity** | SHA-1/SHA-256 | Tampering detection built into Git |
| **Offline work** | Local refs | Full read/write access without network |
| **Atomic operations** | Ref updates | `git update-ref` is atomic, no race conditions |

### What You Get For Free

By using Git's data model, `git-issue` inherits decades of battle-tested
distributed systems engineering:

- ✅ **Content-addressable storage** -- Issues are deduplicated, cryptographically verified
- ✅ **Three-way merge** -- Divergent updates resolve deterministically
- ✅ **Atomic ref updates** -- No race conditions when multiple processes modify issues
- ✅ **Efficient transfer** -- Git's packfile protocol minimizes bandwidth
- ✅ **Protocol v2 support** -- Server-side filtering for repos with 10,000+ issues
- ✅ **SSH/HTTPS transport** -- Same authentication as code pushes
- ✅ **Clone/fork/mirror** -- Issues travel with code automatically
- ✅ **Garbage collection** -- Unreachable issues are cleaned up by `git gc`

This isn't "using Git as a database". This is **recognizing that issue
tracking is distributed synchronization of append-only logs**, which is
exactly what Git was designed to do.

## Installation

### Homebrew (macOS/Linux)

```bash
brew install remenoscodes/git-native-issue/git-native-issue
```

### Install Script (Any POSIX System)

```bash
curl -sSL https://raw.githubusercontent.com/remenoscodes/git-native-issue/main/install.sh | sh
```

Or download and run:
```bash
curl -LO https://github.com/remenoscodes/git-native-issue/releases/latest/download/git-native-issue-*.tar.gz
tar xzf git-native-issue-*.tar.gz
cd git-native-issue-*
./install.sh          # Installs to /usr/local
./install.sh ~/.local # Installs to ~/.local
```

### Makefile (From Source)

```bash
git clone https://github.com/remenoscodes/git-native-issue.git
cd git-native-issue
make install          # System-wide (/usr/local)
make install prefix=~ # User install (~/bin)
```

### Arch Linux (AUR)

```bash
yay -S git-native-issue      # Coming soon
```

### Verify Installation

```bash
git issue version
# git-issue version 1.0.2
```

## Commands

| Command | Description |
|---------|-------------|
| `git issue create <title>` | Create a new issue |
| `git issue ls` | List issues |
| `git issue show <id>` | Show issue details and comments |
| `git issue comment <id>` | Add a comment |
| `git issue edit <id>` | Edit metadata (labels, assignee, priority, milestone) |
| `git issue state <id>` | Change issue state |
| `git issue import` | Import issues from GitHub |
| `git issue export` | Export issues to GitHub |
| `git issue sync` | Two-way sync (import + export) |
| `git issue search <pattern>` | Search issues by text |
| `git issue merge <remote>` | Merge issues from a remote |
| `git issue fsck` | Validate issue data integrity |
| `git issue init [<remote>]` | Configure repo for issue tracking |

### Creating Issues

```sh
git issue create "Fix login crash" \
  -m "TypeError when clicking submit" \
  -l bug -l auth \
  -a alice@example.com \
  -p critical \
  --milestone v1.0
```

### Editing Issues

```sh
# Replace all labels
git issue edit a7f3b2c -l bug -l urgent

# Add/remove individual labels
git issue edit a7f3b2c --add-label security
git issue edit a7f3b2c --remove-label urgent

# Change assignee and priority
git issue edit a7f3b2c -a bob@example.com -p high

# Change title
git issue edit a7f3b2c -t "Fix login crash on special characters"
```

### Listing Issues

```sh
git issue ls                    # Open issues (default)
git issue ls --all              # All issues
git issue ls --state closed     # Closed issues
git issue ls -l bug             # Filter by label
git issue ls --assignee alice@example.com
git issue ls --priority critical
git issue ls --sort priority    # Sort by priority (desc)
git issue ls --sort updated --reverse  # Oldest updates first
git issue ls --format full      # Show labels, assignee, priority, milestone
git issue ls --format oneline   # Scripting-friendly (no brackets)
```

Sort fields: `created` (default), `updated`, `priority`, `state`.

### Searching

```sh
git issue search "crash"        # Search titles, bodies, and comments
git issue search -i "firefox"   # Case-insensitive
git issue search "bug" --state open  # Only open issues
```

### GitHub Bridge

Import and export issues from/to GitHub. Requires [`gh`](https://cli.github.com/) and `jq`.

```sh
# Import all open issues from a GitHub repo
git issue import github:owner/repo

# Import all issues (open + closed)
git issue import github:owner/repo --state all

# Preview what would be imported
git issue import github:owner/repo --dry-run

# Export local issues to GitHub
git issue export github:owner/repo

# Two-way sync (import then export)
git issue sync github:owner/repo --state all
```

**How it works:**

- `import` fetches GitHub issues via `gh api`, creates local `refs/issues/` commits with full metadata (labels, assignee, milestone, comments, author)
- `export` creates GitHub issues from local issues, exports comments, syncs state
- A `Provider-ID` trailer tracks the mapping (e.g., `Provider-ID: github:owner/repo#42`) to prevent duplicates on re-import/re-export
- Re-importing skips already-imported issues; re-exporting syncs state changes

**Prerequisites:**

```sh
brew install gh jq       # macOS
gh auth login            # authenticate with GitHub
```

### Distributed Merge

When multiple people track the same issues, their ref chains can diverge.
`git issue merge` reconciles them:

```sh
# Fetch and merge issues from a remote
git issue merge origin

# Detect divergences without merging
git issue merge origin --check

# Skip fetch, use existing remote tracking refs
git issue merge origin --no-fetch
```

**Merge strategy:**

- New issues from remote are created locally
- If local is behind, fast-forward
- If diverged, create a merge commit with resolved metadata:
  - **Scalar fields** (state, assignee, priority, milestone): last-writer-wins by timestamp
  - **Labels**: three-way set merge (additions from both sides preserved, removals honored)
  - **Comments**: union (both sides' commits reachable via merge parents)

### Data Integrity

```sh
# Validate all issue refs
git issue fsck

# Quiet mode (only errors)
git issue fsck --quiet
```

Checks: UUID format, empty tree usage, required trailers (`State`, `Format-Version`), single root commit per issue.

## How It Works: The Data Model

Each issue is a chain of commits on its own ref. It's just Git:

```
refs/issues/a7f3b2c1-4e5d-4f8a-b9c3-1234567890ab
    |
    v
  [Close issue]              State: closed
    |                        Fixed-By: abc123
    v
  [Reproduced on Firefox]    (comment)
    |
    v
  [Fix login crash...]       State: open
                             Labels: bug, auth
                             Priority: critical
                             Format-Version: 1
```

**Why this works beautifully:**

1. **Commits are events** -- Each commit is an immutable event (issue
   creation, comment, state change). Git's content-addressable storage
   gives us cryptographic integrity for free.

2. **Refs are identities** -- `refs/issues/<uuid>` points to the latest
   state of an issue. Git's ref machinery handles updates atomically.

3. **Trailers are metadata** -- `State: open`, `Labels: bug, auth` are
   standard Git trailers. They're parseable by `git interpret-trailers`
   and queryable via `git for-each-ref` with zero subprocess spawning:

   ```sh
   git for-each-ref \
     --format='%(refname:short) %(contents:subject) %(trailers:key=State,valueonly)' \
     refs/issues/
   ```

4. **Merge commits resolve conflicts** -- When two people modify the
   same issue offline, Git's three-way merge machinery creates a merge
   commit with resolved metadata. No CRDTs, no operational transforms,
   just merge commits.

5. **Fetch/push is synchronization** -- `git fetch origin 'refs/issues/*'`
   pulls issues. `git push origin 'refs/issues/*'` shares them. The
   same protocol that syncs code syncs issues.

**Performance:** This scales to 10,000+ issues because `git for-each-ref`
is a single batch operation -- not one subprocess per issue like most
Git porcelain commands.

### Visual: The Complete Picture

Here's how everything fits together in Git's object model:

```
Repository:
  .git/
    refs/
      heads/main          → [code commits]
      issues/
        a7f3b2c1-...      → commit(close)    State: closed
                              ↓                Fixed-By: abc123
                           commit(comment)   "Reproduced on Firefox"
                              ↓
                           commit(create)    State: open
                              ↓                Labels: bug, auth
                           tree(empty)       (root of issue chain)

What Git provides:
  • Atomic ref updates    → No race conditions on concurrent edits
  • Three-way merge       → Automatic conflict resolution on divergence
  • Content addressing    → Deduplication + cryptographic integrity
  • Transfer protocol     → Efficient sync over SSH/HTTPS
  • Garbage collection    → Unreachable issues cleaned automatically
```

It's not "abusing Git" -- it's **using Git exactly as designed**: a
distributed append-only content-addressable database with built-in
merge resolution.

## The Format Spec

The real deliverable is [ISSUE-FORMAT.md](ISSUE-FORMAT.md) -- a
standalone specification for storing issues in Git, independent of
this tool. Any implementation that produces conforming refs and commits
is a valid implementation.

If the Git community blesses this format, platforms like GitHub, GitLab,
and Forgejo can adopt native support for `refs/issues/*`, making issue
portability as natural as code portability.

## Design Decisions: Following Git's Philosophy

Every design choice aligns with Git's philosophy: **simple primitives,
composed well**.

### UUIDs (not sequential IDs)
Sequential IDs (issue #1, #2, #3) require coordination. In distributed
systems, two people can't both create "issue #42" offline. UUIDs are
collision-free by design -- the same reason Git uses SHA-1 hashes
instead of sequential commit numbers.

### Git trailers (not JSON, not YAML)
JSON in commit messages breaks `git log` readability. YAML is complex
to parse. Git trailers are a 20-year-old standard (`git interpret-trailers`)
that's human-readable, machine-parseable, and compatible with existing
Git tooling.

### Subject-line-as-title
The issue title is the commit subject line. This means `git log refs/issues/*`
naturally shows issue titles, and `%(contents:subject)` in `git for-each-ref`
extracts it with zero parsing. Git's existing formatting machinery works
out of the box.

### Three-way set merge for labels
Labels are a set. When two people modify labels offline, the merge should
preserve additions from both sides and honor explicit removals. Git's
three-way merge (base, ours, theirs) handles this perfectly -- no CRDTs,
no vector clocks, just merge-base computation.

### Last-writer-wins for state
State (open/closed), assignee, and priority are scalar values. When two
people change them offline, there's no "correct" merge -- just pick the
most recent by timestamp. Simple, deterministic, and matches user
expectations.

### Import/export bridges (not live sync)
GitHub and GitLab won't adopt `refs/issues/*` overnight. Bridges allow
migration and interop without solving real-time two-way sync (which
requires webhooks, conflict resolution UI, and operational complexity).
Start with batch import/export. Live sync is a v2 problem.

### Zero dependencies on working tree
Issues live in `refs/`, not the working tree. This means:
- No `.issues/` directory cluttering `git status`
- No merge conflicts in issue files during code merges
- No "commit your issues" workflow confusion
- Issues work in bare repositories (on servers)

## What Makes This Different: The Ancient Problem

Distributed issue tracking has been attempted for nearly 20 years. Every
previous attempt failed to gain traction. Why?

**Six fundamental problems:**

1. **Merge conflicts** -- Storing issues as files in the working tree
   (Bugs Everywhere, Ditz) creates merge conflicts that break `git merge`.
   Users must resolve issue file conflicts manually, which is unacceptable.

2. **Network effects** -- Platforms like GitHub provide issue tracking as
   part of a hosting service. Switching to distributed issues means losing
   web UI, notifications, and integrations. No single project can overcome
   this chicken-and-egg problem.

3. **No format spec** -- Every tool invented its own format. No interop,
   no ecosystem, no way for Git platforms to adopt it. Just code that
   happened to produce some files or refs.

4. **Excluding non-developers** -- Git is for developers. Issue tracking
   is for everyone. File-based storage excludes users who can't read commit
   logs or run shell commands.

5. **Weak offline argument** -- Most developers have internet. The "work
   offline" pitch isn't compelling enough to overcome the switching cost.

6. **Resource constraints** -- These were side projects, not funded products.
   They couldn't compete with GitHub's issue tracker on polish and features.

**How `git-issue` addresses these:**

| Problem | Solution |
|---------|----------|
| **Merge conflicts** | Issues live in `refs/`, not working tree. Code merges never touch issues. |
| **Network effects** | Ship a standalone **format spec** (`ISSUE-FORMAT.md`). Platforms can adopt it incrementally. |
| **No format spec** | The spec is the deliverable. Implementations are interchangeable. |
| **Excluding non-developers** | Start with developers. Import/export bridges keep issues in GitHub for non-dev stakeholders. |
| **Weak offline argument** | The real pitch: **issue portability**. Code outlives hosting platforms. Issues should too. |
| **Resource constraints** | Keep scope minimal. Format spec + one reference implementation. Ecosystem adoption is the goal, not feature parity with Jira. |

## Prior Art

This project builds on lessons from 10+ previous attempts:

| Tool | Year | Status | Key Lesson |
|------|------|--------|-----------|
| Fossil | 2006 | Active | Proves CRDT-based append-only model works |
| Bugs Everywhere | 2005 | Dead | File-based storage creates merge conflicts |
| ticgit | 2008 | Dead | Creator (Scott Chacon) built GitHub instead |
| git-appraise | 2015 | Dead | `refs/notes/` model is elegant but needs ecosystem support |
| git-issue (Spinellis) | 2016 | Active | Simple shell-based approach works; ~500 lines, pragmatic |
| git-dit | 2016 | Dead | Commits + trailers works (validated our approach) |
| git-bug | 2018 | Active | CRDTs are overkill; missing format spec |

**What's different this time**: The format spec. No previous tool
produced a standalone, implementable specification. Every tool's
"format" was just whatever their code produced. `ISSUE-FORMAT.md` is
the deliverable that makes ecosystem adoption possible.

## Running Tests

```sh
make test
```

153 tests: 76 core + 36 bridge + 20 merge/fsck + 21 QoL.

## Performance Notes

Each issue is one ref. For repositories with many issues (1000+),
configure Git protocol v2 to avoid advertising all refs on every
fetch:

```sh
git config protocol.version 2
```

Protocol v2 uses server-side filtering, so only requested refs are
transferred. Without it, every `git fetch` advertises all refs
including `refs/issues/*`.

## License

GPL-2.0 -- same as Git itself.
