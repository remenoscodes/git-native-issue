# Beads Comparison Document — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write `docs/comparisons/beads.md` — a public-facing technical comparison of git-native-issue vs Beads (bd), the first entry in a comparison document series.

**Architecture:** Single markdown document with 10 sections, written incrementally. Each task produces one or two sections, verified for factual accuracy against both projects' source code, then committed. A final task creates the comparisons directory README.

**Tech Stack:** Markdown. Reference sources: git-native-issue repo (local), Beads repo (cloned to /tmp/beads), Beads GitHub releases API for binary size data.

**Spec:** `docs/superpowers/specs/2026-04-20-beads-comparison-design.md`

---

### File Map

- **Create:** `docs/comparisons/beads.md` — the comparison document
- **Create:** `docs/comparisons/README.md` — index for the comparison series
- **Reference:** `README.md` (Prior Art section, lines 631-648)
- **Reference:** `ISSUE-FORMAT.md` (merge rules, trailer spec)
- **Reference:** `/tmp/beads/README.md` (Beads features, commands)
- **Reference:** `/tmp/beads/LICENSE` (MIT)
- **Reference:** Beads v1.0.2 release assets (binary sizes)

---

### Task 1: Create comparisons directory + header + At a Glance table

**Files:**
- Create: `docs/comparisons/beads.md`

- [ ] **Step 1: Create the document with header and At a Glance table**

Write the document header including:
- Title: `git-native-issue vs Beads (bd)`
- Metadata line: `Last verified against Beads v1.0.2 (2026-04-20)`
- Intro quote describing what Beads is
- At a Glance table with these rows:

| Dimension | git-native-issue | Beads (bd) |
|-----------|-----------------|------------|
| **Storage** | Git commits + refs + trailers | Dolt (version-controlled SQL) |
| **Language** | POSIX Shell | Go |
| **Codebase** | ~5K lines, 25 scripts | ~314K lines, 1,061 files |
| **Dependencies** | Git (+ optional `gh`, `jq` for bridges) | 212 Go modules, Dolt engine |
| **Install size** | 0 (shell scripts on PATH) | ~41-44MB compressed (~80-100MB binary) |
| **Merge strategy** | Git's own merge primitives | Dolt cell-level merge |
| **Formal spec** | ISSUE-FORMAT.md (33KB) | None (implementation is the spec) |
| **License** | GPL-2.0 | MIT |
| **Version** | v1.4.0 | v1.0.2 |
| **Repo** | `remenoscodes/git-native-issue` | `gastownhall/beads` |

Then the one-paragraph verdict.

- [ ] **Step 2: Verify table data accuracy**

Cross-check each cell:
- git-native-issue line count: `wc -l bin/git-issue-*` + `wc -l bridge/*`
- Beads line count: already verified (314K Go lines, 1061 files)
- Beads install size: already verified from `gh release view v1.0.2` (41MB darwin_arm64, 44MB linux_amd64)
- Beads license: already verified (MIT)
- git-native-issue version: check `bin/git-issue-version` or `CHANGELOG.md`

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add beads comparison header and At a Glance table"
```

---

### Task 2: Sections 2-3 — Common Ground + The Fundamental Fork

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 2 — What They Have in Common**

~150 words. Four bullet points from the spec:
- Both reject centralized trackers as single points of failure
- Both use hash-based IDs (UUID v4 vs content-hash base36)
- Both sync via push/pull
- Both bridge to GitHub, GitLab, Gitea, Azure DevOps

- [ ] **Step 2: Write Section 3 — The Fundamental Fork**

~300 words. The philosophical centerpiece:
- Name both theses explicitly
- Beads: "Issues need a real database"
- git-native-issue: "Git already IS the database"
- Frame the rest of the document as evidence

- [ ] **Step 3: Verify claims**

Confirm Beads' README describes Dolt as its storage engine. Confirm git-native-issue's README describes the "Git as database" philosophy.

- [ ] **Step 4: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add common ground and fundamental fork sections"
```

---

### Task 3: Section 4 — Storage Comparison

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 4 — Storage**

~400 words. Two subsections with ASCII diagrams:

**git-native-issue model** — commit chain under `refs/issues/<uuid>`, empty tree, trailers as metadata. Bullet points: human-readable, tamper-evident, zero overhead, works in bare repos.

**Beads model** — Dolt database in `.beads/embeddeddolt/`, SQL tables (issues, dependencies, comments, events, labels, wisps). Bullet points: full SQL power, cell-level versioning, large footprint, requires Dolt engine.

Closing argument: git-native-issue's storage IS Git; Beads' storage is a parallel system.

- [ ] **Step 2: Verify storage details**

Check Beads README and source for exact table names. Check git-native-issue's ISSUE-FORMAT.md for the exact empty tree SHA and ref format.

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add storage architecture comparison"
```

---

### Task 4: Section 5 — Merge Comparison

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 5 — Merge**

~300 words. Show that git-native-issue composes Git's existing merge primitives:
- Comments: union of commit chains
- Labels: three-way set merge via `git merge-base` + `comm` + `sort`
- Scalars: LWW via `%(authordate)`
- Merge commits: `git commit-tree` with two parents

The ISSUE-FORMAT.md contribution is policy (which strategy per field), not new algorithms.

Contrast: Beads delegates to Dolt's cell-level merge engine — a black box.

- [ ] **Step 2: Verify merge details**

Read ISSUE-FORMAT.md merge section to confirm the exact strategies. Check that the Git commands referenced are accurate.

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add merge strategy comparison"
```

---

### Task 5: Section 6 — The Dependency Graph Question

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 6 — Dependencies**

~600 words. The key rebuttal. Structure:

1. Name Beads' strongest feature (dependency graph, ready queue, cycle detection)
2. Argue: data modeling problem, not storage engine problem
3. Show trailer-based graph model (`Blocks:`, `Blocked-By:`, `Parent:`, `Related:`)
4. **Querying subsection**: honest about O(n) cost, argue "fast enough at realistic scale"
5. **Cycle detection subsection**: non-trivial DFS, acknowledge implementation cost
6. GitHub Issues analogy: models epics/stories/tasks with zero built-in hierarchy
7. Ready queue: "open issues with no unresolved Blocked-By targets"
8. Closing: feature gap today, not architectural limitation. ~400-600 lines of shell to close it.

- [ ] **Step 2: Verify Beads' dependency features**

Check Beads README for exact `bd dep` commands, `bd ready` behavior, and cycle detection. Ensure we're not misrepresenting their feature set.

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add dependency graph question section"
```

---

### Task 6: Section 7 — Agent Integration

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 7 — Agent Integration**

~250 words. Cover:
- Beads' agent-first design: JSON output, `--claim`, `bd ready`, Anthropic SDK, MCP server
- git-native-issue's plugin approach (claude-git-native-issue)
- Note: Beads IS human-usable (full CLI + TUI)
- Argument: agent concerns don't need to live in the issue tracker core
- `--json` flag is a small addition; trailers ARE structured data

- [ ] **Step 2: Verify Beads' agent features**

Check Beads README for MCP server, Anthropic SDK integration, `--claim` flag, `--json` flag.

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add agent integration comparison"
```

---

### Task 7: Section 8 — Honest Assessment (What They Have That We Don't)

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 8 — Tiered Assessment**

~400 words. Three tiers:

**Tier 1 — Worth considering:**
- `--json` output flag
- Dependency trailers (`Blocks:`, `Blocked-By:`, `Parent:`)
- `git issue ready` command
- `git issue dep tree` command

**Tier 2 — Interesting but out of scope:**
- Molecules, formulas, gates (workflow orchestration)
- Hierarchical IDs (solvable with `Parent:` trailers)
- Multi-repo federation (premature for v1.x)
- Contributor/maintainer roles (Beads-specific problem)

**Tier 3 — Unnecessary complexity:**
- Wisps (unclear benefit for issue tracking)
- Compaction (trades auditability for AI context window optimization)
- OpenTelemetry (observability for a CLI issue tracker?)
- 212 Go module dependencies

- [ ] **Step 2: Verify each feature exists in Beads**

Spot-check molecules, gates, wisps, formulas, OpenTelemetry in Beads source/README.

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add tiered honest assessment"
```

---

### Task 8: Section 9 — Feature Matrix

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write the comprehensive feature matrix**

Large table grouped by category:

**Core Operations:**
| Feature | git-native-issue | Beads |
Create, list, show, edit, state change, search, comment — both have these.

**Dependencies & Hierarchy:**
Dependency add/remove/tree, ready queue, cycle detection, epics, sub-tasks — Beads has, git-native-issue planned/N/A.

**Collaboration:**
Assign, claim, comment threading — mix of both.

**Sync & Bridges:**
GitHub, GitLab, Gitea, Azure DevOps (both), Jira, Linear (Beads only), DoltHub (Beads only).

**Agent Support:**
JSON output, MCP server, ready queue, atomic claim, built-in LLM SDK — Beads has most, git-native-issue has plugin approach.

**Maintenance:**
fsck (git-native-issue), compact/gc/doctor (Beads).

**Data Properties:**
Tamper-evident, human-readable (`git log`), formal spec, bare repo support, zero dependencies — git-native-issue advantages.

Use: `✓`, `planned`, `—` (not applicable), `via plugin`.

- [ ] **Step 2: Cross-verify every cell**

For each "✓" in the Beads column, confirm the feature exists via README or source. For each "✓" in the git-native-issue column, confirm via existing commands.

- [ ] **Step 3: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add comprehensive feature matrix"
```

---

### Task 9: Section 10 — When to Use Which

**Files:**
- Modify: `docs/comparisons/beads.md`

- [ ] **Step 1: Write Section 10 — Closing Guidance**

~200 words. Two subsections:

**Use git-native-issue when:**
- You already use Git and want zero new dependencies
- Issues should travel with your code (clone includes issues)
- You value a formal spec that other tools can implement
- Human readability matters (`git log` shows issues)
- You work in constrained environments (CI, bare repos, embedded systems)

**Consider Beads when:**
- Your primary users are AI agents, not humans
- You need complex SQL queries over issue data
- Your team already uses Dolt
- You need Jira/Linear sync specifically
- You need dependency graph queries at scale (thousands of issues)

Honest, not dismissive.

- [ ] **Step 2: Commit**

```bash
git add docs/comparisons/beads.md
git commit -m "docs(comparisons): add closing guidance section"
```

---

### Task 10: Comparisons README + Final Review

**Files:**
- Create: `docs/comparisons/README.md`
- Modify: `docs/comparisons/beads.md` (if final review finds issues)

- [ ] **Step 1: Create `docs/comparisons/README.md`**

```markdown
# Comparisons

Detailed technical comparisons of git-native-issue against other
distributed issue tracking tools.

| Tool | Approach | Document |
|------|----------|----------|
| [Beads (bd)](https://github.com/gastownhall/beads) | Dolt SQL database | [beads.md](beads.md) |

*More comparisons coming: git-bug, Fossil, Bugs Everywhere, git-appraise.*
```

- [ ] **Step 2: Read the full document end-to-end**

Read `docs/comparisons/beads.md` from top to bottom. Check:
- Flow: does each section build on the previous?
- Tone: advocacy with honesty, not dismissive?
- Accuracy: all claims verified?
- Completeness: all 10 sections present?

- [ ] **Step 3: Fix any issues found in review**

- [ ] **Step 4: Commit**

```bash
git add docs/comparisons/README.md docs/comparisons/beads.md
git commit -m "docs(comparisons): add series README and finalize beads comparison"
```
