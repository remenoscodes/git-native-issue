#!/bin/sh
#
# Tests for git-issue provider-migrate
#
# Run: sh t/test-provider-migrate.sh
#

set -e

# Colors (if terminal supports them)
if test -t 1
then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	NC=''
fi

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
TEST_DIR="$(mktemp -d)"

trap 'rm -rf "$TEST_DIR"' EXIT

pass() {
	TESTS_PASSED=$((TESTS_PASSED + 1))
	printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
	TESTS_FAILED=$((TESTS_FAILED + 1))
	printf "${RED}  FAIL${NC} %s\n" "$1"
	if test -n "${2:-}"
	then
		printf "       %s\n" "$2"
	fi
}

run_test() {
	TESTS_RUN=$((TESTS_RUN + 1))
}

# Helper: create a test issue with a Provider-ID
# Args: $1 = title, $2 = provider-id (optional)
create_test_issue() {
	_title="$1"
	_pid="${2:-}"

	_empty_tree="$(git hash-object -t tree /dev/null)"
	_uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null)"

	_tmpfile="$(mktemp)"
	printf '%s\n' "$_title" > "$_tmpfile"

	if test -n "$_pid"
	then
		git interpret-trailers --in-place --trailer "Provider-ID: $_pid" "$_tmpfile"
	fi

	_commit="$(git commit-tree -- "$_empty_tree" < "$_tmpfile")"
	git update-ref "refs/issues/$_uuid" "$_commit"
	rm -f "$_tmpfile"

	printf '%s' "$_uuid"
}

setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git commit --allow-empty -q -m "initial"
	export PATH="$BIN_DIR:$PATH"
}

printf "Running git-issue provider-migrate tests...\n\n"

# ============================================================
# TEST: basic migration (2 matching + 1 unrelated)
# ============================================================
run_test
setup_repo
uuid1="$(create_test_issue "Issue one" "github:owner/old-repo#1")"
uuid2="$(create_test_issue "Issue two" "github:owner/old-repo#2")"
uuid3="$(create_test_issue "Unrelated" "github:other/repo#5")"
output="$(git issue provider-migrate github:owner/old-repo github:owner/new-repo 2>&1)"
case "$output" in
	*"Migrated 2 issues"*)
		pass "basic migration: 2 matching migrated"
		;;
	*)
		fail "basic migration: 2 matching migrated" "output: $output"
		;;
esac

# ============================================================
# TEST: new Provider-ID is the most recent (head -1)
# ============================================================
run_test
newest_pid="$(git log --format='%(trailers:key=Provider-ID,valueonly)' "refs/issues/$uuid1" | sed '/^$/d' | sed 's/^[[:space:]]*//' | head -1)"
if test "$newest_pid" = "github:owner/new-repo#1"
then
	pass "new Provider-ID is the most recent in chain"
else
	fail "new Provider-ID is the most recent in chain" "got: '$newest_pid'"
fi

# ============================================================
# TEST: old Provider-ID preserved in chain
# ============================================================
run_test
all_pids="$(git log --format='%(trailers:key=Provider-ID,valueonly)' "refs/issues/$uuid1" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
case "$all_pids" in
	*"github:owner/old-repo#1"*)
		pass "old Provider-ID preserved in chain"
		;;
	*)
		fail "old Provider-ID preserved in chain" "pids: $all_pids"
		;;
esac

# ============================================================
# TEST: unrelated issue not modified
# ============================================================
run_test
unrelated_count="$(git rev-list --count "refs/issues/$uuid3")"
if test "$unrelated_count" -eq 1
then
	pass "unrelated issue not modified"
else
	fail "unrelated issue not modified" "expected 1 commit, got $unrelated_count"
fi

# ============================================================
# TEST: dry-run does not modify anything
# ============================================================
run_test
setup_repo
uuid_dry="$(create_test_issue "Dry run issue" "github:owner/old-repo#10")"
before_sha="$(git rev-parse "refs/issues/$uuid_dry")"
git issue provider-migrate --dry-run github:owner/old-repo github:owner/new-repo >/dev/null 2>&1
after_sha="$(git rev-parse "refs/issues/$uuid_dry")"
if test "$before_sha" = "$after_sha"
then
	pass "dry-run does not modify refs"
else
	fail "dry-run does not modify refs" "ref changed from $before_sha to $after_sha"
fi

# ============================================================
# TEST: dry-run shows preview with [dry-run] prefix
# ============================================================
run_test
output="$(git issue provider-migrate --dry-run github:owner/old-repo github:owner/new-repo 2>&1)"
case "$output" in
	*"[dry-run]"*)
		pass "dry-run shows preview with [dry-run] prefix"
		;;
	*)
		fail "dry-run shows preview with [dry-run] prefix" "output: $output"
		;;
esac

# ============================================================
# TEST: idempotent (second run is no-op)
# ============================================================
run_test
setup_repo
uuid_idem="$(create_test_issue "Idempotent issue" "github:owner/old-repo#20")"
git issue provider-migrate github:owner/old-repo github:owner/new-repo >/dev/null 2>&1
before_sha="$(git rev-parse "refs/issues/$uuid_idem")"
output="$(git issue provider-migrate github:owner/old-repo github:owner/new-repo 2>&1)"
after_sha="$(git rev-parse "refs/issues/$uuid_idem")"
if test "$before_sha" = "$after_sha"
then
	case "$output" in
		*"Migrated 0 issues"*)
			pass "idempotent: second run is no-op"
			;;
		*)
			fail "idempotent: second run is no-op" "output: $output"
			;;
	esac
else
	fail "idempotent: second run is no-op" "ref changed"
fi

# ============================================================
# TEST: cross-platform migration (github -> gitlab)
# ============================================================
run_test
setup_repo
uuid_cross="$(create_test_issue "Cross-platform" "github:owner/repo#7")"
output="$(git issue provider-migrate github:owner/repo gitlab:owner/repo 2>&1)"
newest_pid="$(git log --format='%(trailers:key=Provider-ID,valueonly)' "refs/issues/$uuid_cross" | sed '/^$/d' | sed 's/^[[:space:]]*//' | head -1)"
if test "$newest_pid" = "gitlab:owner/repo#7"
then
	pass "cross-platform migration (github -> gitlab)"
else
	fail "cross-platform migration (github -> gitlab)" "got: '$newest_pid'"
fi

# ============================================================
# TEST: issues without Provider-ID are skipped
# ============================================================
run_test
setup_repo
uuid_nopid="$(create_test_issue "No provider ID")"
uuid_withpid="$(create_test_issue "Has provider ID" "github:owner/repo#1")"
output="$(git issue provider-migrate github:owner/repo github:owner/new-repo 2>&1)"
nopid_count="$(git rev-list --count "refs/issues/$uuid_nopid")"
case "$output" in
	*"Migrated 1 issue"*)
		if test "$nopid_count" -eq 1
		then
			pass "issues without Provider-ID are skipped"
		else
			fail "issues without Provider-ID are skipped" "no-pid issue was modified"
		fi
		;;
	*)
		fail "issues without Provider-ID are skipped" "output: $output"
		;;
esac

# ============================================================
# TEST: error on missing arguments
# ============================================================
run_test
setup_repo
if git issue provider-migrate 2>/dev/null
then
	fail "error on missing arguments" "should have failed"
else
	pass "error on missing arguments"
fi

# ============================================================
# TEST: error on same old and new prefix
# ============================================================
run_test
setup_repo
if git issue provider-migrate github:owner/repo github:owner/repo 2>/dev/null
then
	fail "error on same old and new prefix" "should have failed"
else
	pass "error on same old and new prefix"
fi

# ============================================================
# TEST: error when not in a git repo (exit 128)
# ============================================================
run_test
_non_git_dir="$(mktemp -d)"
if output="$(cd "$_non_git_dir" && "$BIN_DIR/git-issue-provider-migrate" github:a/b github:a/c 2>&1)"
then
	fail "error when not in a git repo" "should have failed"
else
	exit_code=$?
	if test "$exit_code" -eq 128
	then
		pass "error when not in a git repo (exit 128)"
	else
		fail "error when not in a git repo (exit 128)" "expected exit 128, got $exit_code"
	fi
fi
rm -rf "$_non_git_dir"

# ============================================================
# SUMMARY
# ============================================================
printf "\n%.60s\n" "============================================================"
printf "Tests: %d | Passed: ${GREEN}%d${NC} | Failed: ${RED}%d${NC}\n" \
	"$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "%.60s\n" "============================================================"

if test "$TESTS_FAILED" -gt 0
then
	exit 1
fi
