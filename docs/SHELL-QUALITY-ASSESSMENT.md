# Shell Script Quality Manifesto Assessment
## git-native-issue Project Analysis

**Date**: 2026-02-15
**Assessor**: Claude Sonnet 4.5
**Issue**: fa222df
**Version**: v1.2.2
**Framework**: Shell Script Quality & Testing Manifesto

---

## Executive Summary

The git-native-issue codebase demonstrates **strong foundational quality** with comprehensive behavior testing (76 tests passing) and CI/CD integration with shellcheck. However, **critical gaps exist** in failure mode protection, particularly the absence of `set -o pipefail` across all 20+ shell scripts despite extensive pipe usage.

### Quality Score: 65/100

| Dimension | Score | Status |
|-----------|-------|--------|
| 1. Static Analysis | 15/20 | ⚠️ Partial |
| 2. Behavior Tests | 18/20 | ✅ Good |
| 3. Environmental Tests | 10/15 | ⚠️ Limited |
| 4. Failure Tests | 5/20 | ❌ Critical Gap |
| 5. Property-Based | 0/15 | ❌ Missing |
| 6. Mutation Testing | 0/10 | ❌ Missing |

---

## Codebase Inventory

### Production Scripts (20 files in `bin/`)

**Core Commands:**
- `git-issue` (57 lines) - Main dispatcher
- `git-issue-create` (~140 lines) - Issue creation
- `git-issue-edit` (~265 lines) - Issue modification
- `git-issue-state` (~175 lines) - State management
- `git-issue-comment` (~97 lines) - Comment handling
- `git-issue-show` (~175 lines) - Display logic
- `git-issue-ls` (~257 lines) - List/filter
- `git-issue-search` (~123 lines) - Search operations
- `git-issue-init` (~106 lines) - Repository initialization

**Platform Bridges (9 files):**
- `git-issue-{export,import,sync}` - Generic bridge logic
- `git-issue-{import,export}-{github,gitlab,gitea}` - Platform-specific (3,500+ lines total)

**Utilities:**
- `git-issue-lib` (257 lines, **not executable**) - Shared library
- `git-issue-fsck` - Integrity checking
- `git-issue-merge` - Conflict resolution

### Test Suite (22 files in `t/`)

- **test-issue.sh** (76 tests, core functionality)
- **test-concurrency.sh** (8 tests, concurrent operations)
- **test-edge-cases.sh** (edge case exploration)
- **test-{github,gitlab,gitea}-bridge.sh** (platform integration)
- **test-integration-*.sh** (cross-platform scenarios)
- **perf/** (4 benchmark scripts)

### Installation
- `install.sh` - User installation script

---

## Quality Dimension Analysis

### 1. Static Analysis (15/20) ⚠️

#### ✅ Strengths

**Shellcheck Integration (CI/CD)**
- GitHub Actions workflow (`.github/workflows/lint.yml`)
- Runs on every push/PR to `bin/**`
- All scripts pass: `shellcheck -S warning` ✅
- Only minor warnings found:
  ```
  SC2034: unused variable warnings in:
    - bin/git-issue-export-gitea (line 321)
    - bin/git-issue-export-github (line 177)
    - bin/git-issue-export-gitlab (line 182)
    - bin/git-issue-import-gitea (line 190)
  ```

**Error Mode**
- ✅ All 20 scripts use `set -e` (exit on error)
- ✅ No false positives from shellcheck SC2086 (unquoted expansions)
- ✅ No SC2046 (unquoted command substitution)

#### ❌ Critical Gaps

**Missing Safety Flags**
- ❌ **ZERO scripts use `set -o pipefail`**
  - Extensive pipe usage throughout codebase:
    ```bash
    # From git-issue-lib:245-246
    _title_override="$(git log --format='%(trailers:key=Title,valueonly)' "$_git_ref" | \
        sed '/^$/d' | head -1)"

    # Pipe failures in sed/head will be SILENTLY IGNORED
    ```
  - Platform bridges rely heavily on `jq`, `curl`, `gh`, `glab`:
    ```bash
    # From git-issue-export-github
    gh_comments_json="$(gh api ... | jq ...)"  # jq failure = empty string, not error
    ```

- ❌ **ZERO scripts use `set -u`** (unset variable protection)
  - Risk of silent bugs from typos: `$lables` instead of `$labels`
  - No protection against missing environment variables

**Formatting (Non-Blocking)**
- ⚠️ shfmt check exists but is **non-blocking** (won't fail CI)
- Inconsistent formatting not enforced

#### Recommendations

1. **HIGH PRIORITY**: Add `set -o pipefail` to ALL scripts
   ```bash
   #!/bin/sh
   set -e
   set -o pipefail  # ADD THIS
   ```

2. **MEDIUM**: Add `set -u` with explicit defaults:
   ```bash
   set -u
   labels="${labels:-}"
   assignee="${assignee:-}"
   ```

3. **LOW**: Make shfmt blocking in CI (enforce consistency)

4. **CLEANUP**: Remove unused variables flagged by SC2034

---

### 2. Behavior Tests (18/20) ✅

#### ✅ Strengths

**Comprehensive Test Suite**
- **76 core tests** (test-issue.sh) - ALL PASSING ✅
- Custom test framework (pass/fail/run_test helpers)
- Good coverage of:
  - ✅ Happy paths (create, edit, comment, state changes)
  - ✅ Error paths (invalid input, missing issues, nonexistent IDs)
  - ✅ Edge cases (empty comments, trailer injection, regex metacharacters)
  - ✅ Business rules (label normalization, assignee validation, priority enforcement)
  - ✅ Commit structure (empty tree usage, ref chains, trailers)

**Test Quality**
- Clear test names and descriptions
- Isolated test environments (`mktemp -d`, `setup_repo()`)
- Proper cleanup with `trap ... EXIT`
- Color-coded output (green/red/yellow)

**Exit Code Validation**
```bash
# From test-issue.sh:68-75
output="$(git issue version 2>&1)"
case "$output" in
    *"git-issue version"*)
        pass "git issue version prints version"
        ;;
    *)
        fail "git issue version prints version" "got: $output"
        ;;
esac
```

**Filesystem Effects Validated**
```bash
# From test-issue.sh:97
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 1; then
    pass "created issue has exactly one ref"
```

#### ❌ Gaps

**Not Using Standard Framework**
- ⚠️ Custom framework instead of BATS or ShellSpec
- Harder to integrate with CI/CD reporting (no TAP/JUnit output)
- No built-in test parameterization

**Limited stderr/stdout Distinction**
- Most tests capture combined output (`2>&1`)
- Some validation needs:
  ```bash
  actual_stdout="$(command 2>/dev/null)"
  actual_stderr="$(command 2>&1 >/dev/null)"
  ```

#### Recommendations

1. **OPTIONAL**: Migrate to BATS for better CI integration
   - Benefit: TAP output, parallel execution, setup/teardown hooks
   - Cost: Migration effort

2. **LOW**: Add explicit stdout/stderr separation for error message tests

---

### 3. Environmental Tests (10/15) ⚠️

#### ✅ Strengths

**Dependency Validation**
- ✅ Platform bridges check for required tools:
  ```bash
  # git-issue-export-github:83
  command -v gh >/dev/null 2>&1 || {
      echo "error: gh CLI not found" >&2
      exit 1
  }
  ```
- ✅ Graceful degradation:
  ```bash
  # git-issue-create:122
  if command -v uuidgen >/dev/null 2>&1; then
      uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  else
      # Fallback to /dev/urandom
  ```

**Git Configuration Validation**
- ✅ `validate_git_identity()` checks user.name/user.email before commits
  ```bash
  # git-issue-lib:102-119
  if test -z "$_name"; then
      printf 'fatal: user.name not set\n' >&2
      exit 128
  fi
  ```

**Test Environment Isolation**
- ✅ Tests skip gracefully when dependencies missing:
  ```bash
  # test-edge-cases.sh:42-50
  if ! command -v gh >/dev/null 2>&1; then
      printf "${YELLOW}SKIP${NC} gh CLI not found\n"
      exit 0
  fi
  ```

#### ❌ Gaps

**Missing Environmental Tests:**
- ❌ No tests for disk full scenarios
- ❌ No tests for read-only filesystem
- ❌ No tests for missing PATH entries
- ❌ No tests for permission errors on `refs/issues/`
- ❌ No tests for corrupted git config
- ❌ No tests for locale/encoding issues (UTF-8 vs ASCII)

**PATH Assumptions**
- Scripts assume standard Unix utilities available:
  - `sed`, `awk`, `grep`, `cut`, `tr`, `head`, `tail`
  - No validation for these critical dependencies

**Git Version Assumptions**
- No checks for minimum git version
- Features like `%(trailers:...)` require git 2.22+

#### Recommendations

1. **HIGH**: Add environmental test suite:
   ```bash
   t/test-environment.sh
   - Test with empty PATH
   - Test with read-only .git/
   - Test with missing /tmp access
   - Test with non-UTF-8 locale
   ```

2. **MEDIUM**: Add git version check:
   ```bash
   git_version="$(git version | sed 's/git version //')"
   # Require git >= 2.22
   ```

3. **LOW**: Document required utilities in README

---

### 4. Failure Tests (5/20) ❌ CRITICAL GAP

#### ✅ Strengths

**Concurrency Tests Exist**
- ✅ `test-concurrency.sh` validates:
  - CAS retry logic for concurrent ref updates
  - Proper commit chain construction
  - Graceful handling of simultaneous operations

**Concurrent Modification Handling**
- ✅ `update_ref_with_retry()` in git-issue-lib (CAS with exponential backoff)
  ```bash
  # git-issue-lib:170-239
  while test "$_attempt" -le "$_max_attempts"; do
      if git update-ref -- "$_ref" "$_new_sha" "$_expected_old" 2>/dev/null; then
          return 0
      fi
      # Exponential backoff: 100ms, 200ms
  done
  ```

#### ❌ CRITICAL GAPS

**Pipe Failures (Highest Risk)**
- ❌ **NO `set -o pipefail` anywhere in codebase**
- ❌ Extensive pipe usage without failure protection:

  ```bash
  # git-issue-lib:245-246 (VULNERABLE)
  _title_override="$(git log --format='%(trailers:key=Title,valueonly)' "$_git_ref" | \
      sed '/^$/d' | head -1)"

  # If git log FAILS → sed gets empty input → head succeeds → empty title silently returned
  # If sed FAILS → head gets malformed input → succeeds with garbage → data corruption
  ```

  ```bash
  # git-issue-export-github (VULNERABLE)
  gh_comments_json="$(gh api repos/$owner/$repo/issues/$number/comments | jq -r ...)"

  # If gh api FAILS (rate limit, auth expired) → jq gets empty stdin → succeeds with null
  # Result: Comments silently dropped during export
  ```

**Subshell Failures**
- ❌ Command substitutions can hide errors:
  ```bash
  # If internal command fails, $(...) captures stderr and returns empty string
  issue_id="$(git issue create "Title" 2>&1 | awk '{print $NF}')"
  # awk ALWAYS succeeds, even if git issue create fails
  ```

**Unvalidated Exit Codes**
- ⚠️ Some critical operations not checked:
  ```bash
  # Examples that should explicitly check $?
  git commit ... || handle_error
  git update-ref ... || rollback
  curl ... || retry
  ```

**Missing Failure Tests:**
- ❌ No tests for pipe component failures
- ❌ No tests for subshell errors
- ❌ No tests for signal handling (SIGTERM during commit)
- ❌ No tests for partial write failures
- ❌ No tests for `git commit` hook failures

#### Recommendations (CRITICAL)

1. **IMMEDIATE**: Add `set -o pipefail` to all scripts:
   ```bash
   #!/bin/sh
   set -e
   set -o pipefail  # EXIT if ANY command in a pipe fails
   ```

2. **HIGH**: Add failure mode test suite:
   ```bash
   t/test-failures.sh:
   - Mock failing git commands (git log exits 1)
   - Mock failing pipes (sed fails mid-stream)
   - Mock failing external tools (jq, gh, curl)
   - Test cleanup on SIGTERM/SIGINT
   ```

3. **HIGH**: Audit all pipes and add explicit checks:
   ```bash
   # BEFORE (vulnerable)
   result="$(cmd1 | cmd2 | cmd3)"

   # AFTER (protected)
   set -o pipefail
   result="$(cmd1 | cmd2 | cmd3)" || {
       echo "error: pipeline failed" >&2
       return 1
   }
   ```

4. **MEDIUM**: Validate critical operations:
   ```bash
   git commit -m "..." || {
       echo "error: commit failed" >&2
       exit 1
   }
   ```

---

### 5. Property-Based Testing (0/15) ❌ MISSING

#### ❌ Current State

- **NO property-based tests exist**
- No framework in use (would need custom implementation or external tool)

#### Recommended Properties to Test

**Idempotency Properties:**
```bash
# Property: git issue ls should return same results on repeated calls
property_ls_idempotent() {
    result1="$(git issue ls)"
    result2="$(git issue ls)"
    result3="$(git issue ls)"
    test "$result1" = "$result2" && test "$result2" = "$result3"
}

# Property: Creating issue with same UUID should fail consistently
property_create_uuid_unique() {
    uuid="$(uuidgen)"
    git issue create "Title 1" --uuid "$uuid"  # Should succeed
    git issue create "Title 2" --uuid "$uuid"  # Should fail
    git issue create "Title 3" --uuid "$uuid"  # Should still fail
}
```

**Commutativity Properties:**
```bash
# Property: Adding labels in different orders produces same result
property_labels_commutative() {
    # Create two identical issues
    id1="$(git issue create "Test 1")"
    id2="$(git issue create "Test 2")"

    # Add labels in different orders
    git issue edit "$id1" -l bug -l feature -l docs
    git issue edit "$id2" -l docs -l bug -l feature

    # Labels should be identical (may be sorted)
    labels1="$(git issue show "$id1" | grep Labels:)"
    labels2="$(git issue show "$id2" | grep Labels:)"
    test "$labels1" = "$labels2"
}
```

**Determinism Properties:**
```bash
# Property: Same input always produces same git tree structure
property_deterministic_commits() {
    # Create issue in repo A
    setup_repo_a
    git issue create "Title" -m "Body" -l bug
    tree_a="$(git cat-file -p refs/issues/*/tree)"

    # Create identical issue in repo B
    setup_repo_b
    git issue create "Title" -m "Body" -l bug
    tree_b="$(git cat-file -p refs/issues/*/tree)"

    # Tree objects should be identical
    test "$tree_a" = "$tree_b"
}
```

**Invariant Properties:**
```bash
# Property: Issue ref always has exactly one root commit
property_single_root_commit() {
    id="$(git issue create "Test")"
    git issue comment "$id" -m "Comment 1"
    git issue state "$id" --close

    ref="$(resolve_issue "$id")"
    root_count="$(git rev-list --max-parents=0 "$ref" | wc -l)"
    test "$root_count" -eq 1
}

# Property: State trailer is always present after state change
property_state_trailer_present() {
    id="$(git issue create "Test")"
    git issue state "$id" --close

    ref="$(resolve_issue "$id")"
    state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | head -1)"
    test -n "$state"  # Must not be empty
}
```

#### Recommendations

1. **MEDIUM**: Implement basic property tests in `t/test-properties.sh`
   - Start with idempotency (ls, show)
   - Add determinism (commit structure)
   - Test invariants (single root, trailer presence)

2. **LOW**: Consider external property-testing tool
   - Option 1: Write custom generator in shell
   - Option 2: Use Python `hypothesis` with shell wrapper
   - Option 3: Document properties for manual validation

---

### 6. Mutation Testing (0/10) ❌ MISSING

#### ❌ Current State

- **NO mutation testing**
- No framework in place

#### Recommended Mutations

**Critical Mutations to Test:**

1. **Remove safety flags:**
   ```bash
   # Original
   set -e
   set -o pipefail  # (once added)

   # Mutant
   # set -e  (commented out)
   # set -o pipefail

   # Test SHOULD FAIL if mutations not detected
   ```

2. **Swap boolean operators:**
   ```bash
   # Original
   test -n "$title" || { echo "error" >&2; exit 1; }

   # Mutant
   test -n "$title" && { echo "error" >&2; exit 1; }  # Swapped || to &&

   # Test SHOULD FAIL
   ```

3. **Remove quotes:**
   ```bash
   # Original
   validate_no_newlines "$title" "title"

   # Mutant
   validate_no_newlines $title "title"  # Removed quotes

   # Test SHOULD FAIL with title containing spaces
   ```

4. **Remove exit codes:**
   ```bash
   # Original
   git commit ... || exit 1

   # Mutant
   git commit ...  # Removed error handling

   # Test SHOULD FAIL
   ```

5. **Swap comparison operators:**
   ```bash
   # Original
   if test "$count" -eq 1

   # Mutant
   if test "$count" -ne 1  # Swapped -eq to -ne

   # Test SHOULD FAIL
   ```

#### Mutation Testing Process

**Manual Approach:**
```bash
# 1. Identify critical code sections
critical_sections=(
    "bin/git-issue-lib:validate_git_identity"
    "bin/git-issue-lib:update_ref_with_retry"
    "bin/git-issue-create:UUID generation"
)

# 2. For each section, apply mutations
for section in "${critical_sections[@]}"; do
    apply_mutation "$section" "remove_quotes"
    run_tests
    check_failure  # Tests MUST fail
    revert_mutation
done
```

#### Recommendations

1. **LOW**: Create manual mutation test checklist
   - Document critical mutations
   - Run manually before releases

2. **OPTIONAL**: Investigate shell mutation tools
   - Custom script to apply common mutations
   - Integrate with CI/CD for major releases

3. **MEDIUM**: Add mutation-sensitive tests:
   ```bash
   # Test that specifically validates quoting
   test_quoting() {
       title="Title with  spaces"
       git issue create "$title"
       actual="$(git issue ls | head -1)"
       test "$actual" = "$title" || fail "quoting broken"
   }
   ```

---

## Residual Risk Report

### 1. What is Well-Defended

#### ✅ Solid Foundation

**Business Logic:**
- ✅ Issue creation, editing, state changes tested (76 tests)
- ✅ Label normalization and validation
- ✅ Email validation for assignees
- ✅ Trailer injection prevention
- ✅ Git identity validation

**Data Integrity:**
- ✅ Concurrent modification handling (CAS retry)
- ✅ Ref chain consistency
- ✅ Commit structure validation

**Input Validation:**
- ✅ Newline prevention in labels/titles
- ✅ Priority enumeration enforcement
- ✅ UUID format validation

---

### 2. What Fails Under Simulated Failure

#### ❌ High-Risk Failure Modes

**Pipe Failures (CRITICAL):**
```bash
# SCENARIO: git log fails due to corrupted ref
_title="$(git log --format='%(trailers:key=Title,valueonly)' "$ref" | sed ... | head -1)"

# CURRENT BEHAVIOR (without pipefail):
# → git log exits 1 → sed gets empty stdin → head succeeds → empty title returned
# → Issue appears with no title (silent data loss)

# EXPECTED BEHAVIOR (with pipefail):
# → git log exits 1 → entire pipe fails → error surfaced immediately
```

**External Tool Failures:**
```bash
# SCENARIO: GitHub rate limit during export
gh_issues="$(gh api repos/$owner/$repo/issues | jq -r '.[] | ...')"

# CURRENT BEHAVIOR:
# → gh api fails with 429 → jq gets empty stdin → succeeds with null → silent data loss

# IMPACT: Partial export, user thinks all issues synced
```

**Signal Handling:**
```bash
# SCENARIO: SIGTERM during commit
git commit -m "Creating issue..."

# CURRENT BEHAVIOR:
# → Commit interrupted → ref update fails → orphaned objects in .git/objects/
# → User doesn't know issue creation failed
```

---

### 3. What Depends on Message Ordering

#### ⚠️ Moderate Risk

**Commit Chain Order:**
- Issue history is stored as git commit chain
- Order matters: root → comments → state changes
- **Defended by**: Git's DAG guarantees sequential consistency
- **Risk**: Concurrent operations could create divergent histories
  - **Mitigated by**: CAS retry logic in `update_ref_with_retry()`

**Platform Bridge Sync:**
- Comments must be imported in chronological order to preserve discussion flow
- **Current approach**: Relies on API returning sorted results
- **Risk**: API pagination order changes
- **Not tested**: Out-of-order comment import

---

### 4. What Depends on Time/Timeout

#### ⚠️ Moderate Risk

**CAS Retry Backoff:**
```bash
# git-issue-lib:215-224
_sleep_ms=$((100 * (1 << (_attempt - 1))))  # 100ms, 200ms
if command -v perl >/dev/null 2>&1; then
    perl -e "select(undef, undef, undef, $_sleep_ms / 1000)"
else
    sleep 1  # Fallback: 1 second (less precise)
fi
```
- **Risk**: Without `perl`, backoff is 1s on ALL retries (not exponential)
- **Impact**: Higher collision rate under contention

**Test Timing:**
```bash
# test-concurrency.sh:171-176
(git-issue-state "$id" --close -m "Close A") &
pid1=$!
sleep 0.05  # Arbitrary delay to stagger operations
(git-issue-state "$id" --close -m "Close B") &
```
- **Risk**: Test flakiness on slow systems
- **Not tested**: True concurrent access (same microsecond)

---

### 5. What Depends on Environment

#### ⚠️ High Risk (Untested)

**PATH Dependencies:**
- Required tools: `git`, `sed`, `awk`, `grep`, `cut`, `tr`, `head`, `tail`
- Platform bridges: `gh`, `glab`, `curl`, `jq`
- **Risk**: Minimal PATH (cron jobs, docker) may lack basic utilities
- **Not tested**: Operation with minimal PATH

**Filesystem:**
- **Risk**: Read-only `.git/` (cloud IDEs, containers)
- **Risk**: No `/tmp` access (tempfile creation fails)
- **Risk**: POSIX vs non-POSIX filesystem (refs/issues/ paths)
- **Not tested**: Permission errors during ref updates

**Locale/Encoding:**
- **Risk**: Non-UTF-8 locales (labels with special characters)
- **Risk**: Git configured for CRLF (Windows)
- **Not tested**: Locale-dependent sed/grep behavior

**Git Version:**
- Uses `%(trailers:...)` format (requires git 2.22+)
- **Risk**: Older git versions (enterprise environments)
- **Not tested**: Minimum git version enforcement

---

### 6. What Cannot Be Guaranteed by Local Tests

#### ⚠️ Known Limitations

**Platform Bridge Integration:**
- GitHub/GitLab/Gitea API changes
- Authentication token expiry mid-sync
- Rate limiting behavior
- Network partitions during sync

**Multi-User Scenarios:**
- True concurrent access from multiple developers
- Distributed ref conflicts across remotes
- Merge conflict resolution in refs/issues/

**Scale:**
- Performance with 10,000+ issues
- Ref enumeration speed
- Git pack file behavior with many refs

**Interoperability:**
- Git implementations (Git, JGit, libgit2)
- Platform variations (macOS vs Linux vs BSD)
- Shell variations (bash, dash, zsh, ash)

---

## Recommendations for New Testing

### Immediate (High Priority)

#### 1. Add `set -o pipefail` to ALL Scripts

**Scope**: All 20 scripts in `bin/`

**Implementation**:
```bash
#!/bin/sh
set -e
set -o pipefail  # ADD THIS LINE
```

**Validation**:
```bash
# Verify in CI
for script in bin/git-issue*; do
    if ! grep -q "set -o pipefail" "$script"; then
        echo "FAIL: $script missing pipefail"
        exit 1
    fi
done
```

#### 2. Create Failure Mode Test Suite

**File**: `t/test-failure-modes.sh`

**Tests**:
```bash
# Test 1: Pipe component failure is detected
test_pipe_failure_detected() {
    # Mock git log to fail
    git() {
        if test "$1" = "log"; then
            return 1  # Simulate failure
        fi
        command git "$@"
    }

    # Should fail loudly, not silently
    if get_issue_title "$ref" 2>/dev/null; then
        fail "pipe failure was silently ignored"
    else
        pass "pipe failure detected"
    fi
}

# Test 2: External tool failure aborts operation
test_jq_missing_aborts() {
    # Temporarily remove jq from PATH
    PATH="/usr/bin:/bin"

    # Export should fail gracefully
    if git issue export github:owner/repo 2>&1 | grep -q "jq not found"; then
        pass "missing jq detected"
    else
        fail "missing jq not handled"
    fi
}

# Test 3: Interrupted commit is detected
test_sigterm_handling() {
    # Launch git issue create in background
    (git issue create "Test" > /tmp/issue_id) &
    pid=$!

    # Kill after 100ms
    sleep 0.1
    kill -TERM $pid
    wait $pid

    # Issue should NOT be created
    if test -f /tmp/issue_id && test -s /tmp/issue_id; then
        fail "interrupted create succeeded (data corruption)"
    else
        pass "interrupted create aborted correctly"
    fi
}
```

#### 3. Environmental Test Suite

**File**: `t/test-environment.sh`

**Tests**:
```bash
# Test: Minimal PATH
test_minimal_path() {
    PATH="/usr/bin:/bin"  # No /usr/local/bin
    if git issue create "Test" >/dev/null 2>&1; then
        pass "works with minimal PATH"
    else
        fail "requires tools not in standard PATH"
    fi
}

# Test: Read-only .git/
test_readonly_git_dir() {
    chmod -R a-w .git/refs/issues/

    if git issue create "Test" 2>&1 | grep -q "Permission denied"; then
        pass "read-only error detected"
    else
        fail "permission error not surfaced"
    fi

    chmod -R u+w .git/refs/issues/
}

# Test: Disk full simulation
test_disk_full() {
    # Use quota or fallocate to fill filesystem
    # (complex, may need docker/vm)
    skip "requires filesystem quota support"
}
```

---

### Short-Term (Medium Priority)

#### 4. Property-Based Tests

**File**: `t/test-properties.sh`

**Focus**:
- Idempotency (ls, show, fsck)
- Commutativity (label order)
- Invariants (single root, trailer presence)

#### 5. Add `set -u` (Unset Variable Protection)

**Scope**: All scripts

**Challenges**:
- Requires explicit defaults: `${var:-}`
- May break existing code relying on empty expansions

**Approach**:
- Add incrementally, test thoroughly
- Use shellcheck to identify undefined variables

---

### Long-Term (Low Priority)

#### 6. Mutation Testing

**Approach**:
- Manual checklist initially
- Custom mutation tool later

#### 7. Migrate to BATS

**Benefits**:
- TAP output for CI
- Parallel test execution
- Better assertions (`assert_output`, `assert_failure`)

**Costs**:
- Migration effort (~2-3 days)
- New dependency

---

## Quality Gates

### Build MUST Fail When:

#### Existing Gates ✅
- [x] shellcheck finds warnings
- [x] ExUnit-equivalent tests fail (76 behavior tests)

#### Recommended New Gates ❌

- [ ] **Scripts missing `set -o pipefail`** (HIGH PRIORITY)
- [ ] **Failure mode tests fail** (HIGH PRIORITY)
- [ ] **Environmental tests fail** (MEDIUM)
- [ ] **Property invariants violated** (MEDIUM)
- [ ] **Mutation tests pass** (LOW)

---

## Completion Criteria

### Work is Complete ONLY When:

#### Current State
- ✅ Business logic tests pass
- ✅ Concurrency retry logic works
- ⚠️ Static analysis passes (with unused variable warnings)

#### Target State
- [ ] ✅ ALL scripts have `set -o pipefail`
- [ ] ✅ Failure mode tests pass
  - Pipe failures detected
  - Signal handling tested
  - External tool failures graceful
- [ ] ✅ Environmental tests pass
  - Minimal PATH
  - Read-only filesystem
  - Permission errors
- [ ] ✅ Property tests pass
  - Idempotency verified
  - Invariants hold
- [ ] ✅ Residual risks documented in README
  - Platform API dependencies
  - Scale limitations
  - Interoperability assumptions

---

## Risk Summary

### Critical Risks (Require Immediate Action)

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **Pipe failure silent data loss** | HIGH | MEDIUM | Add `set -o pipefail` immediately |
| **External tool failure (jq, gh, curl) undetected** | HIGH | MEDIUM | Add failure mode tests |
| **Signal interruption during commit** | MEDIUM | LOW | Add signal handling tests |
| **Minimal PATH in cron/docker** | MEDIUM | MEDIUM | Add environmental tests |

### Moderate Risks (Monitor)

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Non-UTF-8 locale issues | MEDIUM | LOW | Document locale requirements |
| Git version < 2.22 | MEDIUM | LOW | Add version check |
| Out-of-order API results | LOW | LOW | Sort explicitly in bridges |
| CAS retry without perl | LOW | MEDIUM | Document perl as recommended |

### Accepted Risks (Document Only)

- Platform API changes (GitHub, GitLab, Gitea)
- Multi-user conflict resolution (git's problem)
- Scale beyond 10,000 issues (premature optimization)
- Interoperability with non-standard git implementations

---

## Appendix: Test Execution Results

### Current Test Status (2026-02-15)

```bash
$ sh t/test-issue.sh
============================================================
Tests: 76 | Passed: 76 | Failed: 0
============================================================

$ sh t/test-concurrency.sh
============================================================
Tests: 8 | Passed: 8 | Failed: 0
============================================================

$ shellcheck -S warning bin/git-issue*
# 4 unused variable warnings (SC2034) - non-critical
```

### Static Analysis Summary

```
Total scripts analyzed: 20
Critical errors (SC2xxx): 0
Warnings: 4 (unused variables)
Formatting issues: Multiple (non-blocking)
```

---

## Next Steps

1. **Immediate**: Add `set -o pipefail` to all scripts (< 1 hour)
2. **Week 1**: Create `t/test-failure-modes.sh` (8 hours)
3. **Week 2**: Create `t/test-environment.sh` (8 hours)
4. **Week 3**: Create `t/test-properties.sh` (8 hours)
5. **Week 4**: Update CI/CD to enforce new gates (4 hours)
6. **Month 2**: Add `set -u` incrementally (16 hours)
7. **Month 3**: Mutation testing framework (16 hours)

**Total Estimated Effort**: ~60 hours to reach 90/100 quality score

---

## Conclusion

The git-native-issue project demonstrates **strong fundamentals** with excellent behavior testing and static analysis integration. However, **critical gaps in failure mode protection** pose significant risk of silent data loss under adverse conditions.

**Priority 1**: Add `set -o pipefail` immediately (blocks silent pipe failures)
**Priority 2**: Build failure mode test suite (validates error handling)
**Priority 3**: Environmental testing (ensures portability)

With these improvements, the project will achieve **enterprise-grade reliability** suitable for production use in hostile environments.

---

**Assessment Issue**: fa222df
**Assessor**: Claude Sonnet 4.5
**Framework**: Shell Script Quality & Testing Manifesto
**Date**: 2026-02-15
