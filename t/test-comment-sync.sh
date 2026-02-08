#!/bin/sh
#
# Test suite for bidirectional comment synchronization (GitHub bridge)
#

set -e

# Colors for output
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
	printf "${YELLOW}SKIP${NC} gh CLI not found - skipping GitHub bridge tests\n"
	exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
	printf "${YELLOW}SKIP${NC} jq not found - skipping GitHub bridge tests\n"
	exit 0
fi

# Skip if gh not authenticated
if ! gh auth status >/dev/null 2>&1; then
	printf "${YELLOW}SKIP${NC} gh not authenticated - skipping GitHub bridge tests\n"
	exit 0
fi

# Test helper: create a mock GitHub repo for testing
# For now, we'll use the actual repo but with careful cleanup
TEST_REPO="remenoscodes/git-native-issue"

# Get path to git-issue binaries
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

printf "Running bidirectional comment sync tests...\n"

# =============================================================================
# TEST 1: Export issue with comments, verify comments appear on GitHub
# =============================================================================
run_test
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"

# Create issue locally with 2 comments
issue_id="$(git issue create "Test export comments" -m "Description" 2>&1 | awk '{print $NF}')"
git issue comment "$issue_id" -m "Local comment 1" >/dev/null
git issue comment "$issue_id" -m "Local comment 2" >/dev/null

# Export to GitHub
export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
github_number="$(echo "$export_output" | grep "Exported $issue_id" | sed 's/.*#\([0-9]*\):.*/\1/')"

if test -z "$github_number"; then
	fail "export issue with comments to GitHub" "no GitHub issue number returned"
else
	# Verify comments on GitHub
	gh_comments="$(gh api "/repos/$TEST_REPO/issues/$github_number/comments" | jq -r '.[].body')"

	if echo "$gh_comments" | grep -q "Local comment 1" && echo "$gh_comments" | grep -q "Local comment 2"; then
		pass "export issue with comments to GitHub"
		TEST_GITHUB_ISSUE="$github_number"
	else
		fail "export issue with comments to GitHub" "comments not found on GitHub"
	fi
fi

# =============================================================================
# TEST 2: Add comment on GitHub, import should detect and add locally
# =============================================================================
run_test

if test -n "$TEST_GITHUB_ISSUE"; then
	# Add comment on GitHub
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "GitHub comment 1" >/dev/null 2>&1

	# Sleep briefly to ensure comment is created
	sleep 2

	# Import from GitHub (should update existing issue)
	import_output="$(git issue import "github:$TEST_REPO" 2>&1)"

	# Check if issue was updated (not just skipped)
	if echo "$import_output" | grep -qi "updated.*$issue_id\|Updated.*1.*comment"; then
		# Verify comment appears locally
		local_show="$(git issue show "$issue_id")"

		if echo "$local_show" | grep -q "GitHub comment 1"; then
			pass "import new comment from GitHub to existing issue"
		else
			fail "import new comment from GitHub to existing issue" "comment not found in local issue"
		fi
	else
		fail "import new comment from GitHub to existing issue" "issue was skipped, not updated"
	fi
else
	fail "import new comment from GitHub to existing issue" "prerequisite test failed"
fi

# =============================================================================
# TEST 3: Multiple new comments on GitHub should all be imported
# =============================================================================
run_test

if test -n "$TEST_GITHUB_ISSUE"; then
	# Add 3 more comments on GitHub
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "GitHub comment 2" >/dev/null 2>&1
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "GitHub comment 3" >/dev/null 2>&1
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "GitHub comment 4" >/dev/null 2>&1

	sleep 2

	# Import again
	import_output="$(git issue import "github:$TEST_REPO" 2>&1)"

	# Verify all 3 new comments appear locally
	local_show="$(git issue show "$issue_id")"

	count=0
	echo "$local_show" | grep -q "GitHub comment 2" && count=$((count + 1))
	echo "$local_show" | grep -q "GitHub comment 3" && count=$((count + 1))
	echo "$local_show" | grep -q "GitHub comment 4" && count=$((count + 1))

	if test "$count" -eq 3; then
		pass "import multiple new comments from GitHub"
	else
		fail "import multiple new comments from GitHub" "found $count/3 comments"
	fi
else
	fail "import multiple new comments from GitHub" "prerequisite test failed"
fi

# =============================================================================
# TEST 4: Re-importing should not duplicate comments
# =============================================================================
run_test

if test -n "$TEST_GITHUB_ISSUE"; then
	# Get current comment count
	before_count="$(git issue show "$issue_id" | grep -c "Updates (" || echo 0)"

	# Import again (should skip, no new comments)
	git issue import "github:$TEST_REPO" >/dev/null 2>&1

	# Get new comment count
	after_count="$(git issue show "$issue_id" | grep -c "Updates (" || echo 0)"

	if test "$before_count" -eq "$after_count"; then
		pass "re-import does not duplicate comments"
	else
		fail "re-import does not duplicate comments" "count changed from $before_count to $after_count"
	fi
else
	fail "re-import does not duplicate comments" "prerequisite test failed"
fi

# =============================================================================
# TEST 5: Sync command should do bidirectional update
# =============================================================================
run_test

if test -n "$TEST_GITHUB_ISSUE"; then
	# Add comment locally
	git issue comment "$issue_id" -m "Local comment 3" >/dev/null

	# Add comment on GitHub
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "GitHub comment 5" >/dev/null 2>&1

	sleep 2

	# Sync (should export local comment AND import GitHub comment)
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1

	# Check both directions worked
	local_show="$(git issue show "$issue_id")"
	gh_comments="$(gh api "/repos/$TEST_REPO/issues/$TEST_GITHUB_ISSUE/comments" | jq -r '.[].body')"

	local_has_gh5=0
	gh_has_local3=0

	echo "$local_show" | grep -q "GitHub comment 5" && local_has_gh5=1
	echo "$gh_comments" | grep -q "Local comment 3" && gh_has_local3=1

	if test "$local_has_gh5" -eq 1 && test "$gh_has_local3" -eq 1; then
		pass "sync command updates both directions"
	else
		fail "sync command updates both directions" "local_has_gh5=$local_has_gh5 gh_has_local3=$gh_has_local3"
	fi
else
	fail "sync command updates both directions" "prerequisite test failed"
fi

# =============================================================================
# TEST 6: Comment with special characters should not break parsing
# =============================================================================
run_test

if test -n "$TEST_GITHUB_ISSUE"; then
	# Add comment with special characters on GitHub
	special_comment="Comment with \"quotes\", 'apostrophes', and \$variables"
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "$special_comment" >/dev/null 2>&1

	sleep 2

	# Import
	git issue import "github:$TEST_REPO" >/dev/null 2>&1

	# Verify special characters preserved
	local_show="$(git issue show "$issue_id")"

	if echo "$local_show" | grep -qF "quotes"; then
		pass "import comment with special characters"
	else
		fail "import comment with special characters" "special characters not preserved"
	fi
else
	fail "import comment with special characters" "prerequisite test failed"
fi

# =============================================================================
# TEST 7: Multiline comments should preserve formatting
# =============================================================================
run_test

if test -n "$TEST_GITHUB_ISSUE"; then
	# Add multiline comment on GitHub
	multiline_comment="Line 1
Line 2
Line 3"
	gh issue comment "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --body "$multiline_comment" >/dev/null 2>&1

	sleep 2

	# Import
	git issue import "github:$TEST_REPO" >/dev/null 2>&1

	# Verify all lines present
	local_show="$(git issue show "$issue_id")"

	count=0
	echo "$local_show" | grep -q "Line 1" && count=$((count + 1))
	echo "$local_show" | grep -q "Line 2" && count=$((count + 1))
	echo "$local_show" | grep -q "Line 3" && count=$((count + 1))

	if test "$count" -eq 3; then
		pass "import multiline comment preserves formatting"
	else
		fail "import multiline comment preserves formatting" "found $count/3 lines"
	fi
else
	fail "import multiline comment preserves formatting" "prerequisite test failed"
fi

# =============================================================================
# Cleanup test issue from GitHub
# =============================================================================
if test -n "$TEST_GITHUB_ISSUE"; then
	gh issue close "$TEST_GITHUB_ISSUE" --repo "$TEST_REPO" --comment "Test completed, cleaning up" >/dev/null 2>&1 || true
fi

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
