#!/bin/sh
#
# Tests for git-issue import (Azure DevOps bridge)
#
# Run: sh t/test-azuredevops-bridge.sh
#
# Uses a mock 'az' script that returns fixture JSON based on commands.
# Real 'jq' is used (not mocked).
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
FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
TEST_DIR="$(mktemp -d)"
ORIG_PATH="$PATH"

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

# Set up a fresh test repo with mock az on PATH
setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git commit --allow-empty -q -m "initial"

	# Create mock az
	mkdir -p "$TEST_DIR/mock-bin"
	create_mock_az
	chmod +x "$TEST_DIR/mock-bin/az"

	export PATH="$TEST_DIR/mock-bin:$BIN_DIR:$ORIG_PATH"
}

# Default mock az that handles the standard import test case
create_mock_az() {
	cat > "$TEST_DIR/mock-bin/az" <<MOCKEOF
#!/bin/sh
# Mock az CLI for testing Azure DevOps bridge

case "\$*" in
	"account show"*)
		printf '{"id":"sub-123","name":"Test Subscription"}\n'
		;;
	"extension show --name azure-devops"*)
		printf '{"name":"azure-devops","version":"1.0.0"}\n'
		;;
	*"boards query"*"--wiql"*)
		cat "$FIXTURE_DIR/azuredevops-wiql-response.json"
		;;
	*"boards work-item show"*"--id 1"*)
		cat "$FIXTURE_DIR/azuredevops-workitem-1.json"
		;;
	*"boards work-item show"*"--id 2"*)
		cat "$FIXTURE_DIR/azuredevops-workitem-2.json"
		;;
	*"boards work-item show"*"--id 3"*)
		cat "$FIXTURE_DIR/azuredevops-workitem-3.json"
		;;
	*"devops invoke"*"workItemId=1"*)
		cat "$FIXTURE_DIR/azuredevops-workitem-1-comments.json"
		;;
	*"devops invoke"*"workItemId=2"*)
		printf '{"comments":[],"count":0}\n'
		;;
	*"devops invoke"*"workItemId=3"*)
		printf '{"comments":[],"count":0}\n'
		;;
	*)
		echo "mock-az: unhandled call: \$*" >&2
		exit 1
		;;
esac
MOCKEOF
}

printf "Running git-issue Azure DevOps bridge tests...\n\n"

# ============================================================
# IMPORT TESTS
# ============================================================

# ============================================================
# TEST: import creates correct refs
# ============================================================
run_test
setup_repo
output="$(git issue import azuredevops:testorg/TestProject --state all 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 3
then
	pass "import creates refs for Azure DevOps work items"
else
	fail "import creates refs for Azure DevOps work items" "expected 3 refs, got $ref_count"
fi

# ============================================================
# TEST: imported work item has correct title
# ============================================================
run_test
found_title=0
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Platform migration initiative"
	then
		found_title=1
		epic_ref="$ref"
		break
	fi
done
if test "$found_title" -eq 1
then
	pass "imported work item has correct title"
else
	fail "imported work item has correct title" "title not found"
fi

# ============================================================
# TEST: imported work item has Provider-ID trailer
# ============================================================
run_test
root="$(git rev-list --max-parents=0 "$epic_ref")"
pid="$(git log -1 --format='%(trailers:key=Provider-ID,valueonly)' "$root" | sed '/^$/d')"
pid="$(printf '%s' "$pid" | sed 's/^[[:space:]]*//')"
if test "$pid" = "azuredevops:testorg/TestProject#1"
then
	pass "imported work item has correct Provider-ID trailer"
else
	fail "imported work item has correct Provider-ID trailer" "got: '$pid'"
fi

# ============================================================
# TEST: imported work item has Format-Version trailer
# ============================================================
run_test
fv="$(git log -1 --format='%(trailers:key=Format-Version,valueonly)' "$root" | sed '/^$/d')"
fv="$(printf '%s' "$fv" | sed 's/^[[:space:]]*//')"
if test "$fv" = "1"
then
	pass "imported work item has Format-Version: 1 trailer"
else
	fail "imported work item has Format-Version: 1 trailer" "got: '$fv'"
fi

# ============================================================
# TEST: work item type maps to type: label (Epic)
# ============================================================
run_test
labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d')"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
case "$labels" in
	*"type:epic"*)
		pass "Epic work item maps to type:epic label"
		;;
	*)
		fail "Epic work item maps to type:epic label" "got: '$labels'"
		;;
esac

# ============================================================
# TEST: ADO tags (semicolon-separated) convert to labels
# ============================================================
run_test
# Tags should be "migration; platform; Q2" → "migration,platform,Q2"
case "$labels" in
	*"migration"*"platform"*"Q2"*)
		pass "ADO semicolon-separated tags convert to comma-separated labels"
		;;
	*)
		fail "ADO semicolon-separated tags convert to comma-separated labels" "got: '$labels'"
		;;
esac

# ============================================================
# TEST: AssignedTo identity maps to Assignee email
# ============================================================
run_test
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d')"
assignee="$(printf '%s' "$assignee" | sed 's/^[[:space:]]*//')"
if test "$assignee" = "alice@example.com"
then
	pass "AssignedTo identity maps to Assignee email trailer"
else
	fail "AssignedTo identity maps to Assignee email trailer" "got: '$assignee'"
fi

# ============================================================
# TEST: Parent-ID trailer recorded when System.Parent is set
# ============================================================
run_test
# Find Bug (work item #2, has parent=1)
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Login page crashes on special characters"
	then
		bug_ref="$ref"
		break
	fi
done
bug_root="$(git rev-list --max-parents=0 "$bug_ref")"
parent_id="$(git log -1 --format='%(trailers:key=Parent-ID,valueonly)' "$bug_root" | sed '/^$/d')"
parent_id="$(printf '%s' "$parent_id" | sed 's/^[[:space:]]*//')"
if test "$parent_id" = "azuredevops:testorg/TestProject#1"
then
	pass "Parent-ID trailer recorded for child work item"
else
	fail "Parent-ID trailer recorded for child work item" "got: '$parent_id'"
fi

# ============================================================
# TEST: Bug work item maps to type:bug label
# ============================================================
run_test
bug_labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$bug_root" | sed '/^$/d')"
bug_labels="$(printf '%s' "$bug_labels" | sed 's/^[[:space:]]*//')"
case "$bug_labels" in
	*"type:bug"*)
		pass "Bug work item maps to type:bug label"
		;;
	*)
		fail "Bug work item maps to type:bug label" "got: '$bug_labels'"
		;;
esac

# ============================================================
# TEST: Unassigned work item has no Assignee trailer
# ============================================================
run_test
bug_assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$bug_root" | sed '/^$/d')"
if test -z "$bug_assignee"
then
	pass "unassigned work item has no Assignee trailer"
else
	fail "unassigned work item has no Assignee trailer" "got: '$bug_assignee'"
fi

# ============================================================
# TEST: Closed work item (Done state) has State: closed
# ============================================================
run_test
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Update onboarding documentation"
	then
		story_ref="$ref"
		break
	fi
done
state="$(git log --format='%(trailers:key=State,valueonly)' "$story_ref" | sed '/^$/d' | head -1)"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "closed"
then
	pass "closed ADO work item (Done) imported with State: closed"
else
	fail "closed ADO work item (Done) imported with State: closed" "got: '$state'"
fi

# ============================================================
# TEST: User Story maps to type:user-story label
# ============================================================
run_test
story_root="$(git rev-list --max-parents=0 "$story_ref")"
story_labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$story_root" | sed '/^$/d')"
story_labels="$(printf '%s' "$story_labels" | sed 's/^[[:space:]]*//')"
case "$story_labels" in
	*"type:user-story"*)
		pass "User Story maps to type:user-story label"
		;;
	*)
		fail "User Story maps to type:user-story label" "got: '$story_labels'"
		;;
esac

# ============================================================
# TEST: Comments imported as child commits
# ============================================================
run_test
# Epic (work item #1) has 2 comments = root + 2 comments + close? No, it's open
# root + 2 comments = 3 commits
total="$(git rev-list --count "$epic_ref")"
if test "$total" -eq 3
then
	pass "comments imported as child commits (2 comments on Epic)"
else
	fail "comments imported as child commits (2 comments on Epic)" "expected 3 commits, got $total"
fi

# ============================================================
# TEST: Comment has Provider-Comment-ID trailer
# ============================================================
run_test
head_commit="$(git rev-parse "$epic_ref")"
pcid="$(git log -1 --format='%(trailers:key=Provider-Comment-ID,valueonly)' "$head_commit" | sed '/^$/d')"
pcid="$(printf '%s' "$pcid" | sed 's/^[[:space:]]*//')"
if test "$pcid" = "azuredevops:testorg/TestProject#comment-1002"
then
	pass "comment has correct Provider-Comment-ID trailer"
else
	fail "comment has correct Provider-Comment-ID trailer" "got: '$pcid'"
fi

# ============================================================
# TEST: HTML stripped from description
# ============================================================
run_test
epic_root="$(git rev-list --max-parents=0 "$epic_ref")"
body="$(git log -1 --format='%b' "$epic_root" | sed '/^[A-Z][A-Za-z-]*: /d' | sed '/^$/d')"
case "$body" in
	*"<div>"*|*"<br>"*|*"</div>"*)
		fail "HTML stripped from description" "HTML tags still present: '$body'"
		;;
	*"Migrate all services"*)
		pass "HTML stripped from description"
		;;
	*)
		fail "HTML stripped from description" "expected content not found: '$body'"
		;;
esac

# ============================================================
# TEST: Idempotency - re-import skips already-imported
# ============================================================
run_test
output="$(git issue import azuredevops:testorg/TestProject --state all 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
case "$output" in
	*"Skipped:"*"3"*)
		if test "$ref_count" -eq 3
		then
			pass "re-import skips already-imported items (idempotent)"
		else
			fail "re-import skips already-imported items (idempotent)" "ref count changed to $ref_count"
		fi
		;;
	*)
		fail "re-import skips already-imported items (idempotent)" "output: $output"
		;;
esac

# ============================================================
# TEST: import with --dry-run does not create refs
# ============================================================
run_test
setup_repo
output="$(git issue import azuredevops:testorg/TestProject --state all --dry-run 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 0
then
	case "$output" in
		*"DRY RUN"*"Would import"*)
			pass "import --dry-run shows plan but creates no refs"
			;;
		*)
			fail "import --dry-run shows plan but creates no refs" "output: $output"
			;;
	esac
else
	fail "import --dry-run shows plan but creates no refs" "created $ref_count refs"
fi

# ============================================================
# TEST: all commits use empty tree
# ============================================================
run_test
setup_repo
create_mock_az
chmod +x "$TEST_DIR/mock-bin/az"
git issue import azuredevops:testorg/TestProject --state all >/dev/null 2>&1
empty_tree="$(git hash-object -t tree /dev/null)"
all_ok=1
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	for commit in $(git rev-list "$ref")
	do
		tree="$(git log -1 --format='%T' "$commit")"
		if test "$tree" != "$empty_tree"
		then
			all_ok=0
			break
		fi
	done
done
if test "$all_ok" -eq 1
then
	pass "all imported commits use empty tree"
else
	fail "all imported commits use empty tree"
fi

# ============================================================
# TEST: import preserves author identity
# ============================================================
run_test
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Platform migration initiative"
	then
		author_name="$(git log -1 --format='%an' "$root")"
		author_email="$(git log -1 --format='%ae' "$root")"
		if test "$author_name" = "Alice Developer" && test "$author_email" = "alice@example.com"
		then
			pass "import preserves author identity"
		else
			fail "import preserves author identity" "name='$author_name' email='$author_email'"
		fi
		break
	fi
done

# ============================================================
# TEST: import preserves creation timestamp
# ============================================================
run_test
# Re-find epic ref in current repo (previous setup_repo may have changed repo)
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Platform migration initiative"
	then
		epic_ref="$ref"
		break
	fi
done
epic_root="$(git rev-list --max-parents=0 "$epic_ref")"
author_date="$(git log -1 --format='%aI' "$epic_root")"
case "$author_date" in
	2025-04-01T09:00:00*)
		pass "import preserves creation timestamp"
		;;
	*)
		fail "import preserves creation timestamp" "got: '$author_date'"
		;;
esac

# ============================================================
# TEST: missing az CLI gives clear error
# ============================================================
run_test
setup_repo
# Remove mock az from PATH
rm -f "$TEST_DIR/mock-bin/az"
output="$(git issue import azuredevops:testorg/TestProject 2>&1)" || true
case "$output" in
	*"'az'"*"required"*|*"not found"*)
		pass "missing az CLI gives clear error"
		;;
	*)
		fail "missing az CLI gives clear error" "output: $output"
		;;
esac
# Restore mock
create_mock_az
chmod +x "$TEST_DIR/mock-bin/az"

# ============================================================
# TEST: auth failure gives useful error
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/az" <<'MOCKEOF_UNAUTH'
#!/bin/sh
case "$*" in
	"account show"*)
		exit 1
		;;
	*)
		exit 1
		;;
esac
MOCKEOF_UNAUTH
chmod +x "$TEST_DIR/mock-bin/az"
output="$(git issue import azuredevops:testorg/TestProject 2>&1)" || true
case "$output" in
	*"not authenticated"*|*"az login"*)
		pass "auth failure returns useful error message"
		;;
	*)
		fail "auth failure returns useful error message" "output: $output"
		;;
esac

# ============================================================
# TEST: invalid provider string fails
# ============================================================
run_test
setup_repo
create_mock_az
chmod +x "$TEST_DIR/mock-bin/az"
if git issue import "azuredevops:invalid" 2>/dev/null
then
	fail "import with invalid provider string fails" "should have failed"
else
	pass "import with invalid provider string fails"
fi

# ============================================================
# TEST: import outside git repo fails
# ============================================================
run_test
tmpdir="$(mktemp -d)"
cd "$tmpdir"
if git issue import azuredevops:testorg/TestProject 2>/dev/null
then
	fail "import outside git repo fails" "should have failed"
else
	pass "import outside git repo fails"
fi
cd "$TEST_DIR"
rm -rf "$tmpdir"

# ============================================================
# TEST: empty description handled gracefully
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/az" <<MOCKEOF_EMPTY
#!/bin/sh
case "\$*" in
	"account show"*)
		printf '{"id":"sub-123"}\n'
		;;
	"extension show --name azure-devops"*)
		printf '{"name":"azure-devops"}\n'
		;;
	*"boards query"*)
		printf '{"workItems":[{"id":99}]}\n'
		;;
	*"boards work-item show"*"--id 99"*)
		printf '{"id":99,"fields":{"System.Id":99,"System.Title":"No description item","System.Description":"","System.State":"New","System.WorkItemType":"Task","System.CreatedDate":"2025-01-01T00:00:00Z","System.CreatedBy":{"displayName":"Dev","uniqueName":"dev@test.com"},"System.AssignedTo":null,"System.Tags":"","System.Parent":null}}\n'
		;;
	*"devops invoke"*)
		printf '{"comments":[],"count":0}\n'
		;;
	*)
		exit 1
		;;
esac
MOCKEOF_EMPTY
chmod +x "$TEST_DIR/mock-bin/az"
git issue import azuredevops:testorg/TestProject --state all >/dev/null 2>&1
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 1
then
	pass "empty description handled gracefully"
else
	fail "empty description handled gracefully" "got $ref_count refs"
fi

# ============================================================
# TEST: work item with no tags has only type label
# ============================================================
run_test
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d')"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "type:task"
then
	pass "work item with no tags has only type: label"
else
	fail "work item with no tags has only type: label" "got: '$labels'"
fi

# ============================================================
# CROSS-PLATFORM EXPORT TESTS
# ============================================================

# ============================================================
# TEST: without --cross-platform, ADO items skipped by GitHub export
# ============================================================
run_test
setup_repo
create_mock_az
chmod +x "$TEST_DIR/mock-bin/az"
# Import ADO items
git issue import azuredevops:testorg/TestProject --state all >/dev/null 2>&1

# Create mock gh for export
cat > "$TEST_DIR/mock-bin/gh" <<'MOCKEOF_GH'
#!/bin/sh
case "$*" in
	"auth status"*)
		exit 0
		;;
	"api /user"*)
		printf '{"login":"testuser","id":1}\n'
		;;
	*)
		printf '{"number":42}\n'
		;;
esac
MOCKEOF_GH
chmod +x "$TEST_DIR/mock-bin/gh"

output="$(git issue export github:testowner/testrepo 2>&1 || true)"
case "$output" in
	*"Skipped"*"imported from azuredevops:"*)
		pass "without --cross-platform, ADO items skipped by GitHub export"
		;;
	*)
		fail "without --cross-platform, ADO items skipped by GitHub export" "output: $output"
		;;
esac

# ============================================================
# TEST: with --cross-platform, ADO items exported to GitHub
# ============================================================
run_test
setup_repo
create_mock_az
chmod +x "$TEST_DIR/mock-bin/az"
git issue import azuredevops:testorg/TestProject --state all >/dev/null 2>&1

# Create mock gh that tracks exports
cat > "$TEST_DIR/mock-bin/gh" <<MOCKEOF_GH2
#!/bin/sh
case "\$*" in
	"auth status"*)
		exit 0
		;;
	"api /user"*)
		printf '{"login":"testuser","id":1}\n'
		;;
	*"--method POST"*"/issues"*)
		printf '{"number":42,"html_url":"https://github.com/testowner/testrepo/issues/42"}\n'
		echo "EXPORTED" >> "$TEST_DIR/export-log"
		;;
	*"--method POST"*"/comments"*)
		printf '{"id":100}\n'
		;;
	*"--method PATCH"*)
		printf '{"number":42}\n'
		;;
	*"/search/"*)
		printf '{"items":[],"total_count":0}\n'
		;;
	*"/commits"*)
		printf '[]\n'
		;;
	*)
		printf '{}\n'
		;;
esac
MOCKEOF_GH2
chmod +x "$TEST_DIR/mock-bin/gh"

output="$(git issue export github:testowner/testrepo --cross-platform 2>&1 || true)"
if test -f "$TEST_DIR/export-log"
then
	export_count="$(wc -l < "$TEST_DIR/export-log" | tr -d ' ')"
	if test "$export_count" -gt 0
	then
		pass "with --cross-platform, ADO items exported to GitHub"
	else
		fail "with --cross-platform, ADO items exported to GitHub" "no exports recorded"
	fi
else
	fail "with --cross-platform, ADO items exported to GitHub" "export log not created. output: $output"
fi

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
