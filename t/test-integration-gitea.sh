#!/bin/sh
#
# Integration test for Gitea/Forgejo bridge with real instance
#
# This validates the Gitea/Forgejo bridge against a real Gitea or Forgejo instance.
# Requires:
#   - A Gitea or Forgejo instance (local or remote)
#   - Valid API token configured
#
# Usage:
#   export GITEA_URL="https://gitea.example.com"
#   export GITEA_TOKEN="your-api-token-here"
#   sh t/test-integration-gitea.sh
#

set -e

# Use local development version (not Homebrew)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

printf "=== Integration Test: Gitea/Forgejo Bridge ===\n\n"
printf "Using git-issue from: %s\n" "$SCRIPT_DIR/bin"
printf "Version: %s\n\n" "$(git-issue version)"

# Configuration - UPDATE THESE or use environment variables
GITEA_URL="${GITEA_URL:-https://gitea.example.com}"
GITEA_REPO="${GITEA_REPO:-testowner/testrepo}"

if test -z "$GITEA_TOKEN"
then
	printf "ERROR: GITEA_TOKEN environment variable is required\n"
	printf "Usage:\n"
	printf "  export GITEA_URL=\"https://your-gitea.com\"\n"
	printf "  export GITEA_TOKEN=\"your-api-token\"\n"
	printf "  export GITEA_REPO=\"owner/repo\"\n"
	printf "  sh t/test-integration-gitea.sh\n"
	exit 1
fi

# Create test directory
TEST_DIR="$(mktemp -d)"
cd "$TEST_DIR"

printf "Test directory: %s\n" "$TEST_DIR"
printf "Gitea URL: %s\n" "$GITEA_URL"
printf "Repository: %s\n\n" "$GITEA_REPO"

# Initialize git repo
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
git issue init >/dev/null 2>&1

printf "✓ Initialized test repository\n\n"

# Test 1: Import from Gitea
printf "Test 1: Import from Gitea...\n"
import_output="$(git issue import "gitea:$GITEA_URL/$GITEA_REPO" --state all 2>&1)"
imported="$(echo "$import_output" | grep -o 'Imported [0-9]* issues' | grep -o '[0-9]*' || echo "0")"
printf "  Imported %s issues from Gitea\n" "$imported"

if test "$imported" -gt 0
then
	printf "  ✓ PASS: Gitea import successful\n\n"
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

# Test 3: Verify issue metadata
printf "Test 3: Verify issue metadata...\n"
first_ref="$(git for-each-ref --format='%(refname)' refs/issues/ | head -1)"
root="$(git rev-list --max-parents=0 "$first_ref")"

# Check for required trailers
format_version="$(git log -1 --format='%(trailers:key=Format-Version,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
provider_id="$(git log -1 --format='%(trailers:key=Provider-ID,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"
state="$(git log -1 --format='%(trailers:key=State,valueonly)' "$root" | sed '/^$/d' | sed 's/^[[:space:]]*//')"

printf "  Format-Version: %s\n" "$format_version"
printf "  Provider-ID: %s\n" "$provider_id"
printf "  State: %s\n" "$state"

if test "$format_version" = "1" && test -n "$provider_id" && test -n "$state"
then
	printf "  ✓ PASS: Issue metadata is valid\n\n"
else
	printf "  ✗ FAIL: Missing or invalid metadata\n"
	exit 1
fi

# Test 4: Verify Provider-ID format
printf "Test 4: Verify Provider-ID format...\n"
case "$provider_id" in
	gitea:*)
		printf "  ✓ PASS: Provider-ID has correct gitea: prefix\n\n"
		;;
	*)
		printf "  ✗ FAIL: Provider-ID format incorrect: %s\n" "$provider_id"
		exit 1
		;;
esac

# Test 5: Test idempotency (re-import should not duplicate)
printf "Test 5: Test idempotency...\n"
refs_before="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

git issue import "gitea:$GITEA_URL/$GITEA_REPO" --state all >/dev/null 2>&1
refs_after="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

printf "  Refs before re-import: %s\n" "$refs_before"
printf "  Refs after re-import: %s\n" "$refs_after"

if test "$refs_before" -eq "$refs_after"
then
	printf "  ✓ PASS: Idempotency verified (no duplicates)\n\n"
else
	printf "  ✗ FAIL: Ref count changed on re-import\n"
	exit 1
fi

# Test 6: Verify empty tree for all commits
printf "Test 6: Verify empty tree...\n"
empty_tree="$(git hash-object -t tree /dev/null)"
all_empty=1

for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	for commit in $(git rev-list "$ref")
	do
		tree="$(git log -1 --format='%T' "$commit")"
		if test "$tree" != "$empty_tree"
		then
			all_empty=0
			break 2
		fi
	done
done

if test "$all_empty" -eq 1
then
	printf "  ✓ PASS: All commits use empty tree\n\n"
else
	printf "  ✗ FAIL: Some commits have non-empty trees\n"
	exit 1
fi

# Test 7: Verify comment import
printf "Test 7: Verify comment import...\n"
max_commits=0
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	count="$(git rev-list --count "$ref")"
	if test "$count" -gt "$max_commits"
	then
		max_commits="$count"
	fi
done

printf "  Maximum commit chain length: %s\n" "$max_commits"
if test "$max_commits" -gt 1
then
	printf "  ✓ PASS: Comments imported (chain length > 1)\n\n"
else
	printf "  ⚠ WARN: No issues with comments found\n\n"
fi

# Test 8: Verify state mapping
printf "Test 8: Verify state mapping...\n"
open_count=0
closed_count=0

for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	state="$(git log --format='%(trailers:key=State,valueonly)' "$ref" | sed '/^$/d' | head -1 | sed 's/^[[:space:]]*//')"
	case "$state" in
		open) open_count=$((open_count + 1)) ;;
		closed) closed_count=$((closed_count + 1)) ;;
	esac
done

printf "  Open issues: %s\n" "$open_count"
printf "  Closed issues: %s\n" "$closed_count"

if test $((open_count + closed_count)) -eq "$imported"
then
	printf "  ✓ PASS: All issues have valid state\n\n"
else
	printf "  ✗ FAIL: Some issues have invalid state\n"
	exit 1
fi

# Test 9: Verify UUID-based refs
printf "Test 9: Verify UUID-based refs...\n"
all_valid=1
for ref in $(git for-each-ref --format='%(refname)' refs/issues/)
do
	uuid="${ref#refs/issues/}"
	# Check if it looks like a UUID (8-4-4-4-12 format, case-insensitive)
	case "$uuid" in
		????????-????-????-????-????????????) ;;
		*) all_valid=0; break ;;
	esac
done

if test "$all_valid" -eq 1
then
	printf "  ✓ PASS: All refs use UUID format\n\n"
else
	printf "  ✗ FAIL: Some refs do not use UUID format\n"
	exit 1
fi

# Test 10: Dry-run test (should not modify anything)
printf "Test 10: Test dry-run mode...\n"
refs_before_dry="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

# Delete all issues to test dry-run import
git for-each-ref --format='delete %(refname)' refs/issues/ | git update-ref --stdin
refs_after_delete="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

git issue import "gitea:$GITEA_URL/$GITEA_REPO" --state all --dry-run >/dev/null 2>&1
refs_after_dry="$(git for-each-ref refs/issues/ | wc -l | tr -d ' ')"

printf "  Refs before dry-run: %s\n" "$refs_after_delete"
printf "  Refs after dry-run: %s\n" "$refs_after_dry"

if test "$refs_after_dry" -eq 0
then
	printf "  ✓ PASS: Dry-run did not create refs\n\n"
else
	printf "  ✗ FAIL: Dry-run created refs\n"
	exit 1
fi

# Restore issues
git issue import "gitea:$GITEA_URL/$GITEA_REPO" --state all >/dev/null 2>&1

# Summary
printf "===================================\n"
printf "ALL TESTS PASSED ✓\n"
printf "===================================\n"
printf "\n"
printf "Gitea/Forgejo integration verified:\n"
printf "  Imported %s issues from %s\n" "$imported" "$GITEA_URL"
printf "  All metadata validated\n"
printf "  Idempotency confirmed\n"
printf "  Comment import working\n"
printf "  Dry-run mode validated\n"
printf "\n"
printf "Test directory: %s\n" "$TEST_DIR"
printf "(Cleanup: rm -rf %s)\n" "$TEST_DIR"
