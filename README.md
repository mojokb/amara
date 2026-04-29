<p align="center">
  <img src="macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-512px.png" width="128" alt="Amara icon"/>
  <h1 align="center">Amara</h1>
  <p align="center">
    A native macOS workspace for AI-agent coding with git worktrees.<br/>
    Run claude and codex in parallel — one workspace per branch, all in one window.
  </p>
  <p align="center">
    <a href="https://github.com/mojokb/amara/releases/latest">
      <img alt="Download" src="https://img.shields.io/github/v/release/mojokb/amara?label=Download&style=flat-square">
    </a>
    <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square">
    <img alt="Architecture" src="https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-lightgrey?style=flat-square">
  </p>
</p>

---

## Overview

Amara is purpose-built for agentic development workflows where multiple AI coding agents run in parallel, each on its own `git worktree`. Instead of juggling terminal windows and branches manually, Amara gives every worktree its own isolated workspace — with claude, codex, and a shell always running in the background.

Built on [libghostty](https://github.com/ghostty-org/ghostty) for high-performance terminal rendering.

## Features

### Worktree Management
- Sidebar lists all `git worktree` branches — refresh on demand or auto-detect
- Select a worktree to open its workspace; background sessions keep running
- Create new worktrees directly from the UI (`+` button)
- File browser per worktree with git status indicators (`M` / `A` / `D` / `U` / `R`)

### Agent Sessions
- **claude** and **codex** tabs per worktree, each with a dedicated persistent PTY
- **Shell panel** (bottom, resizable) — always-available plain terminal
- Sessions start immediately when a worktree is first opened
- Background agents continue running while you work elsewhere

### Agent Communication
- **Output log viewer** — popover with full scrollable, searchable output history per agent
- **Inter-agent routing** — send claude's output to codex (or vice versa) manually or automatically on idle
- **Sidebar attention indicators** — blue dot + last output line preview when an agent needs attention

### PR Integration (Gitea)
- PR badge on each worktree row (`#42`, colored by state: open / draft / merged)
- Polls for PR status every 60 seconds
- When a PR is merged, prompts to remove the worktree automatically

### File Editor
- Open files from the browser as vim tabs alongside agent tabs
- Markdown files: toggle between rendered preview and vim editor
- Tabs auto-close when vim exits

## Installation

Download the latest **Amara.dmg** from [Releases](https://github.com/mojokb/amara/releases/latest), open it, and drag Amara to Applications.

**Requirements:** macOS 13 Ventura or later, Apple Silicon or Intel.

## Build from Source

```bash
git clone https://github.com/mojokb/amara
cd amara

# Debug build
xcodebuild -project macos/Ghostty.xcodeproj \
  -target Amara -configuration Debug build

# Release DMG (requires Developer ID certificate + APP_PASSWORD)
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
bash make-installer.sh
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details and file index.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Terminal rendering | [libghostty](https://github.com/ghostty-org/ghostty) (Zig + Metal) |
| App framework | SwiftUI + AppKit (macOS 13+) |
| Agent monitoring | Named FIFO + `DispatchSource` (real-time stream) |
| PR integration | Gitea REST API (`/api/v1/repos`) |
| Markdown preview | WKWebView with CSS dark/light mode |

## License

Amara is based on [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto and distributed under the MIT License. See [LICENSE](LICENSE) for details.
