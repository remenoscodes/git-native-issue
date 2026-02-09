#!/bin/sh
#
# Tests for git-issue with local-only repos (no remote configured)
#
# This test validates that core commands work perfectly without any remote,
# ensuring git-issue is truly distributed and doesn't couple to remote providers.
#
# Run: sh t/test-local-only-repo.sh
#

set -e

# Colors (if terminal supports them)
if test -t 1
then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
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

# Setup test repo WITHOUT remote
cd "$TEST_DIR"
git init local-only-repo
cd local-only-repo
git config user.name "Test User"
git config user.email "test@example.com"

export PATH="$BIN_DIR:$PATH"

printf "${YELLOW}Testing git-issue with local-only repo (no remote)...${NC}\n\n"

# Verify no remotes exist
run_test
remotes="$(git remote | wc -l | tr -d ' ')"
if test "$remotes" -eq 0
then
	pass "Repo has no remotes (verified)"
else
	fail "Repo should have no remotes" "Found: $(git remote)"
fi

# ============================================================
# CORE COMMANDS (should work without remote)
# ============================================================

printf "\n${YELLOW}Core commands (must work without remote):${NC}\n"

# Test: create issue
run_test
output="$(git issue create "Fix login bug" -m "Critical security issue" 2>&1)"
if printf '%s' "$output" | grep -q "Created issue"
then
	issue_id="$(printf '%s' "$output" | sed 's/Created issue //')"
	pass "git issue create works without remote"
else
	fail "git issue create failed without remote" "$output"
	issue_id=""
fi

# Test: list issues
run_test
if test -n "$issue_id"
then
	output="$(git issue ls 2>&1)"
	if printf '%s' "$output" | grep -q "$issue_id"
	then
		pass "git issue ls works without remote"
	else
		fail "git issue ls failed without remote" "$output"
	fi
fi

# Test: show issue
run_test
if test -n "$issue_id"
then
	output="$(git issue show "$issue_id" 2>&1)"
	if printf '%s' "$output" | grep -q "Fix login bug"
	then
		pass "git issue show works without remote"
	else
		fail "git issue show failed without remote" "$output"
	fi
fi

# Test: comment on issue
run_test
if test -n "$issue_id"
then
	output="$(git issue comment "$issue_id" -m "Working on this" 2>&1)"
	if printf '%s' "$output" | grep -q "Added comment"
	then
		pass "git issue comment works without remote"
	else
		fail "git issue comment failed without remote" "$output"
	fi
fi

# Test: edit issue
run_test
if test -n "$issue_id"
then
	output="$(git issue edit "$issue_id" -p critical --add-label security 2>&1)"
	if test $? -eq 0
	then
		pass "git issue edit works without remote"
	else
		fail "git issue edit failed without remote" "$output"
	fi
fi

# Test: change state
run_test
if test -n "$issue_id"
then
	output="$(git issue state "$issue_id" --close 2>&1)"
	if printf '%s' "$output" | grep -q "Closed issue"
	then
		pass "git issue state works without remote"
	else
		fail "git issue state failed without remote" "$output"
	fi
fi

# Test: search issues
run_test
output="$(git issue search "login" 2>&1)"
if printf '%s' "$output" | grep -q "Fix login bug"
then
	pass "git issue search works without remote"
else
	fail "git issue search failed without remote" "$output"
fi

# Test: fsck (data integrity check)
run_test
output="$(git issue fsck 2>&1)"
if test $? -eq 0
then
	pass "git issue fsck works without remote"
else
	fail "git issue fsck failed without remote" "$output"
fi

# ============================================================
# INIT COMMAND (should handle no remote gracefully)
# ============================================================

printf "\n${YELLOW}Init command (should handle no remote):${NC}\n"

# Test: init without arguments and no remotes (should provide helpful message)
run_test
output="$(git issue init 2>&1 || true)"
if printf '%s' "$output" | grep -q "git issue init is OPTIONAL"
then
	pass "git issue init provides helpful message when no remotes"
else
	fail "git issue init should explain it's optional" "$output"
fi

# Test: init with non-existent remote (should fail clearly)
run_test
output="$(git issue init nonexistent 2>&1 || true)"
if printf '%s' "$output" | grep -q "remote 'nonexistent' does not exist"
then
	pass "git issue init reports missing remote clearly"
else
	fail "git issue init error message unclear" "$output"
fi

# ============================================================
# REMOTE-DEPENDENT COMMANDS (should fail with clear message)
# ============================================================

printf "\n${YELLOW}Remote-dependent commands (should fail clearly):${NC}\n"

# Test: merge requires remote
run_test
output="$(git issue merge 2>&1 || true)"
if printf '%s' "$output" | grep -q "remote name is required"
then
	pass "git issue merge requires remote (expected)"
else
	fail "git issue merge error unclear" "$output"
fi

# Test: sync requires provider (not git remote)
run_test
output="$(git issue sync 2>&1 || true)"
if printf '%s' "$output" | grep -q "provider is required"
then
	pass "git issue sync requires provider (expected)"
else
	fail "git issue sync error unclear" "$output"
fi

# Test: import requires provider
run_test
output="$(git issue import 2>&1 || true)"
if printf '%s' "$output" | grep -q "provider is required"
then
	pass "git issue import requires provider (expected)"
else
	fail "git issue import error unclear" "$output"
fi

# Test: export requires provider
run_test
output="$(git issue export 2>&1 || true)"
if printf '%s' "$output" | grep -q "provider is required"
then
	pass "git issue export requires provider (expected)"
else
	fail "git issue export error unclear" "$output"
fi

# ============================================================
# REFS VALIDATION (issues stored correctly)
# ============================================================

printf "\n${YELLOW}Refs validation (issues in refs/issues/*):${NC}\n"

# Test: refs/issues/* exist
run_test
refs_count="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"
if test "$refs_count" -gt 0
then
	pass "Issues stored in refs/issues/* (count: $refs_count)"
else
	fail "No refs/issues/* found" "Expected at least 1 issue ref"
fi

# Test: issue data integrity
run_test
if test -n "$issue_id"
then
	ref="$(git for-each-ref --format='%(refname)' "refs/issues/$issue_id*" | head -1)"
	if test -n "$ref"
	then
		# Verify it's a valid commit
		if git cat-file -t "$ref" >/dev/null 2>&1
		then
			pass "Issue ref points to valid commit"
		else
			fail "Issue ref invalid" "Ref: $ref"
		fi
	else
		fail "Cannot find ref for issue $issue_id"
	fi
fi

# ============================================================
# SUMMARY
# ============================================================

printf "\n${YELLOW}========================================${NC}\n"
printf "Tests run:    %d\n" "$TESTS_RUN"
printf "${GREEN}Passed:       %d${NC}\n" "$TESTS_PASSED"
if test "$TESTS_FAILED" -gt 0
then
	printf "${RED}Failed:       %d${NC}\n" "$TESTS_FAILED"
else
	printf "Failed:       %d\n" "$TESTS_FAILED"
fi
printf "${YELLOW}========================================${NC}\n"

if test "$TESTS_FAILED" -gt 0
then
	exit 1
fi

printf "\n${GREEN}All tests passed!${NC}\n"
printf "\n${YELLOW}Key findings:${NC}\n"
printf "  ✓ Core commands work perfectly without remote\n"
printf "  ✓ Issues stored in refs/issues/* independently\n"
printf "  ✓ No coupling between core functionality and remotes\n"
printf "  ✓ Bridge commands (sync/import/export) correctly require provider\n"
if printf '%s' "$(git issue init 2>&1 || true)" | grep -q "does not exist"
then
	printf "  ⚠ git issue init could be improved for local-only repos\n"
fi
printf "\n"
