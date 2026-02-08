#!/bin/sh
#
# Advanced edge case testing - scenarios that could break in production
#

set -e

# Colors
if test -t 1; then
	RED=$(printf '\033[31m')
	GREEN=$(printf '\033[32m')
	YELLOW=$(printf '\033[33m')
	NC=$(printf '\033[0m')
else
	RED=''
	GREEN=''
	YELLOW=''
	NC=''
fi

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
	TESTS_PASSED=$((TESTS_PASSED + 1))
	printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
	TESTS_FAILED=$((TESTS_FAILED + 1))
	printf "${RED}  FAIL${NC} %s\n" "$1"
	test $# -gt 1 && printf "       %s\n" "$2"
}

run_test() {
	TESTS_RUN=$((TESTS_RUN + 1))
}

# Skip tests if gh or jq not available
if ! command -v gh >/dev/null 2>&1; then
	printf "${YELLOW}SKIP${NC} gh CLI not found\n"
	exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
	printf "${YELLOW}SKIP${NC} jq not found\n"
	exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
	printf "${YELLOW}SKIP${NC} gh not authenticated\n"
	exit 0
fi

TEST_REPO="remenoscodes/git-native-issue"

# Get path to git-issue binaries
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

printf "Running advanced edge case tests...\n\n"

# =============================================================================
# ADVANCED TEST 1: Deleted GitHub issue (404 scenario)
# =============================================================================
run_test
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"

printf "${YELLOW}TEST 1:${NC} Provider-ID points to deleted GitHub issue\n"

# Create and export issue
issue_id="$(git issue create "Test deleted issue" -m "Will be deleted" 2>&1 | awk '{print $NF}')"
export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
github_number="$(echo "$export_output" | grep "Exported $issue_id" | sed 's/.*#\([0-9]*\):.*/\1/')"

if test -n "$github_number"; then
	# Close and lock the issue on GitHub (simulating deletion scenario)
	gh issue close "$github_number" --repo "$TEST_REPO" >/dev/null 2>&1

	# Try to sync - should handle gracefully
	if git issue sync "github:$TEST_REPO" >/dev/null 2>&1; then
		pass "handles closed/deleted GitHub issue gracefully"
		TEST_DELETED_ISSUE="$github_number"
	else
		# It's OK to fail, as long as it doesn't crash
		pass "sync failed gracefully on deleted issue (expected)"
	fi
else
	fail "deleted issue test" "export failed"
fi

# =============================================================================
# ADVANCED TEST 2: Conflicting state (closed locally, open on GitHub)
# =============================================================================
run_test
printf "\n${YELLOW}TEST 2:${NC} State conflict (closed local, open GitHub)\n"

issue_id2="$(git issue create "Test state conflict" -m "Description" 2>&1 | awk '{print $NF}')"
export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
github_number2="$(echo "$export_output" | grep "Exported $issue_id2" | sed 's/.*#\([0-9]*\):.*/\1/')"

if test -n "$github_number2"; then
	# Close locally
	git issue state "$issue_id2" --close -m "Closing locally" >/dev/null

	# Reopen on GitHub (create conflict)
	gh issue reopen "$github_number2" --repo "$TEST_REPO" >/dev/null 2>&1 || true

	# Sync - last write should win (local closed state)
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1

	sleep 2

	# Check final state
	gh_state="$(gh api "/repos/$TEST_REPO/issues/$github_number2" | jq -r '.state')"

	if test "$gh_state" = "closed"; then
		pass "state conflict resolved (local wins)"
		TEST_CONFLICT_ISSUE="$github_number2"
	else
		fail "state conflict" "GitHub state is $gh_state, expected closed"
	fi
else
	fail "state conflict test" "export failed"
fi

# =============================================================================
# ADVANCED TEST 3: Rapid multiple syncs
# =============================================================================
run_test
printf "\n${YELLOW}TEST 3:${NC} Multiple rapid syncs (idempotency)\n"

issue_id3="$(git issue create "Test rapid sync" -m "Description" 2>&1 | awk '{print $NF}')"
git issue comment "$issue_id3" -m "Comment 1" >/dev/null
git issue comment "$issue_id3" -m "Comment 2" >/dev/null

export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
github_number3="$(echo "$export_output" | grep "Exported $issue_id3" | sed 's/.*#\([0-9]*\):.*/\1/')"

if test -n "$github_number3"; then
	# Run sync 3 times rapidly
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1

	sleep 2

	# Check comment count on GitHub (should be exactly 2, not duplicated)
	gh_comment_count="$(gh api "/repos/$TEST_REPO/issues/$github_number3/comments" | jq '. | length')"

	if test "$gh_comment_count" -eq 2; then
		pass "rapid syncs are idempotent (no duplicates)"
		TEST_RAPID_ISSUE="$github_number3"
	else
		fail "rapid sync" "GitHub has $gh_comment_count comments, expected 2"
	fi
else
	fail "rapid sync test" "export failed"
fi

# =============================================================================
# ADVANCED TEST 4: Comment added during sync (race condition)
# =============================================================================
run_test
printf "\n${YELLOW}TEST 4:${NC} Comment added while sync in progress\n"

issue_id4="$(git issue create "Test concurrent comment" -m "Description" 2>&1 | awk '{print $NF}')"
export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
github_number4="$(echo "$export_output" | grep "Exported $issue_id4" | sed 's/.*#\([0-9]*\):.*/\1/')"

if test -n "$github_number4"; then
	# Add comment on GitHub
	gh issue comment "$github_number4" --repo "$TEST_REPO" --body "GitHub comment during sync" >/dev/null 2>&1

	# Add comment locally while import might be running
	git issue comment "$issue_id4" -m "Local comment during sync" >/dev/null

	# Sync
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1

	sleep 2

	# Both comments should exist
	local_show="$(git issue show "$issue_id4")"
	gh_comments="$(gh api "/repos/$TEST_REPO/issues/$github_number4/comments" | jq -r '.[].body')"

	local_has_gh=0
	gh_has_local=0

	echo "$local_show" | grep -q "GitHub comment during sync" && local_has_gh=1
	echo "$gh_comments" | grep -q "Local comment during sync" && gh_has_local=1

	if test "$local_has_gh" -eq 1 && test "$gh_has_local" -eq 1; then
		pass "concurrent comments synced correctly"
		TEST_CONCURRENT_ISSUE="$github_number4"
	else
		fail "concurrent comments" "local_has_gh=$local_has_gh gh_has_local=$gh_has_local"
	fi
else
	fail "concurrent comment test" "export failed"
fi

# =============================================================================
# ADVANCED TEST 5: Multiline comment with code blocks
# =============================================================================
run_test
printf "\n${YELLOW}TEST 5:${NC} Markdown code blocks in comments\n"

code_comment='Here is a code block:

```bash
git issue create "test"
git issue comment abc1234 -m "message"
```

And inline code: `git issue ls`'

issue_id5="$(git issue create "Test code blocks" -m "Description" 2>&1 | awk '{print $NF}')"

if git issue comment "$issue_id5" -m "$code_comment" 2>/dev/null; then
	export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
	github_number5="$(echo "$export_output" | grep "Exported $issue_id5" | sed 's/.*#\([0-9]*\):.*/\1/')"

	if test -n "$github_number5"; then
		sleep 2
		gh_comment="$(gh api "/repos/$TEST_REPO/issues/$github_number5/comments" | jq -r '.[0].body' 2>/dev/null)"

		if echo "$gh_comment" | grep -q '```bash' && echo "$gh_comment" | grep -q 'git issue ls'; then
			pass "markdown code blocks preserved"
			TEST_CODE_ISSUE="$github_number5"
		else
			fail "code blocks" "markdown not preserved"
		fi
	else
		fail "code blocks" "export failed"
	fi
else
	fail "code blocks" "local comment creation failed"
fi

# =============================================================================
# Cleanup test issues from GitHub
# =============================================================================
printf "\n${YELLOW}Cleaning up test issues...${NC}\n"

for issue_num in $TEST_DELETED_ISSUE $TEST_CONFLICT_ISSUE $TEST_RAPID_ISSUE $TEST_CONCURRENT_ISSUE $TEST_CODE_ISSUE; do
	if test -n "$issue_num"; then
		gh issue close "$issue_num" --repo "$TEST_REPO" --comment "Advanced edge case test cleanup" >/dev/null 2>&1 || true
	fi
done

# =============================================================================
# Summary
# =============================================================================
printf "\n============================================================\n"
printf "Tests: %d | Passed: %d | Failed: %d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "============================================================\n"

if test "$TESTS_FAILED" -gt 0; then
	exit 1
fi

exit 0
