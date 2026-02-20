#!/bin/sh
#
# test-properties.sh - Property-based tests for git-issue
#
# Validates invariants, idempotency, commutativity, and determinism
# of the git-issue data model.
#
# Run: sh t/test-properties.sh
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
	if test -n "${2:-}"; then
		printf ": %s" "$2"
	fi
	printf "\n"
}

skip() {
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

printf "Running git-issue property-based tests...\n\n"

# ============================================================
# PROPERTY 1: IDEMPOTENCY - git issue ls
# Repeated calls to ls return identical output
# ============================================================
printf "== Idempotency ==\n"

run_test
setup_repo
git issue create "Idempotent ls test A" -l bug >/dev/null 2>&1
git issue create "Idempotent ls test B" -l feature >/dev/null 2>&1
git issue create "Idempotent ls test C" -l docs >/dev/null 2>&1

output1="$(git issue ls 2>&1)"
output2="$(git issue ls 2>&1)"
output3="$(git issue ls 2>&1)"

if test "$output1" = "$output2" && test "$output2" = "$output3"
then
	pass "git issue ls is idempotent (3 consecutive calls)"
else
	fail "git issue ls is idempotent" "outputs differ between calls"
fi

# ============================================================
# PROPERTY 2: IDEMPOTENCY - git issue ls --all
# ============================================================
run_test
setup_repo
out="$(git issue create "Closed issue" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue create "Open issue" >/dev/null 2>&1
git issue state "$id" --close >/dev/null 2>&1

output1="$(git issue ls --all 2>&1)"
output2="$(git issue ls --all 2>&1)"
output3="$(git issue ls --all 2>&1)"

if test "$output1" = "$output2" && test "$output2" = "$output3"
then
	pass "git issue ls --all is idempotent (3 consecutive calls)"
else
	fail "git issue ls --all is idempotent" "outputs differ between calls"
fi

# ============================================================
# PROPERTY 3: IDEMPOTENCY - git issue show
# Repeated calls to show return identical output
# ============================================================
run_test
setup_repo
out="$(git issue create "Show idempotency" -m "Body text" -l bug -p high 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue comment "$id" -m "A comment" >/dev/null 2>&1

output1="$(git issue show "$id" 2>&1)"
output2="$(git issue show "$id" 2>&1)"
output3="$(git issue show "$id" 2>&1)"

if test "$output1" = "$output2" && test "$output2" = "$output3"
then
	pass "git issue show is idempotent (3 consecutive calls)"
else
	fail "git issue show is idempotent" "outputs differ between calls"
fi

# ============================================================
# PROPERTY 4: IDEMPOTENCY - git issue fsck
# Repeated calls to fsck return identical output
# ============================================================
run_test
setup_repo
git issue create "Fsck idem A" -l bug -p high >/dev/null 2>&1
git issue create "Fsck idem B" -l feature >/dev/null 2>&1
out="$(git issue create "Fsck idem C" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue comment "$id" -m "A comment" >/dev/null 2>&1
git issue state "$id" --close -m "Done" >/dev/null 2>&1

output1="$(git issue fsck 2>&1)"
output2="$(git issue fsck 2>&1)"
output3="$(git issue fsck 2>&1)"

if test "$output1" = "$output2" && test "$output2" = "$output3"
then
	pass "git issue fsck is idempotent (3 consecutive calls)"
else
	fail "git issue fsck is idempotent" "outputs differ between calls"
fi

# ============================================================
# PROPERTY 5: IDEMPOTENCY - git issue ls with label filter
# ============================================================
run_test
setup_repo
git issue create "Bug A" -l bug >/dev/null 2>&1
git issue create "Bug B" -l bug >/dev/null 2>&1
git issue create "Feature" -l feature >/dev/null 2>&1

output1="$(git issue ls -l bug 2>&1)"
output2="$(git issue ls -l bug 2>&1)"

if test "$output1" = "$output2"
then
	pass "git issue ls with label filter is idempotent"
else
	fail "git issue ls with label filter is idempotent" "outputs differ"
fi

# ============================================================
# PROPERTY 5: IDEMPOTENCY - git issue ls with state filter
# ============================================================
run_test
output1="$(git issue ls -s open 2>&1)"
output2="$(git issue ls -s open 2>&1)"

if test "$output1" = "$output2"
then
	pass "git issue ls with state filter is idempotent"
else
	fail "git issue ls with state filter is idempotent" "outputs differ"
fi

printf "\n== Commutativity ==\n"

# ============================================================
# PROPERTY 6: COMMUTATIVITY - Label order does not affect final state
# Adding labels in different orders produces equivalent results
# ============================================================
run_test
setup_repo
out1="$(git issue create "Label order 1" -l alpha -l beta -l gamma 2>&1)"
id1="$(printf '%s' "$out1" | awk '{print $NF}')"
ref1="$(git for-each-ref --format='%(refname)' "refs/issues/$id1*")"
labels1="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref1" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"

out2="$(git issue create "Label order 2" -l gamma -l alpha -l beta 2>&1)"
id2="$(printf '%s' "$out2" | awk '{print $NF}')"
ref2="$(git for-each-ref --format='%(refname)' "refs/issues/$id2*")"
labels2="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref2" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"

# Normalize: split, sort, rejoin for comparison
sorted1="$(printf '%s' "$labels1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | tr '\n' ',' | sed 's/,$//')"
sorted2="$(printf '%s' "$labels2" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | tr '\n' ',' | sed 's/,$//')"

if test "$sorted1" = "$sorted2"
then
	pass "label order does not affect stored labels (sorted match)"
else
	fail "label order commutativity" "sorted1='$sorted1' sorted2='$sorted2'"
fi

# ============================================================
# PROPERTY 7: COMMUTATIVITY - Adding labels via edit in different order
# ============================================================
run_test
setup_repo
out1="$(git issue create "Edit order 1" 2>&1)"
id1="$(printf '%s' "$out1" | awk '{print $NF}')"
git issue edit "$id1" --add-label alpha >/dev/null 2>&1
git issue edit "$id1" --add-label beta >/dev/null 2>&1
ref1="$(git for-each-ref --format='%(refname)' "refs/issues/$id1*")"
labels1="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref1" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"

out2="$(git issue create "Edit order 2" 2>&1)"
id2="$(printf '%s' "$out2" | awk '{print $NF}')"
git issue edit "$id2" --add-label beta >/dev/null 2>&1
git issue edit "$id2" --add-label alpha >/dev/null 2>&1
ref2="$(git for-each-ref --format='%(refname)' "refs/issues/$id2*")"
labels2="$(git log --format='%(trailers:key=Labels,valueonly)' "$ref2" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"

sorted1="$(printf '%s' "$labels1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | tr '\n' ',' | sed 's/,$//')"
sorted2="$(printf '%s' "$labels2" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | tr '\n' ',' | sed 's/,$//')"

if test "$sorted1" = "$sorted2"
then
	pass "edit --add-label order does not affect final label set"
else
	fail "edit label order commutativity" "sorted1='$sorted1' sorted2='$sorted2'"
fi

# ============================================================
# PROPERTY 8: COMMUTATIVITY - State toggle commutativity
# close then open produces same final state as just open
# ============================================================
run_test
setup_repo
out="$(git issue create "State toggle" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue state "$id" --close >/dev/null 2>&1
git issue state "$id" --open >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"

if test "$state" = "open"
then
	pass "close then open returns to open state"
else
	fail "state toggle commutativity" "expected 'open', got '$state'"
fi

printf "\n== Determinism ==\n"

# ============================================================
# PROPERTY 9: DETERMINISM - Same input produces same git tree structure
# Creating issues with same parameters results in identical tree objects
# ============================================================
run_test
setup_repo
out1="$(git issue create "Determinism test" -m "body" -l bug -p high 2>&1)"
id1="$(printf '%s' "$out1" | awk '{print $NF}')"
ref1="$(git for-each-ref --format='%(refname)' "refs/issues/$id1*")"
tree1="$(git log -1 --format='%T' "$ref1")"

out2="$(git issue create "Determinism test" -m "body" -l bug -p high 2>&1)"
id2="$(printf '%s' "$out2" | awk '{print $NF}')"
ref2="$(git for-each-ref --format='%(refname)' "refs/issues/$id2*")"
tree2="$(git log -1 --format='%T' "$ref2")"

if test "$tree1" = "$tree2"
then
	pass "same input produces same tree object"
else
	fail "deterministic tree" "tree1='$tree1' tree2='$tree2'"
fi

# ============================================================
# PROPERTY 10: DETERMINISM - Empty tree used for all issue commits
# ============================================================
run_test
setup_repo
out="$(git issue create "Empty tree check" -l bug 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
empty_tree="$(git hash-object -t tree /dev/null)"

all_trees_empty=true
for commit_hash in $(git rev-list "$ref")
do
	commit_tree="$(git log -1 --format='%T' "$commit_hash")"
	if test "$commit_tree" != "$empty_tree"
	then
		all_trees_empty=false
		break
	fi
done

if $all_trees_empty
then
	pass "all commits in issue ref use empty tree"
else
	fail "empty tree determinism" "found non-empty tree in commit chain"
fi

# ============================================================
# PROPERTY 11: DETERMINISM - Consistent UUID format across issues
# ============================================================
run_test
setup_repo
i=0
all_valid=true
while test $i -lt 5
do
	git issue create "UUID test $i" >/dev/null 2>&1
	i=$((i + 1))
done

for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	uuid="${ref#refs/issues/}"
	case "$uuid" in
		????????-????-????-????-????????????)
			;;
		*)
			all_valid=false
			break
			;;
	esac
done

if $all_valid
then
	pass "all 5 created issues have valid UUID format"
else
	fail "UUID format consistency" "found non-UUID ref: $uuid"
fi

printf "\n== Invariants ==\n"

# ============================================================
# PROPERTY 12: INVARIANT - Issue ref always has exactly one root commit
# A root commit is one with no parents (--max-parents=0)
# ============================================================
run_test
setup_repo
out="$(git issue create "Root commit invariant" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue comment "$id" -m "Comment 1" >/dev/null 2>&1
git issue comment "$id" -m "Comment 2" >/dev/null 2>&1
git issue state "$id" --close -m "Closing" >/dev/null 2>&1

ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
root_count="$(git rev-list --max-parents=0 "$ref" | wc -l | tr -d ' ')"

if test "$root_count" -eq 1
then
	pass "issue ref has exactly one root commit after multiple operations"
else
	fail "single root invariant" "expected 1 root, got $root_count"
fi

# ============================================================
# PROPERTY 13: INVARIANT - Root commit always has State trailer
# ============================================================
run_test
setup_repo
out="$(git issue create "State trailer invariant" -l bug -p critical 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
root="$(git rev-list --max-parents=0 "$ref")"
state="$(git log -1 --format='%(trailers:key=State,valueonly)' "$root" | sed '/^$/d')"

if test -n "$state"
then
	pass "root commit always has State trailer"
else
	fail "root State trailer invariant" "no State trailer found on root commit"
fi

# ============================================================
# PROPERTY 14: INVARIANT - State trailer present after state change
# ============================================================
run_test
setup_repo
out="$(git issue create "State change trailer" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue state "$id" --close -m "Closing" >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
head_commit="$(git rev-parse "$ref")"
state="$(git log -1 --format='%(trailers:key=State,valueonly)' "$head_commit" | sed '/^$/d' | sed 's/^[[:space:]]*//')"

if test "$state" = "closed"
then
	pass "State trailer present on commit after state change"
else
	fail "state change trailer invariant" "expected 'closed', got '$state'"
fi

# ============================================================
# PROPERTY 15: INVARIANT - Format-Version trailer on root commit
# ============================================================
run_test
setup_repo
out="$(git issue create "Format version invariant" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
root="$(git rev-list --max-parents=0 "$ref")"
fv="$(git log -1 --format='%(trailers:key=Format-Version,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"

if test "$fv" = "1"
then
	pass "root commit has Format-Version: 1 trailer"
else
	fail "Format-Version invariant" "expected '1', got '$fv'"
fi

# ============================================================
# PROPERTY 16: INVARIANT - Ref chain forms valid DAG (linear chain)
# Each non-root commit has exactly one parent
# ============================================================
run_test
setup_repo
out="$(git issue create "DAG invariant test" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue comment "$id" -m "Comment A" >/dev/null 2>&1
git issue comment "$id" -m "Comment B" >/dev/null 2>&1
git issue state "$id" --close -m "Close" >/dev/null 2>&1
git issue state "$id" --open -m "Reopen" >/dev/null 2>&1

ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
valid_dag=true
for commit_hash in $(git rev-list "$ref")
do
	parent_count="$(git log -1 --format='%P' "$commit_hash" | wc -w | tr -d ' ')"
	# Root has 0 parents, all others have exactly 1
	if test "$parent_count" -gt 1
	then
		valid_dag=false
		break
	fi
done

if $valid_dag
then
	pass "ref chain forms valid DAG (no merge commits, linear chain)"
else
	fail "DAG invariant" "found commit with multiple parents"
fi

# ============================================================
# PROPERTY 17: INVARIANT - Commit count matches operation count
# create=1 + N operations = N+1 total commits
# ============================================================
run_test
setup_repo
out="$(git issue create "Commit count test" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue comment "$id" -m "C1" >/dev/null 2>&1
git issue comment "$id" -m "C2" >/dev/null 2>&1
git issue state "$id" --close -m "Close" >/dev/null 2>&1
# 1 create + 2 comments + 1 state change = 4 commits

ref="$(git for-each-ref --format='%(refname)' "refs/issues/$id*")"
count="$(git rev-list --count "$ref")"

if test "$count" -eq 4
then
	pass "commit count matches operation count (4 ops = 4 commits)"
else
	fail "commit count invariant" "expected 4 commits, got $count"
fi

# ============================================================
# PROPERTY 18: INVARIANT - Each issue has independent ref namespace
# Operations on one issue do not affect another
# ============================================================
run_test
setup_repo
out1="$(git issue create "Independent A" -l bug 2>&1)"
id1="$(printf '%s' "$out1" | awk '{print $NF}')"
out2="$(git issue create "Independent B" -l feature 2>&1)"
id2="$(printf '%s' "$out2" | awk '{print $NF}')"

# Modify issue A heavily
git issue comment "$id1" -m "A comment" >/dev/null 2>&1
git issue state "$id1" --close -m "Closing A" >/dev/null 2>&1

# Issue B should be untouched
ref2="$(git for-each-ref --format='%(refname)' "refs/issues/$id2*")"
count2="$(git rev-list --count "$ref2")"
state2="$(git log --format='%(trailers:key=State,valueonly)' "$ref2" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"

if test "$count2" -eq 1 && test "$state2" = "open"
then
	pass "operations on issue A do not affect issue B"
else
	fail "issue independence invariant" "issue B: count=$count2 state='$state2'"
fi

# ============================================================
# PROPERTY 19: INVARIANT - Closed issues excluded from default ls
# ============================================================
run_test
setup_repo
out="$(git issue create "Closed exclusion" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue create "Still open" >/dev/null 2>&1

before_count="$(git issue ls | wc -l | tr -d ' ')"
git issue state "$id" --close >/dev/null 2>&1
after_count="$(git issue ls | wc -l | tr -d ' ')"

if test "$before_count" -eq 2 && test "$after_count" -eq 1
then
	pass "closed issues excluded from default ls (2 -> 1)"
else
	fail "closed exclusion invariant" "before=$before_count after=$after_count"
fi

# ============================================================
# PROPERTY 20: INVARIANT - ls --all includes both open and closed
# ============================================================
run_test
all_count="$(git issue ls --all | wc -l | tr -d ' ')"

if test "$all_count" -eq 2
then
	pass "ls --all includes both open and closed issues"
else
	fail "ls --all invariant" "expected 2, got $all_count"
fi

# ============================================================
# PROPERTY 21: INVARIANT - Reopened issue appears in default ls
# ============================================================
run_test
setup_repo
out="$(git issue create "Reopen test" 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue state "$id" --close >/dev/null 2>&1
closed_count="$(git issue ls | wc -l | tr -d ' ')"
git issue state "$id" --open >/dev/null 2>&1
reopened_count="$(git issue ls | wc -l | tr -d ' ')"

if test "$closed_count" -eq 0 && test "$reopened_count" -eq 1
then
	pass "reopened issue reappears in default ls"
else
	fail "reopen invariant" "closed=$closed_count reopened=$reopened_count"
fi

printf "\n== Stability (multi-iteration) ==\n"

# ============================================================
# PROPERTY 22: STABILITY - ls output stable across 10 calls
# ============================================================
run_test
setup_repo
git issue create "Stability A" -l bug >/dev/null 2>&1
git issue create "Stability B" -l feature >/dev/null 2>&1
git issue create "Stability C" -l docs >/dev/null 2>&1

baseline="$(git issue ls 2>&1)"
stable=true
i=0
while test $i -lt 10
do
	current="$(git issue ls 2>&1)"
	if test "$current" != "$baseline"
	then
		stable=false
		break
	fi
	i=$((i + 1))
done

if $stable
then
	pass "git issue ls stable across 10 consecutive calls"
else
	fail "ls stability" "output changed on iteration $i"
fi

# ============================================================
# PROPERTY 23: STABILITY - show output stable across 10 calls
# ============================================================
run_test
setup_repo
out="$(git issue create "Show stability" -m "Body" -l bug -p high 2>&1)"
id="$(printf '%s' "$out" | awk '{print $NF}')"
git issue comment "$id" -m "Comment" >/dev/null 2>&1

baseline="$(git issue show "$id" 2>&1)"
stable=true
i=0
while test $i -lt 10
do
	current="$(git issue show "$id" 2>&1)"
	if test "$current" != "$baseline"
	then
		stable=false
		break
	fi
	i=$((i + 1))
done

if $stable
then
	pass "git issue show stable across 10 consecutive calls"
else
	fail "show stability" "output changed on iteration $i"
fi

# ============================================================
# Summary
# ============================================================
printf "\n============================================================\n"
printf "Property Tests: %d | Passed: %d | Failed: %d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "============================================================\n"

if test "$TESTS_FAILED" -gt 0; then
	exit 1
fi
exit 0
