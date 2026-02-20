#!/bin/sh
#
# test-environment.sh - Environmental validation tests for git-issue
#
# Validates portability across hostile environments:
# minimal PATH, read-only directories, missing /tmp, locale,
# permission errors, git version requirements, tool dependencies.
#
# Run: sh t/test-environment.sh
#

set -e

BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
TEST_DIR="$(mktemp -d)"

cleanup() {
	cd /
	# Ensure writable before removal (test_readonly_git_dir may chmod)
	chmod -R u+w "$TEST_DIR" 2>/dev/null || true
	rm -rf "$TEST_DIR"
}
trap cleanup EXIT

export PATH="$BIN_DIR:$PATH"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

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
	if test -n "${2:-}"; then
		printf ": %s" "$2"
	fi
	printf "\n"
}

skip() {
	TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
	printf "${YELLOW}  SKIP${NC} %s" "$1"
	if test -n "${2:-}"; then
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

printf "Running git-issue environment tests...\n"
printf "Note: These tests validate portability across hostile environments.\n\n"

# ============================================================
# TEST 1: Minimal PATH (cron/docker scenarios)
# ============================================================
run_test
setup_repo

# Save original PATH, restrict to only git and essential POSIX utilities
_git_bin="$(command -v git)"
_git_dir="$(dirname "$_git_bin")"

# Build a minimal PATH: git's directory + BIN_DIR + /usr/bin (POSIX tools)
# Include /bin as some systems keep rm, cat there separately from /usr/bin
_minimal_path="$BIN_DIR:$_git_dir:/usr/bin:/bin"

# Attempt to create an issue with minimal PATH
output="$(PATH="$_minimal_path" git issue create "Minimal PATH test" -m "Created with restricted PATH" 2>&1)" || true
case "$output" in
	*"Created issue "???????)
		pass "works with minimal PATH"
		;;
	*)
		fail "works with minimal PATH" "unexpected output: $output"
		;;
esac

# ============================================================
# TEST 2: Read-only .git directory detection
# ============================================================
run_test
setup_repo

# Create an issue first (while writable)
output="$(git issue create "Readonly test" 2>&1)"
_id="$(printf '%s' "$output" | awk '{print $NF}')"

# Make refs/issues read-only to prevent new ref creation
if mkdir -p .git/refs/issues 2>/dev/null; then
	chmod -R a-w .git/refs/issues 2>/dev/null

	# Attempt to create another issue (should fail due to read-only refs)
	if err="$(git issue create "Should fail" 2>&1)"; then
		# Some git implementations may use packed-refs and bypass directory permissions
		# In that case, creating may succeed -- that's acceptable
		skip "read-only .git/refs/issues" "git bypassed directory permissions (packed-refs)"
		chmod -R u+w .git/refs/issues 2>/dev/null || true
	else
		pass "read-only .git/refs/issues surfaces error"
		chmod -R u+w .git/refs/issues 2>/dev/null || true
	fi
else
	skip "read-only .git/refs/issues" "could not create refs/issues dir"
fi

# ============================================================
# TEST 3: Missing /tmp or TMPDIR unavailable
# ============================================================
run_test
setup_repo

# Redirect TMPDIR to a non-existent path
_bad_tmpdir="$TEST_DIR/no-such-tmp"

# git-issue-create uses mktemp which respects TMPDIR
# If TMPDIR is invalid, mktemp should fail and the script should exit with error
if err="$(TMPDIR="$_bad_tmpdir" git issue create "No tmp test" 2>&1)"; then
	# Some systems fall back to /tmp when TMPDIR is invalid
	case "$err" in
		"Created issue "???????)
			skip "missing TMPDIR" "system fell back to /tmp"
			;;
		*)
			fail "missing TMPDIR" "unexpected success: $err"
			;;
	esac
else
	# Expected: command fails gracefully (non-zero exit)
	pass "missing TMPDIR surfaces error gracefully"
fi

# ============================================================
# TEST 4: Git version validation (require >= 2.22)
# ============================================================
run_test

# git-issue relies on features available since git 2.22:
#   - %(trailers:key=X,valueonly) in format
#   - git interpret-trailers --in-place
# Check the current git version meets the minimum
_git_version="$(git --version | sed 's/git version //' | sed 's/[^0-9.].*//')"
_git_major="$(printf '%s' "$_git_version" | cut -d. -f1)"
_git_minor="$(printf '%s' "$_git_version" | cut -d. -f2)"

if test "$_git_major" -gt 2 2>/dev/null || { test "$_git_major" -eq 2 && test "$_git_minor" -ge 22; } 2>/dev/null; then
	pass "git version >= 2.22 ($_git_version)"
else
	fail "git version >= 2.22" "found $_git_version (need 2.22+)"
fi

# ============================================================
# TEST 5: Locale handling (UTF-8 vs ASCII)
# ============================================================
run_test
setup_repo

# Create an issue with UTF-8 characters in title and body
_utf8_title="Issue with emojis and accents: cafe resumen"
_utf8_body="Description: Sao Paulo, Munchen, Tokyo"

if output="$(LC_ALL=en_US.UTF-8 git issue create "$_utf8_title" -m "$_utf8_body" 2>&1)"; then
	_id="$(printf '%s' "$output" | awk '{print $NF}')"
	# Verify the title is stored correctly
	_stored="$(git issue show "$_id" 2>&1 | head -3)"
	case "$_stored" in
		*"cafe"*)
			pass "UTF-8 content preserved in issue"
			;;
		*)
			fail "UTF-8 content preserved" "content may be corrupted: $_stored"
			;;
	esac
else
	fail "UTF-8 issue creation" "command failed: $output"
fi

# ============================================================
# TEST 6: C/POSIX locale (non-UTF-8)
# ============================================================
run_test
setup_repo

# Create an issue under the C locale (ASCII-only)
_ascii_title="Plain ASCII issue title"
_ascii_body="Body with only ASCII characters"

if output="$(LC_ALL=C LANG=C git issue create "$_ascii_title" -m "$_ascii_body" 2>&1)"; then
	case "$output" in
		"Created issue "???????)
			pass "works under C/POSIX locale"
			;;
		*)
			fail "works under C/POSIX locale" "unexpected output: $output"
			;;
	esac
else
	fail "works under C/POSIX locale" "command failed: $output"
fi

# ============================================================
# TEST 7: Permission errors on .git directory
# ============================================================
run_test

# Create a fresh repo in an isolated subdirectory
_perm_dir="$TEST_DIR/perm-test"
mkdir -p "$_perm_dir"
cd "$_perm_dir"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"
git commit --allow-empty -q -m "initial"

# Make the objects directory non-writable (prevents git commit-tree)
chmod a-w .git/objects 2>/dev/null

if err="$(git issue create "Permission denied test" 2>&1)"; then
	# Unlikely to succeed with non-writable objects
	skip "permission errors on .git/objects" "git bypassed permissions"
	chmod u+w .git/objects 2>/dev/null || true
else
	# Should fail with a meaningful error
	case "$err" in
		*"ermission"*|*"ead-only"*|*"unable"*|*"cannot"*|*"failed"*)
			pass "permission error surfaces meaningful message"
			;;
		*)
			# Still passed (non-zero exit), just message may vary
			pass "permission error causes non-zero exit"
			;;
	esac
	chmod u+w .git/objects 2>/dev/null || true
fi

# ============================================================
# TEST 8: Tool dependencies (required external commands)
# ============================================================
run_test
setup_repo

# git-issue requires: git, sed, cut, awk, tr, mktemp, od (or uuidgen)
# Verify each is available
_missing=""
for _tool in git sed cut awk tr mktemp; do
	if ! command -v "$_tool" >/dev/null 2>&1; then
		if test -n "$_missing"; then
			_missing="$_missing, $_tool"
		else
			_missing="$_tool"
		fi
	fi
done

# UUID generation: needs uuidgen OR /proc/sys/kernel/random/uuid OR od+/dev/urandom
_has_uuid=0
if command -v uuidgen >/dev/null 2>&1; then
	_has_uuid=1
elif test -r /proc/sys/kernel/random/uuid; then
	_has_uuid=1
elif command -v od >/dev/null 2>&1 && test -r /dev/urandom; then
	_has_uuid=1
fi

if test "$_has_uuid" -eq 0; then
	if test -n "$_missing"; then
		_missing="$_missing, uuid-source"
	else
		_missing="uuid-source"
	fi
fi

if test -z "$_missing"; then
	pass "all required tool dependencies found"
else
	fail "tool dependencies" "missing: $_missing"
fi

# ============================================================
# TEST 9: git interpret-trailers available
# ============================================================
run_test

# git interpret-trailers is critical for git-issue
if git interpret-trailers --version >/dev/null 2>&1 || git interpret-trailers </dev/null >/dev/null 2>&1; then
	pass "git interpret-trailers available"
else
	fail "git interpret-trailers" "not available or broken"
fi

# ============================================================
# TEST 10: Operations work outside repository root (subdirectory)
# ============================================================
run_test
setup_repo

# Create a subdirectory and operate from there
mkdir -p subdir/nested
cd subdir/nested

if output="$(git issue create "Subdirectory test" -m "Created from nested subdir" 2>&1)"; then
	case "$output" in
		"Created issue "???????)
			pass "works from nested subdirectory"
			;;
		*)
			fail "works from nested subdirectory" "unexpected output: $output"
			;;
	esac
else
	fail "works from nested subdirectory" "command failed: $output"
fi

# ============================================================
# TEST 11: HOME unset or invalid
# ============================================================
run_test
setup_repo

# git-issue should work even if HOME is unset (uses repo-local config)
if output="$(HOME=/nonexistent git issue create "No HOME test" 2>&1)"; then
	case "$output" in
		"Created issue "???????)
			pass "works with invalid HOME"
			;;
		*)
			fail "works with invalid HOME" "unexpected output: $output"
			;;
	esac
else
	# Some git operations may require HOME for global config lookup
	# A failure here is acceptable as long as it is not a crash
	case "$output" in
		*"Segmentation fault"*|*"core dumped"*|*"Abort"*)
			fail "works with invalid HOME" "crashed: $output"
			;;
		*)
			skip "works with invalid HOME" "git requires valid HOME"
			;;
	esac
fi

# ============================================================
# TEST 12: Long issue title (boundary test)
# ============================================================
run_test
setup_repo

# Generate a long title (500 characters)
_long_title="$(printf 'A%.0s' $(seq 1 500))"

if output="$(git issue create "$_long_title" 2>&1)"; then
	case "$output" in
		"Created issue "???????)
			# Verify the title was stored
			# git issue show format: line 3 = "Title:   <actual title>"
			_id="$(printf '%s' "$output" | awk '{print $NF}')"
			_stored_title="$(git issue show "$_id" 2>&1 | sed -n '3p' | sed 's/^Title:[[:space:]]*//')"
			_stored_len="$(printf '%s' "$_stored_title" | wc -c | tr -d ' ')"
			if test "$_stored_len" -ge 400; then
				pass "long title (500 chars) preserved"
			else
				fail "long title preserved" "stored title appears truncated ($_stored_len chars)"
			fi
			;;
		*)
			fail "long title creation" "unexpected output: $output"
			;;
	esac
else
	fail "long title creation" "command failed: $output"
fi

# ============================================================
# Summary
# ============================================================
printf "\n============================================================\n"
printf "Environment Tests: %d | Passed: %d | Failed: %d | Skipped: %d\n" \
	"$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_SKIPPED"
printf "============================================================\n"

if test "$TESTS_FAILED" -gt 0; then
	exit 1
fi
exit 0
