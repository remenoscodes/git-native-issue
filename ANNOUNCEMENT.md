# git-native-issue v1.0.2: The First Distributed Issue Tracker with a Standalone Format Specification

In 2007, Linus Torvalds challenged the open source community with a simple idea: "A 'git for bugs', where you can track bugs locally and without a web interface." Nearly two decades later, we're proud to announce **git-native-issue v1.0.2** — the first distributed issue tracker to deliver not just a tool, but a **standalone, implementable format specification**.

## Why This Matters: The Format Is the Deliverable

Every previous distributed issue tracker produced a tool whose "format" was simply whatever the code happened to generate. git-bug uses JSON blobs with CRDTs. Fossil uses SQLite artifacts. git-appraise uses git-notes. Each approach is locked to its implementation.

**git-issue is different.** The real deliverable is [ISSUE-FORMAT.md](ISSUE-FORMAT.md) — a specification that defines how to store issues using only Git's native primitives: commits, refs, and trailers. Any implementation that produces conforming refs is valid. Multiple tools can read and write the same issue data. This is the foundation for ecosystem adoption.

If the Git community blesses this format, platforms like GitHub, GitLab, and Forgejo could adopt native support for `refs/issues/*`, making issue portability as natural as code portability. Your issues would finally travel with your code.

## Built for Distribution from Day One

Most issue trackers are centralized tools with offline modes bolted on. git-issue is **distributed-first**, with field-specific merge rules designed for conflict-free collaboration:

- **Comments**: Append-only union merge (all comments from both sides preserved)
- **State**: Last-writer-wins by timestamp
- **Labels**: Three-way set merge (additions from both sides honored, removals respected)
- **Scalar fields** (assignee, priority, milestone): Last-writer-wins

No central coordinator. No Lamport clocks. No CRDTs. Just deterministic, predictable merge semantics that work offline and sync anywhere.

## Git-Native, Zero Dependencies

Issues are stored as chains of commits under `refs/issues/<uuid>`. Each commit uses Git's standard trailer format for metadata. The issue title is the commit subject line. The description is the commit body. Everything is queryable with standard Git plumbing commands:

```sh
git for-each-ref \
  --format='%(refname:short) %(contents:subject) %(trailers:key=State,valueonly)' \
  refs/issues/
```

No external database. No JSON. No custom binary formats. Just commits, trailers, and refs — the same primitives Git has used for two decades.

## Dogfooding: We Track Our Own Issues

git-issue tracks its own development using itself. Want to see real-world usage? Clone the repo and run:

```sh
git issue ls --all
git issue show a7f3b2c
```

Our issues are in `refs/issues/*`, synced via `git push` and `git fetch` like code. When you report a bug, you're creating a commit. When we close it, we're updating metadata with Git trailers. This isn't a demo — it's production.

## Production-Ready

- **153 tests** covering core functionality (76), GitHub bridge (36), merge rules (20), and quality-of-life features (21)
- **POSIX-compliant** shell scripts (works on Linux, macOS, BSD)
- **Multiple installation methods**: Homebrew, asdf, install script, Makefile
- **Security audited** with validation against trailer injection, command injection, and input sanitization
- **Performance tested** on repositories with 10,000+ issues
- **CI/CD validated** across 9 platforms (Ubuntu, macOS, Debian, Alpine, Arch)

## Try It in 30 Seconds

```sh
# Install (Homebrew)
brew install remenoscodes/git-native-issue/git-native-issue

# Or use install script
curl -sSL https://raw.githubusercontent.com/remenoscodes/git-native-issue/main/install.sh | sh

# Create an issue
git issue create "Add dark mode support" -m "Users have requested this feature"

# List issues
git issue ls

# Comment and close
git issue comment a7f3b2c -m "Implemented in commit abc123"
git issue state a7f3b2c --close --fixed-by abc123

# Push issues to your remote
git push origin 'refs/issues/*'
```

Your issues now travel with your code. No API. No web interface. Just Git.

**See also**: [QUICKSTART.md](QUICKSTART.md) for a complete 5-minute tutorial.

## What's New in v1.0.2

Since v1.0.0, we've added:

- **Quality-of-life improvements**: `--sort`, `--assignee`, `--priority` filters, `search` command
- **Enhanced testing**: 153 tests (up from 117), all platforms validated
- **Better packaging**: Homebrew tap, asdf plugin, AUR PKGBUILD
- **Improved GitHub bridge**: Bidirectional sync with duplicate detection
- **Documentation polish**: QUICKSTART.md, CONTRIBUTING.md, better examples

## What's Next

This is v1.0.2 — a production-ready implementation with a stable format specification. Our roadmap:

1. **Submit ISSUE-FORMAT.md to the Git community** for review and potential inclusion in official Git documentation
2. **Enable interoperability** by documenting the format so other tools can implement it
3. **Ecosystem adoption** — work with hosting platforms to add native `refs/issues/*` support
4. **Second implementation** — Python or Go implementation to validate format spec

We're starting with a standalone tool and a solid spec. The goal is to make distributed issue tracking as foundational as distributed version control.

## Links

- **Repository**: [github.com/remenoscodes/git-native-issue](https://github.com/remenoscodes/git-native-issue)
- **Format Specification**: [ISSUE-FORMAT.md](ISSUE-FORMAT.md)
- **Quick Start**: [QUICKSTART.md](QUICKSTART.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **Release v1.0.2**: [github.com/remenoscodes/git-native-issue/releases/tag/v1.0.2](https://github.com/remenoscodes/git-native-issue/releases/tag/v1.0.2)
- **Homebrew tap**: [github.com/remenoscodes/homebrew-git-native-issue](https://github.com/remenoscodes/homebrew-git-native-issue)
- **asdf plugin**: [github.com/remenoscodes/git-native-issue-asdf](https://github.com/remenoscodes/git-native-issue-asdf)
- **Report issues** (dogfooding!): `git issue create` in your clone

## Join Us

Clone the repo. Read the spec. Create an issue (using git-issue itself). Tell us what you think.

After 18 years, Linus's vision is finally becoming reality — not because we built a better centralized tracker, but because we built a **format** that makes issues as portable as code.

Let's make distributed issue tracking the default.

---

**License**: GPL-2.0 (same as Git)
**Author**: Emerson Soares ([@remenoscodes](https://github.com/remenoscodes))
