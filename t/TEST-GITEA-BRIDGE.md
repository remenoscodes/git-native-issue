# Gitea/Forgejo Bridge Test Suite

Comprehensive test suite for the Gitea and Forgejo bridge implementation in git-native-issue.

## Files Created

### 1. `test-gitea-bridge.sh`
Main test suite with **30+ comprehensive tests** covering:

#### Import Tests (25 tests)
- Basic import functionality
- Issue title and body preservation
- Provider-ID trailer format (`gitea:https://...`)
- Format-Version trailer
- Labels preservation
- Assignee handling (single and multiple)
- State mapping (open/closed)
- Comment import as child commits
- Provider-Comment-ID trailers
- Idempotency (re-import detection)
- State filtering (`--state open`, `--state closed`, `--state all`)
- Dry-run mode
- Empty body handling
- Invalid provider string error handling
- Outside git repo error handling
- Empty tree verification
- UUID-based ref naming
- Unicode support (emoji, multi-byte characters)
- Long text handling (1500+ characters)
- New comment detection and update
- Forgejo-specific field handling
- Multiple assignees (Gitea extension)
- Markdown character preservation

#### Mock API Testing
- Simulates Gitea/Forgejo API responses
- Mock `curl` command for isolated testing
- Fixture-based JSON responses
- No external dependencies required

### 2. `test-integration-gitea.sh`
Optional integration test for **real Gitea/Forgejo instances**:

#### Integration Tests (10 tests)
1. Import from real Gitea instance
2. Verify local refs created
3. Verify issue metadata (trailers)
4. Verify Provider-ID format
5. Test idempotency (no duplicates)
6. Verify empty tree for all commits
7. Verify comment import
8. Verify state mapping (open/closed)
9. Verify UUID-based refs
10. Test dry-run mode

#### Requirements
- Real Gitea or Forgejo instance
- Valid API token
- Environment variables:
  - `GITEA_URL` - Instance URL (e.g., https://gitea.example.com)
  - `GITEA_TOKEN` - API authentication token
  - `GITEA_REPO` - Repository path (e.g., owner/repo)

### 3. Fixture Files
Created in `t/fixtures/`:

- `gitea-issues-all.json` - Sample of 3 issues (open + closed)
- `gitea-issues-open.json` - Sample of 2 open issues
- `gitea-issue-1-comments.json` - 2 comments for issue #1
- `gitea-issue-3-comments.json` - 1 comment for issue #3

#### Fixture Data Structure
Based on Gitea/Forgejo API v1 format:

```json
{
  "number": 1,
  "title": "Issue title",
  "state": "open",
  "body": "Issue description",
  "created_at": "2025-04-01T09:00:00Z",
  "updated_at": "2025-04-02T11:30:00Z",
  "user": {
    "login": "username",
    "full_name": "User Name",
    "email": "user@example.com"
  },
  "labels": [{"name": "bug"}],
  "assignee": {
    "login": "assignee",
    "full_name": "Assignee Name",
    "email": "assignee@example.com"
  }
}
```

## Running the Tests

### Mock Tests (Recommended for CI/CD)
```bash
# From repository root
sh t/test-gitea-bridge.sh
```

**No external dependencies required** - uses mock curl and fixture files.

### Integration Tests (Optional)
```bash
# Set up environment
export GITEA_URL="https://your-gitea.com"
export GITEA_TOKEN="your-api-token-here"
export GITEA_REPO="owner/repo"

# Run integration tests
sh t/test-integration-gitea.sh
```

## Test Coverage Summary

| Category | Tests | Description |
|----------|-------|-------------|
| **Import Basics** | 8 | Core import functionality, refs, titles, metadata |
| **Metadata** | 6 | Provider-ID, Format-Version, labels, assignees, state |
| **Comments** | 3 | Comment import, Provider-Comment-ID, updates |
| **Filtering** | 3 | State filtering (open/closed/all) |
| **Edge Cases** | 7 | Unicode, long text, markdown, empty body, special chars |
| **Error Handling** | 3 | Invalid input, outside repo, missing dependencies |
| **Idempotency** | 2 | Re-import detection, no duplicates |
| **Gitea/Forgejo Specific** | 3 | Forgejo fields, multiple assignees, API compatibility |
| **Total Mock Tests** | **30+** | Comprehensive coverage with no external dependencies |
| **Integration Tests** | **10** | Real instance validation (optional) |

## Key Differences from GitLab Bridge

1. **API Access Method**
   - GitLab: Uses `glab` CLI tool
   - Gitea/Forgejo: Uses direct `curl` to REST API

2. **Provider-ID Format**
   - GitLab: `gitlab:group/project#123`
   - Gitea: `gitea:https://gitea.example.com/owner/repo#123`

3. **State Names**
   - GitLab: `opened` / `closed`
   - Gitea: `open` / `closed`

4. **Multiple Assignees**
   - GitLab: Supports multiple via `assignees` array
   - Gitea: Also supports via `assignees` array (Gitea extension)

5. **Comment ID Format**
   - GitLab: `gitlab:group/project#note-123`
   - Gitea: `gitea:https://gitea.example.com/owner/repo#comment-123`

## Mock Architecture

The mock `curl` command intercepts API calls and returns fixture data based on the endpoint pattern:

```bash
# Example API endpoints mocked:
repos/testowner/testrepo/issues?state=open
repos/testowner/testrepo/issues?state=closed
repos/testowner/testrepo/issues?state=all
repos/testowner/testrepo/issues/1/comments
repos/testowner/testrepo/issues/2/comments
version
```

This allows **100% isolated testing** without requiring a real Gitea/Forgejo instance.

## Test Patterns

### Pattern 1: Basic Import Test
```bash
run_test
setup_repo
git issue import gitea:https://gitea.example.com/testowner/testrepo --state all
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 3
then
    pass "import creates correct number of refs"
else
    fail "import creates correct number of refs" "expected 3, got $ref_count"
fi
```

### Pattern 2: Metadata Verification
```bash
run_test
root="$(git rev-list --max-parents=0 "$ref")"
pid="$(git log -1 --format='%(trailers:key=Provider-ID,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
if test "$pid" = "gitea:https://gitea.example.com/testowner/testrepo#1"
then
    pass "Provider-ID format correct"
else
    fail "Provider-ID format correct" "got: '$pid'"
fi
```

### Pattern 3: Edge Case Testing
```bash
run_test
setup_repo
# Create custom mock with edge case data
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF'
#!/bin/sh
printf '[{"number":50,"title":"Unicode: 日本語 🎉","body":"Test","...}]\n'
MOCKEOF
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:https://gitea.example.com/testowner/testrepo
# Verify unicode preserved...
```

## Future Enhancements

Potential additions for future test coverage:

1. **Export Tests** (when export bridge is implemented)
   - Create issues via API
   - Update state via API
   - Export comments
   - Dry-run export mode

2. **Sync Tests** (when sync is implemented)
   - Bidirectional sync
   - Conflict resolution
   - 3+ consecutive syncs

3. **Performance Tests**
   - Large issue sets (100+ issues)
   - Large comment threads (50+ comments)
   - Pagination handling

4. **Error Handling**
   - Network failures
   - API rate limiting
   - Invalid JSON responses
   - Authentication failures

## Notes

- All tests use the **empty tree** for commits (following v2 architecture)
- All issues use **UUID-based refs** (not sequential IDs)
- Tests are **POSIX-compliant shell** (works on Linux, macOS, BSD)
- **No external dependencies** beyond git, jq, and standard POSIX utilities
- Tests follow the same pattern as `test-gitlab-bridge.sh` for consistency

## Integration with CI/CD

Recommended CI/CD setup:

```yaml
# .github/workflows/test.yml
test-gitea-bridge:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - name: Install jq
      run: sudo apt-get install -y jq
    - name: Run Gitea/Forgejo bridge tests
      run: sh t/test-gitea-bridge.sh
```

No secrets or external services required for mock tests!
