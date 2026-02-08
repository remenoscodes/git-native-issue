#!/bin/sh
#
# Tests for v0.5 quality-of-life features:
#   - ls --sort, --assignee, --priority, --reverse
#   - git issue search
#   - git issue init [remote-name]
#   - export body extraction (interpret-trailers)
#
# Run: sh t/test-qol.sh
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

setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git commit --allow-empty -q -m "initial"
	export PATH="$BIN_DIR:$PATH"
}

printf "Running git-issue QoL tests...\n\n"

# ============================================================
# LS FILTER TESTS
# ============================================================

# ============================================================
# TEST: ls --assignee filters by assignee
# ============================================================
run_test
setup_repo
git issue create "Alice bug" -a alice@test.com >/dev/null
git issue create "Bob bug" -a bob@test.com >/dev/null
git issue create "Unassigned bug" >/dev/null
output="$(git issue ls --assignee alice@test.com 2>&1)"
count="$(printf '%s\n' "$output" | grep -c . || echo 0)"
case "$output" in
	*"Alice bug"*)
		if test "$count" -eq 1
		then
			pass "ls --assignee filters by assignee"
		else
			fail "ls --assignee filters by assignee" "expected 1 result, got $count"
		fi
		;;
	*)
		fail "ls --assignee filters by assignee" "got: $output"
		;;
esac

# ============================================================
# TEST: ls --priority filters by priority
# ============================================================
run_test
setup_repo
git issue create "Low prio" -p low >/dev/null
git issue create "High prio" -p high >/dev/null
git issue create "Critical prio" -p critical >/dev/null
output="$(git issue ls --priority high 2>&1)"
count="$(printf '%s\n' "$output" | grep -c . || echo 0)"
case "$output" in
	*"High prio"*)
		if test "$count" -eq 1
		then
			pass "ls --priority filters by priority"
		else
			fail "ls --priority filters by priority" "expected 1 result, got $count"
		fi
		;;
	*)
		fail "ls --priority filters by priority" "got: $output"
		;;
esac

# ============================================================
# TEST: ls --priority rejects invalid value
# ============================================================
run_test
setup_repo
if git issue ls --priority foo 2>/dev/null
then
	fail "ls --priority rejects invalid value" "should have failed"
else
	pass "ls --priority rejects invalid value"
fi

# ============================================================
# TEST: ls --sort priority orders by priority level
# ============================================================
run_test
setup_repo
git issue create "Low task" -p low >/dev/null
git issue create "Critical task" -p critical >/dev/null
git issue create "Medium task" -p medium >/dev/null
output="$(git issue ls --sort priority --format oneline 2>&1)"
# Default sort (descending): critical first, then medium, then low
first_line="$(printf '%s\n' "$output" | head -1)"
last_line="$(printf '%s\n' "$output" | tail -1)"
case "$first_line" in
	*"Critical task"*)
		case "$last_line" in
			*"Low task"*)
				pass "ls --sort priority orders by priority level"
				;;
			*)
				fail "ls --sort priority orders by priority level" "last: $last_line"
				;;
		esac
		;;
	*)
		fail "ls --sort priority orders by priority level" "first: $first_line"
		;;
esac

# ============================================================
# TEST: ls --sort priority --reverse reverses order
# ============================================================
run_test
setup_repo
git issue create "Low task" -p low >/dev/null
git issue create "Critical task" -p critical >/dev/null
output="$(git issue ls --sort priority --reverse --format oneline 2>&1)"
first_line="$(printf '%s\n' "$output" | head -1)"
case "$first_line" in
	*"Low task"*)
		pass "ls --sort priority --reverse reverses order"
		;;
	*)
		fail "ls --sort priority --reverse reverses order" "first: $first_line"
		;;
esac

# ============================================================
# TEST: ls --sort updated orders by last modification
# ============================================================
run_test
setup_repo
GIT_AUTHOR_DATE="2025-01-01T00:00:00Z" git issue create "Old issue" >/dev/null
GIT_AUTHOR_DATE="2025-06-01T00:00:00Z" git issue create "New issue" >/dev/null
output="$(git issue ls --sort updated --format oneline 2>&1)"
first_line="$(printf '%s\n' "$output" | head -1)"
case "$first_line" in
	*"New issue"*)
		pass "ls --sort updated orders by last modification"
		;;
	*)
		fail "ls --sort updated orders by last modification" "first: $first_line"
		;;
esac

# ============================================================
# TEST: ls --sort rejects invalid value
# ============================================================
run_test
setup_repo
if git issue ls --sort invalid 2>/dev/null
then
	fail "ls --sort rejects invalid value" "should have failed"
else
	pass "ls --sort rejects invalid value"
fi

# ============================================================
# SEARCH TESTS
# ============================================================

# ============================================================
# TEST: search finds issue by title
# ============================================================
run_test
setup_repo
git issue create "Login crash on Firefox" >/dev/null
git issue create "Dark mode request" >/dev/null
output="$(git issue search "Firefox" 2>&1)"
case "$output" in
	*"Login crash on Firefox"*)
		pass "search finds issue by title"
		;;
	*)
		fail "search finds issue by title" "got: $output"
		;;
esac

# ============================================================
# TEST: search finds issue by comment
# ============================================================
run_test
setup_repo
out="$(git issue create "Some bug" 2>&1)"
short_id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue comment "$short_id" -m "The needle is in this haystack" >/dev/null
output="$(git issue search "needle" 2>&1)"
case "$output" in
	*"Some bug"*)
		pass "search finds issue by comment"
		;;
	*)
		fail "search finds issue by comment" "got: $output"
		;;
esac

# ============================================================
# TEST: search finds issue by body
# ============================================================
run_test
setup_repo
git issue create "Bug report" -m "This happens when using special tokens" >/dev/null
output="$(git issue search "special tokens" 2>&1)"
case "$output" in
	*"Bug report"*)
		pass "search finds issue by body"
		;;
	*)
		fail "search finds issue by body" "got: $output"
		;;
esac

# ============================================================
# TEST: search -i is case insensitive
# ============================================================
run_test
setup_repo
git issue create "UPPERCASE title" >/dev/null
output="$(git issue search -i "uppercase" 2>&1)"
case "$output" in
	*"UPPERCASE title"*)
		pass "search -i is case insensitive"
		;;
	*)
		fail "search -i is case insensitive" "got: $output"
		;;
esac

# ============================================================
# TEST: search --state filters results
# ============================================================
run_test
setup_repo
out="$(git issue create "Open bug" 2>&1)"
short_id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$short_id" --close >/dev/null
git issue create "Another open bug" >/dev/null
output="$(git issue search "bug" --state open 2>&1)"
case "$output" in
	*"Another open bug"*)
		case "$output" in
			*"Open bug"*)
				fail "search --state filters results" "closed issue should not appear"
				;;
			*)
				pass "search --state filters results"
				;;
		esac
		;;
	*)
		fail "search --state filters results" "got: $output"
		;;
esac

# ============================================================
# TEST: search with no matches returns nothing
# ============================================================
run_test
setup_repo
git issue create "Normal issue" >/dev/null
output="$(git issue search "xyzzy_nonexistent" 2>&1)"
case "$output" in
	*"Normal issue"*)
		fail "search with no matches returns nothing" "should not find anything"
		;;
	*)
		pass "search with no matches returns nothing"
		;;
esac

# ============================================================
# TEST: search requires pattern
# ============================================================
run_test
setup_repo
if git issue search 2>/dev/null
then
	fail "search requires pattern" "should have failed"
else
	pass "search requires pattern"
fi

# ============================================================
# TEST: search outside git repo fails
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue search "test" 2>/dev/null
then
	fail "search outside git repo fails" "should have failed"
else
	pass "search outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# INIT TESTS
# ============================================================

# ============================================================
# TEST: init with custom remote
# ============================================================
run_test
setup_repo
git remote add upstream https://example.com/test.git 2>/dev/null
output="$(git issue init upstream 2>&1)"
refspec="$(git config --get-all remote.upstream.fetch | grep issues || true)"
case "$refspec" in
	*"refs/issues"*)
		pass "init with custom remote"
		;;
	*)
		fail "init with custom remote" "refspec not found: $refspec"
		;;
esac

# ============================================================
# TEST: init with custom remote is idempotent
# ============================================================
run_test
# Repo still from previous test
output="$(git issue init upstream 2>&1)"
case "$output" in
	*"already configured"*)
		pass "init with custom remote is idempotent"
		;;
	*)
		fail "init with custom remote is idempotent" "got: $output"
		;;
esac

# ============================================================
# TEST: init with nonexistent remote fails
# ============================================================
run_test
setup_repo
git remote add origin https://example.com/test.git 2>/dev/null
if git issue init nonexistent 2>/dev/null
then
	fail "init with nonexistent remote fails" "should have failed"
else
	pass "init with nonexistent remote fails"
fi

# ============================================================
# TEST: init default still works
# ============================================================
run_test
setup_repo
git remote add origin https://example.com/test.git 2>/dev/null
output="$(git issue init 2>&1)"
refspec="$(git config --get-all remote.origin.fetch | grep issues || true)"
case "$refspec" in
	*"refs/issues"*)
		pass "init default still works"
		;;
	*)
		fail "init default still works" "refspec not found"
		;;
esac

# ============================================================
# EXPORT BODY EXTRACTION TEST
# ============================================================

# ============================================================
# TEST: export body extraction preserves trailer-like body lines
# ============================================================
run_test
setup_repo
# Create an issue whose body contains a line that looks like a trailer
git issue create "Trailer body test" -m "Note: this should not be stripped" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
# Extract body using the same logic as export
raw_body="$(git log -1 --format='%b' "$root")"
trailer_block="$(printf '%s\n' "$raw_body" | git interpret-trailers --parse 2>/dev/null)" || trailer_block=""
if test -n "$trailer_block"
then
	n_trailers="$(printf '%s\n' "$trailer_block" | wc -l | tr -d ' ')"
	n_body="$(printf '%s\n' "$raw_body" | wc -l | tr -d ' ')"
	n_keep=$((n_body - n_trailers - 1))
	if test "$n_keep" -gt 0
	then
		body="$(printf '%s\n' "$raw_body" | head -n "$n_keep")"
	else
		body=""
	fi
else
	body="$raw_body"
fi
case "$body" in
	*"Note: this should not be stripped"*)
		pass "export body extraction preserves trailer-like body lines"
		;;
	*)
		fail "export body extraction preserves trailer-like body lines" "body: '$body'"
		;;
esac

# ============================================================
# TEST: version shows 1.2.0
# ============================================================
run_test
setup_repo
output="$(git issue version 2>&1)"
case "$output" in
	*"1.2.0"*)
		pass "version shows 1.2.0"
		;;
	*)
		fail "version shows 1.2.0" "got: $output"
		;;
esac

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
