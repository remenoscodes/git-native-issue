#!/bin/sh
#
# test-concurrency.sh - Tests for concurrent modification handling
#

set -e

BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
TEST_DIR="$(mktemp -d)"

cleanup() {
	cd /
	rm -rf "$TEST_DIR"
}
trap cleanup EXIT

export PATH="$BIN_DIR:$PATH"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
if test -t 1; then
	GREEN='\033[0;32m'
	RED='\033[0;31m'
	YELLOW='\033[0;33m'
	NC='\033[0m'
else
	GREEN=''
	RED=''
	YELLOW=''
	NC=''
fi

pass() {
	TESTS_PASSED=$((TESTS_PASSED + 1))
	printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
	TESTS_FAILED=$((TESTS_FAILED + 1))
	printf "${RED}  FAIL${NC} %s" "$1"
	if test -n "$2"; then
		printf ": %s" "$2"
	fi
	printf "\n"
}

skip() {
	printf "${YELLOW}  SKIP${NC} %s" "$1"
	if test -n "$2"; then
		printf ": %s" "$2"
	fi
	printf "\n"
}

run_test() {
	TESTS_RUN=$((TESTS_RUN + 1))
}

setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir -p "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git config user.name "Test User"
	git config user.email "test@example.com"
	git commit --allow-empty -q -m "initial"
}

printf "Running git-issue concurrency tests...\n"
printf "Note: These tests verify retry logic and error handling.\n\n"

# TEST 1: Normal state change succeeds (baseline)
run_test
setup_repo
id="$(git-issue-create "Concurrency test" 2>&1 | awk '{print $NF}')"
if git-issue-state "$id" --close -m "Close" >/dev/null 2>&1
then
	pass "normal state change succeeds"
else
	fail "normal state change" "should succeed"
fi

# TEST 2: Normal edit succeeds (baseline)
run_test
setup_repo
id="$(git-issue-create "Edit test" 2>&1 | awk '{print $NF}')"
if git-issue-edit "$id" -l bug >/dev/null 2>&1
then
	pass "normal edit succeeds"
else
	fail "normal edit" "should succeed"
fi

# TEST 3: Normal comment succeeds (baseline)
run_test
setup_repo
id="$(git-issue-create "Comment test" 2>&1 | awk '{print $NF}')"
if git-issue-comment "$id" -m "Test comment" >/dev/null 2>&1
then
	pass "normal comment succeeds"
else
	fail "normal comment" "should succeed"
fi

# TEST 4: Multiple rapid operations succeed (tests retry doesn't break normal case)
run_test
setup_repo
id="$(git-issue-create "Rapid test" 2>&1 | awk '{print $NF}')"
git-issue-state "$id" --close -m "Close 1" >/dev/null 2>&1
git-issue-state "$id" --open -m "Reopen" >/dev/null 2>&1
git-issue-state "$id" --close -m "Close 2" >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | head -1)"
if test "$state" = "closed"
then
	pass "rapid sequential operations succeed"
else
	fail "rapid operations" "expected state=closed, got $state"
fi

# TEST 5: Git config validation (missing user.name)
run_test
if test -n "${SKIP_GIT_CONFIG_TESTS:-}"
then
	skip "git config validation" "SKIP_GIT_CONFIG_TESTS set"
else
	setup_repo
	# This test is tricky - git uses global config if local is unset
	# We can't easily test this without affecting global config
	# So we'll skip for now unless we can mock git config
	skip "git config validation" "requires isolated environment"
fi

# TEST 6: Empty tree validation
run_test
setup_repo
id="$(git-issue-create "Empty tree test" 2>&1 | awk '{print $NF}')"
# Normal operation should pass (empty tree generation should work)
if git-issue-state "$id" --close -m "Test" >/dev/null 2>&1
then
	pass "empty tree generation works"
else
	fail "empty tree generation"
fi

# TEST 7: Ref update creates proper commit chain
run_test
setup_repo
id="$(git-issue-create "Chain test" 2>&1 | awk '{print $NF}')"
git-issue-state "$id" --close -m "Close" >/dev/null 2>&1
git-issue-comment "$id" -m "Comment" >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
count="$(git rev-list --count "$ref")"
# Should have: root + state change + comment = 3 commits
if test "$count" -eq 3
then
	pass "ref update creates proper commit chain"
else
	fail "commit chain" "expected 3 commits, got $count"
fi

# TEST 8: Concurrent operations (simulated)
run_test
setup_repo
id="$(git-issue-create "Concurrent sim" 2>&1 | awk '{print $NF}')"
# Launch two state changes in background
(git-issue-state "$id" --close -m "Close A" >/dev/null 2>&1) &
pid1=$!
sleep 0.05  # Small delay to stagger starts
(git-issue-state "$id" --close -m "Close B" >/dev/null 2>&1) &
pid2=$!

wait $pid1
result1=$?
wait $pid2
result2=$?

# At least one should succeed
if test "$result1" -eq 0 || test "$result2" -eq 0
then
	pass "concurrent operations (at least one succeeds)"
else
	fail "concurrent operations" "both failed: $result1, $result2"
fi

printf "\n============================================================\n"
printf "Tests: %d | Passed: %d | Failed: %d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "============================================================\n"

if test "$TESTS_FAILED" -gt 0; then
	exit 1
fi
exit 0
