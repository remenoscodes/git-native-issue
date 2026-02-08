# Contributing to git-native-issue

Thanks for your interest in contributing! This project welcomes contributions from everyone.

## Quick Start

```bash
git clone https://github.com/remenoscodes/git-native-issue.git
cd git-native-issue
make test    # Run all 153 tests
```

## Development Setup

### Prerequisites

- Git 2.17+ (for `git interpret-trailers --parse` support)
- POSIX shell (sh, bash, zsh, dash all work)
- Standard POSIX tools (sed, awk, grep, etc.)
- For GitHub bridge: `gh` CLI and `jq`

### Running Tests

```bash
# All tests (153 total: 76 core + 36 bridge + 20 merge + 21 QoL)
make test

# Specific test file
sh t/test-issue.sh
sh t/test-merge.sh
sh t/test-qol.sh
sh t/test-bridge.sh

# Individual test (edit the test file to run only one)
```

All tests must pass before merging PRs.

### Code Style

- **POSIX shell only** - No bashisms, no zsh-isms
- **shellcheck passing** - CI enforces this
- **2-space indentation** for shell scripts
- **Tab indentation** for Makefiles

Run linter before committing:
```bash
make lint    # Runs shellcheck on all scripts
```

## Making Changes

### 1. Fork and Branch

```bash
gh repo fork remenoscodes/git-native-issue
git checkout -b feature/your-feature-name
```

### 2. Write Code

- Follow POSIX shell conventions
- Add tests for new features
- Update documentation if needed

### 3. Test

```bash
make test    # All tests must pass
make lint    # All checks must pass
```

### 4. Commit

Write clear commit messages:

```
Add support for issue templates

Implements #42. Users can now create .git/issue-template.md
for default issue body content.

- Add read_template() function
- Update git-issue-create with --template flag
- Add tests in t/test-issue.sh lines 450-475
```

**Important**: We do not use `Co-Authored-By` trailers in this project.

### 5. Push and Open PR

```bash
git push origin feature/your-feature-name
gh pr create
```

## Project Structure

```
bin/
  git-issue          # Main dispatcher
  git-issue-create   # Create command
  git-issue-ls       # List command
  git-issue-show     # Show command
  ...                # Other subcommands

t/
  test-issue.sh      # Core functionality tests
  test-merge.sh      # Merge/fsck tests
  test-qol.sh        # Quality-of-life features
  test-bridge.sh     # GitHub bridge tests

doc/
  git-issue.1        # Man pages
  ...

ISSUE-FORMAT.md      # The format specification
README.md            # User documentation
```

## What to Contribute

### High Priority

- **Bug fixes** - Always welcome
- **Test coverage** - Improve existing tests
- **Documentation** - Clarify unclear sections
- **Performance** - Optimize slow operations

### Medium Priority

- **New features** - Discuss in an issue first
- **Bridge implementations** - GitLab, Gitea, Forgejo
- **Package managers** - Help with Nix, Snap, etc.

### Needs Discussion

- **Format changes** - ISSUE-FORMAT.md is a spec, changes have wide impact
- **Breaking changes** - Discuss first, plan migration path
- **Large refactors** - Create RFC issue before starting

## Issue Tracking

### Using git-issue (Dogfooding!)

We track issues using git-issue itself:

```bash
git clone https://github.com/remenoscodes/git-native-issue.git
cd git-native-issue
git fetch origin 'refs/issues/*:refs/issues/*'  # Get existing issues
git issue ls                                     # List issues
git issue create "Your bug report" -l bug
git push origin 'refs/issues/*'                 # Share your issue
```

### Using GitHub Issues

If you prefer, GitHub Issues work too. We sync bidirectionally.

## Testing Guidelines

### Writing Tests

Tests use shell's built-in test framework:

```bash
run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
}

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}  FAIL${NC} %s\n" "$1"
}

# Example test
run_test
setup_repo
git issue create "Test issue" >/dev/null
output="$(git issue ls 2>&1)"
case "$output" in
    *"Test issue"*)
        pass "create command works"
        ;;
    *)
        fail "create command works" "got: $output"
        ;;
esac
```

### Test Best Practices

- **Isolated tests** - Each test creates its own repo in /tmp
- **Clean up** - Use `trap 'rm -rf "$TEST_DIR"' EXIT`
- **No side effects** - Tests should not affect system state
- **Deterministic** - Same input = same output, always

## Code Review Process

1. **CI must pass** - All tests, shellcheck, installation validation
2. **Maintainer review** - Usually within 2-3 days
3. **Feedback addressed** - Make requested changes
4. **Approval** - Maintainer approves PR
5. **Merge** - Squash and merge to main

## Release Process

Releases happen when:
- Bug fixes accumulate (patch release)
- New features complete (minor release)
- Breaking changes (major release)

Maintainers handle releases. Contributors don't need to worry about versioning.

## Questions?

- Open an issue (git-issue or GitHub)
- Start a discussion on GitHub Discussions
- Ask on the PR itself

## License

By contributing, you agree that your contributions will be licensed under GPL-2.0 (same as Git itself).

## Code of Conduct

Be respectful, collaborative, and professional. We're all here to make distributed issue tracking better.

---

Thank you for contributing! 🚀
