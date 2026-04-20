# Design: git-native-issue vs Beads Comparison Document

**Date**: 2026-04-20
**Status**: Draft
**Author**: Emerson Soares

## Purpose

First entry in a comparison series (`docs/comparisons/<tool>.md`) analyzing
competing distributed issue trackers against git-native-issue. Each document
serves dual purpose:

1. **Public positioning** — advocacy with honesty for potential adopters
2. **Roadmap input** — identifies which competitor features are worth adding,
   which are solvable with existing primitives, and which are architectural bloat

Future entries: git-bug, Fossil, Bugs Everywhere, git-appraise, etc.
A summary table in `docs/comparisons/README.md` will link all entries.

## Target Audience

Mixed technical level. Git-literate developers who understand commits, refs,
and merge at a conceptual level. Layered depth: accessible arguments first
(zero deps, portable), technical depth for those who want it (trailers,
merge primitives, for-each-ref queries).

## Tone

Advocacy with honesty. Written from git-native-issue's perspective.
Acknowledges competitor strengths, makes clear judgments about tradeoffs,
never dismisses features without reasoning.

## Output

**File**: `docs/comparisons/beads.md`

## Document Structure

### 1. Header + At a Glance

Quick-reference comparison table covering: storage, language, lines of code,
dependencies, binary size, merge strategy, spec availability, license.

One-paragraph verdict immediately below the table: git-native-issue treats
Git as the database; Beads brings a separate database alongside Git. Both
solve distributed issue tracking; git-native-issue does it with zero
dependencies beyond Git.

### 2. What They Have in Common

Brief section (~150 words). Shared ground:

- Both reject centralized trackers (GitHub Issues, Jira) as single points
  of failure
- Both use hash-based IDs for collision-free distributed work (UUID v4 vs
  hash-derived bd-xxxx)
- Both sync via push/pull rather than webhooks or polling
- Both bridge to GitHub, GitLab, Gitea, Azure DevOps

Purpose: establish that the divergence is architectural, not functional.

### 3. The Fundamental Fork

The philosophical centerpiece (~300 words).

Two competing theses:

- **Beads**: "Issues need a real database; Git is the wrong abstraction for
  queries and graphs." Ships Dolt (version-controlled SQL) as storage engine.
- **git-native-issue**: "Git already IS a distributed append-only
  content-addressable database. Issues are commits, identity is refs,
  metadata is trailers, merge is Git merge."

Name the fork explicitly. Frame the rest of the document as evidence for the
Git-native thesis.

### 4. Storage: Commits + Refs + Trailers vs Dolt SQL

Concrete comparison (~400 words).

**git-native-issue model:**

```
refs/issues/<uuid> → commit chain (append-only)
  ├── root commit: title (subject) + metadata (trailers)
  ├── comment commits: body text
  └── state-change commits: State: trailer
  All point to empty tree (4b825dc...)
```

- Human-readable via `git log refs/issues/*`
- Tamper-evident (SHA-based content addressing)
- Zero bytes overhead beyond Git objects
- Works in bare repos, no working tree needed

**Beads model:**

```
.beads/embeddeddolt/ → Dolt database
  ├── issues table (id, title, status, priority, type, ...)
  ├── dependencies table (graph edges)
  ├── comments, events, labels, wisps, ...
  └── refs/dolt/data (Dolt's own ref namespace)
```

- Full SQL query power (indexes, joins, foreign keys)
- Cell-level versioning
- ~200MB binary + database files
- Requires Dolt engine (embedded or server mode)

Key argument: git-native-issue's storage IS Git. Beads' storage is a
parallel system that happens to have Git-like properties.

### 5. Merge: Git's Own Primitives vs an External Engine

~300 words. Core argument: git-native-issue does not invent merge semantics.
It composes Git's existing primitives:

- **Comments**: Union of commit chains (how Git merge works by default)
- **Labels**: Three-way set merge via `git merge-base` + `comm` + `sort`
  (standard UNIX tools from the 1970s)
- **Scalars**: Last-writer-wins via `%(authordate)` (Git's own timestamp)
- **Merge commits**: `git commit-tree` with two parents (Git plumbing)

The ISSUE-FORMAT.md spec contribution is policy decisions over these
primitives (labels use set merge, additions beat removals, etc.), not new
algorithms.

Beads delegates merge to Dolt's cell-level engine — a separate system with
its own semantics that users must trust as a black box.

### 6. The Dependency Graph Question

The key rebuttal section (~500 words). Beads' strongest selling point is
its dependency graph (`dep add/remove/tree`, `bd ready`, cycle detection).

Argument: this is a data modeling problem, not a storage engine problem.
Git trailers model the same graph:

```
Blocks: a7f3b2c
Blocked-By: c4e5f6d
Parent: b8c9d0e
Related: f1a2b3c
```

These are append-only, queryable via `git log --format='%(trailers:key=Blocks)'`,
and merge-safe (union semantics).

Show how GitHub Issues models epics, stories, tasks, and blockers with zero
built-in hierarchy — using labels + cross-references. git-native-issue's
trailers are MORE structured than GitHub's freeform markdown.

A ready queue is: "open issues where no unresolved Blocked-By target exists."
Computable with `git for-each-ref` + awk.

Acknowledge: this is a feature gap today, not an architectural limitation.
Closing it requires new trailers in the spec + ~3 new commands (~200 lines
of shell), not a database migration.

### 7. Agent Integration

~250 words. Beads was designed agent-first: JSON output everywhere,
atomic `--claim`, `bd ready`, built-in Anthropic SDK, MCP server.

git-native-issue approaches this via plugins (claude-git-native-issue)
rather than baking agent concerns into the core tool.

Argument: keeping the core tool human-first is a feature, not a limitation.
Trailers ARE structured data — agents consume them naturally. A `--json`
output flag is a small addition. Agent orchestration (molecules, gates,
formulas) belongs in orchestration tools, not issue trackers.

### 8. What Beads Has That We Don't (And Whether It Matters)

~400 words. Tiered honest assessment:

**Tier 1 — Worth considering (small additions that close real gaps):**

- `--json` output flag for machine consumption
- Dependency trailers (`Blocks:`, `Blocked-By:`, `Parent:`)
- `git issue ready` command (unblocked task query)
- `git issue dep tree` command (dependency visualization)

**Tier 2 — Interesting but out of scope:**

- Molecules, formulas, gates — workflow orchestration primitives that belong
  in a separate tool
- Hierarchical IDs (`bd-a3f8.1.1`) — convenient but solvable with `Parent:`
  trailers
- Multi-repo federation — interesting for enterprise, premature for v1.x
- Contributor/maintainer role detection — solves a Beads-specific problem
  (keeping planning DBs out of PRs)

**Tier 3 — Architectural bloat:**

- Wisps (ephemeral TTL messages in an append-only tracker — contradicts the
  model)
- Compaction/memory decay (rewriting history contradicts content-addressable
  design)
- OpenTelemetry (observability for an issue tracker CLI tool?)
- 212 Go module dependencies for a task that shell scripts handle

### 9. Feature Matrix

Comprehensive table. Every feature from both tools, side by side.

Categories:

- Core (create, list, show, edit, state, search, comment)
- Dependencies & hierarchy
- Collaboration (assign, claim, comment)
- Sync & bridges (GitHub, GitLab, Gitea, Azure DevOps, Jira, Linear)
- Agent support (JSON output, MCP, ready queue, claim)
- Maintenance (fsck, compact, gc, doctor)
- Data properties (tamper-evident, human-readable, spec-driven, bare repo)

Values: checkmark, "planned", "N/A — by design" (for deliberate omissions).

### 10. When to Use Which

Closing section (~200 words). Clear guidance:

**Use git-native-issue when:**

- You already use Git and want zero new dependencies
- Issues should travel with your code (clone includes issues)
- You value a formal spec that other tools can implement
- Human readability matters (`git log` shows your issues)
- You work in environments where a 200MB binary is impractical

**Consider Beads when:**

- Your primary users are AI agents, not humans
- You need complex SQL queries over issue data
- Your team already uses Dolt
- You need Jira/Linear sync specifically

Honest, not dismissive.

## Roadmap Implications

Not included in the public document. Captured separately as issues in the
git-native-issue tracker:

1. Add `--json` output flag to `git issue ls` and `git issue show`
2. Spec new trailers: `Blocks:`, `Blocked-By:`, `Parent:`, `Related:`
3. Add `git issue dep add/remove/list/tree` commands
4. Add `git issue ready` command
5. Consider `--format json` as alternative to `--json` flag

## Non-Goals

- This document does NOT propose implementing beads' features in
  git-native-issue
- This document does NOT change ISSUE-FORMAT.md
- This document does NOT cover other competitors (separate documents)
- No code changes result from this spec — it is a documentation deliverable

## Success Criteria

- Reader who knows neither tool can understand the architectural difference
  in under 2 minutes (At a Glance + Verdict)
- Reader evaluating tools gets a comprehensive feature matrix to reference
- The dependency graph argument is convincing: trailers + Git merge solve
  the same problem without a database
- Honest about gaps without being self-deprecating
