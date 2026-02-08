#!/bin/sh
#
# Tests for git-issue merge and fsck
#
# Run: sh t/test-merge.sh
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

# Helper: create a diverged issue for merge testing
# Args: <title> [extra args for create]
# Sets: issue_uuid, issue_short, issue_ref, base_commit
setup_diverged_issue() {
	out="$(git issue create "$@" 2>&1)"
	issue_short="$(printf '%s' "$out" | sed 's/Created issue //')"
	issue_ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
	issue_uuid="${issue_ref#refs/issues/}"
	base_commit="$(git rev-parse "$issue_ref")"
}

printf "Running git-issue merge & fsck tests...\n\n"

# ============================================================
# FSCK TESTS
# ============================================================

# ============================================================
# TEST: fsck passes on valid issues
# ============================================================
run_test
setup_repo
git issue create "Valid issue 1" -l bug >/dev/null
git issue create "Valid issue 2" -p high >/dev/null
output="$(git issue fsck 2>&1)"
case "$output" in
	*"ok"*"ok"*"no errors"*)
		pass "fsck passes on valid issues"
		;;
	*)
		fail "fsck passes on valid issues" "got: $output"
		;;
esac

# ============================================================
# TEST: fsck with no issues
# ============================================================
run_test
setup_repo
output="$(git issue fsck 2>&1)"
case "$output" in
	*"No issues found"*)
		pass "fsck handles no issues"
		;;
	*)
		fail "fsck handles no issues" "got: $output"
		;;
esac

# ============================================================
# TEST: fsck detects missing State trailer
# ============================================================
run_test
setup_repo
# Create a malformed issue manually (no State: trailer)
empty_tree="$(git hash-object -t tree /dev/null)"
tmpfile="$(mktemp)"
printf 'Bad issue\n\nFormat-Version: 1\n' > "$tmpfile"
commit="$(git commit-tree "$empty_tree" < "$tmpfile")"
uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
git update-ref "refs/issues/$uuid" "$commit"
rm -f "$tmpfile"
if git issue fsck 2>/dev/null
then
	fail "fsck detects missing State trailer" "should have failed"
else
	pass "fsck detects missing State trailer"
fi

# ============================================================
# TEST: fsck detects missing Format-Version trailer
# ============================================================
run_test
setup_repo
empty_tree="$(git hash-object -t tree /dev/null)"
tmpfile="$(mktemp)"
printf 'Bad issue\n\nState: open\n' > "$tmpfile"
commit="$(git commit-tree "$empty_tree" < "$tmpfile")"
uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
git update-ref "refs/issues/$uuid" "$commit"
rm -f "$tmpfile"
if git issue fsck 2>/dev/null
then
	fail "fsck detects missing Format-Version trailer" "should have failed"
else
	pass "fsck detects missing Format-Version trailer"
fi

# ============================================================
# TEST: fsck --quiet only shows errors
# ============================================================
run_test
setup_repo
git issue create "Quiet test" >/dev/null
output="$(git issue fsck --quiet 2>&1)"
case "$output" in
	*"ok"*)
		fail "fsck --quiet only shows errors" "should not show 'ok'"
		;;
	*"no errors"*)
		pass "fsck --quiet only shows errors"
		;;
	*)
		fail "fsck --quiet only shows errors" "got: $output"
		;;
esac

# ============================================================
# TEST: fsck outside git repo fails
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue fsck 2>/dev/null
then
	fail "fsck outside git repo fails" "should have failed"
else
	pass "fsck outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# MERGE TESTS
# ============================================================

# ============================================================
# TEST: merge creates new issue from remote
# ============================================================
run_test
setup_repo
# Create an issue only in "remote" tracking refs
empty_tree="$(git hash-object -t tree /dev/null)"
tmpfile="$(mktemp)"
printf 'Remote-only issue\n' > "$tmpfile"
git interpret-trailers --in-place --trailer "State: open" "$tmpfile"
git interpret-trailers --in-place --trailer "Format-Version: 1" "$tmpfile"
commit="$(git commit-tree "$empty_tree" < "$tmpfile")"
uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
git update-ref "refs/remotes/testremote/issues/$uuid" "$commit"
rm -f "$tmpfile"

output="$(git issue merge testremote --no-fetch 2>&1)"
case "$output" in
	*"Created"*"Remote-only issue"*)
		# Verify local ref exists
		if git rev-parse --verify "refs/issues/$uuid" >/dev/null 2>&1
		then
			pass "merge creates new issue from remote"
		else
			fail "merge creates new issue from remote" "local ref not created"
		fi
		;;
	*)
		fail "merge creates new issue from remote" "got: $output"
		;;
esac

# ============================================================
# TEST: merge fast-forwards when local is behind
# ============================================================
run_test
setup_repo
setup_diverged_issue "Fast-forward test"
# Add a comment (advancing the chain)
git issue comment "$issue_short" -m "A comment" >/dev/null
advanced_head="$(git rev-parse "$issue_ref")"

# Reset local to base, put advanced in remote
git update-ref "$issue_ref" "$base_commit"
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$advanced_head"

output="$(git issue merge testremote --no-fetch 2>&1)"
local_after="$(git rev-parse "$issue_ref")"
if test "$local_after" = "$advanced_head"
then
	case "$output" in
		*"Fast-forwarded"*)
			pass "merge fast-forwards when local is behind"
			;;
		*)
			fail "merge fast-forwards when local is behind" "got: $output"
			;;
	esac
else
	fail "merge fast-forwards when local is behind" "ref not updated"
fi

# ============================================================
# TEST: merge skips when remote is behind (up-to-date)
# ============================================================
run_test
setup_repo
setup_diverged_issue "Up-to-date test"
git issue comment "$issue_short" -m "Local ahead" >/dev/null
local_head="$(git rev-parse "$issue_ref")"

# Put base (behind) in remote
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$base_commit"

output="$(git issue merge testremote --no-fetch 2>&1)"
local_after="$(git rev-parse "$issue_ref")"
if test "$local_after" = "$local_head"
then
	case "$output" in
		*"up-to-date"*)
			pass "merge skips when remote is behind"
			;;
		*)
			fail "merge skips when remote is behind" "got: $output"
			;;
	esac
else
	fail "merge skips when remote is behind" "ref changed unexpectedly"
fi

# ============================================================
# TEST: merge skips when already in sync
# ============================================================
run_test
setup_repo
setup_diverged_issue "Sync test"
local_head="$(git rev-parse "$issue_ref")"

# Same commit in remote
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$local_head"

output="$(git issue merge testremote --no-fetch 2>&1)"
case "$output" in
	*"up-to-date"*)
		pass "merge skips when already in sync"
		;;
	*)
		fail "merge skips when already in sync" "got: $output"
		;;
esac

# ============================================================
# TEST: merge resolves diverged issue with comments (union)
# ============================================================
run_test
setup_repo
setup_diverged_issue "Diverged comments test"

# Add local comment
git issue comment "$issue_short" -m "Local comment" >/dev/null
local_head="$(git rev-parse "$issue_ref")"

# Reset to base, add remote comment
git update-ref "$issue_ref" "$base_commit"
git issue comment "$issue_short" -m "Remote comment" >/dev/null
remote_head="$(git rev-parse "$issue_ref")"

# Set local back, put remote in tracking
git update-ref "$issue_ref" "$local_head"
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$remote_head"

output="$(git issue merge testremote --no-fetch 2>&1)"
case "$output" in
	*"Merged"*"diverged"*)
		# Verify merge commit has two parents
		merge_head="$(git rev-parse "$issue_ref")"
		parent_count="$(git log -1 --format='%P' "$merge_head" | wc -w | tr -d ' ')"
		if test "$parent_count" -eq 2
		then
			# Verify both comments are reachable
			all_subjects="$(git log --format='%s' "$issue_ref")"
			case "$all_subjects" in
				*"Local comment"*"Remote comment"*|*"Remote comment"*"Local comment"*)
					pass "merge creates merge commit preserving both comments"
					;;
				*)
					fail "merge creates merge commit preserving both comments" "subjects: $all_subjects"
					;;
			esac
		else
			fail "merge creates merge commit preserving both comments" "expected 2 parents, got $parent_count"
		fi
		;;
	*)
		fail "merge creates merge commit preserving both comments" "got: $output"
		;;
esac

# ============================================================
# TEST: merge resolves scalar with LWW (later timestamp wins)
# ============================================================
run_test
setup_repo
setup_diverged_issue "Scalar LWW test" -p low

# Local: change priority to medium (earlier timestamp)
GIT_AUTHOR_DATE="2025-01-01T00:00:00Z" \
	git issue edit "$issue_short" -p medium >/dev/null
local_head="$(git rev-parse "$issue_ref")"

# Reset to base, remote: change priority to critical (later timestamp wins)
git update-ref "$issue_ref" "$base_commit"
GIT_AUTHOR_DATE="2025-06-01T00:00:00Z" \
	git issue edit "$issue_short" -p critical >/dev/null
remote_head="$(git rev-parse "$issue_ref")"

# Set local back, put remote in tracking
git update-ref "$issue_ref" "$local_head"
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$remote_head"

git issue merge testremote --no-fetch >/dev/null 2>&1

# Check resolved priority — remote's "critical" should win (later timestamp)
resolved_priority="$(git log --format='%(trailers:key=Priority,valueonly)' "$issue_ref" | \
	sed '/^$/d' | sed 's/^[[:space:]]*//' | head -1)"
if test "$resolved_priority" = "critical"
then
	pass "merge resolves scalar with LWW (later timestamp wins)"
else
	fail "merge resolves scalar with LWW (later timestamp wins)" "got priority: '$resolved_priority'"
fi

# ============================================================
# TEST: merge resolves labels with three-way set merge
# ============================================================
run_test
setup_repo
# Create issue with base labels: bug, docs
setup_diverged_issue "Label merge test" -l bug -l docs

# Local: add "security", remove "docs" → bug, security
git issue edit "$issue_short" --remove-label docs --add-label security >/dev/null
local_head="$(git rev-parse "$issue_ref")"

# Reset to base, remote: add "urgent", keep docs → bug, docs, urgent
git update-ref "$issue_ref" "$base_commit"
git issue edit "$issue_short" --add-label urgent >/dev/null
remote_head="$(git rev-parse "$issue_ref")"

# Set local back, put remote in tracking
git update-ref "$issue_ref" "$local_head"
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$remote_head"

git issue merge testremote --no-fetch >/dev/null 2>&1

# Expected: bug (kept by both), security (added by local), urgent (added by remote)
# docs removed by local, not re-added by remote (removal wins if not also added)
resolved_labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$issue_ref" | \
	sed '/^$/d' | sed 's/^[[:space:]]*//' | head -1)"

# Check each expected label is present
has_bug=0; has_security=0; has_urgent=0; has_docs=0
case ",$resolved_labels," in
	*"bug"*) has_bug=1 ;;
esac
case ",$resolved_labels," in
	*"security"*) has_security=1 ;;
esac
case ",$resolved_labels," in
	*"urgent"*) has_urgent=1 ;;
esac
case ",$resolved_labels," in
	*"docs"*) has_docs=1 ;;
esac

if test "$has_bug" -eq 1 && test "$has_security" -eq 1 && \
   test "$has_urgent" -eq 1 && test "$has_docs" -eq 0
then
	pass "merge resolves labels with three-way set merge"
else
	fail "merge resolves labels with three-way set merge" "got: '$resolved_labels'"
fi

# ============================================================
# TEST: merge --check detects divergence without merging
# ============================================================
run_test
setup_repo
setup_diverged_issue "Check mode test"

git issue comment "$issue_short" -m "Local" >/dev/null
local_head="$(git rev-parse "$issue_ref")"

git update-ref "$issue_ref" "$base_commit"
git issue comment "$issue_short" -m "Remote" >/dev/null
remote_head="$(git rev-parse "$issue_ref")"

git update-ref "$issue_ref" "$local_head"
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$remote_head"

output="$(git issue merge testremote --no-fetch --check 2>&1)"
local_after="$(git rev-parse "$issue_ref")"

if test "$local_after" = "$local_head"
then
	case "$output" in
		*"diverged"*)
			pass "merge --check detects divergence without merging"
			;;
		*)
			fail "merge --check detects divergence without merging" "got: $output"
			;;
	esac
else
	fail "merge --check detects divergence without merging" "ref was modified"
fi

# ============================================================
# TEST: merge with no remote issues
# ============================================================
run_test
setup_repo
output="$(git issue merge testremote --no-fetch 2>&1)"
case "$output" in
	*"No issues found"*)
		pass "merge handles no remote issues"
		;;
	*)
		fail "merge handles no remote issues" "got: $output"
		;;
esac

# ============================================================
# TEST: merge outside git repo fails
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue merge testremote 2>/dev/null
then
	fail "merge outside git repo fails" "should have failed"
else
	pass "merge outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# TEST: merge preserves only one side's changes for scalar
# ============================================================
run_test
setup_repo
setup_diverged_issue "Scalar merge test" -a "base@test.com" -p low

# Local: change assignee only
git issue edit "$issue_short" -a "local@test.com" >/dev/null
local_head="$(git rev-parse "$issue_ref")"

# Remote: change priority only
git update-ref "$issue_ref" "$base_commit"
git issue edit "$issue_short" -p critical >/dev/null
remote_head="$(git rev-parse "$issue_ref")"

git update-ref "$issue_ref" "$local_head"
git update-ref "refs/remotes/testremote/issues/$issue_uuid" "$remote_head"

git issue merge testremote --no-fetch >/dev/null 2>&1

resolved_assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$issue_ref" | \
	sed '/^$/d' | sed 's/^[[:space:]]*//' | head -1)"
resolved_priority="$(git log --format='%(trailers:key=Priority,valueonly)' "$issue_ref" | \
	sed '/^$/d' | sed 's/^[[:space:]]*//' | head -1)"

if test "$resolved_assignee" = "local@test.com" && test "$resolved_priority" = "critical"
then
	pass "merge preserves non-conflicting scalar changes from both sides"
else
	fail "merge preserves non-conflicting scalar changes from both sides" \
		"assignee='$resolved_assignee' priority='$resolved_priority'"
fi

# ============================================================
# TEST: merge with real remote (two-repo scenario)
# ============================================================
run_test
setup_repo
git issue create "Two-repo test" -l feature >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
uuid="${ref#refs/issues/}"
short_id="$(printf '%s' "$uuid" | cut -c1-7)"

# Create a bare remote and push
git clone -q --bare "$TEST_DIR/repo" "$TEST_DIR/bare.git" 2>/dev/null
# Push issue refs to bare
git push -q "$TEST_DIR/bare.git" "refs/issues/*:refs/issues/*" 2>/dev/null

# Clone to a second repo
git clone -q "$TEST_DIR/bare.git" "$TEST_DIR/repo2" 2>/dev/null
cd "$TEST_DIR/repo2"
export PATH="$BIN_DIR:$PATH"
git fetch -q origin "+refs/issues/*:refs/issues/*" 2>/dev/null

# Add a comment in repo2
git issue comment "$short_id" -m "Comment from repo2" >/dev/null
git push -q origin "refs/issues/*:refs/issues/*" 2>/dev/null

# Back in repo1, add a local comment
cd "$TEST_DIR/repo"
git issue comment "$short_id" -m "Comment from repo1" >/dev/null

# Add the bare as a remote if not already
git remote add bare "$TEST_DIR/bare.git" 2>/dev/null || true

# Merge from bare (which has repo2's changes)
output="$(git issue merge bare 2>&1)"
case "$output" in
	*"Merged"*|*"Fast-forwarded"*|*"Created"*)
		# Check both comments are present
		all_subjects="$(git log --format='%s' "$ref")"
		case "$all_subjects" in
			*"Comment from repo1"*"Comment from repo2"*|*"Comment from repo2"*"Comment from repo1"*)
				pass "merge works with real remote (two-repo scenario)"
				;;
			*)
				fail "merge works with real remote (two-repo scenario)" "missing comments: $all_subjects"
				;;
		esac
		;;
	*)
		fail "merge works with real remote (two-repo scenario)" "got: $output"
		;;
esac

# ============================================================
# TEST: fsck passes after merge (merge commits are valid)
# ============================================================
run_test
output="$(git issue fsck --quiet 2>&1)"
case "$output" in
	*"no errors"*)
		pass "fsck passes after merge"
		;;
	*"error"*)
		fail "fsck passes after merge" "got: $output"
		;;
	*)
		fail "fsck passes after merge" "got: $output"
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
