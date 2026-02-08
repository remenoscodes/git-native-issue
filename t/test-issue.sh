#!/bin/sh
#
# Tests for git-issue
#
# Run: sh t/test-issue.sh
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

# Set up a fresh test repo for each test
setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git commit --allow-empty -q -m "initial"
	export PATH="$BIN_DIR:$PATH"
}

printf "Running git-issue tests...\n\n"

# ============================================================
# TEST: git issue version
# ============================================================
run_test
setup_repo
output="$(git issue version 2>&1)"
case "$output" in
	*"git-issue version"*)
		pass "git issue version prints version"
		;;
	*)
		fail "git issue version prints version" "got: $output"
		;;
esac

# ============================================================
# TEST: git issue create basic
# ============================================================
run_test
setup_repo
output="$(git issue create "Test issue title" 2>&1)"
case "$output" in
	"Created issue "???????)
		pass "git issue create outputs short ID"
		;;
	*)
		fail "git issue create outputs short ID" "got: $output"
		;;
esac

# ============================================================
# TEST: created issue has correct ref
# ============================================================
run_test
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 1
then
	pass "created issue has exactly one ref"
else
	fail "created issue has exactly one ref" "got $ref_count refs"
fi

# ============================================================
# TEST: issue ref uses UUID format
# ============================================================
run_test
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
uuid="${ref#refs/issues/}"
case "$uuid" in
	????????-????-????-????-????????????)
		pass "issue ref uses UUID format"
		;;
	*)
		fail "issue ref uses UUID format" "got: $uuid"
		;;
esac

# ============================================================
# TEST: root commit has correct subject (title)
# ============================================================
run_test
root="$(git rev-list --max-parents=0 "$ref")"
subject="$(git log -1 --format='%s' "$root")"
if test "$subject" = "Test issue title"
then
	pass "root commit subject is the issue title"
else
	fail "root commit subject is the issue title" "got: $subject"
fi

# ============================================================
# TEST: root commit uses empty tree
# ============================================================
run_test
tree="$(git log -1 --format='%T' "$root")"
empty_tree="$(git hash-object -t tree /dev/null)"
if test "$tree" = "$empty_tree"
then
	pass "root commit uses empty tree"
else
	fail "root commit uses empty tree" "got tree: $tree"
fi

# ============================================================
# TEST: root commit has State: open trailer
# ============================================================
run_test
state="$(git log -1 --format='%(trailers:key=State,valueonly)' "$root" | sed '/^$/d')"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "open"
then
	pass "root commit has State: open trailer"
else
	fail "root commit has State: open trailer" "got: '$state'"
fi

# ============================================================
# TEST: root commit has Format-Version: 1 trailer
# ============================================================
run_test
fv="$(git log -1 --format='%(trailers:key=Format-Version,valueonly)' "$root" | sed '/^$/d')"
fv="$(printf '%s' "$fv" | sed 's/^[[:space:]]*//')"
if test "$fv" = "1"
then
	pass "root commit has Format-Version: 1 trailer"
else
	fail "root commit has Format-Version: 1 trailer" "got: '$fv'"
fi

# ============================================================
# TEST: create with labels
# ============================================================
run_test
setup_repo
git issue create "Bug with labels" -l bug -l auth >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d')"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, auth"
then
	pass "create with labels stores Labels: trailer"
else
	fail "create with labels stores Labels: trailer" "got: '$labels'"
fi

# ============================================================
# TEST: create with body
# ============================================================
run_test
setup_repo
git issue create "Issue with body" -m "This is the description body" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
body="$(git log -1 --format='%b' "$root" | sed '/^[A-Z][A-Za-z-]*: /d' | sed '/^$/d')"
case "$body" in
	*"This is the description body"*)
		pass "create with body stores description"
		;;
	*)
		fail "create with body stores description" "got: '$body'"
		;;
esac

# ============================================================
# TEST: create with priority
# ============================================================
run_test
setup_repo
git issue create "High priority bug" -p critical >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
prio="$(git log -1 --format='%(trailers:key=Priority,valueonly)' "$root" | sed '/^$/d')"
prio="$(printf '%s' "$prio" | sed 's/^[[:space:]]*//')"
if test "$prio" = "critical"
then
	pass "create with priority stores Priority: trailer"
else
	fail "create with priority stores Priority: trailer" "got: '$prio'"
fi

# ============================================================
# TEST: create rejects invalid priority
# ============================================================
run_test
setup_repo
if git issue create "Bad priority" -p urgent 2>/dev/null
then
	fail "create rejects invalid priority" "should have failed"
else
	pass "create rejects invalid priority"
fi

# ============================================================
# TEST: create requires title
# ============================================================
run_test
setup_repo
if git issue create 2>/dev/null
then
	fail "create requires title" "should have failed"
else
	pass "create requires title"
fi

# ============================================================
# TEST: git issue ls shows open issues
# ============================================================
run_test
setup_repo
git issue create "First issue" >/dev/null
git issue create "Second issue" >/dev/null
count="$(git issue ls | wc -l | tr -d ' ')"
if test "$count" -eq 2
then
	pass "ls shows open issues"
else
	fail "ls shows open issues" "expected 2, got $count"
fi

# ============================================================
# TEST: git issue ls filters by state
# ============================================================
run_test
setup_repo
out1="$(git issue create "Open issue" 2>&1)"
id1="$(printf '%s' "$out1" | sed 's/Created issue //')"
git issue create "Another issue" >/dev/null
git issue state "$id1" --close >/dev/null
open_count="$(git issue ls | wc -l | tr -d ' ')"
all_count="$(git issue ls --all | wc -l | tr -d ' ')"
if test "$open_count" -eq 1 && test "$all_count" -eq 2
then
	pass "ls filters by state"
else
	fail "ls filters by state" "open=$open_count all=$all_count"
fi

# ============================================================
# TEST: git issue ls filters by label
# ============================================================
run_test
setup_repo
git issue create "Bug issue" -l bug >/dev/null
git issue create "Feature issue" -l feature >/dev/null
bug_count="$(git issue ls -l bug | wc -l | tr -d ' ')"
feat_count="$(git issue ls -l feature | wc -l | tr -d ' ')"
if test "$bug_count" -eq 1 && test "$feat_count" -eq 1
then
	pass "ls filters by label"
else
	fail "ls filters by label" "bug=$bug_count feature=$feat_count"
fi

# ============================================================
# TEST: git issue show displays issue details
# ============================================================
run_test
setup_repo
out="$(git issue create "Show test issue" -m "Description here" -l bug -p high 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
show_output="$(git issue show "$id")"
case "$show_output" in
	*"Show test issue"*"bug"*"high"*)
		pass "show displays issue details"
		;;
	*)
		fail "show displays issue details" "missing expected content"
		;;
esac

# ============================================================
# TEST: git issue show with nonexistent ID
# ============================================================
run_test
setup_repo
if git issue show "zzzzzzz" 2>/dev/null
then
	fail "show with nonexistent ID fails" "should have failed"
else
	pass "show with nonexistent ID fails"
fi

# ============================================================
# TEST: git issue comment adds a comment
# ============================================================
run_test
setup_repo
out="$(git issue create "Comment test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue comment "$id" -m "This is a comment" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
commit_count="$(git rev-list --count "$ref")"
if test "$commit_count" -eq 2
then
	pass "comment creates a child commit"
else
	fail "comment creates a child commit" "expected 2 commits, got $commit_count"
fi

# ============================================================
# TEST: comment commit has correct parent
# ============================================================
run_test
head_commit="$(git rev-parse "$ref")"
parent="$(git log -1 --format='%P' "$head_commit")"
root="$(git rev-list --max-parents=0 "$ref")"
if test "$parent" = "$root"
then
	pass "comment commit has root as parent"
else
	fail "comment commit has root as parent" "parent=$parent root=$root"
fi

# ============================================================
# TEST: comment content is stored correctly
# ============================================================
run_test
comment_subject="$(git log -1 --format='%s' "$head_commit")"
if test "$comment_subject" = "This is a comment"
then
	pass "comment content stored correctly"
else
	fail "comment content stored correctly" "got: '$comment_subject'"
fi

# ============================================================
# TEST: git issue state --close changes state
# ============================================================
run_test
setup_repo
out="$(git issue create "State test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --close >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | sed '/^$/d' | head -1)"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "closed"
then
	pass "state --close changes state to closed"
else
	fail "state --close changes state to closed" "got: '$state'"
fi

# ============================================================
# TEST: git issue state --open reopens issue
# ============================================================
run_test
git issue state "$id" --open >/dev/null
state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | sed '/^$/d' | head -1)"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "open"
then
	pass "state --open reopens issue"
else
	fail "state --open reopens issue" "got: '$state'"
fi

# ============================================================
# TEST: state change with --fixed-by records trailer
# ============================================================
run_test
setup_repo
out="$(git issue create "Fix test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --close --fixed-by abc123 --release v1.0 >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
fixed="$(git log -1 --format='%(trailers:key=Fixed-By,valueonly)' "$ref" | sed '/^$/d')"
fixed="$(printf '%s' "$fixed" | sed 's/^[[:space:]]*//')"
release="$(git log -1 --format='%(trailers:key=Release,valueonly)' "$ref" | sed '/^$/d')"
release="$(printf '%s' "$release" | sed 's/^[[:space:]]*//')"
if test "$fixed" = "abc123" && test "$release" = "v1.0"
then
	pass "state change records Fixed-By and Release trailers"
else
	fail "state change records Fixed-By and Release trailers" "fixed='$fixed' release='$release'"
fi

# ============================================================
# TEST: multiple issues have unique UUIDs
# ============================================================
run_test
setup_repo
git issue create "Issue A" >/dev/null
git issue create "Issue B" >/dev/null
git issue create "Issue C" >/dev/null
uuid_count="$(git for-each-ref --format='%(refname)' refs/issues/ | sort -u | wc -l | tr -d ' ')"
if test "$uuid_count" -eq 3
then
	pass "multiple issues have unique UUIDs"
else
	fail "multiple issues have unique UUIDs" "expected 3 unique, got $uuid_count"
fi

# ============================================================
# TEST: git issue init configures fetch refspec
# ============================================================
run_test
setup_repo
git remote add origin https://example.com/test.git
git issue init >/dev/null
refspec="$(git config --get-all remote.origin.fetch | grep issues || true)"
if test -n "$refspec"
then
	pass "init configures fetch refspec for issues"
else
	fail "init configures fetch refspec for issues"
fi

# ============================================================
# TEST: git issue init is idempotent
# ============================================================
run_test
git issue init >/dev/null
refspec_count="$(git config --get-all remote.origin.fetch | grep -c issues || true)"
if test "$refspec_count" -eq 1
then
	pass "init is idempotent"
else
	fail "init is idempotent" "refspec added $refspec_count times"
fi

# ============================================================
# TEST: for-each-ref listing works (spec compliance)
# ============================================================
run_test
setup_repo
git issue create "Spec compliance test" -l bug >/dev/null
output="$(git for-each-ref \
	--format='%(refname:short) %(contents:subject) %(trailers:key=State,valueonly)' \
	refs/issues/)"
case "$output" in
	*"Spec compliance test"*"open"*)
		pass "for-each-ref listing works per spec"
		;;
	*)
		fail "for-each-ref listing works per spec" "got: $output"
		;;
esac

# ============================================================
# TEST: show displays comments
# ============================================================
run_test
setup_repo
out="$(git issue create "Comment display test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue comment "$id" -m "First comment" >/dev/null
git issue comment "$id" -m "Second comment" >/dev/null
show_output="$(git issue show "$id")"
case "$show_output" in
	*"First comment"*"Second comment"*)
		pass "show displays comments in order"
		;;
	*)
		fail "show displays comments in order"
		;;
esac

# ============================================================
# TEST: comment requires message
# ============================================================
run_test
setup_repo
out="$(git issue create "Msg required test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
if git issue comment "$id" 2>/dev/null
then
	fail "comment requires -m message" "should have failed"
else
	pass "comment requires -m message"
fi

# ============================================================
# TEST: state requires a state flag
# ============================================================
run_test
if git issue state "$id" 2>/dev/null
then
	fail "state requires --open/--close/--state" "should have failed"
else
	pass "state requires --open/--close/--state"
fi

# ============================================================
# TEST: works outside git repo
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue ls 2>/dev/null
then
	fail "fails outside git repo" "should have failed"
else
	pass "fails outside git repo"
fi
rm -rf "$tmpdir"

# ============================================================
# TEST: create with --assignee
# ============================================================
run_test
setup_repo
git issue create "Assignee test" -a "dev@example.com" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d')"
assignee="$(printf '%s' "$assignee" | sed 's/^[[:space:]]*//')"
if test "$assignee" = "dev@example.com"
then
	pass "create with --assignee stores Assignee: trailer"
else
	fail "create with --assignee stores Assignee: trailer" "got: '$assignee'"
fi

# ============================================================
# TEST: create with --milestone
# ============================================================
run_test
setup_repo
git issue create "Milestone test" --milestone "v1.0" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
ms="$(git log -1 --format='%(trailers:key=Milestone,valueonly)' "$root" | sed '/^$/d')"
ms="$(printf '%s' "$ms" | sed 's/^[[:space:]]*//')"
if test "$ms" = "v1.0"
then
	pass "create with --milestone stores Milestone: trailer"
else
	fail "create with --milestone stores Milestone: trailer" "got: '$ms'"
fi

# ============================================================
# TEST: create with all options combined
# ============================================================
run_test
setup_repo
git issue create "Full options test" \
	-m "Detailed description" \
	-l bug -l security \
	-a "alice@example.com" \
	-p critical \
	--milestone "v2.0" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
t_title="$(git log -1 --format='%s' "$root")"
t_state="$(git log -1 --format='%(trailers:key=State,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
t_labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
t_assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
t_prio="$(git log -1 --format='%(trailers:key=Priority,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
t_ms="$(git log -1 --format='%(trailers:key=Milestone,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
t_fv="$(git log -1 --format='%(trailers:key=Format-Version,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
if test "$t_title" = "Full options test" &&
   test "$t_state" = "open" &&
   test "$t_labels" = "bug, security" &&
   test "$t_assignee" = "alice@example.com" &&
   test "$t_prio" = "critical" &&
   test "$t_ms" = "v2.0" &&
   test "$t_fv" = "1"
then
	pass "create with all options stores all trailers correctly"
else
	fail "create with all options stores all trailers correctly" \
		"title='$t_title' state='$t_state' labels='$t_labels' assignee='$t_assignee' prio='$t_prio' ms='$t_ms' fv='$t_fv'"
fi

# ============================================================
# TEST: create with special characters in title
# ============================================================
run_test
setup_repo
git issue create 'Fix "quoted" $pecial chars & more!' >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
subject="$(git log -1 --format='%s' "$root")"
if test "$subject" = 'Fix "quoted" $pecial chars & more!'
then
	pass "create handles special characters in title"
else
	fail "create handles special characters in title" "got: '$subject'"
fi

# ============================================================
# TEST: newline injection in title is rejected
# ============================================================
run_test
setup_repo
nl="$(printf 'line1\nline2')"
if git issue create "$nl" 2>/dev/null
then
	fail "newline in title is rejected" "should have failed"
else
	pass "newline in title is rejected"
fi

# ============================================================
# TEST: ls with no issues returns empty
# ============================================================
run_test
setup_repo
output="$(git issue ls)"
if test -z "$output"
then
	pass "ls with no issues returns empty"
else
	fail "ls with no issues returns empty" "got: '$output'"
fi

# ============================================================
# TEST: ls --state closed explicitly
# ============================================================
run_test
setup_repo
out="$(git issue create "Will close" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue create "Stays open" >/dev/null
git issue state "$id" --close >/dev/null
closed_count="$(git issue ls --state closed | wc -l | tr -d ' ')"
if test "$closed_count" -eq 1
then
	pass "ls --state closed shows only closed issues"
else
	fail "ls --state closed shows only closed issues" "got $closed_count"
fi

# ============================================================
# TEST: show displays assignee and milestone
# ============================================================
run_test
setup_repo
out="$(git issue create "Metadata show test" -a "bob@test.com" --milestone "v3.0" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
show_output="$(git issue show "$id")"
case "$show_output" in
	*"bob@test.com"*"v3.0"*)
		pass "show displays assignee and milestone"
		;;
	*)
		fail "show displays assignee and milestone" "output missing metadata"
		;;
esac

# ============================================================
# TEST: show displays state change indicator
# ============================================================
run_test
setup_repo
out="$(git issue create "State display test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --close >/dev/null
show_output="$(git issue show "$id")"
case "$show_output" in
	*"[State changed to: closed]"*)
		pass "show displays state change indicator"
		;;
	*)
		fail "show displays state change indicator"
		;;
esac

# ============================================================
# TEST: show issue with no body
# ============================================================
run_test
setup_repo
out="$(git issue create "No body issue" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
show_output="$(git issue show "$id")"
case "$show_output" in
	*"No body issue"*)
		pass "show works for issue with no body"
		;;
	*)
		fail "show works for issue with no body"
		;;
esac

# ============================================================
# TEST: comment on nonexistent issue fails
# ============================================================
run_test
setup_repo
if git issue comment "zzzzzzz" -m "ghost comment" 2>/dev/null
then
	fail "comment on nonexistent issue fails" "should have failed"
else
	pass "comment on nonexistent issue fails"
fi

# ============================================================
# TEST: comment commit uses empty tree
# ============================================================
run_test
setup_repo
out="$(git issue create "Tree check" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue comment "$id" -m "Check tree" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
head_tree="$(git log -1 --format='%T' "$ref")"
empty_tree="$(git hash-object -t tree /dev/null)"
if test "$head_tree" = "$empty_tree"
then
	pass "comment commit uses empty tree"
else
	fail "comment commit uses empty tree" "got: $head_tree"
fi

# ============================================================
# TEST: three comments form correct chain
# ============================================================
run_test
setup_repo
out="$(git issue create "Chain test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue comment "$id" -m "Comment 1" >/dev/null
git issue comment "$id" -m "Comment 2" >/dev/null
git issue comment "$id" -m "Comment 3" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
total="$(git rev-list --count "$ref")"
if test "$total" -eq 4
then
	pass "three comments create correct 4-commit chain"
else
	fail "three comments create correct 4-commit chain" "got $total commits"
fi

# ============================================================
# TEST: state --state custom value
# ============================================================
run_test
setup_repo
out="$(git issue create "Custom state test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --state "in-progress" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | sed '/^$/d' | head -1)"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "in-progress"
then
	pass "state --state accepts custom values"
else
	fail "state --state accepts custom values" "got: '$state'"
fi

# ============================================================
# TEST: state --reason stores Reason: trailer
# ============================================================
run_test
setup_repo
out="$(git issue create "Reason test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --close --reason "duplicate" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
reason="$(git log -1 --format='%(trailers:key=Reason,valueonly)' "$ref" | sed '/^$/d')"
reason="$(printf '%s' "$reason" | sed 's/^[[:space:]]*//')"
if test "$reason" = "duplicate"
then
	pass "state --reason stores Reason: trailer"
else
	fail "state --reason stores Reason: trailer" "got: '$reason'"
fi

# ============================================================
# TEST: state -m uses custom message as subject
# ============================================================
run_test
setup_repo
out="$(git issue create "Message test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --close -m "Won't fix this bug" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
subject="$(git log -1 --format='%s' "$ref")"
if test "$subject" = "Won't fix this bug"
then
	pass "state -m uses custom message as commit subject"
else
	fail "state -m uses custom message as commit subject" "got: '$subject'"
fi

# ============================================================
# TEST: state on nonexistent issue fails
# ============================================================
run_test
setup_repo
if git issue state "zzzzzzz" --close 2>/dev/null
then
	fail "state on nonexistent issue fails" "should have failed"
else
	pass "state on nonexistent issue fails"
fi

# ============================================================
# TEST: state change commit uses empty tree
# ============================================================
run_test
setup_repo
out="$(git issue create "State tree check" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue state "$id" --close >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
head_tree="$(git log -1 --format='%T' "$ref")"
empty_tree="$(git hash-object -t tree /dev/null)"
if test "$head_tree" = "$empty_tree"
then
	pass "state change commit uses empty tree"
else
	fail "state change commit uses empty tree" "got: $head_tree"
fi

# ============================================================
# TEST: full lifecycle (create, comment, close, reopen, comment)
# ============================================================
run_test
setup_repo
out="$(git issue create "Lifecycle test" -l bug -p high -m "Full lifecycle" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue comment "$id" -m "Investigating" >/dev/null
git issue state "$id" --close --fixed-by deadbeef --release v1.0 --reason completed >/dev/null
git issue state "$id" --open -m "Regression found" >/dev/null
git issue comment "$id" -m "Reopened due to edge case" >/dev/null

ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
total="$(git rev-list --count "$ref")"
final_state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | sed '/^$/d' | head -1)"
final_state="$(printf '%s' "$final_state" | sed 's/^[[:space:]]*//')"

if test "$total" -eq 5 && test "$final_state" = "open"
then
	pass "full lifecycle: create, comment, close, reopen, comment"
else
	fail "full lifecycle" "commits=$total state='$final_state'"
fi

# ============================================================
# TEST: show full lifecycle displays all updates
# ============================================================
run_test
show_output="$(git issue show "$id")"
case "$show_output" in
	*"Investigating"*"closed"*"open"*"Regression found"*"Reopened"*)
		pass "show displays full lifecycle history"
		;;
	*)
		fail "show displays full lifecycle history"
		;;
esac

# ============================================================
# TEST: ls output format is correct
# ============================================================
run_test
setup_repo
git issue create "Format check" -l docs >/dev/null
output="$(git issue ls)"
# Expected format: <7-char-id> [<state>] <title>
case "$output" in
	???????\ \[open\]\ Format\ check)
		pass "ls output format matches spec"
		;;
	*)
		fail "ls output format matches spec" "got: '$output'"
		;;
esac

# ============================================================
# TEST: create outside git repo fails
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue create "Should fail" 2>/dev/null
then
	fail "create outside git repo fails" "should have failed"
else
	pass "create outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# TEST: show outside git repo fails
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue show "abc1234" 2>/dev/null
then
	fail "show outside git repo fails" "should have failed"
else
	pass "show outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# TEST: git issue edit changes labels
# ============================================================
run_test
setup_repo
out="$(git issue create "Edit labels test" -l bug 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -l feature -l docs >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1)"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "feature, docs"
then
	pass "edit replaces labels"
else
	fail "edit replaces labels" "got: '$labels'"
fi

# ============================================================
# TEST: git issue edit --add-label adds to existing
# ============================================================
run_test
setup_repo
out="$(git issue create "Add label test" -l bug 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" --add-label security >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1)"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, security"
then
	pass "edit --add-label appends to existing labels"
else
	fail "edit --add-label appends to existing labels" "got: '$labels'"
fi

# ============================================================
# TEST: git issue edit --remove-label removes from existing
# ============================================================
run_test
setup_repo
out="$(git issue create "Remove label test" -l bug -l docs -l feature 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" --remove-label docs >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1)"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
case "$labels" in
	*"docs"*)
		fail "edit --remove-label removes label" "got: '$labels'"
		;;
	*)
		pass "edit --remove-label removes label"
		;;
esac

# ============================================================
# TEST: git issue edit changes assignee
# ============================================================
run_test
setup_repo
out="$(git issue create "Edit assignee test" -a alice@test.com 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -a bob@test.com >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
assignee="$(git log --format='%(trailers:key=Assignee,valueonly)' "$ref" | sed '/^$/d' | head -1)"
assignee="$(printf '%s' "$assignee" | sed 's/^[[:space:]]*//')"
if test "$assignee" = "bob@test.com"
then
	pass "edit changes assignee"
else
	fail "edit changes assignee" "got: '$assignee'"
fi

# ============================================================
# TEST: git issue edit changes priority
# ============================================================
run_test
setup_repo
out="$(git issue create "Edit priority test" -p low 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -p critical >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
prio="$(git log --format='%(trailers:key=Priority,valueonly)' "$ref" | sed '/^$/d' | head -1)"
prio="$(printf '%s' "$prio" | sed 's/^[[:space:]]*//')"
if test "$prio" = "critical"
then
	pass "edit changes priority"
else
	fail "edit changes priority" "got: '$prio'"
fi

# ============================================================
# TEST: git issue edit changes milestone
# ============================================================
run_test
setup_repo
out="$(git issue create "Edit milestone test" --milestone v1.0 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" --milestone v2.0 >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
ms="$(git log --format='%(trailers:key=Milestone,valueonly)' "$ref" | sed '/^$/d' | head -1)"
ms="$(printf '%s' "$ms" | sed 's/^[[:space:]]*//')"
if test "$ms" = "v2.0"
then
	pass "edit changes milestone"
else
	fail "edit changes milestone" "got: '$ms'"
fi

# ============================================================
# TEST: git issue edit changes title
# ============================================================
run_test
setup_repo
out="$(git issue create "Original title" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -t "New title" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
new_title="$(git log --format='%(trailers:key=Title,valueonly)' "$ref" | sed '/^$/d' | head -1)"
new_title="$(printf '%s' "$new_title" | sed 's/^[[:space:]]*//')"
if test "$new_title" = "New title"
then
	pass "edit changes title via Title: trailer"
else
	fail "edit changes title via Title: trailer" "got: '$new_title'"
fi

# ============================================================
# TEST: git issue edit creates a child commit
# ============================================================
run_test
setup_repo
out="$(git issue create "Commit count test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -p high >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
total="$(git rev-list --count "$ref")"
if test "$total" -eq 2
then
	pass "edit creates a child commit"
else
	fail "edit creates a child commit" "expected 2, got $total"
fi

# ============================================================
# TEST: git issue edit rejects invalid priority
# ============================================================
run_test
setup_repo
out="$(git issue create "Bad prio edit" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
if git issue edit "$id" -p urgent 2>/dev/null
then
	fail "edit rejects invalid priority" "should have failed"
else
	pass "edit rejects invalid priority"
fi

# ============================================================
# TEST: git issue edit requires at least one option
# ============================================================
run_test
if git issue edit "$id" 2>/dev/null
then
	fail "edit requires at least one option" "should have failed"
else
	pass "edit requires at least one option"
fi

# ============================================================
# TEST: git issue edit on nonexistent issue fails
# ============================================================
run_test
setup_repo
if git issue edit "zzzzzzz" -p low 2>/dev/null
then
	fail "edit on nonexistent issue fails" "should have failed"
else
	pass "edit on nonexistent issue fails"
fi

# ============================================================
# TEST: git issue edit with custom message
# ============================================================
run_test
setup_repo
out="$(git issue create "Custom msg edit" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -p high -m "Escalating priority" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
subject="$(git log -1 --format='%s' "$ref")"
if test "$subject" = "Escalating priority"
then
	pass "edit uses custom message as commit subject"
else
	fail "edit uses custom message as commit subject" "got: '$subject'"
fi

# ============================================================
# TEST: ls --format full shows metadata
# ============================================================
run_test
setup_repo
git issue create "Format test" -l bug -a dev@test.com -p high --milestone v1.0 >/dev/null
output="$(git issue ls --format full)"
case "$output" in
	*"Format test"*"labels:"*"bug"*"assignee:"*"dev@test.com"*)
		pass "ls --format full shows metadata"
		;;
	*)
		fail "ls --format full shows metadata" "got: $output"
		;;
esac

# ============================================================
# TEST: ls --format oneline has no brackets
# ============================================================
run_test
output="$(git issue ls --format oneline)"
case "$output" in
	*"["*)
		fail "ls --format oneline has no brackets" "got: $output"
		;;
	*" open "*"Format test"*)
		pass "ls --format oneline has no brackets"
		;;
	*)
		fail "ls --format oneline has no brackets" "got: $output"
		;;
esac

# ============================================================
# TEST: ls --format rejects invalid value
# ============================================================
run_test
if git issue ls --format json 2>/dev/null
then
	fail "ls rejects invalid format" "should have failed"
else
	pass "ls rejects invalid format"
fi

# ============================================================
# TEST: --remove-label does not corrupt substring labels
# ============================================================
run_test
setup_repo
out="$(git issue create "Substring label test" -l bug -l debugger -l feature 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" --remove-label bug >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1)"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "debugger, feature"
then
	pass "--remove-label does not corrupt substring labels"
else
	fail "--remove-label does not corrupt substring labels" "got: '$labels'"
fi

# ============================================================
# TEST: --remove-label handles regex metacharacters
# ============================================================
run_test
setup_repo
out="$(git issue create "Regex label test" -l "C++" -l bug -l "bug.fix" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" --remove-label "C++" >/dev/null
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
labels="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref" | sed '/^$/d' | head -1)"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug, bug.fix"
then
	pass "--remove-label handles regex metacharacters (C++)"
else
	fail "--remove-label handles regex metacharacters (C++)" "got: '$labels'"
fi

# ============================================================
# TEST: Title: trailer respected by ls
# ============================================================
run_test
setup_repo
out="$(git issue create "Original ls title" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
git issue edit "$id" -t "Updated ls title" >/dev/null
output="$(git issue ls)"
case "$output" in
	*"Updated ls title"*)
		pass "ls respects Title: trailer"
		;;
	*)
		fail "ls respects Title: trailer" "got: $output"
		;;
esac

# ============================================================
# TEST: Title: trailer respected by show
# ============================================================
run_test
output="$(git issue show "$id")"
case "$output" in
	*"Updated ls title"*)
		pass "show respects Title: trailer"
		;;
	*)
		fail "show respects Title: trailer" "got: $output"
		;;
esac

# ============================================================
# TEST: comment rejects trailer injection
# ============================================================
run_test
setup_repo
out="$(git issue create "Injection test" 2>&1)"
id="$(printf '%s' "$out" | sed 's/Created issue //')"
nl="$(printf 'legit comment\nState: closed')"
if git issue comment "$id" -m "$nl" 2>/dev/null
then
	fail "comment rejects trailer injection" "should have failed"
else
	pass "comment rejects trailer injection"
fi

# ============================================================
# TEST: version shows 1.0.2
# ============================================================
run_test
setup_repo
output="$(git issue version 2>&1)"
case "$output" in
	*"1.0.2"*)
		pass "version shows 1.0.2"
		;;
	*)
		fail "version shows 1.0.2" "got: $output"
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
