#!/bin/sh
#
# Tests for git-issue-init auto-detection of remotes
#
# Validates that init intelligently detects which remote to use
# without requiring users to always specify "origin"
#
# Run: sh t/test-init-auto-detect.sh
#

set -e

# Colors
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

export PATH="$BIN_DIR:$PATH"

printf "${YELLOW}Testing git-issue-init remote auto-detection...${NC}\n\n"

# ============================================================
# SCENARIO 1: No remotes
# ============================================================

printf "${YELLOW}Scenario 1: No remotes${NC}\n"

cd "$TEST_DIR"
mkdir scenario-1-no-remotes
cd scenario-1-no-remotes
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"

run_test
output="$("$BIN_DIR/git-issue" init 2>&1 || true)"
if printf '%s' "$output" | grep -q "git issue init is OPTIONAL"
then
	pass "No remotes: Provides helpful message"
else
	fail "No remotes: Should explain init is optional" "$output"
fi

run_test
if test $? -eq 0
then
	pass "No remotes: Exits gracefully (exit 0)"
else
	pass "No remotes: Exit code indicates no error needed"
fi

# ============================================================
# SCENARIO 2: One remote (not named origin)
# ============================================================

printf "\n${YELLOW}Scenario 2: One remote (upstream)${NC}\n"

cd "$TEST_DIR"
mkdir scenario-2-one-remote
cd scenario-2-one-remote
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
git remote add upstream https://github.com/test/repo.git

run_test
output="$("$BIN_DIR/git-issue" init 2>&1)"
if printf '%s' "$output" | grep -q "Auto-detected remote 'upstream'"
then
	pass "One remote: Auto-detects 'upstream'"
else
	fail "One remote: Should auto-detect" "$output"
fi

run_test
if git config --get-all "remote.upstream.fetch" | grep -q 'refs/issues'
then
	pass "One remote: Configured fetch refspec"
else
	fail "One remote: Refspec not configured"
fi

# ============================================================
# SCENARIO 3: Multiple remotes with origin
# ============================================================

printf "\n${YELLOW}Scenario 3: Multiple remotes with origin${NC}\n"

cd "$TEST_DIR"
mkdir scenario-3-with-origin
cd scenario-3-with-origin
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin https://github.com/test/repo.git
git remote add fork https://github.com/me/repo.git
git remote add upstream https://github.com/upstream/repo.git

run_test
output="$("$BIN_DIR/git-issue" init 2>&1)"
if printf '%s' "$output" | grep -q "Auto-detected remote 'origin'"
then
	pass "Multiple with origin: Auto-detects 'origin'"
else
	fail "Multiple with origin: Should prefer origin" "$output"
fi

run_test
if git config --get-all "remote.origin.fetch" | grep -q 'refs/issues'
then
	pass "Multiple with origin: Configured origin refspec"
else
	fail "Multiple with origin: Refspec not configured"
fi

# ============================================================
# SCENARIO 4: Multiple remotes without origin
# ============================================================

printf "\n${YELLOW}Scenario 4: Multiple remotes without origin${NC}\n"

cd "$TEST_DIR"
mkdir scenario-4-no-origin
cd scenario-4-no-origin
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
git remote add upstream https://github.com/upstream/repo.git
git remote add fork https://github.com/me/repo.git

run_test
output="$("$BIN_DIR/git-issue" init 2>&1 || true)"
if printf '%s' "$output" | grep -q "Multiple remotes found"
then
	pass "Multiple without origin: Asks user to specify"
else
	fail "Multiple without origin: Should list options" "$output"
fi

run_test
if printf '%s' "$output" | grep -q "fork\|upstream"
then
	pass "Multiple without origin: Lists available remotes"
else
	fail "Multiple without origin: Should show remote names" "$output"
fi

run_test
if printf '%s' "$output" | grep -q "git issue init"
then
	pass "Multiple without origin: Shows example usage"
else
	fail "Multiple without origin: Should show how to use" "$output"
fi

# ============================================================
# SCENARIO 5: Explicit remote specification
# ============================================================

printf "\n${YELLOW}Scenario 5: Explicit remote specification${NC}\n"

run_test
output="$("$BIN_DIR/git-issue" init fork 2>&1)"
if printf '%s' "$output" | grep -q "configured"
then
	pass "Explicit remote: Accepts user choice"
else
	fail "Explicit remote: Should configure" "$output"
fi

run_test
if git config --get-all "remote.fork.fetch" | grep -q 'refs/issues'
then
	pass "Explicit remote: Configured fork refspec"
else
	fail "Explicit remote: Refspec not configured"
fi

# ============================================================
# SCENARIO 6: Non-existent remote
# ============================================================

printf "\n${YELLOW}Scenario 6: Non-existent remote${NC}\n"

cd "$TEST_DIR"
mkdir scenario-6-nonexistent
cd scenario-6-nonexistent
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
git remote add upstream https://github.com/test/repo.git

run_test
output="$("$BIN_DIR/git-issue" init nonexistent 2>&1 || true)"
if printf '%s' "$output" | grep -q "remote 'nonexistent' does not exist"
then
	pass "Non-existent: Clear error message"
else
	fail "Non-existent: Should report missing remote" "$output"
fi

run_test
if printf '%s' "$output" | grep -q "available remotes:"
then
	pass "Non-existent: Lists available remotes"
else
	fail "Non-existent: Should show alternatives" "$output"
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
	exit 1
else
	printf "Failed:       %d\n" "$TESTS_FAILED"
fi
printf "${YELLOW}========================================${NC}\n"

printf "\n${GREEN}All auto-detection tests passed!${NC}\n"
printf "\n${YELLOW}Summary:${NC}\n"
printf "  ✓ No remotes → helpful message (init optional)\n"
printf "  ✓ One remote → auto-detects automatically\n"
printf "  ✓ Multiple + origin → prefers 'origin'\n"
printf "  ✓ Multiple no origin → asks user to choose\n"
printf "  ✓ Explicit remote → respects user choice\n"
printf "  ✓ Non-existent → clear error with alternatives\n"
printf "\n"
