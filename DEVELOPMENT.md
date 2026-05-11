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

---

## Planned 0.2.0: Task + Daily TODO

### 배경

git worktree가 **물리적 태스크 분리**(브랜치별 격리)라면, 0.3.0은 **논리적 태스크 관리** 레이어를 추가한다.
Kanban 보드 형태를 검토했으나, Amara의 실제 사용 패턴(1인 또는 소수, 3~5개 동시 워크트리)에는 과도한 UI임을 확인.
대신 "오늘 할 일 → 에이전트에 위임 → 모니터링 → 완료" 흐름을 하나의 데이터 모델로 통합한다.

### 데이터 모델

```swift
struct AmaraTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var status: Status          // todo | inProgress | review | done
    var assignee: Assignee      // .me | .claude | .codex
    var worktreePath: String?   // 에이전트 할당 시 연결
    var branch: String?
    var prNumber: Int?
    var date: Date              // 오늘 필터링용

    enum Status: String, Codable { case todo, inProgress, review, done }
    enum Assignee: String, Codable { case me, claude, codex }
}
```

저장 위치: `<repositoryPath>/.amara/tasks.json`

### 사용 흐름

```
아침: Amara에서 오늘 할 일 입력
  "결제 API 리팩터"  [→ claude]   ← 클릭 시 worktree + 에이전트 자동 시작
  "로그인 버그 픽스" [→ codex]
  "팀 미팅 준비"     (직접 할 것)

오후: 사이드바에서 에이전트 상태 모니터링
  ● feature/payment   결제 API 리팩터   claude 실행 중
  ● feature/fix-login 로그인 버그 픽스  주의 필요

PR 머지 감지 → 연결 태스크 자동 done
```

### 구현 범위

| 파일 | 작업 |
|------|------|
| `AmaraTask.swift` | 신규 — 태스크 데이터 모델 |
| `TaskStore.swift` | 신규 — CRUD + JSON 영속성 + 생명주기 훅 |
| `DailyTodoView.swift` | 신규 — 오늘 할 일 목록 + [→ agent] 버튼 |
| `WorkspaceManager.swift` | 수정 — TaskStore 소유, createWorktree/handlePRMerged 훅 연동 |
| `WorkspaceRootView.swift` | 수정 — Today 뷰 토글 진입점 |
| `WorktreeListView.swift` | 수정 — 워크트리 행에 태스크 제목 + 상태 dot 표시 |

### 생명주기 자동화

- `createWorktree(branch:)` → 태스크 자동 생성 및 link
- `select(path:)` → 연결 태스크 todo → inProgress 자동 전환
- `handlePRMerged(_:)` → 연결 태스크 → done 자동 전환 (기존 Gitea 훅 활용)

### 경쟁 도구 대비 차별점

conductor.build, claude-squad 모두 "에이전트 실행" 레이어만 있고 계획(planning) 레이어가 없다.
이 피처로 Amara는 **계획 → 위임 → 모니터링 → 완료**의 전체 사이클을 단일 앱에서 제공한다.

---

## Planned 0.2.0: Context Agent

### 배경

프로젝트를 진행하는 동안 축적되는 비정형 정보(프로젝트 개요, 고객 메일, 회의 transcription 등)를
에이전트에게 위임하기 전에 개발자가 직접 찾아봐야 하는 비효율이 존재한다.
Context Agent는 이 정보를 레포지토리 수준에서 인덱싱하고 채팅 인터페이스로 조회할 수 있게 한다.

### 문서 구조

```
<repo>/
└── .amara/
    └── context/              ← 여기에 파일을 넣으면 자동 인식
        ├── project.md        (프로젝트 개요)
        ├── emails/           (고객 메일 .md/.txt)
        └── meetings/         (회의 transcription .md/.txt)
```

파일 변경을 감지(`DispatchSource` 또는 `FSEventStream`)하여 자동 재인덱스.

### 아키텍처

```swift
ContextSession (ObservableObject, 레포 수준 싱글턴)
├── documents: [ContextDocument]   // .amara/context/ 스캔 결과
├── messages: [ChatMessage]        // 대화 히스토리
├── ask(_ question: String)        // Claude API 스트리밍 호출
│     system prompt = 인덱싱된 문서 전체
│     user = 질문
└── watchDocuments()               // FSEventStream으로 파일 변경 감지

ContextDocument
├── path: String
├── title: String                  // 파일명 or 첫 번째 H1
├── content: String
└── kind: .projectDoc | .email | .meeting | .other
```

검색 방식: 문서 전체를 system prompt에 주입 (프로젝트 단위 소규모 문서에 적합).
문서가 많아지면 청크 기반 RAG로 전환 가능하도록 `ContextSession` 내부에 캡슐화.

### UI 배치

좌측 패널 상단 토글로 세 뷰를 전환:

```
[⎇ Worktrees]  [☐ Today]  [◎ Context]
```

`ContextAgentView` — 채팅 인터페이스:
- 상단: 인덱싱된 문서 목록 (접이식)
- 중단: 대화 히스토리 (스트리밍 응답)
- 하단: 입력창 + 전송 버튼
- 답변 내 파일 참조 → 클릭 시 해당 파일 탭으로 열기

### 구현 범위

| 파일 | 작업 |
|------|------|
| `ContextDocument.swift` | 신규 — 문서 데이터 모델 + kind 분류 |
| `ContextSession.swift` | 신규 — 문서 스캔·인덱싱, Claude API 호출, 대화 관리 |
| `ContextAgentView.swift` | 신규 — 채팅 UI (스트리밍 응답, 문서 목록 패널) |
| `WorkspaceManager.swift` | 수정 — ContextSession 소유 (레포 경로 변경 시 재초기화) |
| `WorkspaceRootView.swift` | 수정 — 좌측 패널 토글에 Context 탭 추가 |
| `SettingsView.swift` | 수정 — Anthropic API 키 입력란 추가 |

### 사용 흐름

```
1. .amara/context/meetings/2026-05-11.md 파일 추가
2. Amara 자동 감지 → ContextSession 재인덱스
3. 사용자: "지난 미팅에서 결제 API 관련 결정사항이 뭐였어?"
4. Claude API → 관련 문서 기반 답변 스트리밍
5. 답변 내 언급된 파일 참조 클릭 → 파일 탭으로 열기
```

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
