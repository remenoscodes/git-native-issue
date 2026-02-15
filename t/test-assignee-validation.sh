#!/bin/sh
#
# test-assignee-validation.sh - Tests for assignee validation and combined filters
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

printf "Running git-issue assignee validation tests...\n\n"

# TEST 1: Valid email formats accepted
run_test
setup_repo
for email in "user@example.com" "first.last@sub.domain.org" "user+tag@example.com" "test_user@example.co.uk"
do
	if git-issue-create "Test $email" -a "$email" >/dev/null 2>&1
	then
		:
	else
		fail "valid email accepted: $email"
		continue
	fi
done
pass "valid email formats accepted"

# TEST 2: Invalid email formats rejected - no @
run_test
setup_repo
if git-issue-create "Test" -a "notanemail" >/dev/null 2>&1
then
	fail "invalid email rejected: no @"
else
	pass "invalid email rejected: no @"
fi

# TEST 3: Invalid email formats rejected - no domain
run_test
setup_repo
if git-issue-create "Test" -a "user@" >/dev/null 2>&1
then
	fail "invalid email rejected: no domain"
else
	pass "invalid email rejected: no domain"
fi

# TEST 4: Invalid email formats rejected - no TLD
run_test
setup_repo
if git-issue-create "Test" -a "user@domain" >/dev/null 2>&1
then
	fail "invalid email rejected: no TLD"
else
	pass "invalid email rejected: no TLD"
fi

# TEST 5: Invalid email formats rejected - missing local part
run_test
setup_repo
if git-issue-create "Test" -a "@example.com" >/dev/null 2>&1
then
	fail "invalid email rejected: missing local part"
else
	pass "invalid email rejected: missing local part"
fi

# TEST 6: Assignee can be changed
run_test
setup_repo
id="$(git-issue-create "Test" -a "user@example.com" 2>&1 | awk '{print $NF}')"
if git-issue-edit "$id" -a "newuser@example.com" >/dev/null 2>&1
then
	ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
	assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
	if test "$assignee" = "newuser@example.com"
	then
		pass "assignee can be changed"
	else
		fail "assignee change" "expected newuser@example.com, got: $assignee"
	fi
else
	fail "assignee should be changeable"
fi

# TEST 7: Assignee displayed correctly
run_test
setup_repo
id="$(git-issue-create "Test assignee display" -a "alice@example.com" 2>&1 | awk '{print $NF}')"
output="$(git-issue-show "$id")"
case "$output" in
	*"Assignee: alice@example.com"*)
		pass "assignee displayed in show"
		;;
	*)
		fail "assignee display" "not found in output"
		;;
esac

# TEST 8: Assignee filter works
run_test
setup_repo
id1="$(git-issue-create "Alice task" -a "alice@example.com" 2>&1 | awk '{print $NF}')"
id2="$(git-issue-create "Bob task" -a "bob@example.com" 2>&1 | awk '{print $NF}')"
id3="$(git-issue-create "Unassigned task" 2>&1 | awk '{print $NF}')"

output="$(git-issue-ls --assignee alice@example.com)"
case "$output" in
	*"$id1"*)
		case "$output" in
			*"$id2"*|*"$id3"*)
				fail "assignee filter" "included non-matching issues"
				;;
			*)
				pass "assignee filter works"
				;;
		esac
		;;
	*)
		fail "assignee filter" "didn't include matching issue"
		;;
esac

# TEST 9: Combined assignee + label filter
run_test
setup_repo
id1="$(git-issue-create "Alice bug" -a "alice@example.com" -l bug 2>&1 | awk '{print $NF}')"
id2="$(git-issue-create "Alice feature" -a "alice@example.com" -l feature 2>&1 | awk '{print $NF}')"
id3="$(git-issue-create "Bob bug" -a "bob@example.com" -l bug 2>&1 | awk '{print $NF}')"

output="$(git-issue-ls --assignee alice@example.com --label bug)"
case "$output" in
	*"$id1"*)
		case "$output" in
			*"$id2"*|*"$id3"*)
				fail "assignee + label filter" "included non-matching issues"
				;;
			*)
				pass "assignee + label filter works"
				;;
		esac
		;;
	*)
		fail "assignee + label filter" "didn't include matching issue"
		;;
esac

# TEST 10: Combined assignee + state filter
run_test
setup_repo
id1="$(git-issue-create "Alice open" -a "alice@example.com" 2>&1 | awk '{print $NF}')"
id2="$(git-issue-create "Alice closed" -a "alice@example.com" 2>&1 | awk '{print $NF}')"
git-issue-state "$id2" --close -m "Done" >/dev/null 2>&1
id3="$(git-issue-create "Bob open" -a "bob@example.com" 2>&1 | awk '{print $NF}')"

output="$(git-issue-ls --assignee alice@example.com --state open)"
case "$output" in
	*"$id1"*)
		case "$output" in
			*"$id2"*|*"$id3"*)
				fail "assignee + state filter" "included non-matching issues"
				;;
			*)
				pass "assignee + state filter works"
				;;
		esac
		;;
	*)
		fail "assignee + state filter" "didn't include matching issue"
		;;
esac

# TEST 11: Combined assignee + label + state filter (triple combination)
run_test
setup_repo
id1="$(git-issue-create "Alice open bug" -a "alice@example.com" -l bug 2>&1 | awk '{print $NF}')"
id2="$(git-issue-create "Alice closed bug" -a "alice@example.com" -l bug 2>&1 | awk '{print $NF}')"
git-issue-state "$id2" --close -m "Fixed" >/dev/null 2>&1
id3="$(git-issue-create "Alice open feature" -a "alice@example.com" -l feature 2>&1 | awk '{print $NF}')"
id4="$(git-issue-create "Bob open bug" -a "bob@example.com" -l bug 2>&1 | awk '{print $NF}')"

output="$(git-issue-ls --assignee alice@example.com --label bug --state open)"
case "$output" in
	*"$id1"*)
		case "$output" in
			*"$id2"*|*"$id3"*|*"$id4"*)
				fail "triple filter (assignee+label+state)" "included non-matching issues"
				;;
			*)
				pass "triple filter (assignee+label+state) works"
				;;
		esac
		;;
	*)
		fail "triple filter" "didn't include matching issue"
		;;
esac

# TEST 12: Assignee in full format display
run_test
setup_repo
id="$(git-issue-create "Full format test" -a "alice@example.com" -l bug -p high 2>&1 | awk '{print $NF}')"
output="$(git-issue-ls --format full)"
case "$output" in
	*"assignee:alice@example.com"*)
		pass "assignee in full format display"
		;;
	*)
		fail "assignee in full format" "not found"
		;;
esac

# TEST 13: Edit assignee changes assignment
run_test
setup_repo
id="$(git-issue-create "Test" -a "alice@example.com" 2>&1 | awk '{print $NF}')"
git-issue-edit "$id" -a "bob@example.com" >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
if test "$assignee" = "bob@example.com"
then
	pass "edit assignee changes assignment"
else
	fail "edit assignee" "expected bob@example.com, got: $assignee"
fi

# TEST 14: Combined edit (assignee + labels + priority)
run_test
setup_repo
id="$(git-issue-create "Combined edit test" 2>&1 | awk '{print $NF}')"
git-issue-edit "$id" -a "alice@example.com" -l bug -l security -p critical >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
priority="$(git log --format='%(trailers:key=Priority,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"

if test "$assignee" = "alice@example.com" && \
   test "$labels" = "bug, security" && \
   test "$priority" = "critical"
then
	pass "combined edit (assignee+labels+priority) works"
else
	fail "combined edit" "assignee=$assignee labels=$labels priority=$priority"
fi

# TEST 15: Email validation error message is helpful
run_test
setup_repo
output="$(git-issue-create "Test" -a "invalid-email" 2>&1 || true)"
case "$output" in
	*"valid email address"*)
		pass "email validation error message is helpful"
		;;
	*)
		fail "error message guidance" "got: $output"
		;;
esac

# TEST 16: Assignee can be unassigned (cleared) with empty string
run_test
setup_repo
id="$(git-issue-create "Test unassign" -a "user@example.com" 2>&1 | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
# Verify initial assignment
assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
if test "$assignee" != "user@example.com"
then
	fail "unassign setup" "expected user@example.com, got: $assignee"
else
	# Clear the assignee
	if git-issue-edit "$id" -a "" >/dev/null 2>&1
	then
		# Verify assignee was cleared
		assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$ref" | head -1 | sed 's/^[[:space:]]*//')"
		if test -z "$assignee"
		then
			# Verify show doesn't display Assignee line in header (before Updates section)
			show_output="$(git-issue-show "$id" | sed '/^----/,$d')"
			case "$show_output" in
				*"Assignee:"*)
					fail "unassign" "Assignee still shown in header"
					;;
				*)
					pass "assignee can be unassigned with empty string"
					;;
			esac
		else
			fail "unassign" "expected empty, got: $assignee"
		fi
	else
		fail "unassign" "edit with empty assignee failed"
	fi
fi

# TEST 17: Unassigned issue not shown when filtering by assignee
run_test
setup_repo
id1="$(git-issue-create "Assigned" -a "user@example.com" 2>&1 | awk '{print $NF}')"
id2="$(git-issue-create "Unassigned" 2>&1 | awk '{print $NF}')"
id3="$(git-issue-create "Was assigned" -a "user@example.com" 2>&1 | awk '{print $NF}')"
git-issue-edit "$id3" -a "" >/dev/null 2>&1

output="$(git-issue-ls --assignee user@example.com)"
case "$output" in
	*"$id1"*)
		case "$output" in
			*"$id2"*|*"$id3"*)
				fail "unassigned filter" "included unassigned or cleared issues"
				;;
			*)
				pass "unassigned issue excluded from assignee filter"
				;;
		esac
		;;
	*)
		fail "unassigned filter" "didn't include assigned issue"
		;;
esac

# TEST 18: Platform user cache write and read
run_test
setup_repo
. "$BIN_DIR/git-issue-lib"
cache_platform_user "alice@example.com" "alice-gh" "12345" "github"
cached_login="$(lookup_cached_login "alice@example.com" "github")"
if test "$cached_login" = "alice-gh"
then
	pass "platform user cache write and read"
else
	fail "platform user cache" "expected alice-gh, got: $cached_login"
fi

# TEST 19: Platform user cache ID lookup
run_test
cached_id="$(lookup_cached_user_id "alice@example.com" "github")"
if test "$cached_id" = "12345"
then
	pass "platform user cache ID lookup"
else
	fail "platform user cache ID" "expected 12345, got: $cached_id"
fi

# TEST 20: Cache update replaces stale entry
run_test
cache_platform_user "alice@example.com" "alice-new" "12345" "github"
cached_login="$(lookup_cached_login "alice@example.com" "github")"
entry_count="$(grep -c "^alice@example.com," "$(get_user_cache_path github)" 2>/dev/null || echo 0)"
if test "$cached_login" = "alice-new" && test "$entry_count" -eq 1
then
	pass "cache update replaces stale entry (no duplicates)"
else
	fail "cache update" "login=$cached_login count=$entry_count"
fi

# TEST 21: Cache miss returns empty (not error)
run_test
cached_login="$(lookup_cached_login "nobody@example.com" "github")"
if test -z "$cached_login"
then
	pass "cache miss returns empty"
else
	fail "cache miss" "expected empty, got: $cached_login"
fi

# TEST 22: Multiple users in cache don't collide
run_test
cache_platform_user "bob@example.com" "bob-gh" "67890" "github"
alice_login="$(lookup_cached_login "alice@example.com" "github")"
bob_login="$(lookup_cached_login "bob@example.com" "github")"
if test "$alice_login" = "alice-new" && test "$bob_login" = "bob-gh"
then
	pass "multiple users in cache don't collide"
else
	fail "multi-user cache" "alice=$alice_login bob=$bob_login"
fi

printf "\n============================================================\n"
printf "Tests: %d | Passed: %d | Failed: %d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "============================================================\n"

if test "$TESTS_FAILED" -gt 0; then
	exit 1
fi
exit 0
