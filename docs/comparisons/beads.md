# git-native-issue vs Beads (bd)

> Last verified against Beads v1.0.2 (2026-04-20)

[Beads](https://github.com/gastownhall/beads) is a Go-based distributed
graph issue tracker powered by [Dolt](https://github.com/dolthub/dolt), a
version-controlled SQL database. It was designed primarily for AI agent
workflows: dependency graphs, ready queues, and JSON output for machine
consumption.

This document compares its approach to git-native-issue's Git-native model.

## At a Glance

| Dimension | git-native-issue | Beads (bd) |
|-----------|-----------------|------------|
| **Storage** | Git commits + refs + trailers | Dolt (version-controlled SQL) |
| **Language** | POSIX Shell | Go |
| **Codebase** | ~7K lines, 22 scripts | ~314K lines, 1,061 files |
| **Dependencies** | Git (+ optional `gh`, `jq` for bridges) | 212 Go modules, Dolt engine |
| **Install size** | 0 (shell scripts on PATH) | ~41-44MB compressed binary |
| **Merge strategy** | Git's own merge primitives | Dolt cell-level merge |
| **Formal spec** | [ISSUE-FORMAT.md](../../ISSUE-FORMAT.md) (33KB) | None (implementation is the spec) |
| **License** | GPL-2.0 | MIT |
| **Version** | v1.4.0 | v1.0.2 |
| **Repo** | [remenoscodes/git-native-issue](https://github.com/remenoscodes/git-native-issue) | [gastownhall/beads](https://github.com/gastownhall/beads) |

Both projects solve distributed issue tracking without a central server.
The difference is architectural: git-native-issue treats Git as the
database -- issues are commits, identity is refs, metadata is trailers,
merge is Git merge. Beads brings a separate database (Dolt) alongside Git.
git-native-issue does this with zero dependencies beyond Git itself, and
produces a formal specification that any tool can implement.

---

## What They Have in Common

Before diving into differences, it is worth noting the shared ground.
Both projects reject centralized trackers (GitHub Issues, Jira, Linear) as
single points of failure. Both use hash-based IDs for collision-free
distributed work -- git-native-issue uses UUID v4, Beads uses content-hash
in base36 (e.g. `bd-a3f8e9`). Both sync via push/pull rather than webhooks
or polling. Both bridge to GitHub, GitLab, Gitea, and Azure DevOps.

The shared DNA ends at the storage layer. Everything that follows stems from
a single architectural fork.

---

## The Fundamental Fork

Two competing theses:

**Beads' thesis**: "Issues need a real database. Git is the wrong
abstraction for queries and graphs." Beads ships Dolt -- a version-controlled
SQL database with cell-level merge, native branching, and built-in sync --
as its storage engine. Issues live in SQL tables with indexes, foreign keys,
and joins.

**git-native-issue's thesis**: "Git already IS a distributed, append-only,
content-addressable database. Issues are just commits."

git-native-issue uses only Git primitives that have existed for 20 years:
commits as events, refs as identity, trailers as structured metadata, and
Git's own merge machinery for conflict resolution. No new storage engine.
No new protocol. No new binary.

The rest of this document presents evidence for the Git-native thesis --
while being honest about where the tradeoffs favor Beads.

---

## Storage: Commits + Refs + Trailers vs Dolt SQL

### git-native-issue

```
refs/issues/<uuid>  -->  commit chain (append-only)
    |-- root commit: title (subject) + metadata (trailers)
    |-- comment commits: body text
    |-- state-change commits: State: trailer
    All point to empty tree (4b825dc...)
```

- **Human-readable**: `git log refs/issues/*` shows your issues
- **Tamper-evident**: every commit is SHA-addressed; changing a byte changes
  the hash
- **Zero overhead**: no files in the working tree, no database files, no
  `.beads/` directory
- **Works everywhere**: bare repos, CI environments, embedded systems --
  anywhere Git runs

Every piece of issue data is a standard Git object. `git clone` copies your
issues. `git push` shares them. `git fsck` validates them.

### Beads

```
.beads/embeddeddolt/  -->  Dolt database
    |-- issues table (id, title, status, priority, type, ...)
    |-- dependencies table (graph edges)
    |-- comments, events, labels, wisps, ...
    |-- refs/dolt/data (Dolt's own ref namespace)
```

- **Full SQL power**: indexes, joins, foreign keys, ad-hoc queries
- **Cell-level versioning**: every field change is tracked independently
- **Large footprint**: Go binary with embedded Dolt engine (~41-44MB
  compressed)
- **Requires Dolt**: either embedded (in-process, single-writer) or server
  mode (external `dolt sql-server`)

Beads' storage is a parallel system alongside Git. It has Git-like
properties (branching, merge, history), but it is not Git. Your issues
live in a separate database. They do not travel with `git clone`.

---

## Merge: Git's Own Primitives vs an External Engine

### How git-native-issue merges

git-native-issue does not invent merge algorithms. It composes Git's
existing primitives:

- **Comments**: union of commit chains. When two branches diverge, merging
  produces a commit with two parents -- both chains are preserved. This is
  how Git merge works by default.
- **Labels**: three-way set merge via `git merge-base` + `comm` + `sort`.
  Additions from both sides are kept. Removals from both sides are honored.
  On tie, additions beat removals (bias toward keeping data). These are
  standard UNIX tools from the 1970s.
- **Scalar fields** (assignee, priority, milestone): last-writer-wins via
  `%(authordate)` -- Git's own author timestamp. Tiebreaker:
  lexicographically greater SHA.
- **Merge commits**: `git commit-tree` with two parents and resolved
  metadata as trailers. Standard Git plumbing.

The [ISSUE-FORMAT.md](../../ISSUE-FORMAT.md) spec contribution is policy
decisions over these primitives -- which strategy applies to which field
type -- not new algorithms. The strategies themselves are textbook
distributed systems patterns implemented with Git commands.

### How Beads merges

Beads delegates merge entirely to Dolt's cell-level merge engine. Dolt
performs a three-way merge at the SQL cell level. This is effective, but it
is a black box: users must trust Dolt's merge semantics, which are not
formally specified and may change between versions.

git-native-issue's merge behavior is specified in a
[formal document](../../ISSUE-FORMAT.md) that any implementation can follow.
Beads' merge behavior is whatever Dolt does.

---

## The Dependency Graph Question

Beads' strongest selling point is its dependency graph: `bd dep add/remove/tree`,
`bd ready` (list unblocked tasks), and cycle detection. This is genuinely
useful for AI agent workflows where agents need to ask "what can I work on
next?"

**Our argument: this is a data modeling problem, not a storage engine
problem.**

Git trailers model the same graph:

```
Blocks: a7f3b2c
Blocked-By: c4e5f6d
Parent: b8c9d0e
Related: f1a2b3c
```

These are append-only (a new commit adds a trailer), merge-safe (union
semantics -- same as comments), and queryable via Git plumbing.

### The GitHub Issues analogy

GitHub Issues has zero built-in hierarchy or dependency primitives. Yet
millions of teams model epics, stories, tasks, and blockers using nothing
but labels, mentions, and markdown checklists. git-native-issue's trailers
are more structured than GitHub's freeform markdown -- they are typed,
machine-parseable, and formally specified.

### Query cost

To be honest about the tradeoff: querying trailers requires iterating issue
refs -- `git for-each-ref refs/issues/` to collect tips, then inspecting
each tip commit's trailers. This is O(n) over all issues, not an indexed
lookup like Dolt's SQL.

For most repositories (hundreds of issues), this is fast -- the same pattern
`git issue ls` already uses for filtering by label or priority. For
thousands of issues, it is slower than SQL but still tractable. The tradeoff
is: no new dependency for queries that are fast enough at realistic scale.

### Cycle detection

Detecting cycles in a trailer-based dependency graph requires a full DFS
traversal across all `Blocks:`/`Blocked-By:` relationships. This is
non-trivial but well-understood -- a standard graph algorithm. We do not
pretend this is a one-liner.

### A ready queue

A ready queue is: "open issues where no unresolved `Blocked-By` target
exists." This requires collecting all open issues' `Blocked-By` trailers,
checking which targets are still open, and filtering. Not trivial, but the
same algorithmic complexity as any graph-based ready queue -- including
Beads'.

### The bottom line

Dependency tracking is a **feature gap** in git-native-issue today, not an
**architectural limitation**. Closing it requires new trailers in the spec
plus approximately five new commands (`dep add`, `dep remove`, `dep list`,
`dep tree`, `ready`) with cycle detection and validation. Realistic
estimate: 400-600 lines of shell. This is meaningful work, but proportional
-- git-native-issue's existing commands average 100-150 lines each.

Beads built a 314K-line Go application with 212 dependencies and a SQL
database to solve a problem that structured metadata and smart queries can
handle.

---

## Agent Integration

Beads was designed agent-first: JSON output everywhere, atomic `--claim`
(sets assignee + in_progress in one operation), `bd ready` (unblocked
tasks), a built-in Anthropic SDK, and an MCP server on PyPI.

git-native-issue approaches agent integration differently -- via plugins
rather than baking agent concerns into the core tool. The
[claude-git-native-issue](https://github.com/remenoscodes/claude-git-native-issue)
plugin enables Claude Code to create, list, update, and close issues
autonomously.

To be clear: Beads is human-usable. It has a full CLI and TUI. The
argument is not that Beads sacrificed human usability, but that
agent-specific concerns -- molecules, gates, formulas, built-in LLM SDKs
-- do not need to live in the issue tracker's core.

Trailers are structured data. Agents consume them naturally. A `--json`
output flag is a small addition to git-native-issue that closes the
machine-readability gap without pulling in the Anthropic SDK as a
dependency of the issue tracker.

Agent orchestration belongs in orchestration tools. Issue tracking belongs
in the issue tracker.

---

## What Beads Has That We Don't (And Whether It Matters)

### Worth considering

Features that close real gaps with small additions:

- **`--json` output**: machine-readable output for agent consumption.
  A natural addition to `git issue ls` and `git issue show`.
- **Dependency trailers**: `Blocks:`, `Blocked-By:`, `Parent:`, `Related:`.
  New trailers in the ISSUE-FORMAT.md spec, queryable with existing Git
  plumbing.
- **`git issue ready`**: list unblocked tasks. A new command built on
  dependency trailers.
- **`git issue dep tree`**: visualize the dependency graph. A new command
  that reads `Blocks:`/`Blocked-By:` trailers and renders a tree.

### Interesting but out of scope

Features that solve real problems but belong in separate tools:

- **Molecules, formulas, gates**: workflow orchestration primitives (compound
  tasks, YAML recipes, async coordination). These are useful but they are
  orchestration, not issue tracking.
- **Hierarchical IDs** (`bd-a3f8.1.1`): convenient shorthand for sub-tasks,
  but solvable with `Parent:` trailers without changing the ID scheme.
- **Multi-repo federation**: interesting for enterprise deployments,
  premature for v1.x of a tool focused on getting the primitives right.
- **Contributor/maintainer roles**: auto-detection of repo access level.
  Solves a Beads-specific problem (keeping planning databases out of PRs).

### Unnecessary complexity

Features that add weight without clear benefit for issue tracking:

- **Wisps** (ephemeral TTL messages): adds complexity to an issue tracker
  with unclear benefit. While append-only systems can support TTL (e.g.
  Kafka retention), it is unclear why an issue tracker needs ephemeral
  messages.
- **Compaction/memory decay**: rewriting closed issue history to save AI
  context windows. This trades auditability for a concern that belongs in
  the agent, not the data store.
- **OpenTelemetry**: structured observability for a CLI issue tracker. The
  overhead of tracing infrastructure outweighs the diagnostic value for a
  tool that runs in milliseconds.
- **212 Go module dependencies**: a large dependency tree for functionality
  that POSIX shell scripts handle with zero external dependencies.

---

## Feature Matrix

| Category | Feature | git-native-issue | Beads (bd) |
|----------|---------|-----------------|------------|
| **Core** | Create issues | ✓ | ✓ |
| | List/filter issues | ✓ | ✓ |
| | Show issue details | ✓ | ✓ |
| | Edit issue metadata | ✓ | ✓ |
| | Change state (open/close) | ✓ | ✓ |
| | Search issues | ✓ | ✓ |
| | Add comments | ✓ | ✓ |
| **Dependencies** | Add/remove dependencies | planned | ✓ |
| | Dependency tree visualization | planned | ✓ |
| | Ready queue (unblocked tasks) | planned | ✓ |
| | Cycle detection | planned | ✓ |
| | Epics / sub-tasks | planned (via `Parent:` trailer) | ✓ (hierarchical IDs) |
| **Collaboration** | Assign issues | ✓ | ✓ |
| | Atomic claim (assign + start) | -- | ✓ |
| | Comment threading | -- | ✓ |
| **Sync** | GitHub | ✓ (import/export/sync) | ✓ |
| | GitLab | ✓ (import/export/sync) | ✓ |
| | Gitea / Forgejo | ✓ (import/export) | ✓ |
| | Azure DevOps | ✓ (import/export) | ✓ |
| | Jira | -- | ✓ |
| | Linear | -- | ✓ |
| | DoltHub | N/A | ✓ |
| **Agent support** | JSON output | planned | ✓ |
| | MCP server | -- | ✓ |
| | Claude plugin | ✓ (via plugin) | ✓ (built-in SDK) |
| | Ready queue | planned | ✓ |
| **Maintenance** | Data integrity validation | ✓ (`git issue fsck`) | ✓ (`bd doctor`) |
| | Garbage collection | N/A (Git GC) | ✓ (`bd gc`) |
| | Compaction | N/A -- by design | ✓ (`bd compact`) |
| **Data properties** | Tamper-evident (SHA-addressed) | ✓ | -- |
| | Human-readable (`git log`) | ✓ | -- |
| | Formal interop spec | ✓ (ISSUE-FORMAT.md) | -- |
| | Works in bare repos | ✓ | -- |
| | Zero dependencies beyond Git | ✓ | -- |
| | Travels with `git clone` | ✓ | -- |
| | SQL ad-hoc queries | -- | ✓ |
| | Cell-level field versioning | -- | ✓ |

Legend: `✓` = available, `planned` = on roadmap, `--` = not available,
`N/A` = not applicable by design.

---

## When to Use Which

**Use git-native-issue when:**

- You already use Git and want zero new dependencies
- Issues should travel with your code (`git clone` copies your issues)
- You value a formal spec that other tools can implement
- Human readability matters (`git log` shows your issues)
- You work in constrained environments (CI, bare repos, air-gapped systems)
- You want issue data that is tamper-evident by construction

**Consider Beads when:**

- Your primary users are AI agents, not humans
- You need complex SQL queries over issue data
- Your team already uses Dolt
- You need Jira or Linear sync specifically
- You need dependency graph queries at scale (thousands of issues)

Both are honest tools built by people who care about distributed issue
tracking. They differ on a single architectural question: whether Git is
enough. We believe it is.
