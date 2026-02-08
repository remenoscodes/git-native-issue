# Launch Post Materials

## Hacker News (Show HN)

**Title (78 chars):**
```
Show HN: Git-native issue tracking – issues are just refs, like everything else
```

**Post:**
```
I built git-native-issue (https://github.com/remenoscodes/git-native-issue), a distributed issue tracker that stores issues as Git commits under refs/issues/.

The insight: issues are append-only event logs, and Git is a distributed append-only database. The data model fits perfectly:

- Commits = issue events (creation, comments, state changes)
- Refs = issue identity (one ref per issue, named by UUID)
- Trailers = structured metadata (State, Labels, Assignee, Priority)
- Merge commits = distributed conflict resolution
- Fetch/push = synchronization (no custom protocol)

Issues travel with your code:
```
$ git issue create "Fix login crash"
Created issue a7f3b2c

$ git push origin 'refs/issues/*'
$ git fetch origin 'refs/issues/*:refs/issues/*'
```

Linus Torvalds called for this in 2007: "A 'git for bugs', where you can track bugs locally and without a web interface." Nearly two decades later, this problem remains unsolved.

The real deliverable is ISSUE-FORMAT.md – a standalone spec that any tool can implement. If the Git community adopts it, platforms like GitHub and GitLab can support refs/issues/* natively, making issue portability as natural as code portability.

10+ previous attempts failed (Bugs Everywhere, ticgit, git-bug, git-dit). The key difference: this is the first to produce a standalone format specification rather than just code that happens to produce some files.

Installation:
```
brew install remenoscodes/git-native-issue/git-native-issue
# or
curl -sSL https://raw.githubusercontent.com/remenoscodes/git-native-issue/main/install.sh | sh
```

Scales to 10,000+ issues using git for-each-ref (single batch operation, not one subprocess per issue). Full GitHub bridge for import/export with gh CLI.

Would love feedback on the format spec and the approach. Happy to answer questions about the implementation.
```

---

## Reddit (r/programming, r/git)

**Title:**
```
[Show] git-native-issue: Distributed issue tracking using Git's native data model – issues are just commits and refs
```

**Post:**
```markdown
## TL;DR

Built a distributed issue tracker where issues are stored as Git commits under `refs/issues/`. No external database, no JSON files in working tree, no custom merge algorithms. Just commits, trailers, and refs – Git's own primitives.

**GitHub**: https://github.com/remenoscodes/git-native-issue

## The Problem

Your code travels with `git clone`. Your issues don't.

Migrate from GitHub to GitLab? Your code comes with you. Your issues stay behind, trapped in a proprietary API. Linus Torvalds called this out in 2007:

> "A 'git for bugs', where you can track bugs locally and without a web interface."
> -- Linus Torvalds, [LKML 2007](https://yarchive.net/comp/linux/bug_tracking.html)

Nearly two decades later, this problem remains unsolved.

## The Solution: Issues Are Just Git

Here's the insight: **issues are append-only event logs, and Git is a distributed append-only content-addressable database**. The data model fits perfectly.

Each issue is a chain of commits on its own ref:

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

## Why Git's Data Model Fits Perfectly

| Issue Tracking Concept | Git Primitive | Why It Works |
|------------------------|---------------|--------------|
| **Issue identity** | `refs/issues/<uuid>` | Unique, immutable, collision-free |
| **Issue events** | Commits in a chain | Append-only, cryptographically verified |
| **Metadata** | Git trailers | Parseable by `git interpret-trailers` |
| **Comments** | Commit messages | Full-text searchable with `git log --grep` |
| **Distributed sync** | `git fetch/push` | Zero custom protocol needed |
| **Conflict resolution** | Three-way merge | Merge commits resolve divergent updates |

## Quick Start

```bash
# Install
brew install remenoscodes/git-native-issue/git-native-issue
# or
curl -sSL https://raw.githubusercontent.com/remenoscodes/git-native-issue/main/install.sh | sh

# Use
git issue create "Fix login crash" -l bug -l auth -p critical
git issue ls
git issue comment a7f3b2c -m "Reproduced on Firefox"
git issue state a7f3b2c --close

# Sync
git push origin 'refs/issues/*'
git fetch origin 'refs/issues/*:refs/issues/*'
```

## The Format Spec

The real deliverable is [ISSUE-FORMAT.md](https://github.com/remenoscodes/git-native-issue/blob/main/ISSUE-FORMAT.md) – a standalone specification for storing issues in Git. Any implementation that produces conforming refs and commits is valid.

If the Git community adopts this format, platforms like GitHub, GitLab, and Forgejo can support `refs/issues/*` natively, making issue portability as natural as code portability.

## What Makes This Different

10+ previous attempts failed (Bugs Everywhere, ticgit, git-bug, git-dit, git-appraise). Six root causes:

1. **Merge conflicts** – File-based storage breaks `git merge`
2. **Network effects** – Can't overcome GitHub's ecosystem alone
3. **No format spec** – Every tool invented its own format
4. **Excluding non-developers** – Git is for devs, issues are for everyone
5. **Weak offline argument** – Most devs have internet
6. **Resource constraints** – Side projects can't compete with GitHub

**How git-native-issue addresses these:**

- Issues in `refs/`, not working tree → zero merge conflicts
- Standalone format spec → platforms can adopt incrementally
- GitHub bridge → non-devs stay on GitHub, devs work locally
- Pitch is portability, not offline → code outlives hosting platforms

## Performance & Scale

Scales to 10,000+ issues using `git for-each-ref` (single batch operation, not one subprocess per issue). Configure Git protocol v2 for efficient transfer:

```bash
git config protocol.version 2
```

## Features

- ✅ Create, list, search, comment, edit, close issues
- ✅ Labels, assignees, priority, milestones
- ✅ GitHub import/export bridge (requires `gh` CLI + `jq`)
- ✅ Two-way sync with GitHub
- ✅ Distributed merge with conflict resolution
- ✅ Data integrity validation (`git issue fsck`)
- ✅ 153 tests (76 core + 36 bridge + 20 merge + 21 QoL)

## Prior Art Research

Surveyed 10+ tools: git-bug, Fossil, git-appraise, git-dit, SIT, Bugs Everywhere, ticgit, Ditz. Key insight: **NO previous tool produced a standalone format spec**. This is the primary differentiator.

git-dit (2016) independently converged on the same design (commits + trailers in refs), validating the approach.

## Would Love Feedback

- Is the format spec clear and implementable?
- What's missing from the core feature set?
- Would platforms like GitHub/GitLab adopt this if it had community support?

Happy to answer questions about implementation, design decisions, or the format spec.

**License**: GPL-2.0 (same as Git itself)
```

---

## Common Questions to Prepare For

### Q: Why not use git-bug? It already exists.
**A:** git-bug is excellent but lacks a standalone format spec. It uses CRDTs (more complex than needed) and its "format" is just what the code produces. ISSUE-FORMAT.md is designed for ecosystem adoption – any tool can implement it, and platforms can support it natively.

### Q: How do you handle merge conflicts?
**A:** Issues live in `refs/`, not the working tree, so code merges never touch issues. When issue chains diverge, `git issue merge` creates merge commits with resolved metadata: last-writer-wins for scalars (state, assignee), three-way set merge for labels, union for comments.

### Q: Doesn't this pollute the Git repo?
**A:** Issues live in `refs/issues/`, which are separate from `refs/heads/` (code branches). They don't appear in `git log`, `git status`, or affect your working tree. Bare repositories support issues without any working directory.

### Q: What about non-developers who need to file issues?
**A:** The GitHub bridge allows two-way sync. Non-dev stakeholders use GitHub's web UI, devs work locally with `git issue`, and sync keeps them aligned. Start with developers, bridges maintain accessibility.

### Q: How is this different from git notes?
**A:** Git notes store metadata *about* commits. Issues are independent entities with their own identity, history, and lifecycle. git-appraise tried using `refs/notes/` but the model doesn't fit – issues aren't annotations on commits.

### Q: Performance with 10,000+ issues?
**A:** `git for-each-ref` is a single batch operation that reads all refs at once. No subprocess spawning. Configure protocol v2 for efficient fetches. Scales well – Git repos with 100,000+ refs are common.

### Q: Why UUIDs instead of sequential IDs?
**A:** Sequential IDs require coordination. In distributed systems, two people can't both create "issue #42" offline. UUIDs are collision-free by design – the same reason Git uses SHA-1 hashes, not sequential commit numbers.

### Q: Can I search issues offline?
**A:** Yes. `git issue search "pattern"` searches titles, bodies, and comments. It's just `git log --grep` under the hood. Works completely offline.

### Q: What if GitHub never adopts this?
**A:** The bridge allows indefinite interop. Import from GitHub, work locally, export back. Even without platform adoption, developers get portability: fork a repo, issues come with it. Migrate hosting providers, issues travel with code.

---

## Post-Launch Monitoring

**First 2 hours after HN post:**
- Respond to questions quickly (helps ranking)
- Correct misunderstandings politely
- Link to ISSUE-FORMAT.md for spec questions
- Mention related tools (git-bug, Fossil) to show awareness

**Watch for:**
- "Why not just use GitHub?" → Portability angle
- "This has been tried before" → Format spec differentiator
- "Too complex" → Show simple examples
- "What about mobile users?" → Bridge maintains accessibility

**Success signals:**
- Upvotes → Front page visibility
- Comments → Engagement (even critical)
- GitHub stars → Real interest
- Installation attempts → Actual usage

---

## Launch Timeline

**Tuesday 9:00 AM PT** (optimal HN time):
1. Post to Hacker News with "Show HN:" prefix
2. Monitor for first 2 hours
3. Respond to top comments quickly

**Wednesday** (24h after HN):
1. Post to r/programming
2. Post to r/git
3. Submit to Lobsters (if accepted)

**Week 1:**
1. Blog post on Dev.to or Hashnode
2. Twitter/Mastodon announcement
3. Email to relevant mailing lists (git@vger.kernel.org)

---

## HN Title Validation

```
Show HN: Git-native issue tracking – issues are just refs, like everything else
```

Character count: **78** ✓ (under 80 limit)

Includes:
- "Show HN:" prefix (required)
- Project name (git-native-issue → shortened to "Git-native issue tracking")
- Core value prop (issues are just refs)
- Intriguing angle (like everything else)

---

## Ready to Launch ✅

All checks complete:
- ✅ v1.0.2 released and tested
- ✅ All CI tests passing (153 tests)
- ✅ Documentation reviewed and updated
- ✅ Installation methods validated
- ✅ GPG signing configured
- ✅ Launch posts prepared
- ✅ Common questions answered
- ✅ HN title under 80 chars

**Confidence: HIGH** 🚀
