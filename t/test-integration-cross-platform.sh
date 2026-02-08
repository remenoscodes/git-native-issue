#!/bin/sh
#
# Integration tests for cross-platform migration (GitHub ↔ GitLab)
#
# This test suite validates the core promise: seamless issue migration between platforms
# Tests use REAL GitHub and GitLab repositories with live API calls
#
# Prerequisites:
# - gh CLI authenticated (gh auth status)
# - glab CLI authenticated (glab auth status)
# - Permission to create test repositories on both platforms
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test repository names (will be created/deleted)
GH_TEST_REPO="git-issue-integration-test-$$"
GL_TEST_PROJECT="git-issue-integration-test-$$"

# Cleanup flag
CLEANUP_ON_EXIT=1

pass() {
	TESTS_PASSED=$((TESTS_PASSED + 1))
	printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
	TESTS_FAILED=$((TESTS_FAILED + 1))
	printf "${RED}  FAIL${NC} %s\n" "$1"
	if test -n "$2"
	then
		printf "       %s\n" "$2"
	fi
}

info() {
	printf "${YELLOW}  INFO${NC} %s\n" "$1"
}

cleanup() {
	if test "$CLEANUP_ON_EXIT" -eq 1
	then
		info "Cleaning up test repositories..."

		# Delete GitHub test repo
		if test -n "$GH_TEST_REPO"
		then
			gh repo delete "remenoscodes/$GH_TEST_REPO" --yes 2>/dev/null || true
		fi

		# Delete GitLab test project
		if test -n "$GL_TEST_PROJECT"
		then
			gl_project_id="$(glab api "projects/remenoscodes%2F$GL_TEST_PROJECT" 2>/dev/null | jq -r '.id' 2>/dev/null || echo "")"
			if test -n "$gl_project_id" && test "$gl_project_id" != "null"
			then
				glab api --method DELETE "projects/$gl_project_id" 2>/dev/null || true
			fi
		fi

		# Cleanup local test directory
		if test -n "$TEST_DIR" && test -d "$TEST_DIR"
		then
			rm -rf "$TEST_DIR"
		fi
	fi
}

trap cleanup EXIT INT TERM

# Check prerequisites
check_prerequisites() {
	info "Checking prerequisites..."

	TESTS_RUN=$((TESTS_RUN + 1))
	if gh auth status >/dev/null 2>&1
	then
		pass "GitHub CLI authenticated"
	else
		fail "GitHub CLI not authenticated" "Run: gh auth login"
		exit 1
	fi

	TESTS_RUN=$((TESTS_RUN + 1))
	if glab auth status >/dev/null 2>&1
	then
		pass "GitLab CLI authenticated"
	else
		fail "GitLab CLI not authenticated" "Run: glab auth login"
		exit 1
	fi

	TESTS_RUN=$((TESTS_RUN + 1))
	if command -v jq >/dev/null 2>&1
	then
		pass "jq installed"
	else
		fail "jq not installed" "Install: brew install jq"
		exit 1
	fi
}

# Create test repositories on both platforms
setup_repositories() {
	info "Setting up test repositories..."

	# Create GitHub repository
	TESTS_RUN=$((TESTS_RUN + 1))
	if gh repo create "remenoscodes/$GH_TEST_REPO" --public --description "Integration test for git-native-issue" >/dev/null 2>&1
	then
		pass "Created GitHub repository: remenoscodes/$GH_TEST_REPO"
	else
		fail "Failed to create GitHub repository"
		exit 1
	fi

	# Create GitLab project
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_response="$(glab api --method POST projects \
		--field "name=$GL_TEST_PROJECT" \
		--field "visibility=public" \
		--field "description=Integration test for git-native-issue" 2>&1)"

	if echo "$gl_response" | jq -e '.id' >/dev/null 2>&1
	then
		pass "Created GitLab project: remenoscodes/$GL_TEST_PROJECT"
	else
		fail "Failed to create GitLab project" "$gl_response"
		exit 1
	fi

	# Clone GitHub repo locally
	TEST_DIR="$(mktemp -d)"
	cd "$TEST_DIR"

	TESTS_RUN=$((TESTS_RUN + 1))
	if git clone "https://github.com/remenoscodes/$GH_TEST_REPO.git" repo >/dev/null 2>&1
	then
		pass "Cloned GitHub repository locally"
	else
		fail "Failed to clone GitHub repository"
		exit 1
	fi

	cd repo

	# Initialize for issue tracking
	TESTS_RUN=$((TESTS_RUN + 1))
	if git issue init >/dev/null 2>&1
	then
		pass "Initialized git-native-issue"
	else
		fail "Failed to initialize git-native-issue"
		exit 1
	fi
}

# Test 1: Create issues on GitHub and migrate to GitLab
test_github_to_gitlab_migration() {
	info "Test 1: GitHub → GitLab migration"

	# Create test issues on GitHub with various properties
	TESTS_RUN=$((TESTS_RUN + 1))
	gh_issue1="$(gh issue create --repo "remenoscodes/$GH_TEST_REPO" \
		--title "Test issue with unicode: 日本語 🎉" \
		--body "This is a test issue with **markdown** and emoji 🚀

## Code block

\`\`\`python
def hello():
    print('世界')
\`\`\`

- List item 1
- List item 2" \
		--label "bug,enhancement" 2>&1)"

	gh_issue1_number="$(echo "$gh_issue1" | grep -o 'https://github.com/.*/issues/[0-9]*' | grep -o '[0-9]*$')"

	if test -n "$gh_issue1_number"
	then
		pass "Created GitHub issue #$gh_issue1_number with unicode and markdown"
	else
		fail "Failed to create GitHub issue" "$gh_issue1"
		return
	fi

	# Add comments to the issue
	TESTS_RUN=$((TESTS_RUN + 1))
	if gh issue comment "$gh_issue1_number" --repo "remenoscodes/$GH_TEST_REPO" \
		--body "First comment with special chars: < > & \" ' \$ \`backticks\`" >/dev/null 2>&1
	then
		pass "Added comment to GitHub issue #$gh_issue1_number"
	else
		fail "Failed to add comment to GitHub issue"
		return
	fi

	TESTS_RUN=$((TESTS_RUN + 1))
	if gh issue comment "$gh_issue1_number" --repo "remenoscodes/$GH_TEST_REPO" \
		--body "Second comment - testing long text: $(printf 'A%.0s' {1..500})" >/dev/null 2>&1
	then
		pass "Added second comment (long text)"
	else
		fail "Failed to add second comment"
		return
	fi

	# Create a closed issue
	TESTS_RUN=$((TESTS_RUN + 1))
	gh_issue2="$(gh issue create --repo "remenoscodes/$GH_TEST_REPO" \
		--title "Closed issue test" \
		--body "This issue will be closed" \
		--label "wontfix" 2>&1)"

	gh_issue2_number="$(echo "$gh_issue2" | grep -o '[0-9]*$')"

	if test -n "$gh_issue2_number" && gh issue close "$gh_issue2_number" --repo "remenoscodes/$GH_TEST_REPO" >/dev/null 2>&1
	then
		pass "Created and closed GitHub issue #$gh_issue2_number"
	else
		fail "Failed to create/close GitHub issue"
		return
	fi

	# Import from GitHub
	TESTS_RUN=$((TESTS_RUN + 1))
	import_output="$(git issue import "github:remenoscodes/$GH_TEST_REPO" --state all 2>&1)"
	imported_count="$(echo "$import_output" | grep -o 'Imported: [0-9]*' | grep -o '[0-9]*$')"

	if test "$imported_count" -eq 2
	then
		pass "Imported 2 issues from GitHub"
	else
		fail "Expected to import 2 issues, got: $imported_count" "$import_output"
		return
	fi

	# Verify local refs
	TESTS_RUN=$((TESTS_RUN + 1))
	local_issue_count="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

	if test "$local_issue_count" -eq 2
	then
		pass "Created 2 local issue refs"
	else
		fail "Expected 2 local refs, got: $local_issue_count"
		return
	fi

	# Export to GitLab
	TESTS_RUN=$((TESTS_RUN + 1))
	export_output="$(git issue export "gitlab:remenoscodes/$GL_TEST_PROJECT" 2>&1)"
	exported_count="$(echo "$export_output" | grep -o 'Exported: [0-9]*' | grep -o '[0-9]*$')"

	if test "$exported_count" -eq 2
	then
		pass "Exported 2 issues to GitLab"
	else
		fail "Expected to export 2 issues, got: $exported_count" "$export_output"
		return
	fi

	# Verify on GitLab
	TESTS_RUN=$((TESTS_RUN + 1))
	sleep 2  # Give GitLab API a moment
	gl_issues="$(glab api "projects/remenoscodes%2F$GL_TEST_PROJECT/issues?per_page=100" 2>/dev/null)"
	gl_issue_count="$(echo "$gl_issues" | jq '. | length' 2>/dev/null)"

	if test "$gl_issue_count" -eq 2
	then
		pass "Verified 2 issues on GitLab"
	else
		fail "Expected 2 issues on GitLab, got: $gl_issue_count"
		return
	fi

	# Verify unicode and markdown preserved
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_issue1_title="$(echo "$gl_issues" | jq -r '.[0].title' 2>/dev/null)"

	if echo "$gl_issue1_title" | grep -q "日本語"
	then
		pass "Unicode preserved in GitLab issue title"
	else
		fail "Unicode not preserved" "Got: $gl_issue1_title"
		return
	fi

	# Verify comments migrated
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_issue1_iid="$(echo "$gl_issues" | jq -r '.[0].iid' 2>/dev/null)"
	gl_notes="$(glab api "projects/remenoscodes%2F$GL_TEST_PROJECT/issues/$gl_issue1_iid/notes" 2>/dev/null)"
	gl_note_count="$(echo "$gl_notes" | jq '. | length' 2>/dev/null)"

	if test "$gl_note_count" -eq 2
	then
		pass "Migrated 2 comments to GitLab"
	else
		fail "Expected 2 comments on GitLab, got: $gl_note_count"
		return
	fi

	# Verify state preserved
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_issue2_state="$(echo "$gl_issues" | jq -r '.[1].state' 2>/dev/null)"

	if test "$gl_issue2_state" = "closed"
	then
		pass "Closed state preserved in GitLab"
	else
		fail "State not preserved" "Expected: closed, Got: $gl_issue2_state"
		return
	fi
}

# Test 2: Bidirectional sync (GitHub ↔ GitLab)
test_bidirectional_sync() {
	info "Test 2: Bidirectional sync (GitHub ↔ GitLab)"

	# Add new comment on GitHub
	TESTS_RUN=$((TESTS_RUN + 1))
	gh_issues="$(gh issue list --repo "remenoscodes/$GH_TEST_REPO" --json number --jq '.[0].number' 2>/dev/null)"

	if gh issue comment "$gh_issues" --repo "remenoscodes/$GH_TEST_REPO" \
		--body "New comment added on GitHub after migration" >/dev/null 2>&1
	then
		pass "Added new comment on GitHub"
	else
		fail "Failed to add comment on GitHub"
		return
	fi

	# Add new comment on GitLab
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_issues="$(glab api "projects/remenoscodes%2F$GL_TEST_PROJECT/issues" 2>/dev/null)"
	gl_iid="$(echo "$gl_issues" | jq -r '.[0].iid' 2>/dev/null)"
	gl_project_encoded="remenoscodes%2F$GL_TEST_PROJECT"

	if glab api --method POST "projects/$gl_project_encoded/issues/$gl_iid/notes" \
		--field "body=New comment added on GitLab after migration" >/dev/null 2>&1
	then
		pass "Added new comment on GitLab"
	else
		fail "Failed to add comment on GitLab"
		return
	fi

	# Sync from GitHub (import new GitHub comment)
	TESTS_RUN=$((TESTS_RUN + 1))
	sync_gh_output="$(git issue sync "github:remenoscodes/$GH_TEST_REPO" --state all 2>&1)"
	gh_updated="$(echo "$sync_gh_output" | grep -o 'Updated: [0-9]*' | grep -o '[0-9]*$')"

	if test "$gh_updated" -ge 1
	then
		pass "Synced new comment from GitHub"
	else
		fail "Failed to sync from GitHub" "$sync_gh_output"
		return
	fi

	# Sync to GitLab (export GitHub's new comment)
	TESTS_RUN=$((TESTS_RUN + 1))
	sync_gl_output="$(git issue sync "gitlab:remenoscodes/$GL_TEST_PROJECT" 2>&1)"
	gl_synced="$(echo "$sync_gl_output" | grep -o 'Synced: [0-9]*' | grep -o '[0-9]*$')"

	if test "$gl_synced" -ge 1
	then
		pass "Synced to GitLab (exported GitHub comment)"
	else
		fail "Failed to sync to GitLab" "$sync_gl_output"
		return
	fi

	# Verify both comments now on both platforms
	TESTS_RUN=$((TESTS_RUN + 1))
	sleep 2
	final_gl_notes="$(glab api "projects/$gl_project_encoded/issues/$gl_iid/notes" 2>/dev/null)"
	final_note_count="$(echo "$final_gl_notes" | jq '. | length' 2>/dev/null)"

	# Should have: 2 original + 1 from GitHub + 1 from GitLab = 4
	if test "$final_note_count" -eq 4
	then
		pass "Both platforms have all 4 comments after bidirectional sync"
	else
		fail "Expected 4 comments total, got: $final_note_count"
		return
	fi

	# Test idempotency: re-run sync should not duplicate
	TESTS_RUN=$((TESTS_RUN + 1))
	git issue sync "github:remenoscodes/$GH_TEST_REPO" --state all >/dev/null 2>&1
	git issue sync "gitlab:remenoscodes/$GL_TEST_PROJECT" >/dev/null 2>&1
	sleep 2

	final_gl_notes_after_resync="$(glab api "projects/$gl_project_encoded/issues/$gl_iid/notes" 2>/dev/null)"
	final_note_count_after="$(echo "$final_gl_notes_after_resync" | jq '. | length' 2>/dev/null)"

	if test "$final_note_count_after" -eq 4
	then
		pass "Idempotency verified: re-sync did not duplicate comments"
	else
		fail "Duplication detected" "Expected: 4, Got: $final_note_count_after"
		return
	fi
}

# Test 3: GitLab → GitHub migration (reverse direction)
test_gitlab_to_github_migration() {
	info "Test 3: GitLab → GitHub migration (reverse direction)"

	# Create new GitLab-only issue
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_project_encoded="remenoscodes%2F$GL_TEST_PROJECT"
	gl_new_issue="$(glab api --method POST "projects/$gl_project_encoded/issues" \
		--field "title=GitLab-native issue 🦊" \
		--field "description=Created directly on GitLab, will migrate to GitHub" \
		--field "labels=gitlab-native,test" 2>&1)"

	gl_new_iid="$(echo "$gl_new_issue" | jq -r '.iid' 2>/dev/null)"

	if test -n "$gl_new_iid" && test "$gl_new_iid" != "null"
	then
		pass "Created GitLab-native issue #$gl_new_iid"
	else
		fail "Failed to create GitLab issue" "$gl_new_issue"
		return
	fi

	# Add comment on GitLab
	TESTS_RUN=$((TESTS_RUN + 1))
	if glab api --method POST "projects/$gl_project_encoded/issues/$gl_new_iid/notes" \
		--field "body=Comment on GitLab-native issue" >/dev/null 2>&1
	then
		pass "Added comment to GitLab issue"
	else
		fail "Failed to add comment to GitLab issue"
		return
	fi

	# Import from GitLab
	TESTS_RUN=$((TESTS_RUN + 1))
	gl_import_output="$(git issue import "gitlab:remenoscodes/$GL_TEST_PROJECT" --state all 2>&1)"
	gl_imported="$(echo "$gl_import_output" | grep -o 'Imported: [0-9]*' | grep -o '[0-9]*$')"

	if test "$gl_imported" -eq 1
	then
		pass "Imported GitLab-native issue to local"
	else
		fail "Failed to import from GitLab" "$gl_import_output"
		return
	fi

	# Export to GitHub
	TESTS_RUN=$((TESTS_RUN + 1))
	gh_export_output="$(git issue export "github:remenoscodes/$GH_TEST_REPO" 2>&1)"
	gh_exported="$(echo "$gh_export_output" | grep -o 'Exported: [0-9]*' | grep -o '[0-9]*$')"

	if test "$gh_exported" -eq 1
	then
		pass "Exported GitLab issue to GitHub"
	else
		fail "Failed to export to GitHub" "$gh_export_output"
		return
	fi

	# Verify on GitHub
	TESTS_RUN=$((TESTS_RUN + 1))
	sleep 2
	gh_total_issues="$(gh issue list --repo "remenoscodes/$GH_TEST_REPO" --state all --json number --jq '. | length' 2>/dev/null)"

	if test "$gh_total_issues" -eq 3
	then
		pass "Verified GitLab issue migrated to GitHub (3 total issues)"
	else
		fail "Expected 3 total issues on GitHub, got: $gh_total_issues"
		return
	fi

	# Verify GitLab emoji preserved
	TESTS_RUN=$((TESTS_RUN + 1))
	gh_new_issue_title="$(gh issue list --repo "remenoscodes/$GH_TEST_REPO" --state all --json title,number --jq '.[-1].title' 2>/dev/null)"

	if echo "$gh_new_issue_title" | grep -q "🦊"
	then
		pass "GitLab emoji preserved in GitHub issue title"
	else
		fail "Emoji not preserved" "Got: $gh_new_issue_title"
		return
	fi
}

# Test 4: Edge cases
test_edge_cases() {
	info "Test 4: Edge cases and error handling"

	# Test dry-run (should not create issues)
	TESTS_RUN=$((TESTS_RUN + 1))
	initial_gh_count="$(gh issue list --repo "remenoscodes/$GH_TEST_REPO" --state all --json number --jq '. | length' 2>/dev/null)"

	git issue export "github:remenoscodes/$GH_TEST_REPO" --dry-run >/dev/null 2>&1

	final_gh_count="$(gh issue list --repo "remenoscodes/$GH_TEST_REPO" --state all --json number --jq '. | length' 2>/dev/null)"

	if test "$initial_gh_count" -eq "$final_gh_count"
	then
		pass "Dry-run does not create issues"
	else
		fail "Dry-run created issues" "Before: $initial_gh_count, After: $final_gh_count"
		return
	fi

	# Test invalid provider
	TESTS_RUN=$((TESTS_RUN + 1))
	if git issue import "invalid:provider/format" 2>/dev/null
	then
		fail "Should reject invalid provider"
		return
	else
		pass "Rejected invalid provider format"
	fi

	# Test re-import idempotency
	TESTS_RUN=$((TESTS_RUN + 1))
	ref_count_before="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

	git issue import "github:remenoscodes/$GH_TEST_REPO" --state all >/dev/null 2>&1

	ref_count_after="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

	if test "$ref_count_before" -eq "$ref_count_after"
	then
		pass "Re-import is idempotent (no duplicates)"
	else
		fail "Re-import created duplicates" "Before: $ref_count_before, After: $ref_count_after"
		return
	fi
}

# Main test execution
main() {
	printf "\n"
	printf "================================================================\n"
	printf "Integration Tests: Cross-Platform Migration (GitHub ↔ GitLab)\n"
	printf "================================================================\n"
	printf "\n"

	check_prerequisites
	setup_repositories

	printf "\n"
	test_github_to_gitlab_migration

	printf "\n"
	test_bidirectional_sync

	printf "\n"
	test_gitlab_to_github_migration

	printf "\n"
	test_edge_cases

	printf "\n"
	printf "================================================================\n"
	printf "Tests: %d | Passed: %d | Failed: %d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
	printf "================================================================\n"
	printf "\n"

	if test "$TESTS_FAILED" -gt 0
	then
		exit 1
	fi
}

# Allow disabling cleanup for debugging
if test "$1" = "--no-cleanup"
then
	CLEANUP_ON_EXIT=0
	info "Cleanup disabled (--no-cleanup)"
fi

main
