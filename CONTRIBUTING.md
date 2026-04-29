# Contributing to Amara

Thank you for your interest in contributing to Amara!
This document covers how to report bugs, request features, and submit pull requests.

> Amara is built on [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto (MIT License).

---

## Reporting a Bug

1. Search [existing issues](https://github.com/mojokb/amara/issues) first — it may already be reported.
2. If not found, [open a new issue](https://github.com/mojokb/amara/issues/new) and include:
   - macOS version and hardware (Apple Silicon / Intel)
   - Amara version (from the title bar or About menu)
   - Steps to reproduce
   - What you expected vs. what actually happened
   - Console logs if relevant (`Console.app` → filter for "Amara")

## Requesting a Feature

[Open a discussion](https://github.com/mojokb/amara/discussions) describing:
- The workflow problem you're trying to solve
- How you imagine it working
- Why it fits Amara's focus (git worktree + AI agent workflows)

## Submitting a Pull Request

1. Open an issue or discussion first so the change can be agreed on before you invest time coding.
2. Fork the repo and create a branch from `develop`.
3. Follow the build instructions in [DEVELOPMENT.md](DEVELOPMENT.md).
4. Keep the scope focused — one feature or fix per PR.
5. Open the PR against `develop`, not `main`.

## Development Setup

```bash
git clone https://github.com/mojokb/amara
cd amara

# Debug build
xcodebuild -project macos/Ghostty.xcodeproj \
  -target Amara -configuration Debug build
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details, file index, and the AgentSession design.

## Code Style

- Swift: follow existing patterns in the codebase (SwiftUI + `@MainActor`, Combine for reactive state)
- No comments unless the *why* is non-obvious
- No new abstractions unless genuinely reused — prefer direct, readable code
- All changes must build cleanly: `xcodebuild` must report `BUILD SUCCEEDED`

## Questions

Open a [Q&A discussion](https://github.com/mojokb/amara/discussions) — issues are reserved for confirmed bugs and accepted features.
