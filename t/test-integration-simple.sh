#!/bin/sh
#
# Simple integration test for cross-platform migration
#
# This validates the core promise: GitHub → Git → GitLab migration
# Uses existing test repositories (create manually before running)
#

set -e

# Use local development version (not Homebrew)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

printf "=== Integration Test: Cross-Platform Migration ===\n\n"
printf "Using git-native-issue from: %s\n" "$SCRIPT_DIR/bin"
printf "Version: %s\n\n" "$(git-issue version)"

# Configuration - UPDATE THESE to match your test repos
GH_REPO="${GH_TEST_REPO:-remenoscodes/git-native-issue-test}"
GL_PROJECT="${GL_TEST_PROJECT:-remenoscodes/git-native-issue-test}"

# Create test directory
TEST_DIR="$(mktemp -d)"
cd "$TEST_DIR"

printf "Test directory: %s\n" "$TEST_DIR"
printf "GitHub repo: %s\n" "$GH_REPO"
printf "GitLab project: %s\n\n" "$GL_PROJECT"

# Initialize git repo
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/$GH_REPO.git"
git issue init >/dev/null 2>&1

printf "✓ Initialized test repository\n\n"

# Test 1: Import from GitHub
printf "Test 1: Import from GitHub...\n"
import_output="$(git issue import "github:$GH_REPO" --state all 2>&1)"
imported="$(echo "$import_output" | grep -o 'Imported [0-9]* issues' | grep -o '[0-9]*' || echo "0")"
printf "  Imported %s issues from GitHub\n" "$imported"

if test "$imported" -gt 0
then
	printf "  ✓ PASS: GitHub import successful\n\n"
else
	printf "  ✗ FAIL: No issues imported\n"
	printf "  Output: %s\n" "$import_output"
	exit 1
fi

# Test 2: Verify local refs
printf "Test 2: Verify local refs...\n"
ref_count="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"
printf "  Found %s local issue refs\n" "$ref_count"

if test "$ref_count" -eq "$imported"
then
	printf "  ✓ PASS: Local refs match imported count\n\n"
else
	printf "  ✗ FAIL: Ref count mismatch\n"
	exit 1
fi

# Test 3: Create local-only issue (no Provider-ID)
printf "Test 3: Create local-only issue...\n"
git issue create "Local issue for testing export" -m "This issue was created locally and will be exported to GitLab" >/dev/null 2>&1
local_ref_count="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"
printf "  Created local issue (total refs: %s)\n" "$local_ref_count"

if test "$local_ref_count" -eq 3
then
	printf "  ✓ PASS: Local issue created\n\n"
else
	printf "  ✗ FAIL: Expected 3 refs, got %s\n" "$local_ref_count"
	exit 1
fi

# Test 4: Export to GitLab
printf "Test 4: Export local issue to GitLab...\n"
export_output="$(git issue export "gitlab:$GL_PROJECT" 2>&1)"
exported="$(echo "$export_output" | grep -E 'Exported [0-9]+ issues' | grep -oE '[0-9]+' | head -1)"
test -z "$exported" && exported="0"
printf "  Exported %s issues to GitLab\n" "$exported"

if test "$exported" -gt 0
then
	printf "  ✓ PASS: GitLab export successful\n\n"
else
	printf "  ✗ FAIL: No issues exported\n"
	printf "  Output: %s\n" "$export_output"
	exit 1
fi

# Test 5: Verify Provider-IDs
printf "Test 5: Verify Provider-IDs...\n"
gh_provider_count="$(git log --all --format='%(trailers:key=Provider-ID,valueonly)' | grep '^github:' | wc -l | tr -d ' ')"
gl_provider_count="$(git log --all --format='%(trailers:key=Provider-ID,valueonly)' | grep '^gitlab:' | wc -l | tr -d ' ')"

printf "  GitHub Provider-IDs: %s\n" "$gh_provider_count"
printf "  GitLab Provider-IDs: %s\n" "$gl_provider_count"

if test "$gh_provider_count" -gt 0 && test "$gl_provider_count" -gt 0
then
	printf "  ✓ PASS: Both providers tracked\n\n"
else
	printf "  ✗ FAIL: Provider-ID tracking incomplete\n"
	exit 1
fi

# Test 6: Test idempotency (re-sync should not create exponential growth)
printf "Test 6: Test idempotency...\n"
refs_first="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

git issue sync "github:$GH_REPO" --state all >/dev/null 2>&1
refs_after_first="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

git issue sync "gitlab:$GL_PROJECT" >/dev/null 2>&1
refs_after_second="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

# Third sync should definitely not create more refs
git issue sync "github:$GH_REPO" --state all >/dev/null 2>&1
git issue sync "gitlab:$GL_PROJECT" >/dev/null 2>&1
refs_after_third="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

printf "  Refs after 1st sync: %s\n" "$refs_first"
printf "  Refs after 2nd sync: %s\n" "$refs_after_first"
printf "  Refs after 3rd sync: %s\n" "$refs_after_second"
printf "  Refs after 4th sync: %s\n" "$refs_after_third"

if test "$refs_after_second" -eq "$refs_after_third"
then
	printf "  ✓ PASS: Idempotency verified (stabilized)\n\n"
else
	printf "  ✗ FAIL: Continued growth detected\n"
	exit 1
fi

# Summary
printf "===================================\n"
printf "ALL TESTS PASSED ✓\n"
printf "===================================\n"
printf "\n"
printf "Migration flow verified:\n"
printf "  GitHub → Git (imported %s issues)\n" "$imported"
printf "  Git → GitLab (exported %s issues)\n" "$exported"
printf "  Bidirectional sync is idempotent\n"
printf "\n"
printf "Test directory: %s\n" "$TEST_DIR"
printf "(Cleanup: rm -rf %s)\n" "$TEST_DIR"
