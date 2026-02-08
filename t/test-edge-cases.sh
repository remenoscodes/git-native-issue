#!/bin/sh
#
# Edge case exploratory testing for GitHub bridge
# Tests scenarios that might break in production
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

printf "Running edge case tests...\n\n"

# =============================================================================
# EDGE CASE 1: Empty comment
# =============================================================================
run_test
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"

printf "${YELLOW}TEST 1:${NC} Empty comment handling\n"

# Create issue with empty comment attempt
issue_id="$(git issue create "Test empty comment" -m "Description" 2>&1 | awk '{print $NF}')"

# Try to add empty comment (should fail gracefully)
if git issue comment "$issue_id" -m "" 2>/dev/null; then
	fail "empty comment" "should reject empty comments"
else
	pass "empty comment rejected with error"
fi

# =============================================================================
# EDGE CASE 2: Very long comment (>5000 chars)
# =============================================================================
run_test
printf "\n${YELLOW}TEST 2:${NC} Very long comment (5000+ chars)\n"

long_comment="$(printf 'A%.0s' $(seq 1 5000))"
issue_id2="$(git issue create "Test long comment" -m "Description" 2>&1 | awk '{print $NF}')"

if git issue comment "$issue_id2" -m "$long_comment" 2>/dev/null; then
	# Export to GitHub and verify
	export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
	github_number="$(echo "$export_output" | grep "Exported $issue_id2" | sed 's/.*#\([0-9]*\):.*/\1/')"

	if test -n "$github_number"; then
		# Check comment on GitHub
		gh_comment="$(gh api "/repos/$TEST_REPO/issues/$github_number/comments" | jq -r '.[0].body' 2>/dev/null)"

		if test ${#gh_comment} -ge 5000; then
			pass "long comment (5000+ chars) synced correctly"
			TEST_LONG_ISSUE="$github_number"
		else
			fail "long comment" "GitHub comment truncated: ${#gh_comment} chars"
		fi
	else
		fail "long comment" "export failed"
	fi
else
	fail "long comment" "local comment creation failed"
fi

# =============================================================================
# EDGE CASE 3: Unicode and emojis
# =============================================================================
run_test
printf "\n${YELLOW}TEST 3:${NC} Unicode and emoji handling\n"

unicode_comment="Testing Unicode: 你好世界 مرحبا العالم שלום עולם 🚀🎉✨"
issue_id3="$(git issue create "Test Unicode" -m "Unicode test" 2>&1 | awk '{print $NF}')"

if git issue comment "$issue_id3" -m "$unicode_comment" 2>/dev/null; then
	export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
	github_number="$(echo "$export_output" | grep "Exported $issue_id3" | sed 's/.*#\([0-9]*\):.*/\1/')"

	if test -n "$github_number"; then
		sleep 2
		gh_comment="$(gh api "/repos/$TEST_REPO/issues/$github_number/comments" | jq -r '.[0].body' 2>/dev/null)"

		if echo "$gh_comment" | grep -q "你好世界" && echo "$gh_comment" | grep -q "🚀"; then
			pass "unicode and emojis preserved"
			TEST_UNICODE_ISSUE="$github_number"
		else
			fail "unicode and emojis" "characters corrupted or missing"
		fi
	else
		fail "unicode and emojis" "export failed"
	fi
else
	fail "unicode and emojis" "local comment creation failed"
fi

# =============================================================================
# EDGE CASE 4: Comment with trailer-like lines in body
# =============================================================================
run_test
printf "\n${YELLOW}TEST 4:${NC} Comment with trailer-like content\n"

trailer_comment="This is a comment.

State: This is not a real trailer
Labels: bug, feature
Provider-ID: This looks like metadata but isn't"

issue_id4="$(git issue create "Test trailer-like content" -m "Description" 2>&1 | awk '{print $NF}')"

# This should be rejected by git-issue-comment
if git issue comment "$issue_id4" -m "$trailer_comment" 2>/dev/null; then
	fail "trailer-like content" "should reject comments with trailer-like lines"
else
	pass "trailer-like content rejected correctly"
fi

# =============================================================================
# EDGE CASE 5: Sync of closed issue
# =============================================================================
run_test
printf "\n${YELLOW}TEST 5:${NC} Sync closed issue state\n"

issue_id5="$(git issue create "Test closed sync" -m "Will be closed" 2>&1 | awk '{print $NF}')"
export_output="$(git issue export "github:$TEST_REPO" 2>&1)"
github_number="$(echo "$export_output" | grep "Exported $issue_id5" | sed 's/.*#\([0-9]*\):.*/\1/')"

if test -n "$github_number"; then
	# Close locally
	git issue state "$issue_id5" --close -m "Closing for test" >/dev/null

	# Sync to GitHub
	git issue sync "github:$TEST_REPO" >/dev/null 2>&1

	sleep 2

	# Check GitHub state
	gh_state="$(gh api "/repos/$TEST_REPO/issues/$github_number" | jq -r '.state')"

	if test "$gh_state" = "closed"; then
		pass "closed state synced to GitHub"
		TEST_CLOSED_ISSUE="$github_number"
	else
		fail "closed state sync" "GitHub state is $gh_state, expected closed"
	fi
else
	fail "closed state sync" "export failed"
fi

# =============================================================================
# EDGE CASE 6: Special characters in comment
# =============================================================================
run_test
printf "\n${YELLOW}TEST 6:${NC} Special shell characters\n"

special_comment='Comment with $SHELL_VAR and `backticks` and $(command) and "quotes" and '\''single'\'' quotes'
issue_id6="$(git issue create "Test special chars" -m "Description" 2>&1 | awk '{print $NF}')"

if git issue comment "$issue_id6" -m "$special_comment" 2>/dev/null; then
	local_show="$(git issue show "$issue_id6")"

	if echo "$local_show" | grep -qF '$SHELL_VAR' && echo "$local_show" | grep -qF '`backticks`'; then
		pass "special shell characters preserved locally"
	else
		fail "special characters" "lost during local storage"
	fi
else
	fail "special characters" "comment creation failed"
fi

# =============================================================================
# Cleanup test issues from GitHub
# =============================================================================
printf "\n${YELLOW}Cleaning up test issues...${NC}\n"

for issue_num in $TEST_LONG_ISSUE $TEST_UNICODE_ISSUE $TEST_CLOSED_ISSUE; do
	if test -n "$issue_num"; then
		gh issue close "$issue_num" --repo "$TEST_REPO" --comment "Edge case test cleanup" >/dev/null 2>&1 || true
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
