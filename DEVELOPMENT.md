# Amara — Development Notes

## Overview

Amara is a native macOS application for managing git worktrees alongside AI agent sessions (claude, codex). Built on top of **libghostty** (embedded terminal library) and **SwiftUI/AppKit**.

---

## Architecture

### Core Components

```
AppDelegate
└── WorkspaceWindowController
    └── WorkspaceRootView (SwiftUI)
        ├── WorktreeListView          ← left panel (210pt fixed)
        │   ├── WorktreeRowView       ← per-worktree row
        │   └── WorktreeFileBrowser   ← double-tap → file browser
        └── WorkspaceContentView      ← right panel
            ├── WorkspaceTabBar       ← [claude] [codex] [file tabs]
            ├── VSplitView
            │   ├── agent panel (top)   ghostty SurfaceView per tab
            │   └── terminal panel (bottom)  plain shell SurfaceView
            └── MarkdownViewerView    ← overlay for .md files
```

### State Ownership

```
WorkspaceManager  (@MainActor, ObservableObject)
├── worktreeProvider: WorktreeProvider   — git worktree list + Gitea PR polling
├── resolver: AgentPathResolver          — resolves claude/codex paths via login shell
├── workspaces: [String: WorktreeWorkspace]  — keyed by worktree path
└── selectedPath: String?

WorktreeWorkspace  (ObservableObject, per worktree)
├── claudeSession: AgentSession         — claude process + output monitoring
├── codexSession:  AgentSession         — codex process + output monitoring
├── shellSurface:  Amara.SurfaceView    — plain shell (bottom panel)
├── fileSurfaces:  [URL: SurfaceView]   — vim per open file
├── activeTab:     WorkspaceTab
├── claudeNeedsAttention / codexNeedsAttention: Bool  (forwarded from sessions)
└── claudeLastMessage / codexLastMessage: String?     (forwarded from sessions)

AgentSession  (ObservableObject, per agent)
├── surface: Amara.SurfaceView          — ghostty terminal display
├── needsAttention: Bool                — idle after producing output
├── lastMessage: String?                — last meaningful output line
├── send(_ text: String)                — write to agent stdin
├── onOutput(_ handler:)                — register output routing callback
└── fifoPath: String                    — /tmp/amara-<uuid> FIFO for stream tap
```

---

## Implemented Features

### Worktree Management
- `git worktree list --porcelain` 파싱 → 좌측 사이드바 표시
- 더블탭 → 파일 브라우저 (슬라이드 애니메이션)
- 워크트리 생성 (`git worktree add -b <branch>`)
- 폴더/브랜치/경로 상태바 (하단)

### Agent Sessions
- 워크트리 선택 시 claude/codex SurfaceView 즉시 생성 (PTY 프로세스 시작)
- 탭 전환 시 SurfaceView는 살아있음 (opacity 0, allowsHitTesting false)
- `AgentPathResolver`: 로그인 셸로 `which claude`, `which codex` 실행 → 전체 경로 캐시

### File Editor
- 파일 브라우저에서 파일 선택 → 탭으로 vim 실행
- `.md` 파일: 마크다운 뷰어 ↔ vim 에디터 토글 버튼
- `MarkdownViewerView`: `WKWebView` 기반, CSS vars로 다크/라이트 모드 대응
- vim 프로세스 종료 시 탭 자동 제거 (`childExitedMessage` 구독)
- 파일별 git 상태 표시 (M/A/D/U/R, `git status --porcelain`)

### Idle Detection & Attention State
- `AgentSession`이 FIFO 스트림을 실시간으로 읽음 (`DispatchSource.makeReadSource`)
- 출력이 2.5초 동안 멈추면 idle 판정 → `needsAttention = true`
- 탭 전환 시 `clearAttention()` 호출 → 플래그 + 메시지 초기화
- 사이드바 행에 파란 점(●) + 마지막 출력 텍스트 표시
- ANSI escape code 제거 후 마지막 의미있는 라인 추출

### Gitea PR 연동
- `GiteaCredentials`: UserDefaults에 서버 URL + 토큰 저장
- `GiteaClient` (actor): `/api/v1/repos/{owner}/{repo}/pulls` REST API
- open + closed PR 병렬 fetch, branch 이름으로 매칭
- 60초 주기 폴링, 머지 감지 → 확인 다이얼로그
- 사이드바 행에 `#42` 캡슐 배지 (색상: open=green, draft=gray, merged=purple)

### UI / 기타
- `VSplitView`: 에이전트 패널(상) + 터미널 패널(하) 드래그 리사이즈
- File 메뉴: "New Workspace" 추가, "New Window" → "New Terminal Window" 변경
- Zoom 단축키: ghostty 네이티브 처리에 위임 (커스텀 코드 제거)
- 워크트리 삭제 전 확인 알럿 ("PR Merged — Remove Worktree?")

---

## Planned: AgentSession (Inter-Agent Communication)

### 구현 완료

ghostty `ghostty_surface_config_s`에 PTY FD 주입 필드가 없어 ghostty가 항상 자체 PTY를 소유함. **Named FIFO + tee wrapper** 방식으로 해결:

```
ghostty surface  (command: "bash -c 'claude 2>&1 | tee /tmp/amara-<uuid>'")
                                                        ↑
                                   Amara가 FIFO를 DispatchSource로 실시간 읽기
```

입력(stdin)은 기존 `sendText()` 유지.

### 에이전트 간 통신 예시

```swift
// claude 완료 시 codex에 전달
claudeSession.onOutput { chunk in
    if isTaskComplete(chunk) {
        codexSession.send(claudeSession.outputBuffer)
    }
}
```

### 다음 단계

- `WorkspaceManager`에 라우팅 API 추가 (`routeOutput(from:to:filter:)`)
- 완료 패턴 감지 로직 구현 (claude/codex 각각의 idle 신호 파싱)

---

## File Index

| 파일 | 역할 |
|------|------|
| `WorkspaceManager.swift` | 전체 워크스페이스 상태, worktreeProvider, resolver |
| `WorktreeWorkspace.swift` | 워크트리별 AgentSession + shellSurface, 파일 탭 관리 |
| `AgentSession.swift` | 에이전트 프로세스 래퍼: FIFO 모니터링, idle 감지, 출력 라우팅 |
| `WorkspaceRootView.swift` | 최상위 레이아웃, PR 머지 확인 알럿 |
| `WorkspaceContentView.swift` | 우측 패널: 탭바 + VSplitView |
| `WorktreeListView.swift` | 좌측 패널: 워크트리 목록, 파일 브라우저 슬라이드 |
| `WorktreeProvider.swift` | git worktree list 실행, Gitea PR 폴링 |
| `WorktreeEntry.swift` | 워크트리 데이터 모델 (path, branch, prInfo) |
| `WorkspaceTab.swift` | 탭 enum (claude, codex, file(URL)) |
| `WorkspaceTabBar.swift` | 탭 UI 컴포넌트 |
| `AgentPathResolver.swift` | 로그인 셸로 claude/codex 경로 탐색 |
| `GiteaClient.swift` | Gitea REST API 클라이언트, PR fetch |
| `GiteaSettingsView.swift` | Gitea 서버 URL/토큰 설정 시트 |
| `PRInfo.swift` | PR 데이터 모델 (number, title, state, headBranch) |
| `MarkdownViewerView.swift` | WKWebView 기반 마크다운 렌더러 |
| `WorktreeFileBrowser.swift` | 파일 트리 브라우저, git 상태 표시 |

---

## Build

```bash
# Debug
xcodebuild -project macos/Ghostty.xcodeproj -target Amara -configuration Debug build

# Release installer
bash make-installer.sh
```

> SourceKit에서 `No such module 'AmaraKit'` 등의 경고가 표시되는 것은 정상입니다. xcodebuild 실제 빌드에서는 발생하지 않습니다.
