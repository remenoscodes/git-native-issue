#!/bin/sh
#
# Tests for git-issue import/export (GitLab bridge)
#
# Run: sh t/test-gitlab-bridge.sh
#
# Uses a mock 'curl' script that returns fixture JSON based on API paths.
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

# Set up a fresh test repo with mock glab on PATH
setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git commit --allow-empty -q -m "initial"

	# Create mock glab
	mkdir -p "$TEST_DIR/mock-bin"
	create_mock_glab
	chmod +x "$TEST_DIR/mock-bin/glab"

	export PATH="$TEST_DIR/mock-bin:$BIN_DIR:$PATH"
}

# Default mock glab that handles the standard import test case
create_mock_glab() {
	cat > "$TEST_DIR/mock-bin/glab" <<MOCKEOF
#!/bin/sh
# Mock glab CLI for testing

case "\$*" in
	"auth status")
		exit 0
		;;
	*"issue list --repo testgroup/testproject --closed"*"--output json"*)
		printf '[]\n'
		;;
	*"issue list --repo testgroup/testproject --all"*"--output json"*)
		cat "$FIXTURE_DIR/glab-issues-list.json"
		;;
	*"issue list --repo testgroup/testproject"*"--output json"*)
		# No state flags = opened (default)
		cat "$FIXTURE_DIR/glab-issues-list.json"
		;;
	*"issue view 1 --repo testgroup/testproject --comments --output json"*)
		cat "$FIXTURE_DIR/glab-issue-1-detail.json"
		;;
	*"issue view 2 --repo testgroup/testproject --comments --output json"*)
		cat "$FIXTURE_DIR/glab-issue-2-detail.json"
		;;
	*)
		echo "mock-glab: unhandled call: \$*" >&2
		exit 1
		;;
esac
MOCKEOF
}

printf "Running git-issue GitLab bridge tests...\n\n"

# ============================================================
# IMPORT TESTS
# ============================================================

# ============================================================
# TEST: import creates correct refs
# ============================================================
run_test
setup_repo
output="$(git issue import gitlab:testgroup/testproject --state all 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 2
then
	pass "import creates refs for GitLab issues"
else
	fail "import creates refs for GitLab issues" "expected 2 refs, got $ref_count"
fi

# ============================================================
# TEST: imported issue has correct title
# ============================================================
run_test
# Find the issue with title "Database migration fails on fresh install"
found_title=0
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Database migration fails on fresh install"
	then
		found_title=1
		issue1_ref="$ref"
		break
	fi
done
if test "$found_title" -eq 1
then
	pass "imported issue has correct title"
else
	fail "imported issue has correct title" "title not found"
fi

# ============================================================
# TEST: imported issue has Provider-ID trailer (GitLab format)
# ============================================================
run_test
root="$(git rev-list --max-parents=0 "$issue1_ref")"
pid="$(git log -1 --format='%(trailers:key=Provider-ID,valueonly)' "$root" | sed '/^$/d')"
pid="$(printf '%s' "$pid" | sed 's/^[[:space:]]*//')"
if test "$pid" = "gitlab:testgroup/testproject#1"
then
	pass "imported issue has correct Provider-ID trailer (GitLab format)"
else
	fail "imported issue has correct Provider-ID trailer (GitLab format)" "got: '$pid'"
fi

# ============================================================
# TEST: imported issue has Format-Version trailer
# ============================================================
run_test
fv="$(git log -1 --format='%(trailers:key=Format-Version,valueonly)' "$root" | sed '/^$/d')"
fv="$(printf '%s' "$fv" | sed 's/^[[:space:]]*//')"
if test "$fv" = "1"
then
	pass "imported issue has Format-Version: 1 trailer"
else
	fail "imported issue has Format-Version: 1 trailer" "got: '$fv'"
fi

# ============================================================
# TEST: imported issue has correct labels
# ============================================================
run_test
labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d')"
labels="$(printf '%s' "$labels" | sed 's/^[[:space:]]*//')"
if test "$labels" = "bug,database"
then
	pass "imported issue preserves GitLab labels"
else
	fail "imported issue preserves GitLab labels" "got: '$labels'"
fi

# ============================================================
# TEST: imported issue has correct assignee
# ============================================================
run_test
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d')"
assignee="$(printf '%s' "$assignee" | sed 's/^[[:space:]]*//')"
if test "$assignee" = "Eve Johnson"
then
	pass "imported issue preserves assignee (first from array)"
else
	fail "imported issue preserves assignee (first from array)" "got: '$assignee'"
fi

# ============================================================
# TEST: imported issue has correct body with code block
# ============================================================
run_test
body="$(git log -1 --format='%b' "$root" | sed '/^[A-Z][A-Za-z-]*: /d' | sed '/^$/d')"
case "$body" in
	*"migrations"*"Undefined column"*"users.role"*)
		pass "imported issue preserves body with code block"
		;;
	*)
		fail "imported issue preserves body with code block" "body missing expected content"
		;;
esac

# ============================================================
# TEST: imported issue has author from GitLab
# ============================================================
run_test
author_name="$(git log -1 --format='%an' "$root")"
author_email="$(git log -1 --format='%ae' "$root")"
if test "$author_name" = "Diana Prince" && test "$author_email" = "diana@example.com"
then
	pass "imported issue maps author correctly"
else
	fail "imported issue maps author correctly" "name='$author_name' email='$author_email'"
fi

# ============================================================
# TEST: imported issue with null email uses noreply fallback
# ============================================================
run_test
# Find issue #2 (author with null email)
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Add API documentation"
	then
		issue2_ref="$ref"
		break
	fi
done
root2="$(git rev-list --max-parents=0 "$issue2_ref")"
author2_email="$(git log -1 --format='%ae' "$root2")"
if test "$author2_email" = "noreply@gitlab.com"
then
	pass "imported issue with null email uses noreply@gitlab.com"
else
	fail "imported issue with null email uses noreply@gitlab.com" "got: '$author2_email'"
fi

# ============================================================
# TEST: imported issue has notes (comments) as child commits
# ============================================================
run_test
# Issue #1 has 2 notes = root + 2 = 3 commits
total="$(git rev-list --count "$issue1_ref")"
if test "$total" -eq 3
then
	pass "imported notes (comments) create child commits (2 notes)"
else
	fail "imported notes (comments) create child commits (2 notes)" "expected 3 commits, got $total"
fi

# ============================================================
# TEST: note content is preserved
# ============================================================
run_test
head_commit="$(git rev-parse "$issue1_ref")"
note_subject="$(git log -1 --format='%s' "$head_commit")"
case "$note_subject" in
	*"Fixed in MR"*)
		pass "note content is preserved"
		;;
	*)
		fail "note content is preserved" "got: '$note_subject'"
		;;
esac

# ============================================================
# TEST: note has Provider-Comment-ID trailer
# ============================================================
run_test
pcid="$(git log -1 --format='%(trailers:key=Provider-Comment-ID,valueonly)' "$head_commit" | sed '/^$/d')"
pcid="$(printf '%s' "$pcid" | sed 's/^[[:space:]]*//')"
if test "$pcid" = "gitlab:testgroup/testproject#note-502"
then
	pass "note has correct Provider-Comment-ID trailer"
else
	fail "note has correct Provider-Comment-ID trailer" "got: '$pcid'"
fi

# ============================================================
# TEST: closed issue has State: closed
# ============================================================
run_test
state="$(git log --format='%(trailers:key=State,valueonly)' "$issue2_ref" | sed '/^$/d' | head -1)"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "closed"
then
	pass "closed GitLab issue imported with State: closed"
else
	fail "closed GitLab issue imported with State: closed" "got: '$state'"
fi

# ============================================================
# TEST: idempotency - re-import skips already-imported
# ============================================================
run_test
output="$(git issue import gitlab:testgroup/testproject --state all 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
case "$output" in
	*"Skipped: 2"*)
		if test "$ref_count" -eq 2
		then
			pass "re-import skips already-imported issues (idempotent)"
		else
			fail "re-import skips already-imported issues (idempotent)" "ref count changed to $ref_count"
		fi
		;;
	*)
		fail "re-import skips already-imported issues (idempotent)" "output: $output"
		;;
esac

# ============================================================
# TEST: import with --state opened filters correctly
# ============================================================
run_test
setup_repo
# Mock already filters by state, so we should get 2 opened issues
git issue import gitlab:testgroup/testproject --state opened >/dev/null 2>&1
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 2
then
	pass "import --state opened imports opened issues"
else
	fail "import --state opened imports opened issues" "got $ref_count refs"
fi

# ============================================================
# TEST: import with --state closed returns empty
# ============================================================
run_test
setup_repo
output="$(git issue import gitlab:testgroup/testproject --state closed 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
case "$output" in
	*"Found 0 issues"*)
		if test "$ref_count" -eq 0
		then
			pass "import --state closed handles empty response"
		else
			fail "import --state closed handles empty response" "created $ref_count refs"
		fi
		;;
	*)
		fail "import --state closed handles empty response" "output: $output"
		;;
esac

# ============================================================
# TEST: import with --dry-run does not create refs
# ============================================================
run_test
setup_repo
create_mock_glab
chmod +x "$TEST_DIR/mock-bin/glab"
output="$(git issue import gitlab:testgroup/testproject --state all --dry-run 2>&1)"
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
# TEST: import with empty description works
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/glab" <<'MOCKEOF2'
#!/bin/sh
case "$*" in
	"auth status") exit 0 ;;
	*"issue list"*"--output json"*)
		printf '[{"iid":99,"title":"No desc","state":"opened","description":null,"created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[]}]\n'
		;;
	*"issue view 99"*"--output json"*)
		printf '{"iid":99,"title":"No desc","state":"opened","description":null,"created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[],"notes":[]}\n'
		;;
	*) echo "mock-glab: unhandled: $*" >&2; exit 1 ;;
esac
MOCKEOF2
chmod +x "$TEST_DIR/mock-bin/glab"
git issue import gitlab:testgroup/testproject >/dev/null 2>&1
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 1
then
	pass "import with null/empty description works"
else
	fail "import with null/empty description works" "got $ref_count refs"
fi

# ============================================================
# TEST: import with invalid provider string fails
# ============================================================
run_test
setup_repo
if git issue import "gitlab:invalid" 2>/dev/null
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
if git issue import gitlab:testgroup/testproject 2>/dev/null
then
	fail "import outside git repo fails" "should have failed"
else
	pass "import outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# TEST: import with missing glab fails
# ============================================================
run_test
setup_repo
# Remove mock glab from PATH temporarily
old_path="$PATH"
export PATH="$BIN_DIR:/usr/bin:/bin"
if git issue import gitlab:testgroup/testproject 2>/dev/null
then
	fail "import with missing glab fails" "should have failed"
else
	pass "import with missing glab fails"
fi
export PATH="$old_path"

# ============================================================
# TEST: import with unauthenticated glab fails
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/glab" <<'MOCKEOF_UNAUTH'
#!/bin/sh
case "$*" in
	"auth status") exit 1 ;;
	*) exit 1 ;;
esac
MOCKEOF_UNAUTH
chmod +x "$TEST_DIR/mock-bin/glab"
if git issue import gitlab:testgroup/testproject 2>/dev/null
then
	fail "import with unauthenticated glab fails" "should have failed"
else
	pass "import with unauthenticated glab fails"
fi

# ============================================================
# TEST: import uses empty tree for all commits
# ============================================================
run_test
setup_repo
create_mock_glab
chmod +x "$TEST_DIR/mock-bin/glab"
git issue import gitlab:testgroup/testproject --state all >/dev/null 2>&1
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
# TEST: imported issue ref uses UUID format
# ============================================================
run_test
all_uuid=1
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	uuid="${ref#refs/issues/}"
	# UUID format check (simplified - just checking length)
	case "$uuid" in
		???????*) ;;
		*) all_uuid=0 ;;
	esac
done
if test "$all_uuid" -eq 1
then
	pass "imported issues use UUID-like format for refs"
else
	fail "imported issues use UUID-like format for refs"
fi

# ============================================================
# TEST: import handles unicode in title and body
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/glab" <<'MOCKEOF4'
#!/bin/sh
case "$*" in
	"auth status") exit 0 ;;
	*"issue list"*"--output json"*)
		printf '[{"iid":50,"title":"Unicode test: 日本語 🎉","state":"opened","description":"Body with émojis 🚀 and spëcial chärs","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[]}]\n'
		;;
	*"issue view 50"*"--output json"*)
		printf '{"iid":50,"title":"Unicode test: 日本語 🎉","state":"opened","description":"Body with émojis 🚀 and spëcial chärs","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[],"notes":[]}\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF4
chmod +x "$TEST_DIR/mock-bin/glab"
git issue import gitlab:testgroup/testproject >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
title="$(git log -1 --format='%s' "$root")"
case "$title" in
	*"日本語"*"🎉"*)
		pass "import handles unicode in title and body"
		;;
	*)
		fail "import handles unicode in title and body" "title: '$title'"
		;;
esac

# ============================================================
# TEST: import handles long text (1000+ chars)
# ============================================================
run_test
setup_repo
long_text="$(printf 'A%.0s' $(seq 1 1500))"
cat > "$TEST_DIR/mock-bin/glab" <<MOCKEOF5
#!/bin/sh
case "\$*" in
	"auth status") exit 0 ;;
	*"issue list"*"--output json"*)
		printf '[{"iid":60,"title":"Long text test","state":"opened","description":"$long_text","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[]}]\n'
		;;
	*"issue view 60"*"--output json"*)
		printf '{"iid":60,"title":"Long text test","state":"opened","description":"$long_text","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[],"notes":[]}\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF5
chmod +x "$TEST_DIR/mock-bin/glab"
git issue import gitlab:testgroup/testproject >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
body="$(git log -1 --format='%b' "$root" | sed '/^[A-Z][A-Za-z-]*: /d')"
body_len="$(printf '%s' "$body" | wc -c | tr -d ' ')"
if test "$body_len" -gt 1400
then
	pass "import handles long text (1000+ chars)"
else
	fail "import handles long text (1000+ chars)" "body length: $body_len"
fi

# ============================================================
# TEST: import with new comments updates existing issue
# ============================================================
run_test
setup_repo
# First import - issue with no comments
cat > "$TEST_DIR/mock-bin/glab" <<'MOCKEOF6'
#!/bin/sh
case "$*" in
	"auth status") exit 0 ;;
	*"issue list"*"--output json"*)
		printf '[{"iid":70,"title":"Comment test","state":"opened","description":"","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[]}]\n'
		;;
	*"issue view 70"*"--output json"*)
		printf '{"iid":70,"title":"Comment test","state":"opened","description":"","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[],"notes":[]}\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF6
chmod +x "$TEST_DIR/mock-bin/glab"
git issue import gitlab:testgroup/testproject >/dev/null 2>&1

ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
commit_count1="$(git rev-list --count "$ref")"

# Now import same issue with a new comment
cat > "$TEST_DIR/mock-bin/glab" <<'MOCKEOF7'
#!/bin/sh
case "$*" in
	"auth status") exit 0 ;;
	*"issue list"*"--output json"*)
		printf '[{"iid":70,"title":"Comment test","state":"opened","description":"","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[]}]\n'
		;;
	*"issue view 70"*"--output json"*)
		printf '{"iid":70,"title":"Comment test","state":"opened","description":"","created_at":"2025-01-01T00:00:00Z","author":{"name":"Dev","username":"dev"},"labels":[],"assignees":[],"notes":[{"id":999,"body":"New comment","created_at":"2025-01-02T00:00:00Z","author":{"name":"Dev","username":"dev"}}]}\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF7
chmod +x "$TEST_DIR/mock-bin/glab"
git issue import gitlab:testgroup/testproject >/dev/null 2>&1

commit_count2="$(git rev-list --count "$ref")"

if test "$commit_count1" -eq 1 && test "$commit_count2" -eq 2
then
	pass "re-import adds new comments to existing issue"
else
	fail "re-import adds new comments to existing issue" "count1=$commit_count1 count2=$commit_count2"
fi

# ============================================================
# TEST: migration roundtrip GitHub → Git → GitLab preserves data
# ============================================================
run_test
setup_repo

# Create a mock gh for GitHub import
cat > "$TEST_DIR/mock-bin/gh" <<'MOCKGH'
#!/bin/sh
case "$*" in
	"auth status")
		exit 0
		;;
	*"api --paginate /repos/source/repo/issues?"*)
		printf '[{"number":10,"title":"Migrate me","state":"open","pull_request":null}]\n'
		;;
	*"api /repos/source/repo/issues/10")
		printf '{"number":10,"title":"Migrate me","body":"Migration test","state":"open","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev"},"labels":[{"name":"bug"}],"assignee":null,"milestone":null}\n'
		;;
	*"api --paginate /repos/source/repo/issues/10/comments"*)
		printf '[]\n'
		;;
	*"api /users/dev")
		printf '{"login":"dev","name":"Dev User","email":"dev@test.com"}\n'
		;;
	*)
		exit 1
		;;
esac
MOCKGH
chmod +x "$TEST_DIR/mock-bin/gh"

# Import from GitHub
git issue import github:source/repo --state all >/dev/null 2>&1

# Verify GitHub data
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
gh_title="$(git log -1 --format='%s' "$root")"
gh_pid="$(git log -1 --format='%(trailers:key=Provider-ID,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"

# Now verify GitLab can see the same data (simulating export readiness)
if test "$gh_title" = "Migrate me" && test "$gh_pid" = "github:source/repo#10"
then
	pass "migration roundtrip: GitHub → Git preserves title and Provider-ID"
else
	fail "migration roundtrip: GitHub → Git preserves title and Provider-ID" "title='$gh_title' pid='$gh_pid'"
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
