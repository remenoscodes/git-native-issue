# Git Issue Format Specification

**Version**: 1
**Status**: Draft
**Author**: Emerson Soares <remenoscodes@gmail.com>
**Date**: 2025-04-23
**Minimum Git Version**: 2.17 (April 2018) — required for
`%(trailers:key=...,valueonly)` format support.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in
[RFC 2119](https://tools.ietf.org/html/rfc2119).

---

## Abstract

This document specifies a format for storing issue tracking data natively
in Git repositories using only Git's existing object model: commits,
refs, and trailers. The format requires no external database, no custom
binary format, and no tools beyond Git's standard plumbing commands.

Issues are stored as chains of commits under the `refs/issues/` namespace.
Each commit's subject line, body, and trailers carry structured issue data.
The format is designed for distributed operation with deterministic
conflict resolution, enabling issues to travel with the repository across
hosting providers via standard `git push` and `git fetch`.

---

## 1. Design Principles

1. **Git-native**: Use only Git's existing primitives (commits, refs,
   trailers, trees). No custom binary formats, no JSON, no external
   databases.

2. **Distributed-first**: Any operation that works locally must also work
   correctly when repositories are merged from multiple clones with no
   central coordinator.

3. **Tooling-friendly**: Issue metadata must be queryable using standard
   Git plumbing commands (`git for-each-ref`, `git log`,
   `git interpret-trailers`) without spawning additional processes.

4. **Simple over clever**: Prefer straightforward data models over
   mathematically optimal but complex ones. Three-way set merge over
   CRDTs. Last-writer-wins over Lamport clocks.

5. **Format over tool**: This specification defines a data format, not a
   tool. Any implementation that produces conforming refs and commits is
   a valid implementation.

---

## 2. Non-Goals

The following features are explicitly OUT OF SCOPE for this format:

1. **Access Control**: The format does not define authorization models. Any
   user with write access to the repository can create, modify, or close
   issues. Access control must be enforced at the Git repository level
   (filesystem permissions, server-side hooks, hosting platform controls).

2. **Real-Time Synchronization**: Issues are synchronized via standard Git
   push/fetch operations. There is no real-time event stream, no webhook
   protocol, and no live collaborative editing. Changes propagate when
   refs are explicitly pushed or fetched.

3. **Non-Developer Participation**: This format requires Git proficiency.
   Creating or modifying issues requires command-line Git access and
   understanding of refs, commits, and SHA identifiers. There is no
   provision for web-only users or issue creation via email.

4. **Rich Media in v1**: Binary attachments (images, videos, PDFs) are
   not supported in Format-Version 1. All issue data must be text-based
   commit messages and trailers. Binary attachments are deferred to a
   future format version (see Section 12).

5. **Hosting Platform Integration**: The format does not mandate how
   hosting platforms (GitHub, GitLab, Forgejo) should display or interact
   with `refs/issues/*`. Platform support is optional and implementation-
   defined. The format can be used without any platform support.

6. **Guaranteed Conflict-Free Resolution**: While the merge rules
   (Section 6) provide deterministic conflict resolution, they use
   heuristics (LWW, three-way set merge) that may not match user intent
   in all cases. The format does not use CRDTs or Lamport clocks for
   mathematically proven conflict-free behavior.

---

## 3. Ref Namespace

Issues are stored under the `refs/issues/` namespace:

```
refs/issues/<uuid>
```

Where `<uuid>` is a full UUID version 4 (RFC 4122), lowercase,
hyphenated. Example:

```
refs/issues/a7f3b2c1-4e5d-4a8b-9c1e-2f3a4b5c6d7e
```

### 2.1 Display Identifiers

For human interaction, implementations SHOULD support abbreviated
identifiers using the first 7 characters of the UUID (before the first
hyphen). Implementations MUST expand abbreviated identifiers
unambiguously, prompting the user if multiple issues match a prefix.

Example: `a7f3b2c` refers to the issue above.

### 2.2 No Counter File

There is no `next-id` file, no sequential counter, and no coordination
mechanism. UUIDs are generated independently on each clone. This is the
only identity scheme that guarantees zero collisions in a distributed
system without coordination.

---

## 3. Issue Structure

Each issue is a chain of one or more commits pointed to by its ref.
The ref always points to the latest commit in the chain (the issue HEAD).

```
refs/issues/<uuid>
    |
    v
  [commit N]  <-- issue HEAD (latest state)
    |
  [commit N-1]
    |
   ...
    |
  [commit 1]  <-- root commit (issue creation)
```

### 3.1 Tree Object

All issue commits use the **empty tree**. For SHA-1 repositories, this
is `4b825dc642cb6eb9a060e54bf899d15006578022`. The empty tree hash
depends on the repository's hash algorithm; implementations SHOULD
compute it via `git hash-object -t tree /dev/null`.
Issues carry no file content; all data is in the commit message.

Implementations MUST use the empty tree. This ensures:
- No disk space wasted on tree objects
- Clear semantic distinction from code commits
- Compatibility with bare repositories

### 3.2 Commit Authorship

The commit author and committer fields carry the identity of the person
who created the issue or comment. Implementations SHOULD use the same
author identity as configured for regular code commits (`user.name` and
`user.email`).

---

## 4. Commit Message Format

Issue commits follow Git's standard commit message convention with
trailers:

```
<subject line>
                          <-- blank line
<body>
                          <-- blank line
<trailer-key>: <trailer-value>
<trailer-key>: <trailer-value>
...
```

### 4.1 Root Commit (Issue Creation)

The root commit (first commit in the chain, with no parent) defines the
issue:

```
<title>

<description>

State: open
Labels: <comma-separated labels>
Assignee: <email>
Format-Version: 1
```

**Required fields**:
- Subject line: The issue title (max 72 characters recommended)
- `State:` trailer: MUST be `open`
- `Format-Version:` trailer: MUST be `1`

**Optional fields**:
- Body: Detailed description of the issue
- `Labels:` trailer: Comma-separated list of labels (see Section 4.7)
- `Assignee:` trailer: Email address of the assignee
- `Priority:` trailer: `low`, `medium`, `high`, or `critical`
- `Milestone:` trailer: Milestone name

**Example**:
```
Fix login crash with special characters

The login page crashes when the user enters special characters
in the password field. Steps to reproduce:
1. Go to login page
2. Enter "pa$$w0rd" as password
3. Click submit

State: open
Labels: bug, auth
Priority: high
Format-Version: 1
```

### 4.2 Comment Commit

A comment commit has the previous issue HEAD as its parent:

```
<comment summary>

<comment body>
```

Comment commits carry no trailers unless they also change issue state
(see Section 4.4). The subject line is a short summary; the body
contains the full comment text.

**Example**:
```
I can reproduce this on Firefox too

Tested on Firefox 120 and Chrome 119. Both crash with the same
error. The issue is in the password sanitizer function at
src/auth/sanitize.js:42.
```

### 4.3 State Change Commit

A state change commit modifies issue metadata:

```
<description of change>

State: closed
Fixed-By: <commit-sha>
```

**Recognized state values**: `open`, `closed`

Implementations MAY support additional states but MUST recognize
`open` and `closed`.

**Optional trailers for state changes**:
- `Fixed-By:` -- SHA of the commit that fixes the issue
- `Release:` -- Version in which the fix ships
- `Reason:` -- Reason for closing (e.g., `duplicate`, `wontfix`,
  `invalid`, `completed`)

**Example**:
```
Close issue -- fix deployed

The fix in commit abc123 handles special characters properly.
Verified in staging environment.

State: closed
Fixed-By: abc123def456789
Release: v2.1.0
Reason: completed
```

### 4.4 Combined Comment and State Change

A single commit MAY contain both a comment and a state change. This
is achieved by including trailers in a comment commit:

```
Fix deployed, closing

The fix in commit abc123 handles special characters properly.

State: closed
Fixed-By: abc123def456789
```

### 4.5 Custom Trailers

Implementations MAY use custom trailers prefixed with `X-`:

```
X-Severity: critical
X-Component: auth
X-Upstream-Bug: https://bugs.example.com/123
```

Custom trailers MUST NOT conflict with standard trailer names defined
in this specification.

### 4.7 Label Format

Labels in the `Labels:` trailer are comma-separated, with optional
whitespace after each comma. The canonical format is:

```
Labels: label1, label2, label3
```

**Rules**:
- Labels are **case-sensitive**: `Bug` and `bug` are distinct labels
- Labels MUST NOT contain commas (the separator character)
- Labels MUST NOT contain newlines
- Labels MUST NOT be empty strings
- Leading and trailing whitespace around each label is trimmed
- The canonical serialization uses comma-space (`, `) as separator
- `Labels: bug, auth` and `Labels: bug,auth` are equivalent

When comparing labels for merge operations (Section 6.3), implementations
MUST trim whitespace and compare the resulting strings exactly
(case-sensitive). Implementations SHOULD normalize labels to lowercase
before comparison to avoid case-variant duplicates (e.g., `bug` and `Bug`
being treated as distinct labels). This normalization is RECOMMENDED but
not REQUIRED, to preserve intentional casing (e.g., `iOS`, `API`, `UI`).

### 4.8 Formal Grammar (ABNF)

The commit message format can be expressed in Augmented Backus-Naur
Form (ABNF, RFC 5234):

```abnf
issue-commit     = root-commit / comment-commit / state-commit / merge-commit

root-commit      = title LF LF description LF LF
                   "State: " state-value LF
                   [optional-trailers]
                   "Format-Version: 1" LF

comment-commit   = comment-subject LF LF comment-body
                   [LF LF state-trailers]

state-commit     = change-subject LF LF change-body LF LF
                   "State: " state-value LF
                   [state-trailers]

merge-commit     = "Merge issue from " remote-name LF
                   [LF body]
                   LF LF
                   "State: " state-value LF
                   [merge-trailers]

title            = 1*TEXT-NO-LF  ; SHOULD be 72 characters or fewer
comment-subject  = TEXT-NO-LF
change-subject   = TEXT-NO-LF
comment-body     = *( TEXT-NO-LF LF )
description      = *( TEXT-NO-LF LF )
change-body      = *( TEXT-NO-LF LF )
body             = *( TEXT-NO-LF LF )

state-value      = "open" / "closed"
remote-name      = TEXT-NO-LF

optional-trailers = *( trailer )
state-trailers    = *( trailer )
merge-trailers    = *( trailer )

trailer          = trailer-key ": " trailer-value LF
trailer-key      = "Labels" / "Assignee" / "Priority" / "Milestone" /
                   "Fixed-By" / "Release" / "Reason" / "Provider-ID" /
                   "Provider-Comment-ID" / "Parent-ID" / "Title" /
                   custom-trailer-key
custom-trailer-key = "X-" TEXT-NO-LF
trailer-value    = TEXT-NO-LF  ; must not contain actual LF

TEXT-NO-LF       = *( %x20-7E / UTF8-2 / UTF8-3 / UTF8-4 )
                   ; Any UTF-8 text except LF (0x0A)

UTF8-2           = %xC2-DF UTF8-tail
UTF8-3           = %xE0-EF 2UTF8-tail
UTF8-4           = %xF0-F7 3UTF8-tail
UTF8-tail        = %x80-BF

LF               = %x0A  ; Git commit messages use LF, not CRLF
```

**Notes**:
- Git commit messages use LF (`\n`, 0x0A), not CRLF (`\r\n`). The
  grammar uses `LF` to reflect this accurately per RFC 5234.
- `title` uses `1*TEXT-NO-LF` (one or more characters) — empty titles
  are invalid.
- The `TEXT-NO-LF` production allows any UTF-8 text except newline.
- Trailer values must not contain embedded newlines (security requirement
  from Section 4.9 and Section 11.1).
- The `Format-Version:` trailer only appears in root commits.

### 4.9 Trailer Value Encoding

Trailer values MUST NOT contain newline characters (LF or CRLF).

Git's trailer format permits multi-line values via RFC 822-style
folding (continuation lines starting with whitespace). This
specification adopts a stricter single-line subset for two reasons:
it prevents trailer-injection attacks (where embedded newlines could
fake additional trailers), and it keeps the parser trivial enough to
implement with line-based shell tools (grep, awk, sed).

**Encoding Rules**:

1. **Single-line fields** (State, Assignee, Priority, Milestone):
   - MUST NOT contain newlines
   - Implementations MUST reject values containing `\n` or `\r`

2. **Multi-line content** (comments, long descriptions):
   - MUST use separate commits instead of trailers
   - Comments are commits (Section 4.2), not trailers

3. **Multi-value fields** (Labels):
   - Use comma-separated values in a single trailer line
   - MUST NOT use multiple `Labels:` trailers

**Validation Example** (POSIX shell):
```sh
case "$value" in
    *$'\n'*|*$'\r'*)
        echo "error: trailer values cannot contain newlines" >&2
        exit 1
        ;;
esac
```

Implementations that encounter trailers with embedded newlines SHOULD
reject the commit as malformed and warn the user. They MUST NOT
silently accept such values, as this enables injection attacks.

### 4.10 Cross-References

To link a code commit to an issue, use the `Fixes-Issue:` trailer in
the code commit message:

```
Fix password sanitizer for special chars

The sanitizer was not escaping $ and other regex metacharacters.

Fixes-Issue: a7f3b2c
```

This is a trailer in a regular code commit (on a code branch), not in
an issue commit. Implementations SHOULD recognize these trailers and
display cross-references when showing issues. The `Fixed-By:` trailer
in issue commits (Section 4.3) complements this by recording the code
commit SHA from the issue side.

---

## 5. State Computation

The current state of an issue is determined by walking the commit chain
from HEAD backward and taking the value of the `State:` trailer from
the **most recent commit that contains one**.

```sh
git log --format='%(trailers:key=State,valueonly)' refs/issues/<uuid> \
  | grep -m1 .
```

If no commit in the chain contains a `State:` trailer, the issue is
malformed. Implementations SHOULD treat such issues as `open` and
SHOULD warn the user.

### 5.1 Field Computation

Other fields follow similar rules:

| Field | Computation | Source |
|-------|------------|--------|
| Title | Subject line of root commit, or most recent `Title:` trailer | Root or any commit |
| Description | Body of root commit | Root commit only |
| State | Most recent `State:` trailer | Any commit |
| Labels | See Section 6 (merge rules) | Most recent `Labels:` trailer |
| Assignee | Most recent `Assignee:` trailer | Any commit |
| Priority | Most recent `Priority:` trailer | Any commit |
| Milestone | Most recent `Milestone:` trailer | Any commit |
| Comments | All non-root commits | Ordered by commit date |

### 5.2 Efficient Listing

For issues with no comments, a single `for-each-ref` command can list
issues:

```sh
git for-each-ref \
  --format='%(refname:short) %(contents:subject) %(trailers:key=State,valueonly)' \
  refs/issues/
```

**Note**: `%(contents:subject)` returns the tip commit's subject line.
For issues with comments, this is the latest comment's subject, NOT
the issue title. To reliably obtain the issue title, implementations
MUST either:
1. Walk to the root commit and read its subject line, or
2. Use the most recent `Title:` trailer if present (see Section 6.5),
   falling back to the root commit's subject line.

For state-only listing (without titles), the `for-each-ref` approach
above is efficient and correct, since `State:` trailers propagate to
the tip.

---

## 6. Merge Rules

When two clones of a repository independently modify issues and then
synchronize (via `git fetch` + ref update), conflicts may arise.
The following rules define deterministic resolution:

### 6.1 Comments (Append-Only)

Comments are individual commits. Both sides' commits are included in the
merged chain, ordered by author timestamp. Conflicts are impossible
because each comment is a distinct commit object.

When merging divergent issue branches, create a merge commit combining
both chains. All comments from both sides are preserved.

### 6.2 State (Last-Writer-Wins)

If both sides changed the state, the commit with the later author
timestamp wins. If timestamps are equal, the commit with the
lexicographically greater SHA wins.

### 6.3 Labels (Three-Way Set Merge)

Labels use three-way set merge relative to the merge base:

1. Compute the label set at the merge base (ancestor)
2. Compute additions and removals for each side:
   - `added_A = labels_A - ancestor`
   - `removed_A = ancestor - labels_A`
   - (same for side B)
3. Result = `ancestor + added_A + added_B - removed_A - removed_B`
4. Tie-breaking: if one side added a label and the other removed it,
   the addition wins (bias toward keeping data)

#### 6.3.1 Label Merge Limitations

The three-way set merge strategy uses **case-sensitive string
comparison** and does NOT perform semantic analysis. This creates
known limitations:

**1. Case Variants**:
- `bug` and `Bug` are distinct labels
- Concurrent addition of both creates duplicates: `bug, Bug`
- Resolution: Implementations SHOULD apply lowercase normalization per
  Section 4.7. Projects SHOULD establish consistent casing conventions.

**2. Semantic Duplicates**:
- `enhancement` and `feature` are distinct labels
- `ui` and `user-interface` are distinct labels
- Merge does not detect that these represent the same concept
- Resolution: Projects SHOULD establish label naming conventions

**3. Alias Collisions**:
- If one branch renames `bug` → `defect` (remove `bug`, add `defect`)
- And another branch adds a comment with label `bug`
- Result: both `bug` and `defect` labels present
- Resolution: Manual conflict resolution required

**4. No Conflict Detection**:
- The merge always produces a result (never fails)
- Semantically conflicting labels may coexist
- Implementations SHOULD provide a `git issue lint` command to detect
  potential label conflicts

**Recommendations for Projects**:
- Document label naming conventions (CONTRIBUTING.md)
- Use lowercase labels consistently (`bug`, not `Bug`)
- Avoid overlapping labels (`feature` XOR `enhancement`, not both)
- Run `git issue lint` periodically to detect duplicates

Projects with strict label requirements SHOULD use access control
(repository hooks) to enforce label naming, not rely on merge
heuristics.

### 6.4 Scalar Fields (Last-Writer-Wins)

For `Assignee:`, `Priority:`, `Milestone:`, and other scalar fields:
the commit with the later author timestamp wins. Equal timestamps are
broken by lexicographically greater SHA.

### 6.5 Title and Description

The root commit's subject line is the canonical title. The root
commit's body is the canonical description. Implementations MAY
override the display title using a `Title:` trailer in a subsequent
commit. The most recent `Title:` trailer takes precedence (LWW).
Descriptions are not overridable.

### 6.7 Merge Commit Format

When creating a merge commit to resolve a divergent issue, the commit
MUST have two parents (local HEAD and remote HEAD) and use the empty
tree. The commit message format:

```
Merge issue from <remote>

State: <resolved-state>
Labels: <resolved-labels>
Assignee: <resolved-assignee>
```

The subject line SHOULD be `Merge issue from <remote>`. The merge
commit MUST include trailers for all resolved fields that have
non-empty values. The merge commit MUST NOT include a
`Format-Version:` trailer (only the root commit carries this).

### 6.8 Conflict Representation (Deferred to Future Version)

**Status**: This section describes a PROPOSED mechanism for unresolvable
conflicts. It is NOT implemented in v1.0.0 and is deferred to a future
format version.

In practice, the field-specific merge rules (Sections 6.1-6.4) resolve
all conflicts automatically using heuristics (LWW, union, three-way set
merge). After 8+ months of production use with multi-contributor
testing, zero unresolvable conflicts have been encountered.

**Future Mechanism** (Format-Version 2+):

If a merge produces a conflict that cannot be resolved automatically
(e.g., both sides changed the title to different values):

1. Create a merge commit with a `Conflict:` trailer listing the
   conflicting fields
2. The issue gets a `conflict` pseudo-label until resolved
3. Implementations SHOULD provide a mechanism for manual conflict
   resolution that allows the user to select a value for each
   conflicting field

**v1.0.0 Behavior**: All conflicts are resolved automatically. If the
heuristics produce an undesirable result, users can manually create a
follow-up commit to correct the merged state

### 6.9 N-way Merge (3+ Parents)

Git supports "octopus" merges with N parents (N ≥ 3). The merge rules
in Sections 6.1-6.4 define **two-way merge** only (local HEAD + remote
HEAD). For N-way merges, implementations MUST reduce the operation to
pairwise merges:

**Reduction Algorithm**:

1. Compute the merge base of all N parents:
   ```sh
   base=$(git merge-base --octopus parent1 parent2 ... parentN)
   ```

2. Perform pairwise merge between base and first parent:
   ```
   result1 = merge(base, parent1)
   ```

3. Iteratively merge each subsequent parent:
   ```
   result2 = merge(result1, parent2)
   result3 = merge(result2, parent3)
   ...
   resultN-1 = merge(resultN-2, parentN)
   ```

4. The final result becomes the merge commit's metadata

**Order Dependency**:

The pairwise reduction is **not commutative**. Results MAY differ based
on parent ordering when conflicts exist. For example:

- `merge(merge(base, A), B)` may differ from `merge(merge(base, B), A)`
- This occurs when A and B both modify the same field differently

Implementations SHOULD process parents in **chronological order**
(sorted by commit timestamp) to produce consistent results across
different clones. If timestamps are equal, sort parents lexicographically
by SHA.

**Example** (3-way merge):

```
Alice changes State: open → closed (timestamp: 1000)
Bob changes State: open → wontfix (timestamp: 1001)
Carol changes Labels: bug → bug, critical (timestamp: 1002)

Chronological order: Alice, Bob, Carol
Result:
  State: wontfix (Bob's LWW wins over Alice)
  Labels: bug, critical (Carol's change applied)
```

**Practical Occurrence**:

N-way merges are rare in practice for issue tracking (they require 3+
clones to independently modify the same issue before synchronizing).
Most merges are 2-way. Implementations MAY warn users when performing
N-way merges and suggest reviewing the result.

---

## 7. Transport

Issues travel via standard Git transport. No custom protocol is needed.

### 7.1 Fetching Issues

```sh
git fetch origin 'refs/issues/*:refs/issues/*'
```

### 7.2 Pushing Issues

```sh
git push origin 'refs/issues/*'
```

### 7.3 Cloning with Issues

By default, `git clone` does NOT fetch `refs/issues/*`. To include
issues in a clone, configure the fetch refspec:

```sh
git config --add remote.origin.fetch '+refs/issues/*:refs/issues/*'
git fetch origin
```

Implementations SHOULD configure this refspec automatically when
initialized in a repository.

### 7.4 Merging Issues from a Remote

When issues are fetched from a remote, the local and remote refs may
diverge (both sides made changes since the last sync). Implementations
SHOULD resolve divergent refs automatically using the merge rules in
Section 6.

The merge workflow:

1. Fetch remote issue refs into a staging namespace:
   ```sh
   git fetch <remote> '+refs/issues/*:refs/remotes/<remote>/issues/*'
   ```

2. For each remote ref, compare with the corresponding local ref:
   - **New issue** (no local ref): create local ref pointing to remote HEAD
   - **Fast-forward** (local is ancestor of remote): update local ref
   - **Up-to-date** (remote is ancestor of local): no action
   - **Diverged**: create a merge commit with two parents (local HEAD
     and remote HEAD), resolving metadata per Section 6

3. Clean up remote tracking refs after merge.

Merge commits use the empty tree (same as all issue commits) and carry
the resolved metadata as trailers.

### 7.5 Shallow and Partial Clones

Issues are compatible with shallow clones. A shallow fetch of
`refs/issues/*` with `--depth=1` provides the current state of all
issues without full history. This is useful for large repositories
where full issue history is not needed locally.

### 7.6 Performance Considerations

Each issue creates one Git ref. For repositories with many issues
(1000+), the ref advertisement during `git fetch` can become a
bottleneck on Git protocol v1, which advertises ALL refs.

Implementations SHOULD recommend Git protocol v2, which uses
server-side ref filtering:

```sh
git config protocol.version 2
```

With protocol v2, only requested refs are transferred, keeping fetch
performance constant regardless of issue count.

---

## 8. Bridge Protocol

External issue trackers (GitHub, GitLab, Jira) can be bridged via
import/export operations. The current implementation uses direct
provider integrations; a plugin protocol is planned for when multiple
provider backends exist.

### 8.1 Import

Import creates local `refs/issues/` commits from an external provider:

1. Fetch issue list from the provider (paginated)
2. For each issue not already imported (checked via `Provider-ID:` trailer):
   - Generate a UUID and create a root commit with full metadata
   - Set `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_AUTHOR_DATE` from
     the original author
   - Import comments as child commits preserving original authorship
   - If the issue is closed, append a `State: closed` commit
   - Record the source via `Provider-ID:` trailer (see Section 9)
3. Skip issues whose `Provider-ID:` already exists locally (idempotent)

Implementations MUST filter out non-issue items (e.g., GitHub pull
requests are not issues).

### 8.2 Export

Export creates provider issues from local `refs/issues/` data:

1. For each local issue ref:
   - If `Provider-ID:` matches the target provider: sync state changes
   - If `Provider-ID:` matches a different provider: skip (foreign import)
   - If no `Provider-ID:`: create a new issue on the provider, export
     comments, sync state, and record the `Provider-ID:` locally by
     appending a child commit
2. Comment export: commits without trailers are treated as comments;
   commits with trailers are metadata changes (skipped)

#### Cross-Platform Export

When the `--cross-platform` flag is passed, export implementations
MUST NOT skip issues with foreign `Provider-ID:` values. Instead,
they fall through to the new-issue creation path. After the first
cross-platform export, the issue gains a target `Provider-ID:` (e.g.,
`github:owner/repo#42`), and subsequent exports enter normal sync mode.

This enables importing from one provider (e.g., Azure DevOps) and
exporting to another (e.g., GitHub):

```
git issue import azuredevops:org/project --state all
git issue export github:owner/repo --cross-platform
```

### 8.3 Round-Trip Safety

The `Provider-ID:` trailer ensures:
- Import then export does not create duplicates
- Re-import skips already-imported issues
- Re-export syncs state without duplicating

### 8.4 Future: Plugin Protocol

When a second provider backend is needed, implementations MAY adopt a
plugin protocol where `git-issue-remote-<provider>` is a separate
executable speaking a line-oriented text protocol on stdin/stdout.
The protocol SHOULD support `capabilities`, `list`, `fetch`, and `push`
commands. The protocol MUST use line-oriented text (NOT JSON) to
eliminate JSON injection vulnerabilities.

---

## 9. Provider Mapping

When issues are imported from external providers, the source is
recorded via a `Provider-ID:` trailer:

```
Provider-ID: github:owner/repo#42
```

Format: `<provider>:<identifier>`

### 9.1 Supported Providers

| Provider     | Format                                  | Example                                  |
|--------------|-----------------------------------------|------------------------------------------|
| GitHub       | `github:<owner>/<repo>#<number>`        | `github:myorg/myrepo#42`                 |
| GitLab       | `gitlab:<group>/<project>#<number>`     | `gitlab:team/app#17`                     |
| Gitea        | `gitea:<owner>/<repo>#<number>`         | `gitea:dev/api#5`                        |
| Forgejo      | `forgejo:<owner>/<repo>#<number>`       | `forgejo:forge/core#12`                  |
| Azure DevOps | `azuredevops:<org>/<project>#<id>`      | `azuredevops:contoso/MyProject#1234`     |

Comments use `Provider-Comment-ID:` with a `#comment-<id>` suffix:

```
Provider-Comment-ID: github:owner/repo#comment-123456
Provider-Comment-ID: azuredevops:org/project#comment-789
```

### 9.2 Parent-ID Trailer

For providers with hierarchical work items (e.g., Azure DevOps Epics,
Features, User Stories, Tasks), the `Parent-ID:` trailer records the
parent relationship:

```
Parent-ID: azuredevops:org/project#42
```

This preserves the hierarchy from the source provider. Implementations
MAY use this trailer to reconstruct parent-child relationships.

### 9.3 Identity

Provider-ID enables:
- Round-trip import/export without duplication
- Cross-reference between local and remote issue IDs
- Detecting already-imported issues during subsequent imports
- Cross-platform export (see Section 8.2)

---

## 10. Compatibility Notes

### 10.1 Relationship to git-notes

This format does NOT use `git notes`. While `git notes` can attach
metadata to objects, notes are mutable (violating append-only semantics)
and do not support the commit-chain model needed for issue history.

### 10.2 Relationship to git-bug

This format is intentionally simpler than git-bug's operation-based
CRDT model. git-bug stores JSON blobs in git objects with Lamport
clocks. This format stores human-readable commit messages with standard
Git trailers. The two formats are not interoperable, but a bridge
between them is straightforward.

### 10.3 Relationship to Fossil

Fossil's ticket system uses immutable artifacts in a G-Set CRDT,
materialized into SQLite tables. This format achieves similar
properties (append-only commits, deterministic state computation)
using Git's native object model instead of SQLite.

### 10.4 Reftable Compatibility

This format uses proper Git refs (`refs/issues/*`) and is fully
compatible with the reftable backend. No plain files outside the
ref system are used.

---

## 11. Security Considerations

### 11.1 Trailer Injection

Implementations MUST validate that user-supplied values for trailer
fields do not contain newline characters. A newline in a trailer value
would inject arbitrary trailers.

### 11.2 Title Injection

Implementations MUST validate that issue titles do not contain newline
characters, as this would corrupt the commit message format.

### 11.3 Command Injection

Implementations MUST NOT pass user-supplied values through shell
expansion. Use `printf '%s'` instead of `echo` for user content.
Use `--` end-of-options markers in all git commands that accept
user-supplied arguments.

---

## 12. Future Extensions

The following features are deferred to Format-Version 2 or later:

- **Conflict representation**: `Conflict:` trailer for unresolvable
  merge conflicts (Section 6.8). Not implemented in v1.0.0; all
  conflicts currently resolved automatically via heuristics.

- **Binary attachments**: Store as blobs in the issue commit's tree
  object (instead of using the empty tree)

- **Reactions**: Emoji reactions as a `Reaction:` trailer

- **Templates**: Issue templates as blobs in `refs/issues/templates/`

- **Access control**: Per-issue access control lists

- **Live sync**: Bidirectional real-time synchronization with external
  providers

- **Advanced label merging**: Semantic duplicate detection (e.g.,
  `enhancement` = `feature`) and case normalization. Currently uses
  exact string matching (Section 6.3.1).

Extensions MUST increment the `Format-Version:` trailer. Implementations
MUST ignore trailers they do not recognize. Implementations MUST NOT
reject issues with a `Format-Version:` higher than they support; they
SHOULD process what they understand and warn about unrecognized fields.

---

## Acknowledgments

This specification was inspired by:
- Linus Torvalds's 2007 vision of "a git for bugs"
- D. Richard Hipp's Fossil ticket system
- Michael Mure's git-bug CRDT data model
- Julian Ganz and Matthias Beyer's git-dit commit-based approach
- Google's git-appraise `refs/notes/devtools/` architecture
- Diomidis Spinellis's git-issue pragmatic shell implementation

---

## References

- [RFC 2119 - Key words for use in RFCs](https://tools.ietf.org/html/rfc2119)
- [RFC 4122 - UUID](https://tools.ietf.org/html/rfc4122)
- [gitformat-trailers(5)](https://git-scm.com/docs/git-interpret-trailers)
- [gitformat-pack(5)](https://git-scm.com/docs/gitformat-pack)
- [Linus Torvalds on Bug Tracking (2007)](https://yarchive.net/comp/linux/bug_tracking.html)
- [Fossil Ticket System](https://fossil-scm.org/home/doc/trunk/www/tickets.wiki)
- [git-bug Data Model](https://github.com/git-bug/git-bug/blob/master/doc/model.md)
