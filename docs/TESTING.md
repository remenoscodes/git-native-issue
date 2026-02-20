# Testing Guide

Comprehensive testing documentation for git-native-issue.

## Overview

The test suite validates git-native-issue across 7 dimensions, totaling 209+
tests. All tests use a custom POSIX shell framework (no external dependencies).

```
sh t/test-issue.sh             # Core behavior (76 tests)
sh t/test-failure-modes.sh     # Failure modes (20 tests)
sh t/test-environment.sh       # Environmental (12 tests)
sh t/test-properties.sh        # Properties/invariants (24 tests)
sh t/test-bridge.sh            # Platform bridges (36 tests)
sh t/test-merge.sh             # Merge/fsck (20 tests)
sh t/test-qol.sh               # Quality-of-life (21 tests)
```

Run everything:

```
make test
```

## Test Dimensions

### 1. Behavior Tests (test-issue.sh)

**76 tests** covering core functionality:

- Issue creation with all option combinations (title, body, labels, assignee,
  priority, milestone)
- Issue listing with filters (state, label, assignee, priority, format, sort)
- Issue display (show with comments, metadata, state changes)
- Issue editing (labels, assignee, priority, milestone, title)
- State management (open, close, reopen, custom states, reasons)
- Comments (creation, ordering, trailer injection prevention)
- Data model (UUID format, empty tree usage, commit chains, trailers)
- Input validation (newlines, invalid priority, missing arguments)
- Edge cases (special characters, regex metacharacters in labels)
- Init and configuration

### 2. Failure Mode Tests (test-failure-modes.sh)

**20 tests** validating error handling under adverse conditions. These tests
use mock binaries injected via PATH to simulate failures in specific components.

**Pipe failure detection** (requires `set -o pipefail`):
- `git log` failure in `show`'s `git log | sed | head` pipeline
- `sed` failure mid-pipe propagates to caller
- `head` failure mid-pipe propagates to caller
- `awk` failure in `ls`'s data processing pipeline
- `sort` failure in `ls`'s result ordering
- `git log` failure in `search`'s `git log | awk` pipeline

**Missing dependency handling**:
- `jq` missing aborts import-github gracefully
- `gh` missing aborts import-github gracefully
- `gh` missing aborts export-github gracefully

**Signal and interruption**:
- SIGTERM triggers EXIT trap for cleanup
- `commit-tree` failure during create leaves no orphan refs

**Subshell and command substitution**:
- `rev-parse` failure in `$()` aborts script via `set -e`
- `interpret-trailers` failure propagates during create
- Empty `hash-object` output triggers explicit check

**Infrastructure resilience**:
- `update-ref` failure detected during state change
- CAS retry exhaustion detected (concurrent modification)
- Corrupt git objects cause graceful failure
- Operations outside git repo fail appropriately

**Technical note**: Tests call scripts directly (`$BIN_DIR/git-issue-show`)
rather than through `git issue show`. When invoked via `git`, the real git
binary prepends its exec-path to `$PATH`, bypassing mock binaries placed
earlier in PATH.

### 3. Environmental Tests (test-environment.sh)

**12 tests** validating behavior under different environmental conditions:

- Git version compatibility (requires git >= 2.22)
- UTF-8 locale handling for special characters
- Minimal PATH operation
- Read-only `.git/` detection
- Missing `/tmp` or `$TMPDIR` handling
- Permission errors on ref updates
- Git user identity validation (user.name, user.email)
- Long titles (500+ characters)

### 4. Property-Based Tests (test-properties.sh)

**24 tests** validating invariants that must hold across all operations:

**Idempotency**:
- `git issue ls` returns identical results on repeated calls
- `git issue show` output is stable across consecutive calls
- `git issue fsck` produces consistent results

**Determinism**:
- Same create parameters produce same commit structure
- Label normalization is deterministic regardless of order

**Invariants**:
- Every issue ref has exactly one root commit
- Root commit always uses empty tree
- State trailer is always present after state change
- Format-Version trailer is present on all root commits
- Comment chains maintain correct parent links
- Close/reopen cycle preserves issue identity

**Commutativity**:
- Label order does not affect final normalized form

### 5. Platform Bridge Tests (test-bridge.sh)

**36 tests** covering GitHub, GitLab, and Gitea/Forgejo bridges:

- Import with various state filters
- Export with dry-run validation
- Provider-ID tracking to prevent duplicates
- Comment sync (new comments appended, existing skipped)
- Re-import idempotency

### 6. Merge/Fsck Tests (test-merge.sh)

**20 tests** covering distributed merge and data integrity:

- Fast-forward merge
- Divergent history merge
- Three-way label merge
- Last-writer-wins for scalar fields
- Fsck validation of ref structure

### 7. Quality-of-Life Tests (test-qol.sh)

**21 tests** covering convenience features:

- Abbreviation matching for issue IDs
- Sort and format options
- Search with case-insensitive mode
- Help text and usage messages

## Test Framework

All tests use a shared pattern:

```sh
#!/bin/sh
set -e

# Test infrastructure
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); printf "  PASS %s\n" "$1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); printf "  FAIL %s\n" "$1"; }
run_test() { TESTS_RUN=$((TESTS_RUN + 1)); }

setup_repo() {
    rm -rf "$TEST_DIR/repo"
    mkdir "$TEST_DIR/repo"
    cd "$TEST_DIR/repo"
    git init -q
    git commit --allow-empty -q -m "initial"
    export PATH="$BIN_DIR:$PATH"
}

# Tests follow...
run_test
setup_repo
# ... test logic ...
# pass "description" or fail "description" "details"
```

Each test:
- Creates a fresh git repository in a temp directory
- Runs operations against the isolated repo
- Validates output and side effects
- Cleans up via EXIT trap

## Writing New Tests

### When to add tests

- New features: behavior tests (test-issue.sh or new file)
- Bug fixes: regression test in the appropriate suite
- Error handling changes: failure mode tests (test-failure-modes.sh)
- New dependencies: environmental tests (test-environment.sh)
- New data model invariants: property tests (test-properties.sh)

### Mocking external commands

For failure mode tests, create mock binaries:

```sh
# Create a mock git that fails on a specific subcommand
mkdir -p "$TEST_DIR/mock-dir"
cat > "$TEST_DIR/mock-dir/git" <<'MOCK'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in
        log) echo "fatal: simulated failure" >&2; exit 128 ;;
    esac
done
# Delegate to real git for other subcommands
real_git=""
old_ifs="$IFS"; IFS=':'
for d in $PATH; do
    case "$d" in */mock-dir) continue ;; esac
    test -x "$d/git" && real_git="$d/git" && break
done
IFS="$old_ifs"
exec "$real_git" "$@"
MOCK
chmod +x "$TEST_DIR/mock-dir/git"

# Use mock by prepending to PATH and calling script directly
PATH="$TEST_DIR/mock-dir:$PATH" "$BIN_DIR/git-issue-show" "$id"
```

### Testing pipe failures

With `set -o pipefail` in all scripts, pipe component failures propagate.
To test this:

1. Mock one component in the pipe (e.g., `sed`, `head`, `awk`)
2. Call the script directly (not through `git issue`)
3. Verify the script exits non-zero

## Quality Gates

The build must fail when:

- Any behavior test fails (core functionality)
- Any failure mode test fails (error handling)
- Any environmental test fails (portability)
- Any property test fails (invariant violation)
- shellcheck finds critical warnings
- Any script is missing `set -o pipefail`

## Safety Flags

All 20 production scripts in `bin/` enforce:

- `set -e` -- Exit immediately on command failure
- `set -o pipefail` -- Exit if any component of a pipe fails

The shared library (`git-issue-lib`) does not set these flags since it is
sourced by other scripts and inherits their settings.

## Related Documentation

- [SHELL-QUALITY-ASSESSMENT.md](SHELL-QUALITY-ASSESSMENT.md) -- Full quality
  assessment report with risk analysis
- [../CONTRIBUTING.md](../CONTRIBUTING.md) -- Contribution guidelines
- [../ISSUE-FORMAT.md](../ISSUE-FORMAT.md) -- The format specification
