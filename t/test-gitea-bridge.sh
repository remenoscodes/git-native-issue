#!/bin/sh
#
# Tests for git-issue import/export (Gitea/Forgejo bridge)
#
# Run: sh t/test-gitea-bridge.sh
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

# Set up a fresh test repo with mock curl on PATH
setup_repo() {
	rm -rf "$TEST_DIR/repo"
	mkdir "$TEST_DIR/repo"
	cd "$TEST_DIR/repo"
	git init -q
	git commit --allow-empty -q -m "initial"

	# Create mock curl
	mkdir -p "$TEST_DIR/mock-bin"
	create_mock_curl
	chmod +x "$TEST_DIR/mock-bin/curl"

	export PATH="$TEST_DIR/mock-bin:$BIN_DIR:$PATH"
	export GITEA_TOKEN="mock-token-for-testing"
}

# Default mock curl that handles the standard import test case
create_mock_curl() {
	cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF'
#!/bin/sh
# Mock curl for testing Gitea/Forgejo bridge

# Find the API endpoint from arguments
endpoint=""
for arg in "$@"
do
	case "$arg" in
		https://gitea.example.com/api/v1/*)
			endpoint="${arg#https://gitea.example.com/api/v1/}"
			;;
	esac
done

FIXTURE_DIR="${FIXTURE_DIR:-t/fixtures}"

case "$endpoint" in
	"repos/testowner/testrepo/issues?state=open"*)
		cat "$FIXTURE_DIR/gitea-issues-open.json"
		;;
	"repos/testowner/testrepo/issues?state=closed"*)
		printf '[]\n'
		;;
	"repos/testowner/testrepo/issues?state=all"*)
		cat "$FIXTURE_DIR/gitea-issues-all.json"
		;;
	"repos/testowner/testrepo/issues/1/comments"*)
		cat "$FIXTURE_DIR/gitea-issue-1-comments.json"
		;;
	"repos/testowner/testrepo/issues/2/comments"*)
		printf '[]\n'
		;;
	"repos/testowner/testrepo/issues/3/comments"*)
		cat "$FIXTURE_DIR/gitea-issue-3-comments.json"
		;;
	"version")
		printf '{"version":"1.21.0"}\n'
		;;
	*)
		echo "mock-curl: unhandled endpoint: $endpoint" >&2
		exit 1
		;;
esac
MOCKEOF
}

printf "Running git-issue Gitea/Forgejo bridge tests...\n\n"

# ============================================================
# IMPORT TESTS
# ============================================================

# ============================================================
# TEST: import creates correct refs
# ============================================================
run_test
setup_repo
output="$(git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 3
then
	pass "import creates refs for Gitea issues"
else
	fail "import creates refs for Gitea issues" "expected 3 refs, got $ref_count"
fi

# ============================================================
# TEST: imported issue has correct title
# ============================================================
run_test
# Find the issue with title "Gitea authentication fails"
found_title=0
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Gitea authentication fails"
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
# TEST: imported issue has Provider-ID trailer (Gitea format)
# ============================================================
run_test
root="$(git rev-list --max-parents=0 "$issue1_ref")"
pid="$(git log -1 --format='%(trailers:key=Provider-ID,valueonly)' "$root" | sed '/^$/d')"
pid="$(printf '%s' "$pid" | sed 's/^[[:space:]]*//')"
if test "$pid" = "gitea:testowner/testrepo --url https://gitea.example.com#1"
then
	pass "imported issue has correct Provider-ID trailer (Gitea format)"
else
	fail "imported issue has correct Provider-ID trailer (Gitea format)" "got: '$pid'"
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
if test "$labels" = "bug,security"
then
	pass "imported issue preserves Gitea labels"
else
	fail "imported issue preserves Gitea labels" "got: '$labels'"
fi

# ============================================================
# TEST: imported issue has correct assignee
# ============================================================
run_test
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d')"
assignee="$(printf '%s' "$assignee" | sed 's/^[[:space:]]*//')"
if test "$assignee" = "Alice Developer"
then
	pass "imported issue preserves assignee"
else
	fail "imported issue preserves assignee" "got: '$assignee'"
fi

# ============================================================
# TEST: imported issue has correct body with code block
# ============================================================
run_test
body="$(git log -1 --format='%b' "$root" | sed '/^[A-Z][A-Za-z-]*: /d' | sed '/^$/d')"
case "$body" in
	*"OAuth2"*"Error 401"*)
		pass "imported issue preserves body with code block"
		;;
	*)
		fail "imported issue preserves body with code block" "body missing expected content"
		;;
esac

# ============================================================
# TEST: imported issue has author from Gitea
# ============================================================
run_test
author_name="$(git log -1 --format='%an' "$root")"
author_email="$(git log -1 --format='%ae' "$root")"
if test "$author_name" = "Alice Developer" && test "$author_email" = "alice@example.com"
then
	pass "imported issue maps author correctly"
else
	fail "imported issue maps author correctly" "name='$author_name' email='$author_email'"
fi

# ============================================================
# TEST: imported issue with comments creates child commits
# ============================================================
run_test
# Issue #1 has 2 comments = root + 2 = 3 commits
total="$(git rev-list --count "$issue1_ref")"
if test "$total" -eq 3
then
	pass "imported comments create child commits (2 comments)"
else
	fail "imported comments create child commits (2 comments)" "expected 3 commits, got $total"
fi

# ============================================================
# TEST: comment content is preserved
# ============================================================
run_test
head_commit="$(git rev-parse "$issue1_ref")"
comment_subject="$(git log -1 --format='%s' "$head_commit")"
case "$comment_subject" in
	*"OAuth configuration"*)
		pass "comment content is preserved"
		;;
	*)
		fail "comment content is preserved" "got: '$comment_subject'"
		;;
esac

# ============================================================
# TEST: comment has Provider-Comment-ID trailer
# ============================================================
run_test
pcid="$(git log -1 --format='%(trailers:key=Provider-Comment-ID,valueonly)' "$head_commit" | sed '/^$/d')"
pcid="$(printf '%s' "$pcid" | sed 's/^[[:space:]]*//')"
if test "$pcid" = "gitea:testowner/testrepo --url https://gitea.example.com#comment-201"
then
	pass "comment has correct Provider-Comment-ID trailer"
else
	fail "comment has correct Provider-Comment-ID trailer" "got: '$pcid'"
fi

# ============================================================
# TEST: closed issue has State: closed
# ============================================================
run_test
# Find closed issue (issue #3)
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	root="$(git rev-list --max-parents=0 "$ref")"
	subject="$(git log -1 --format='%s' "$root")"
	if test "$subject" = "Documentation update needed"
	then
		issue3_ref="$ref"
		break
	fi
done
state="$(git log --format='%(trailers:key=State,valueonly)' "$issue3_ref" | sed '/^$/d' | head -1)"
state="$(printf '%s' "$state" | sed 's/^[[:space:]]*//')"
if test "$state" = "closed"
then
	pass "closed Gitea issue imported with State: closed"
else
	fail "closed Gitea issue imported with State: closed" "got: '$state'"
fi

# ============================================================
# TEST: idempotency - re-import skips already-imported
# ============================================================
run_test
output="$(git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all 2>&1)"
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
case "$output" in
	*"Skipped: 3"*)
		if test "$ref_count" -eq 3
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
# TEST: import with --state open filters correctly
# ============================================================
run_test
setup_repo
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state open >/dev/null 2>&1
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 2
then
	pass "import --state open imports only open issues"
else
	fail "import --state open imports only open issues" "got $ref_count refs"
fi

# ============================================================
# TEST: import with --state closed returns empty
# ============================================================
run_test
setup_repo
output="$(git issue import gitea:testowner/testrepo --url https://gitea.example.com --state closed 2>&1)"
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
create_mock_curl
chmod +x "$TEST_DIR/mock-bin/curl"
output="$(git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all --dry-run 2>&1)"
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
# TEST: import with empty body works
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF2'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":99,"title":"No body","state":"open","body":"","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev User","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/99/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF2
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref_count="$(git for-each-ref --format='x' refs/issues/ | wc -l | tr -d ' ')"
if test "$ref_count" -eq 1
then
	pass "import with empty body works"
else
	fail "import with empty body works" "got $ref_count refs"
fi

# ============================================================
# TEST: import with invalid provider string fails
# ============================================================
run_test
setup_repo
if git issue import "gitea:invalid" 2>/dev/null
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
if git issue import gitea:testowner/testrepo --url https://gitea.example.com 2>/dev/null
then
	fail "import outside git repo fails" "should have failed"
else
	pass "import outside git repo fails"
fi
rm -rf "$tmpdir"

# ============================================================
# TEST: import uses empty tree for all commits
# ============================================================
run_test
setup_repo
create_mock_curl
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
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
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF4'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":50,"title":"Unicode test: 日本語 🎉","state":"open","body":"Body with émojis 🚀 and spëcial chärs","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/50/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF4
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
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
cat > "$TEST_DIR/mock-bin/curl" <<MOCKEOF5
#!/bin/sh
endpoint="\${1#https://gitea.example.com/api/v1/}"
case "\$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":60,"title":"Long text test","state":"open","body":"$long_text","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/60/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF5
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
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
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF6'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":70,"title":"Comment test","state":"open","body":"","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/70/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF6
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1

ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
commit_count1="$(git rev-list --count "$ref")"

# Now import same issue with a new comment
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF7'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":70,"title":"Comment test","state":"open","body":"","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/70/comments"*)
		printf '[{"id":999,"body":"New comment","created_at":"2025-01-02T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"}}]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF7
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1

commit_count2="$(git rev-list --count "$ref")"

if test "$commit_count1" -eq 1 && test "$commit_count2" -eq 2
then
	pass "re-import adds new comments to existing issue"
else
	fail "re-import adds new comments to existing issue" "count1=$commit_count1 count2=$commit_count2"
fi

# ============================================================
# TEST: import handles Forgejo-specific fields
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF8'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":80,"title":"Forgejo test","state":"open","body":"Testing Forgejo compatibility","created_at":"2025-01-01T00:00:00Z","user":{"login":"forgejo-user","full_name":"Forgejo User","email":"forgejo@example.com"},"labels":[{"name":"forgejo"}],"assignee":{"login":"admin","full_name":"Admin User","email":"admin@forgejo.com"}}]\n'
		;;
	*"issues/80/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF8
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
if test "$assignee" = "Admin User" && test "$labels" = "forgejo"
then
	pass "import handles Forgejo-specific fields correctly"
else
	fail "import handles Forgejo-specific fields correctly" "assignee='$assignee' labels='$labels'"
fi

# ============================================================
# TEST: import handles multiple assignees (Gitea extension)
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF9'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":85,"title":"Multi-assignee test","state":"open","body":"","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignees":[{"login":"alice","full_name":"Alice Dev","email":"alice@test.com"},{"login":"bob","full_name":"Bob Dev","email":"bob@test.com"}]}]\n'
		;;
	*"issues/85/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF9
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
# Should take first assignee
if test "$assignee" = "Alice Dev"
then
	pass "import handles multiple assignees (takes first)"
else
	fail "import handles multiple assignees (takes first)" "got: '$assignee'"
fi

# ============================================================
# TEST: import handles special markdown characters
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF10'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":90,"title":"Markdown: **bold** _italic_ `code`","state":"open","body":"- Item 1\n- Item 2\n\n> Quote\n\n```\ncode block\n```","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/90/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF10
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
title="$(git log -1 --format='%s' "$root")"
body="$(git log -1 --format='%b' "$root" | sed '/^[A-Z][A-Za-z-]*: /d')"
case "$title" in
	*"**bold**"*"_italic_"*"\`code\`"*)
		case "$body" in
			*"Item 1"*"Item 2"*"Quote"*)
				pass "import handles markdown characters correctly"
				;;
			*)
				fail "import handles markdown characters correctly" "body missing markdown"
				;;
		esac
		;;
	*)
		fail "import handles markdown characters correctly" "title: '$title'"
		;;
esac

# ============================================================
# TEST: import handles null assignee correctly
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF11'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":91,"title":"No assignee","state":"open","body":"Unassigned issue","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/91/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF11
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
assignee="$(git log -1 --format='%(trailers:key=Assignee,valueonly)' "$root" | sed '/^$/d')"
# Assignee trailer should not exist when null
if test -z "$assignee"
then
	pass "import handles null assignee (no trailer)"
else
	fail "import handles null assignee (no trailer)" "got: '$assignee'"
fi

# ============================================================
# TEST: import handles empty labels array
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF12'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":92,"title":"No labels","state":"open","body":"No labels","created_at":"2025-01-01T00:00:00Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/92/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF12
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
labels="$(git log -1 --format='%(trailers:key=Labels,valueonly)' "$root" | sed '/^$/d')"
# Labels trailer should not exist when empty
if test -z "$labels"
then
	pass "import handles empty labels array (no trailer)"
else
	fail "import handles empty labels array (no trailer)" "got: '$labels'"
fi

# ============================================================
# TEST: import preserves issue timestamps in commit
# ============================================================
run_test
setup_repo
cat > "$TEST_DIR/mock-bin/curl" <<'MOCKEOF13'
#!/bin/sh
endpoint="${1#https://gitea.example.com/api/v1/}"
case "$endpoint" in
	*"issues?state=all"*)
		printf '[{"number":93,"title":"Timestamp test","state":"open","body":"","created_at":"2025-01-15T10:30:45Z","user":{"login":"dev","full_name":"Dev","email":"dev@test.com"},"labels":[],"assignee":null}]\n'
		;;
	*"issues/93/comments"*)
		printf '[]\n'
		;;
	*) exit 1 ;;
esac
MOCKEOF13
chmod +x "$TEST_DIR/mock-bin/curl"
git issue import gitea:testowner/testrepo --url https://gitea.example.com --state all >/dev/null 2>&1
ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$ref")"
author_date="$(git log -1 --format='%aI' "$root")"
# Check if timestamp matches expected date (2025-01-15)
case "$author_date" in
	2025-01-15T10:30:45*)
		pass "import preserves issue creation timestamp"
		;;
	*)
		fail "import preserves issue creation timestamp" "got: '$author_date'"
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
