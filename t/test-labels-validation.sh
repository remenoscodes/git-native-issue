#!/bin/sh
#
# test-labels-validation.sh - Tests for label validation and normalization
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
	NC='\033[0m'
else
	GREEN=''
	RED=''
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

printf "Running git-issue label validation tests...\n\n"

# TEST 1: Label with comma rejected in create
run_test
setup_repo
if git-issue-create "Test" -l "bug,critical" >/dev/null 2>&1
then
	fail "create rejects label with comma"
else
	pass "create rejects label with comma"
fi

# TEST 2: Label with comma rejected in edit --add-label
run_test
setup_repo
id="$(git-issue-create "Test" 2>&1 | awk '{print $NF}')"
if git-issue-edit "$id" --add-label "bug,critical" >/dev/null 2>&1
then
	fail "edit --add-label rejects label with comma"
else
	pass "edit --add-label rejects label with comma"
fi

# TEST 3: Label with comma rejected in edit -l
run_test
setup_repo
id="$(git-issue-create "Test" 2>&1 | awk '{print $NF}')"
if git-issue-edit "$id" -l "bug,critical" >/dev/null 2>&1
then
	fail "edit -l rejects label with comma"
else
	pass "edit -l rejects label with comma"
fi

# TEST 4: Duplicate labels removed in create
run_test
setup_repo
id="$(git-issue-create "Duplicate test" -l bug -l feature -l bug 2>&1 | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, feature"
then
	pass "create deduplicates labels"
else
	fail "create deduplicates labels" "got: '$labels'"
fi

# TEST 5: Duplicate labels removed in edit --add-label
run_test
setup_repo
id="$(git-issue-create "Test" -l bug 2>&1 | awk '{print $NF}')"
git-issue-edit "$id" --add-label bug --add-label feature >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, feature"
then
	pass "edit --add-label deduplicates"
else
	fail "edit --add-label deduplicates" "got: '$labels'"
fi

# TEST 6: Whitespace normalized in labels
run_test
setup_repo
id="$(git-issue-create "Whitespace test" -l "  bug  " -l "feature" 2>&1 | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, feature"
then
	pass "create normalizes whitespace in labels"
else
	fail "create normalizes whitespace in labels" "got: '$labels'"
fi

# TEST 7: Empty labels removed after label operations
run_test
setup_repo
id="$(git-issue-create "Empty test" -l bug 2>&1 | awk '{print $NF}')"
git-issue-edit "$id" --remove-label bug >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
# Get first trailer value (may be empty) without filtering empty lines first
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
if test -z "$labels"
then
	pass "edit removes empty labels after removal"
else
	fail "edit removes empty labels after removal" "got: '$labels'"
fi

# TEST 8: Normal multi-label creation still works
run_test
setup_repo
id="$(git-issue-create "Normal test" -l bug -l security -l urgent 2>&1 | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, security, urgent"
then
	pass "normal multi-label creation works"
else
	fail "normal multi-label creation" "got: '$labels'"
fi

# TEST 9: Unicode and emoji labels preserved
run_test
setup_repo
id="$(git-issue-create "Unicode test" -l "🐛-bug" -l "优先级-high" 2>&1 | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
case "$labels" in
	*"🐛-bug"*"优先级-high"*)
		pass "Unicode/emoji labels preserved"
		;;
	*)
		fail "Unicode/emoji labels" "got: '$labels'"
		;;
esac

# TEST 10: Label with only whitespace rejected
run_test
setup_repo
id="$(git-issue-create "Whitespace-only test" -l "   " 2>&1 | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1)"
if test -z "$labels"
then
	pass "whitespace-only label removed"
else
	fail "whitespace-only label" "got: '$labels'"
fi

# TEST 11: Error message is helpful for comma rejection
run_test
setup_repo
output="$(git-issue-create "Error message test" -l "bug,critical" 2>&1 || true)"
case "$output" in
	*"use multiple -l flags instead"*)
		pass "comma rejection error message is helpful"
		;;
	*)
		fail "error message guidance" "got: '$output'"
		;;
esac

# TEST 12: Combined add and remove labels work correctly
run_test
setup_repo
id="$(git-issue-create "Combined test" -l bug -l security -l docs 2>&1 | awk '{print $NF}')"
git-issue-edit "$id" --remove-label security --add-label urgent >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, docs, urgent"
then
	pass "combined add/remove labels work"
else
	fail "combined add/remove labels" "got: '$labels'"
fi

printf "\n============================================================\n"
printf "Tests: %d | Passed: %d | Failed: %d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "============================================================\n"

if test "$TESTS_FAILED" -gt 0; then
	exit 1
fi
exit 0
