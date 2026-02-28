# DOUGLAS - 코드 분석 문서

## 개요

DOUGLAS는 **macOS 네이티브 AI 에이전트 관리 데스크톱 앱**이다.
화면 오른쪽 끝에 떠 있는 플로팅 사이드바에서 여러 AI 에이전트를 관리하고, 마스터 에이전트가 사용자 요청을 분석하여 적합한 서브 에이전트에게 작업을 자동으로 위임한다.

**핵심 UX 컨셉 — "사장님 모드"**: 사용자는 에이전트를 직접 골라서 시키지 않는다.
사이드바에 타이핑하면 마스터 에이전트가 알아서 적합한 팀원(서브 에이전트)에게 분배한다.
사장님이 "야 거기 누구 이거 해" 하면 비서실장(마스터)이 알아서 처리하는 구조.

- **플랫폼**: macOS 14+ (Sonoma)
- **언어**: Swift 5.9
- **UI 프레임워크**: SwiftUI + AppKit (NSPanel, NSWindow)
- **빌드 시스템**: Swift Package Manager (SPM)
- **배포**: .app 번들 → .dmg (Ad-hoc 코드 서명)

---

## 프로젝트 구조

```
DOUGLAS/
├── Package.swift                    # SPM 패키지 정의
├── CLAUDE.md                        # 개발 규칙 (문서 업데이트 필수, 빌드/커밋 규칙)
├── DEV_GUIDE.md                     # 개발 규칙 가이드
├── ARCHITECTURE.md                  # 이 문서 (코드 분석/구조)
├── scripts/
│   └── build-app.sh                 # 빌드 → .app 번들 → 코드서명 → DMG 생성
├── Sources/
│   ├── App/
│   │   ├── DOUGLASApp.swift         # @main 진입점
│   │   ├── AppDelegate.swift        # 사이드바 패널(400pt), 채팅 윈도우, 마우스 트래킹
│   │   ├── CommandBarPanel.swift    # Spotlight 스타일 커맨드 바 NSPanel
│   │   └── CommandBarManager.swift  # 글로벌 핫키(⌘⇧A) 등록, 커맨드 바 생명주기
│   ├── Models/
│   │   ├── Agent.swift              # 에이전트 모델 (이름, 페르소나, 이미지, isMaster, 도구 설정, roleTemplateID)
│   │   ├── AgentRoleTemplate.swift  # 역할 템플릿 (프로바이더별 힌트, 카테고리)
│   │   ├── AgentRoleTemplateRegistry.swift # 빌트인 9개 템플릿 (requirements_analyst, backend_dev, QA 4종 등)
│   │   ├── AgentTool.swift          # 도구 시스템 (AgentTool, ToolCall, ToolResult, ToolRegistry, ConversationMessage)
│   │   ├── ArtifactParser.swift     # 토론 산출물 파서 (artifact 블록 추출/제거)
│   │   ├── ChatMessage.swift        # 메시지 모델 (MessageType 포함: toolActivity, buildStatus, qaStatus, approvalRequest 등, ImageAttachment 첨부)
│   │   ├── DiscussionArtifact.swift # 토론 산출물 모델 (ArtifactType, 버전 관리)
│   │   ├── ImageAttachment.swift    # 이미지 첨부 모델 (디스크 저장, base64 로드, MIME 판별)
│   │   ├── BuildResult.swift         # 빌드 결과 모델 + BuildLoopStatus + QAResult + QALoopStatus
│   │   ├── FileWriteTracker.swift   # 병렬 실행 파일 쓰기 충돌 감지 (actor)
│   │   ├── ToolExecutionContext.swift # 도구 실행 컨텍스트 (방/에이전트/프로젝트 정보 스냅샷)
│   │   ├── DependencyChecker.swift  # 의존성 체크 (Node.js, Git, Homebrew)
│   │   ├── JiraConfig.swift          # Jira Cloud 연동 설정 (도메인, 이메일, API 토큰)
│   │   ├── ProviderConfig.swift     # 프로바이더 설정 (AuthMethod, ProviderType, isConnected)
│   │   ├── ProviderDetector.swift   # 시스템 AI 프로바이더 자동 감지
│   │   ├── ClaudeCodeInstaller.swift # Claude Code CLI 설치/검증 유틸리티
│   │   ├── ProcessRunner.swift      # 테스트 가능한 프로세스 실행기 (DI seam)
│   │   ├── Room.swift               # 프로젝트 방 모델 (상태 전이, 타이머, 토론 모드, RoomBriefing, RoomStep 승인 게이트)
│   │   └── KeychainHelper.swift     # 파일 기반 API 키 저장 (Keychain 레거시 마이그레이션)
│   ├── ViewModels/
│   │   ├── AgentStore.swift         # 에이전트 CRUD, 마스터 생명주기
│   │   ├── ChatViewModel.swift      # 메시지 전송, 마스터 오케스트레이션
│   │   ├── OnboardingViewModel.swift # 첫 실행 온보딩 (의존성 체크 + Claude 설정 + 프로바이더 선택)
│   │   ├── ProviderManager.swift    # 프로바이더 설정 관리
│   │   ├── BuildLoopRunner.swift     # 빌드/테스트 실행 + 수정 프롬프트 생성 엔진
│   │   ├── RoomManager.swift        # 프로젝트 방 생명주기, 팀 작업 조율, 빌드/QA 루프, 승인 게이트
│   │   └── ToolExecutor.swift       # 도구 호출 루프 + smartSend + 경로 해석/충돌 추적
│   ├── Providers/
│   │   ├── AIProvider.swift         # AIProvider 프로토콜 + 공통 인증 + Tool Use 확장
│   │   ├── ToolFormatConverter.swift # 프로바이더별 도구 형식 변환 + Vision 이미지 블록 빌더
│   │   ├── ClaudeCodeProvider.swift # Claude Code CLI 실행 (Process)
│   │   ├── OpenAIProvider.swift     # OpenAI Chat Completions API + Tool Use
│   │   ├── GoogleProvider.swift     # Google Gemini generateContent API + Tool Use
│   │   ├── AnthropicProvider.swift  # Anthropic API + Tool Use
│   │   ├── OllamaProvider.swift     # (비활성) Ollama/LM Studio
│   │   └── CustomProvider.swift     # (비활성) 커스텀 URL
│   └── Views/
│       ├── FloatingSidebarView.swift # 팀 로스터 + 마스터 채팅 사이드바 UI
│       ├── CommandBarView.swift     # Spotlight 스타일 커맨드 바 SwiftUI 뷰
│       ├── SidebarQuickInputView.swift # (예비) 사이드바 퀵 인풋 컴포넌트
│       ├── ChatView.swift           # 채팅 뷰 (메시지 버블)
│       ├── ChatContentView.swift    # 공유 채팅 UI (메시지 목록, 입력창, 취소 버튼)
│       ├── ChatWindowView.swift     # 독립 채팅 윈도우 래퍼
│       ├── AddAgentSheet.swift      # 에이전트 등록 시트
│       ├── EditAgentSheet.swift     # 에이전트 편집 시트
│       ├── AddProviderSheet.swift   # 프로바이더 설정 시트
│       ├── CreateRoomSheet.swift    # 방 생성 시트
│       ├── OnboardingView.swift     # 첫 실행 온보딩 2단계 UI
│       ├── RoomListView.swift       # 방 목록 + 상태 필터 + 편집 모드 (전체 선택/일괄 완료·삭제)
│       ├── RoomChatView.swift       # 방별 채팅 인터페이스
│       ├── WorkLogView.swift        # 방 작업 로그 뷰
│       ├── AgentAvatarView.swift    # 원형 아바타 (마스터/서브 아이콘 분기)
│       ├── SuggestionCard.swift     # 에이전트 자동 생성 제안 카드
│       ├── DesignTokens.swift       # 디자인 시스템 (색상, 타이포, 간격, 모서리, 애니메이션, 윈도우 크기)
│       ├── SharedComponents.swift   # 공유 UI 컴포넌트 (SheetNavHeader, CardContainer, SendButton 등)
│       └── ToastView.swift          # 임시 알림 오버레이
```

---

## 아키텍처

### MVVM 패턴

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Models     │ ←── │   ViewModels     │ ←── │     Views       │
│             │     │                  │     │                 │
│ Agent       │     │ AgentStore       │     │ FloatingSidebar │
│ ChatMessage │     │ ChatViewModel    │     │ ChatView        │
│ ImageAttach │     │ ProviderManager  │     │ ChatContentView │
│ ProviderCfg │     │ RoomManager      │     │ RoomChatView    │
│ AgentTool   │     │ ToolExecutor     │     │ ChatWindowView  │
└─────────────┘     └──────────────────┘     └─────────────────┘
                            │
                    ┌───────┴───────┐
                    │   Providers   │
                    │               │
                    │ ClaudeCode    │
                    │ OpenAI        │
                    │ Google        │
                    └───────────────┘
```

### 데이터 흐름

1. **EnvironmentObject**로 전역 상태 공유: `AgentStore`, `ProviderManager`, `ChatViewModel`, `RoomManager`
2. **AppDelegate**가 4개 EnvironmentObject를 생성하고 모든 뷰에 주입
3. **UserDefaults**로 영속성 보장 (에이전트 목록, 프로바이더 설정)
4. **Keychain**으로 API 키 보안 저장 (`KeychainHelper`)
5. **파일시스템**으로 채팅 이력, 에이전트 이미지, 이미지 첨부 영속화 (`~/Library/Application Support/DOUGLAS/`)

---

## 핵심 컴포넌트 상세

### 1. AppDelegate (`App/AppDelegate.swift`)

앱의 중심 컨트롤러. 사이드바 패널과 채팅 윈도우의 생명주기를 관리한다.
4개의 핵심 객체를 생성/관리: `agentStore`, `providerManager`, `chatVM`, `commandBarManager`, `roomManager`

**플로팅 사이드바 (400pt)**:
- `ClickThroughPanel` (NSPanel 서브클래스): 화면 오른쪽 끝에 고정
- `constrainFrameRect` 오버라이드로 팝업 열림에도 위치 불변
- `nonactivatingPanel` + `utilityWindow` 스타일로 다른 앱 작업 방해 없음
- `canJoinAllSpaces` + `fullScreenAuxiliary`로 모든 데스크톱에서 접근 가능
- alphaValue 0/1 + ignoresMouseEvents로 보이기/숨기기 (fade 애니메이션 0.15s)
- **패널 폭 400pt**: 팀 로스터 + 마스터 채팅을 수용하기 위해 260pt에서 확장

**마우스 트래킹**:
- 글로벌 + 로컬 `mouseMoved` 이벤트 모니터링
- 화면 오른쪽 8px 이내 → 사이드바 표시
- 패널 밖으로 이동 → 0.3초 후 숨기기
- 채팅 윈도우가 열려있으면 사이드바 고정 (pinned)

**채팅 윈도우 관리**:
- 에이전트별 독립 NSWindow 생성 (로스터에서 에이전트 클릭 시)
- `isReleasedWhenClosed = false`로 AppKit/Swift ARC 메모리 충돌 방지
- `NotificationCenter`로 창 닫힘/최소화/복원 감지
- 채팅 창 열릴 때 `NSApp.setActivationPolicy(.regular)`, 모두 닫히면 `.accessory`

**커맨드 바 연동**:
- `CommandBarManager` 초기화 및 글로벌 핫키 등록
- `toggleCommandBar()` 메서드로 MenuBarExtra와 연결

### 2. AgentStore (`ViewModels/AgentStore.swift`)

에이전트 목록의 CRUD와 상태 관리를 담당한다.

- 앱 시작 시 마스터 에이전트 자동 생성 보장
- 모든 에이전트 상태를 `.idle`로 초기화 (이전 세션 잔여 상태 제거)
- 마스터 에이전트는 삭제 불가
- 기존 워즈니악 에이전트 자동 마이그레이션 제거
- `minimizedAgentIDs`: 도크에 최소화된 채팅 창 추적
- `subAgents`: 마스터를 제외한 일반 에이전트 필터

**masterSystemPrompt()**: 마스터 에이전트의 동적 시스템 프롬프트 생성
- 현재 등록된 서브 에이전트 목록 (이름, 도구 목록, 페르소나 요약) 포함
- 3가지 JSON 응답 형식 명시: delegate, chain, suggest_agent (직접 응답 금지)
- Jira 연동 상태 (JiraConfig.shared.isConfigured) 표시
- 에이전트 목록이 비어있으면 "(없음)" 표시

### 3. ChatViewModel (`ViewModels/ChatViewModel.swift`)

앱의 핵심 오케스트레이션 엔진. 마스터 에이전트의 6가지 기능을 구현한다.

**MasterAction enum**:
```
delegate  → 병렬 위임 (여러 에이전트 동시 실행)
suggest   → 새 에이전트 생성 제안
chain     → 순차 워크플로우 (A→B→C)
unknown   → JSON 파싱 실패 시 원문 표시
```
(respond 액션 제거됨 — 마스터는 직접 응답 금지, 반드시 delegate/suggest_agent/chain만 사용)

**5대 핵심 기능**:

| # | 기능 | 메서드 | 설명 |
|---|------|--------|------|
| 1 | 자동 라우팅 | `handleDelegation()` | 마스터가 JSON으로 위임 에이전트 지정, `withTaskGroup`으로 병렬 실행 |
| 2 | 결과 취합 | `generateSummary()` | 2개 이상 에이전트 응답 시 마스터가 종합 요약 생성 |
| 3 | 에이전트 제안 | `handleAgentSuggestion()` | 적합한 에이전트 없을 때 새 에이전트 생성 제안 (SuggestionCard) |
| 4 | 오류 재시도 | `executeDelegation()` | 실패 시 최대 2회 재시도 (2초 간격), 실패 시 마스터 폴백 응답 |
| 5 | 워크플로우 체이닝 | `handleChain()` | 순차 실행, 이전 단계 출력을 다음 단계 입력에 주입 |

**JSON 파싱 (`parseMasterResponse`)**:
- 마크다운 코드블록 (` ```json ... ``` `) 내부 JSON 추출
- 일반 코드블록 (` ``` ... ``` `) 처리
- `{ ... }` 패턴 매칭
- 파싱 실패 시 `.unknown`으로 폴백 (원문 그대로 표시)

**이미지 첨부 지원**:
- `sendMessage(attachments:)`: 이미지 첨부 메시지 전송
- `buildConversationHistory()`: 이미지 포함 `[ConversationMessage]` 빌드
- 이미지가 있으면 `smartSend(conversationMessages:)` 오버로드 사용

**메시지 영속화**:
- `~/Library/Application Support/DOUGLAS/chats/` 디렉토리에 에이전트별 JSON 저장
- `saveMessages()` / `loadMessages()`로 앱 재시작 시 복원

**알림 시스템**:
- `UNUserNotificationCenter`로 macOS 알림 발송
- 작업 완료 / 오류 발생 시 자동 알림

### 4. ProviderManager (`ViewModels/ProviderManager.swift`)

3개 프로바이더 설정을 관리한다.

| 프로바이더 | 인증 방식 | 설명 |
|-----------|----------|------|
| Claude Code | 없음 (CLI) | 설치된 `claude` CLI 실행, API 키 불필요 |
| OpenAI | API Key | GPT-4o, GPT-4o-mini 등 |
| Google | API Key | Gemini 2.0 Flash, Pro 등 |

- `ensureDefaultProviders()`: 3개 기본 프로바이더 보장, 비활성 프로바이더 (Ollama, LM Studio 등) 자동 제거
- `createProvider(from:)`: ProviderType에 따른 팩토리 메서드

---

## AI Provider 레이어

### AIProvider 프로토콜 (`Providers/AIProvider.swift`)

```swift
protocol AIProvider {
    var config: ProviderConfig { get }
    func fetchModels() async throws -> [String]
    func sendMessage(model:systemPrompt:messages:) async throws -> String

    // Tool Use 확장
    var supportsToolCalling: Bool { get }
    func sendMessageWithTools(
        model: String, systemPrompt: String,
        messages: [ConversationMessage], tools: [AgentTool]
    ) async throws -> AIResponseContent
}
```

- `applyAuth(to:)` 확장: AuthMethod에 따라 Bearer/x-api-key/커스텀 헤더 자동 적용
- `AIProviderError`: invalidURL, invalidResponse, apiError, networkError, noAPIKey
- **Tool Use default 구현**: `supportsToolCalling = false`, tools 무시하고 기존 `sendMessage()` 폴백

### ClaudeCodeProvider (`Providers/ClaudeCodeProvider.swift`)

가장 독특한 프로바이더. Claude Code CLI를 `ProcessRunner`로 실행한다.

- `findClaudePath()`: nvm, homebrew, local 등 다양한 경로에서 claude 바이너리 탐색
- `claude -p <prompt> --model <model>` 형태로 비대화형 실행
- 환경변수 `CLAUDECODE`를 제거하여 중첩 세션 감지 우회
- PATH에 nvm 경로 추가하여 node 의존성 해결
- 시스템 프롬프트 + 대화 히스토리를 단일 프롬프트로 조합

### OpenAIProvider (`Providers/OpenAIProvider.swift`)

- `/v1/models` 엔드포인트로 모델 목록 조회 (gpt, o1, o3, o4 필터)
- `/v1/chat/completions`로 메시지 전송
- 타임아웃: 120초
- **Tool Use**: `supportsToolCalling = true`, `tools` 배열 + `tool_calls` 응답 파싱
- **Vision**: 이미지 첨부 시 `openAIContentArray()`로 `image_url` 블록 생성

### AnthropicProvider (`Providers/AnthropicProvider.swift`)

- Anthropic Messages API (`/v1/messages`)
- **Tool Use**: `supportsToolCalling = true`, `tools` 배열 + `tool_use` content block 파싱
- `tool_result`는 user role 메시지의 content block으로 전송 (Anthropic 규격)
- **Vision**: 이미지 첨부 시 `anthropicContentBlocks()`로 `image` source 블록 생성

### GoogleProvider (`Providers/GoogleProvider.swift`)

- 하드코딩된 모델 목록: gemini-2.0-flash, gemini-2.0-pro, gemini-1.5-flash, gemini-1.5-pro
- `/v1beta/models/{model}:generateContent?key=` 엔드포인트
- 시스템 프롬프트를 user/model 턴 쌍으로 주입
- role 매핑: assistant → model
- **Tool Use**: `supportsToolCalling = true`, `function_declarations` + `functionCall` 파싱
- **Vision**: 이미지 첨부 시 `googleParts()`로 `inlineData` 블록 생성

---

## 모델 레이어

### Agent (`Models/Agent.swift`)

```swift
struct Agent: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String              // 에이전트 표시 이름
    var persona: String           // 시스템 프롬프트 (역할/성격)
    var providerName: String      // "Claude Code", "OpenAI", "Google"
    var modelName: String         // "claude-sonnet-4-6", "gpt-4o" 등
    var status: AgentStatus       // idle / working / busy / error (상태 레퍼런스 참조)
    var isMaster: Bool            // 마스터 에이전트 여부
    var errorMessage: String?     // 마지막 오류 메시지
    var hasImage: Bool            // 아바타 이미지 유무 (파일시스템 저장)
    var resolvedToolIDs: [String] { ... }    // 항상 ToolRegistry.allToolIDs (모든 에이전트 전체 도구)
    var hasToolsEnabled: Bool { ... }        // 항상 true
}
```

- Equatable: 모든 주요 필드 비교 (SwiftUI 변경 감지용)
- Hashable: id만 사용
- `createMaster()`: 기본 마스터 에이전트 팩토리 (Claude Code + 위임 페르소나)
- 이미지: `~/Library/Application Support/DOUGLAS/avatars/{id}.png`에 저장 (static save/load/delete)

### ChatMessage (`Models/ChatMessage.swift`)

```swift
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole        // user / assistant / system
    let content: String
    let agentName: String?       // 응답한 에이전트 이름
    let timestamp: Date
    var messageType: MessageType // text / delegation / summary / chainProgress / suggestion / error / discussionRound / toolActivity
    let attachments: [ImageAttachment]?  // 이미지 첨부 (Vision API용)
}
```

- `init(from decoder:)`: messageType, attachments가 없는 기존 데이터와 역호환 (`.text` 기본값, `nil`)
- MessageType에 따라 채팅 버블의 색상, 아이콘, 테두리가 달라짐
- `attachments`: 이미지 첨부 시 메시지 버블에 썸네일 표시

### ImageAttachment (`Models/ImageAttachment.swift`)

```swift
struct ImageAttachment: Codable, Identifiable {
    let id: UUID
    let filename: String        // UUID.ext
    let mimeType: String        // "image/jpeg", "image/png", "image/gif", "image/webp"
    let fileSizeBytes: Int
}
```

- 디스크 저장: `~/Library/Application Support/DOUGLAS/attachments/{filename}`
- `save(data:mimeType:)`: 데이터를 디스크에 저장하고 메타데이터 반환
- `loadBase64()` / `loadData()`: API 호출 시점에 디스크에서 로드 (메모리 절약)
- `delete()`: 디스크 파일 삭제
- `mimeType(for:)`: 매직바이트로 MIME 타입 판별 (JPEG/PNG/GIF/WebP)
- 크기 제한: 이미지당 최대 20MB
- `ImageAttachmentError`: `.fileTooLarge`, `.unsupportedFormat`

### AgentRoleTemplate (`Models/AgentRoleTemplate.swift`)

```swift
struct AgentRoleTemplate: Identifiable, Codable {
    let id: String                          // "jira_analyst", "backend_dev" 등
    let name: String                        // "Jira 분석가"
    let icon: String                        // SF Symbol
    let category: TemplateCategory          // 분석/개발/품질/운영
    let basePersona: String                 // 기본 시스템 프롬프트
    let providerHints: [String: String]     // 프로바이더별 추가 지시

    func resolvedPersona(for providerType: String) -> String  // 프로바이더별 최적화 프롬프트
}
```

- `AgentRoleTemplateRegistry`: 빌트인 9개 템플릿 (requirements_analyst, backend_dev, frontend_dev, qa_test_automation, qa_exploratory, qa_security, qa_code_review, tech_writer, devops_engineer)
- 에이전트 생성 시 템플릿 선택 → persona/name 자동 설정
- `Agent.roleTemplateID`: 적용된 템플릿 ID (nil = 사용자 정의)

### DiscussionArtifact (`Models/DiscussionArtifact.swift`)

```swift
struct DiscussionArtifact: Identifiable, Codable {
    let id: UUID
    let type: ArtifactType      // api_spec, test_plan, task_breakdown, architecture_decision, generic
    let title: String
    let content: String
    let producedBy: String      // 에이전트 이름
    let createdAt: Date
    var version: Int             // 같은 산출물 업데이트 시 증가
}
```

- 토론 중 에이전트가 ```` ```artifact:<type> title="제목" ```` 형식으로 작성
- `ArtifactParser`가 자동 추출 → `Room.artifacts`에 저장
- 실행 단계에서 `[참고 산출물]`로 컨텍스트 주입

### RoomBriefing (`Models/Room.swift`)

```swift
struct RoomBriefing: Codable {
    let summary: String                         // 작업 요약 (2-3문장)
    let keyDecisions: [String]                  // 핵심 결정사항
    let agentResponsibilities: [String: String] // 에이전트명 → 담당 역할
    let openIssues: [String]                    // 미결 사항

    func asContextString() -> String            // 실행 단계용 포맷
}
```

- 토론 종료 후 `generateBriefing()`이 LLM에게 JSON 형식 브리핑 요청
- 계획 수립: 전체 토론 히스토리(40msg) 대신 브리핑 + 산출물만 전달
- 실행 단계: 브리핑 + 최근 5개 메시지만 전달 → 토큰 대폭 절약
- `Room.briefing`: nil이면 기존 히스토리 폴백

### ArtifactParser (`Models/ArtifactParser.swift`)

```swift
enum ArtifactParser {
    static func extractArtifacts(from content: String, producedBy: String) -> [DiscussionArtifact]
    static func stripArtifactBlocks(from content: String) -> String
}
```

- 정규식으로 ```` ```artifact:<type> title="..." ```` 블록 파싱
- `stripArtifactBlocks`: 채팅 표시 시 산출물 블록 제거 (별도 UI에 표시)

### ToolExecutionContext (`Models/ToolExecutionContext.swift`)

```swift
struct ToolExecutionContext: Sendable {
    let roomID: UUID?
    let agentsByName: [String: UUID]
    let agentListString: String
    let inviteAgent: @Sendable (UUID) async -> Bool
}
```

- 도구 실행 시 필요한 방/에이전트 컨텍스트의 **스냅샷**
- `Sendable`로 `@MainActor` 경계를 안전하게 통과
- `inviteAgent` 클로저: `@Sendable`로 전달, MainActor에서 실행
- `static let empty`: 기본값 (방 컨텍스트 없음)

### DependencyChecker (`Models/DependencyChecker.swift`)

온보딩 시 필수 의존성 (Node.js, Git, Homebrew)의 설치 여부를 확인한다.

- `Dependency` 구조체: 이름, 바이너리명, 필수 여부, 다운로드 URL, 설치 힌트
- `checkAll()`: 각 바이너리를 시스템 PATH에서 탐색
- `allRequiredFound`: 필수 의존성이 모두 설치되었는지 (computed)
- Node.js/Git: 필수, Homebrew: 선택

### KeychainHelper (`Models/KeychainHelper.swift`)

- `save(key:value:)` / `load(key:)` / `delete(key:)` 정적 메서드
- **ChaChaPoly 암호화**: CryptoKit 기반 대칭키 암호화로 API 키 보호
  - 디바이스별 고유 대칭키 자동 생성 (`SymmetricKey(size: .bits256)`)
  - 키 파일 권한 0o600 (소유자만 읽기/쓰기)
- **하위 호환**: 기존 Base64 인코딩 파일 자동 감지 → 암호화 형식으로 마이그레이션
- **레거시 Keychain 마이그레이션**: macOS Keychain에서 파일 기반으로 자동 이전
- `ProviderConfig.apiKey`가 computed property로 작동 (get → 복호화 / set → 암호화)

### JiraConfig (`Models/JiraConfig.swift`)

```swift
class JiraConfig: ObservableObject {
    static let shared = JiraConfig()
    @Published var domain: String      // "mycompany.atlassian.net"
    @Published var email: String       // Jira 계정 이메일
    @Published var apiToken: String    // Jira API 토큰
    var isConfigured: Bool             // 3개 필드 모두 입력됐는지 (computed)
    var baseURL: String                // "https://{domain}" (computed)
}
```

- 싱글턴: `JiraConfig.shared`로 앱 전역 접근
- UserDefaults 영속화: `jira_domain`, `jira_email` 키 (API 토큰은 KeychainHelper)
- `web_fetch` 도구에서 Jira URL 감지 시 자동으로 REST API 호출에 인증 헤더 추가
- `masterSystemPrompt()`에서 Jira 연동 상태 표시

### ProviderConfig (`Models/ProviderConfig.swift`)

```swift
struct ProviderConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: ProviderType      // claudeCode / openAI / google / ...
    var baseURL: String         // API URL 또는 CLI 경로
    var authMethod: AuthMethod  // none / apiKey / bearerToken / customHeader
    var apiKey: String?         // Keychain computed property (get/set → KeychainHelper)
    var isBuiltIn: Bool         // 기본 제공 프로바이더 여부
}
```

- 역호환 디코더: authMethod가 없으면 ProviderType에서 기본값 추론
- `apiKey`는 Codable 저장에서 제외, Keychain을 통해 읽기/쓰기
- `isConnected: Bool` — 프로바이더가 사용 가능한 상태인지 (Claude: 바이너리 존재, API: 키 설정됨, 로컬: 항상 true)

---

## 상태 레퍼런스

### AgentStatus (`Models/Agent.swift`)

에이전트의 현재 활동 상태. `RoomManager.syncAgentStatuses()`가 활성 방 참여 수에 따라 자동 갱신.

| 상태 | 표시 텍스트 | 색상 | 조건 |
|------|-----------|------|------|
| `idle` | 대기 | 회색 | 활성 방 0개 |
| `working` | 작업중 | 주황 | 활성 방 1~2개 |
| `busy` | 바쁨 | 빨강 | 활성 방 3개 이상 |
| `error` | 오류 | 빨강 | 에이전트 실행 중 오류 발생 (수동 해제 전까지 유지) |

- 상태 변경은 런타임 전용 (디스크 저장 안 함)
- 앱 시작 시 모든 에이전트 `.idle`로 초기화
- `.error` 상태는 `syncAgentStatuses()`에서 덮어쓰지 않음

### RoomStatus (`Models/Room.swift`)

방의 워크플로우 상태. 허용된 전이만 가능 (`canTransition(to:)` 검증).

| 상태 | 표시 텍스트 | 색상 | 설명 |
|------|-----------|------|------|
| `planning` | 계획 중 | 보라 | 토론 + 계획 수립 단계 |
| `inProgress` | 진행중 | 주황 | 계획에 따라 작업 실행 중 |
| `awaitingApproval` | 승인 대기 | 노랑 | Human-in-the-loop 승인 게이트 |
| `completed` | 완료 | 초록 | 모든 단계 완료 |
| `failed` | 실패 | 빨강 | 오류 또는 승인 거부로 중단 |

상태 전이:
```
planning → awaitingApproval (토론 후 사용자 승인)
    │              │
    │              ├→ planning (승인 → 계획 수립)
    │              └→ failed (거부)
    │
    ├→ inProgress → completed
    │      │
    │      ├→ awaitingApproval → inProgress (단계 승인)
    │      │                   → failed (거부)
    │      └→ failed
    ├→ completed
    └→ failed
```

`isActive` = `planning` | `inProgress` | `awaitingApproval` (에이전트 상태 계산에 사용)

---

## 뷰 레이어

### FloatingSidebarView (`Views/FloatingSidebarView.swift`)

플로팅 사이드바의 메인 뷰. **팀 로스터 + 마스터 채팅** 구조로 설계되어 있다.

```
┌──────────────────────────────────────┐
│ 🧠 DOUGLAS           [+] [⚙] │  ← 헤더
│ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐  → │
│ │💻│ │📝│ │📊│ │🎨│ │🔧│ │..│     │  ← 에이전트 로스터 (가로 스크롤)
│ │🟠│ │  │ │  │ │🟠│ │🔴│ │  │     │     아바타 + 상태 표시등
│ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘     │
│ ─────────────────────────────────── │
│                                     │
│ 나: 블로그 글 하나 써줘              │
│ 마스터: 마케팅팀에게 위임합니다...     │  ← 마스터 채팅 영역
│ 마케팅: [초안 작성 완료...]           │
│                                     │
│ ┌─────────────────────────────┐     │
│ │ 메시지 입력...               │     │  ← 입력창 (항상 마스터에게)
│ └─────────────────────────────┘     │
└──────────────────────────────────────┘
```

**헤더**: 마스터 아바타 + "DOUGLAS" 타이틀 + 에이전트 추가 버튼 + 설정 버튼

**에이전트 로스터** (가로 스크롤):
- 서브 에이전트를 원형 아바타 + 이름 + 상태 표시등으로 표시
- 상태 표시등 색상: 대기(회색) / 작업중(주황) / 바쁨(빨강) / 오류(빨강)
- 작업중/바쁨 에이전트는 테두리로 시각적 강조 (주황/빨강)
- 에이전트 클릭 → 별도 채팅 윈도우 열기 (직접 대화)
- 우클릭 컨텍스트 메뉴: 편집/정보/삭제
- 20개 이상 에이전트도 가로 스크롤로 수용

**마스터 채팅 영역**:
- `ScrollViewReader` + `LazyVStack` + `MessageBubble`로 메시지 표시
- 웰컴 메시지: "무엇을 시킬까요?"
- SuggestionCard 표시 (마스터의 에이전트 생성 제안)
- 로딩 인디케이터 + 작업 취소 버튼

**입력창**: `TextField(axis: .vertical)` + 전송 버튼 + 이미지 첨부 버튼, `Cmd+Return` 단축키, 항상 마스터에게 전송

**이미지 첨부**:
- 이미지 첨부 버튼 (`photo.badge.plus`): NSOpenPanel으로 jpg/png/gif/webp 선택
- 드래그 앤 드롭: `.onDrop(of:)` + `NSItemProvider`
- 첨부 미리보기: 입력창 상단에 썸네일 행 (X 버튼으로 제거)

**슬래시 커맨드** (`SlashCommand` + `SlashMenuState`):
- `/` 입력 시 드롭다운 메뉴 표시, 타이핑에 따라 필터링
- `/clear`: 마스터 채팅 내역 초기화
- 키보드 네비게이션: ↑/↓ 선택, Enter 실행, Escape 닫기 (`NSEvent.addLocalMonitorForEvents`)

**토스트 알림**: 하단에 에러 메시지 표시 (4초 후 자동 사라짐)

**UtilityWindowManager** (싱글턴): 모든 유틸리티 윈도우를 중앙 관리
- 참조를 배열로 유지하여 메모리 누수 방지
- 창 닫힘 시 자동 정리 (NotificationCenter)

### ChatView / ChatContentView / ChatWindowView

- **ChatView**: 사이드바 내부용 채팅 뷰 (헤더 + ChatContentView)
- **ChatContentView**: 공유 채팅 UI 컴포넌트
- **ChatWindowView**: 독립 윈도우용 채팅 뷰 (ChatContentView 사용)

ChatContentView 구성:
- 메시지 목록: `ScrollView` + `LazyVStack` + `MessageBubble`
- SuggestionCard: 마스터 에이전트의 제안 카드
- 에이전트별 로딩 인디케이터 (`loadingAgentIDs`) + 작업 취소 버튼
- 입력창: TextField (1~5줄 동적) + 전송 버튼 (Cmd+Return)
- 자동 스크롤: 새 메시지 시 하단으로 이동

### MessageBubble (`Views/ChatView.swift` 내부)

MessageType에 따른 시각 차별화:

| MessageType | 배경색 | 아이콘 | 테두리 |
|-------------|--------|--------|--------|
| text | 회색 15% | - | - |
| delegation | 주황 8% | arrow.turn.up.right | - |
| summary | 보라 10% | text.document | 보라 30% |
| chainProgress | 파랑 8% | link | - |
| suggestion | 주황 8% | sparkles | - |
| error | 빨강 10% | exclamationmark.triangle | - |
| discussionRound | 파랑 5% | bubble.left.and.bubble.right | - |
| toolActivity | 회색 8% | wrench.and.screwdriver | - |
| buildStatus | 주황 10% | hammer | - |
| qaStatus | 틸 10% | checkmark.shield | - |
| approvalRequest | 노랑 10% | hand.raised | - |

사용자 메시지: accentColor 배경, 흰색 텍스트, 오른쪽 정렬

이미지 첨부가 있는 메시지: 텍스트 위에 이미지 썸네일 그리드 표시 (최대 180x120pt)

### AgentAvatarView (`Views/AgentAvatarView.swift`)

재사용 가능한 원형 아바타 컴포넌트:
- hasImage 있으면 → 파일시스템에서 이미지 로드 → 원형 클립
- 마스터 에이전트 → `brain.head.profile` (보라색)
- 서브 에이전트 → `person.crop.circle` (파란색)

`pickAgentImage()` 유틸: NSOpenPanel → PNG/JPEG 선택 → 128x128 리사이즈 → 파일시스템 저장

### EditAgentSheet (`Views/EditAgentSheet.swift`)

에이전트 편집 시트:
- 아바타: 이미지 선택/제거
- 이름: 마스터는 수정 불가 (LabeledContent)
- 페르소나: TextEditor
- 프로바이더/모델: Picker (동적 모델 목록 로딩)

### SuggestionCard (`Views/SuggestionCard.swift`)

마스터가 `suggest_agent` 응답 시 채팅 내에 표시되는 인라인 카드:
- 제안된 에이전트의 이름, 역할, 프로바이더/모델 표시
- "생성" 버튼: 즉시 에이전트 추가 (전체 도구 자동 부여)
- "무시" 버튼: 제안 닫기

### AddProviderSheet (`Views/AddProviderSheet.swift`)

프로바이더 설정 UI:
- **Claude Code**: CLI 경로 표시, 연결 상태 확인
- **OpenAI**: SecureField로 API 키 입력, 연결 테스트, 저장
- **Google**: SecureField로 API 키 입력, 연결 테스트, 저장
- **Jira Cloud**: 도메인 + 이메일 + API 토큰 설정 (JiraConfig에 저장, web_fetch 도구에서 사용)

---

## 빌드 및 배포

### build-app.sh

```bash
# 1. swift build -c release
# 2. .app 번들 구성 (Info.plist, 실행파일 복사)
# 3. Ad-hoc 코드서명 (codesign --force --deep --sign -)
# 4. DMG 생성 (create-dmg 또는 hdiutil)
```

**Info.plist 주요 설정**:
- `CFBundleIdentifier`: com.douglas.app
- `LSMinimumSystemVersion`: 14.0
- `LSApplicationCategoryType`: public.app-category.developer-tools
- `NSAppTransportSecurity.NSAllowsArbitraryLoads`: true (로컬 API 접근용)

---

## 해결된 주요 기술 이슈

### 1. 채팅 창 닫을 때 앱 크래시 (SIGSEGV)
- **원인**: `NSWindow.isReleasedWhenClosed` 기본값 `true` → AppKit이 창 해제 → Swift 딕셔너리가 이미 해제된 객체 참조 → double-free
- **해결**: `window.isReleasedWhenClosed = false` + NotificationCenter 기반 정리

### 2. 다른 앱 클릭 시 채팅 창 사라짐
- **원인**: MenuBarExtra 앱의 `.accessory` 활성화 정책이 모든 윈도우를 숨김
- **해결**: 채팅 창 열릴 때 `.regular`, 모두 닫히면 `.accessory`로 동적 전환

### 3. 사이드바 숨김 불일치
- **원인**: `distanceFromRight > panelWidth + 30` 조건에 데드존 존재
- **해결**: "패널 밖 = 항상 숨김 예약"으로 단순화

### 4. 에이전트 이미지 저장 후 미표시
- **원인**: Agent의 `==` 연산자가 `id`만 비교 → SwiftUI가 변경 미감지
- **해결**: 모든 주요 필드 (name, persona, imageData 등) 비교로 확장

### 5. 팝업 시 사이드바 위치 이탈
- **원인**: `.resizable` 스타일 + `.sheet()` 프레젠테이션이 패널 리사이즈 유발
- **해결**: `constrainFrameRect` 오버라이드로 항상 오른쪽 끝 고정 + `.sheet()` → `openCenteredWindow()`로 교체

---

## 글로벌 커맨드 바

### 개요

**Spotlight 스타일** 커맨드 바. 어디서든 `⌘⇧A`(Cmd+Shift+A)로 호출하여 마스터 에이전트에게 빠르게 질문할 수 있다.
사이드바를 열지 않아도 핫키 한번으로 마스터에게 접근 가능.

### 구성 파일

| 파일 | 역할 |
|------|------|
| `CommandBarPanel.swift` | NSPanel 서브클래스. `canBecomeKey` + `onResignKey` 콜백 |
| `CommandBarView.swift` | SwiftUI 뷰. TextEditor(100pt+) + 응답 영역 + 전체 대화 열기 |
| `CommandBarManager.swift` | 핫키 등록, 패널 생명주기, show/dismiss 애니메이션 |

### 핫키 등록

`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` + `addLocalMonitorForEvents`
— 글로벌(앱 비활성 시) + 로컬(앱 활성 시) 듀얼 모니터 패턴 (마우스 트래킹과 동일)
— keyCode `0x00` (A키) + `.command, .shift` 조합

### UX 흐름

```
⌘⇧A → 커맨드 바 화면 중앙 상단에 표시
→ TextEditor에 타이핑 (넓은 입력 영역, 4-5줄)
→ ⌘⏎ 전송 → 마스터가 처리 → 응답 인라인 표시
→ ESC 또는 외부 클릭으로 닫기
→ "전체 대화 열기" → 마스터 채팅 윈도우 확장
```

### 패널 설정

- 크기: 600×360pt, 화면 상단 1/3 지점 중앙
- styleMask: `[.nonactivatingPanel, .titled, .fullSizeContentView]`
- level `.floating`, `hidesOnDeactivate = false`
- 외부 클릭 시 자동 닫기 (`onResignKey` → `dismiss()`)
- show/dismiss: NSAnimationContext 0.15s 페이드 애니메이션

---

## 빠른 접근 방법 요약

| 방법 | 단축키/동작 | 대상 | 용도 |
|------|------------|------|------|
| **사이드바** | 마우스 오른쪽 끝 8px | 마스터 | 기본 채팅 인터페이스 |
| **커맨드 바** | `⌘⇧A` | 마스터 | 빠른 질문, 어디서든 접근 |
| **로스터 클릭** | 에이전트 아바타 탭 | 개별 에이전트 | 직접 대화 (별도 윈도우) |
| **메뉴바** | `⌘⇧E` | 사이드바 토글 | 수동 사이드바 표시/숨기기 |

---

## Tool Use (Function Calling) 시스템

### 개요

에이전트가 파일 읽기/쓰기, 셸 실행 등 실제 작업을 수행할 수 있는 도구 호출 시스템.
하나의 `AgentTool` 정의를 OpenAI/Anthropic/Google 각 프로바이더 형식으로 자동 변환한다.

### 핵심 타입 (`Models/AgentTool.swift`)

| 타입 | 역할 |
|------|------|
| `AgentTool` | 프로바이더 무관 도구 정의 (id, name, description, parameters) |
| `ToolCall` | 모델이 요청한 도구 호출 (id, toolName, arguments) |
| `ToolResult` | 도구 실행 결과 (callID, content, isError) |
| `ToolArgumentValue` | 타입 안전 인자값 enum (string/integer/boolean/array) |
| `AIResponseContent` | 응답 enum (.text / .toolCalls / .mixed) |
| `ConversationMessage` | 도구 메시지 포함 가능한 리치 메시지 타입 |
| `ToolRegistry` | 내장 도구 카탈로그 |

### 내장 도구 (ToolRegistry)

모든 에이전트는 전체 11종 도구에 접근 가능 (프리셋 제한 없음).

| ID | 이름 | 설명 |
|----|------|------|
| `file_read` | 파일 읽기 | 지정 경로 파일 내용 읽기 (50K자 제한) |
| `file_write` | 파일 쓰기 | 지정 경로에 파일 작성 |
| `shell_exec` | 셸 실행 | zsh 명령어 실행 (30K자 출력 제한) |
| `web_search` | 웹 검색 | 웹 검색 (미구현 placeholder) |
| `web_fetch` | 웹 페이지 가져오기 | URL → HTML 가져오기 + Jira REST API 티켓 조회 (JiraConfig 연동) |
| `invite_agent` | 에이전트 초대 | 방에 다른 에이전트를 런타임 초대 (params: agent_name, reason) |
| `list_agents` | 에이전트 목록 | 등록된 서브 에이전트 목록 조회 (params: 없음) |
| `jira_create_subtask` | Jira 서브태스크 생성 | 상위 이슈에 서브태스크 자동 생성 (params: parent_key, summary, project_key?) |
| `jira_update_status` | Jira 상태 변경 | 이슈 상태 전이 (params: issue_key, status_name) |
| `jira_add_comment` | Jira 코멘트 작성 | ADF 형식으로 코멘트 추가 (params: issue_key, comment) |

### ToolFormatConverter (`Providers/ToolFormatConverter.swift`)

프로바이더별 도구 형식 변환 유틸리티:
- `toOpenAI()` / `parseOpenAIToolCalls()` — OpenAI tools 형식
- `toAnthropic()` / `parseAnthropicToolUse()` — Anthropic content blocks 형식
- `toGoogle()` / `parseGoogleFunctionCalls()` — Google function_declarations 형식
- `buildJSONSchema()` — AgentTool.parameters → JSON Schema
- `parseArguments()` / `encodeArguments()` — JSON 문자열 ↔ ToolArgumentValue 변환
- **Vision 이미지 블록 빌더**:
  - `anthropicContentBlocks(text:attachments:)` → `[{type:image, source:{base64}}, {type:text}]`
  - `openAIContentArray(text:attachments:)` → `[{type:image_url, image_url:{url:data:...}}, {type:text}]`
  - `googleParts(text:attachments:)` → `[{inlineData:{mimeType, data}}, {text}]`

### ToolExecutor (`ViewModels/ToolExecutor.swift`)

도구 호출 루프 실행 엔진:

```
smartSend(messages:) → 도구 없거나 미지원? → 기존 sendMessage()
                     → 도구 있고 지원?      → executeWithTools()

smartSend(conversationMessages:) → 이미지 첨부 있으면 도구 없어도 sendMessageWithTools()
                                 → 이미지+도구 → executeWithTools()

executeWithTools() 루프 (최대 10회):
  1. sendMessageWithTools() 호출
  2. .text → 최종 응답 반환
  3. .toolCalls/.mixed → 각 도구 실행 → 결과를 messages에 추가 → 1로 돌아감
```

- 두 가지 `smartSend` 오버로드: 단순 텍스트 `[(role, content)]` + 이미지 가능 `[ConversationMessage]`
- `onToolActivity` 콜백으로 도구 사용 상태를 채팅에 표시 (`.toolActivity` 메시지)
- **경로 검증**: `isPathAllowed()` — `$HOME`, `/tmp`, 시스템 임시 디렉토리만 허용. `.ssh`, `.gnupg`, `Library/Keychains` 차단
- **shell_exec**: nvm 버전 동적 탐색 (하드코딩 아님)
- **web_fetch**: URL → HTTP GET, Jira URL 감지 시 JiraConfig 인증 + REST API 자동 변환
- **invite_agent**: `ToolExecutionContext.inviteAgent` 클로저 호출로 방에 에이전트 초대
- **list_agents**: `ToolExecutionContext.agentListString` 스냅샷 반환
- **jira_create_subtask**: POST `/rest/api/3/issue` — parent_key에서 projectKey 자동 추론
- **jira_update_status**: GET transitions → 대소문자 무시 이름 매칭 → POST transition
- **jira_add_comment**: POST ADF 형식 코멘트 body
- **Jira 공통**: `makeJiraRequest()` 헬퍼로 JiraConfig.shared 인증 + JSON 헤더 처리

### 통합 지점

| 파일 | 변경 |
|------|------|
| `ChatViewModel.swift` | `handleAgentMessage`, `executeDelegation` → `ToolExecutor.smartSend()` (이미지 포함 시 conversationMessages 오버로드) |
| `RoomManager.swift` | `sendUserMessage`, `executeStep` → `ToolExecutor.smartSend()` + `ToolExecutionContext` 전달 (invite_agent/list_agents 지원) |

**방 워크플로우** (`startRoomWorkflow`): 자동 초대 → 토론 → 사용자 승인 → 계획 수립 → 실행.
- **자동 초대** (`autoInviteForAnalyst`): 분석가 방이면 기존 서브 에이전트를 자동 초대 (토론 참여)
- **토론 후 승인**: 토론 완료 시 브리핑 생성 → `.awaitingApproval` → 사용자 승인 후 계획 수립
- **CLI WebFetch 차단**: `ClaudeCodeProvider.sendMessage()`에서 `--disallowed-tools WebFetch` 적용 (바이브코딩 유지, URL 직접 접근만 차단)
- **SuggestionCard 편집**: 에이전트 생성 전 이름/설명을 사용자가 편집 가능 (마스터가 초안 제공)

**승인 게이트** (`executeRoomWork`): `step.requiresApproval == true`이면 `.awaitingApproval` 상태 전환 + `CheckedContinuation`으로 비동기 일시 정지. `approveStep(roomID:)` / `rejectStep(roomID:)` 호출 시 continuation resume. 거부 시 `.failed` 전환.

**작업일지**: `executeRoomWork()` 완료 시 `generateWorkLog()` → 상태 전환 순서. `completeRoom()` (수동 완료)에서도 작업일지 생성.

**QA 루프** (`runQALoop`): 빌드 루프 성공 후 `testCommand`가 있으면 자동 실행. `BuildLoopRunner.runTests()` → 실패 시 QA 에이전트(`roleTemplateID == "qa_engineer"`)에게 수정 프롬프트 → 재테스트 (최대 `maxQARetries`회).

**컨텍스트 압축**: 토론 종료 후 `generateBriefing()`이 전체 히스토리를 JSON 브리핑으로 압축.
- 계획 수립: 브리핑 + 산출물만 전달 (40msg → ~500토큰)
- 실행 단계: 브리핑 + 최근 5개 메시지 (`buildRoomHistory(limit: 5)`)
- 브리핑 없으면 기존 히스토리 폴백

**토론 산출물**: `executeDiscussionTurn()`에서 응답 파싱 → `ArtifactParser.extractArtifacts()` → `Room.artifacts` 저장. 같은 type+title이면 버전 증가.

마스터 라우팅, 요약 생성, 토론 턴 등 텍스트 전용 호출은 기존 `sendMessage()` 유지.

---

## 개발 로드맵

### Phase A — 기반 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| A-1 | Agent Role Template 시스템 (역할 템플릿 + 모델별 어댑터) | ✅ |
| A-2 | 토론 산출물 구조화 (artifact 블록 자동 추출, 버전 관리) | ✅ |
| A-3 | 컨텍스트 요약/압축 전달 메커니즘 (RoomBriefing) | ✅ |

### Phase B — 개발 루프 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| B-1 | **프로젝트 디렉토리 연동**: 방 생성 시 `projectPath` 지정 → 상대 경로 해석, `isPathAllowed` projectPath 허용, `shell_exec` 기본 workDir. `Room.projectPath`, `Room.buildCommand` 추가. CreateRoomSheet에 디렉토리 선택 + 빌드 명령 자동 감지 UI. | ✅ |
| B-2 | **빌드→에러→수정 자율 루프**: `BuildLoopRunner.runBuild()` → 실패 시 에이전트에게 수정 프롬프트 → 재빌드 (최대 `maxBuildRetries`회). `BuildResult`, `BuildLoopStatus` 모델. `RoomManager.runBuildLoop()` 통합. BuildStatusCard UI. | ✅ |
| B-3 | **병렬 실행 파일 충돌 감지**: `FileWriteTracker` actor — 에이전트별 파일 쓰기 기록, 동일 파일 다중 에이전트 수정 시 충돌 경고. `ToolExecutionContext`에 `currentAgentID`, `fileWriteTracker` 추가. 단계별 충돌 초기화. | ✅ |

### Phase C — 통합 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| C-1 | **Jira 깊은 연동**: `jira_create_subtask`(서브태스크 생성), `jira_update_status`(상태 전이), `jira_add_comment`(ADF 코멘트) 3개 쓰기 도구 추가. 모든 에이전트에 포함. `makeJiraRequest()` 공통 인증 헬퍼. | ✅ |
| C-2 | **Human-in-the-loop 승인 게이트**: `RoomStep` 구조체 (plain String + object 혼합 Codable). `RoomStatus.awaitingApproval` 추가. `CheckedContinuation`으로 비동기 일시 정지. ApprovalCard UI. | ✅ |
| C-3 | **QA 자동 검증**: `QAResult`/`QALoopStatus` 모델. `BuildLoopRunner.runTests()` + `qaFixPrompt()`. `RoomManager.runQALoop()` — 빌드 성공 후 테스트 자동 실행, 실패 시 QA 에이전트가 수정 루프. 테스트 명령 자동 감지. | ✅ |

### Phase D — 분석가 중심 워크플로우 재구조화 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| D-1 | **요구사항 분석가 리팩토링**: `jira_analyst` → `requirements_analyst`로 개명. 범용 요구사항 분석 + 팀 빌딩(invite_agent, suggest_agent_creation, list_agents) 중심 역할. 레거시 별칭 유지. | ✅ |
| D-2 | **마스터 라우팅 변경**: 분석가 에이전트 존재 시 복잡한 작업을 분석가에게 우선 위임. 분석가 없으면 suggest_agent로 생성 제안. | ✅ |
| D-3 | **에이전트 생성 제안**: `RoomAgentSuggestion` 모델 + `suggest_agent_creation` 도구 + `ToolExecutionContext.suggestAgentCreation` 콜백 + `RoomManager` 승인/거부 관리 + `AgentSuggestionCard` UI. | ✅ |
| D-4 | **방 목록 "확인 필요" 플래그**: `Room.needsUserAttention` (승인 대기 or pending suggestion). 방 목록에 주황 캡슐 뱃지 표시. | ✅ |
| D-5 | **하드코딩 빌드/QA 루프 제거**: `executeRoomWork()`에서 빌드/QA 자동 호출 블록 제거. 에이전트가 계획 단계에서 직접 shell_exec으로 처리. | ✅ |
| D-6 | **QA 템플릿 세분화**: `qa_engineer` 1개 → `qa_test_automation`, `qa_exploratory`, `qa_security`, `qa_code_review` 4종. 레거시 별칭 유지. | ✅ |

---

## 디자인 시스템 (`Views/DesignTokens.swift` + `Views/SharedComponents.swift`)

### 토큰 구조

| 카테고리 | 내용 |
|----------|------|
| `DesignTokens.Radius` | `sm(4)`, `md(6)`, `lg(8)`, `xl(10)` — squircle 전용 |
| `DesignTokens.Spacing` | `xs(4)`, `sm(8)`, `md(12)`, `lg(16)`, `xl(24)` |
| `DesignTokens.Colors` | 13개 시맨틱 색상 — `background`, `inputBackground`, `surfaceSecondary`, `surfaceTertiary`, `hoverBackground`, `activeRowBackground`, `systemMessageBackground`, `messageBubbleBackground`, `avatarFallback`, `overlay`, `separator`, `closeButton`, `stepInactive` 등 |
| `DesignTokens.FontSize` | `nano(8)`, `badge(9)`, `xs(10)`, `sm(11)`, `body(12)`, `bodyMd(13)`, `icon(14)`, `lg(16)` |
| `DesignTokens.Typography` | `mono(_ size:weight:)` 헬퍼, `monoBadge`, `monoStatus` 프리셋 |
| `DesignTokens.WindowSize` | 7개 시트/윈도우 크기 상수 — `agentSheet`, `createRoomSheet`, `providerSheet`, `agentInfoSheet`, `roomChat`, `workLog`, `onboarding` |
| `DesignTokens.Sidebar` | 사이드바 전용: `cornerRadius`, `shadowOpacity`, `shadowRadius` |
| `DesignTokens.Layout` | 사이드바/로스터/상태 표시 레이아웃 상수 |

### 다크모드 대응 패턴

- `Color.primary.opacity(N)` — 라이트(검정) ↔ 다크(흰색) 자동 적응
- `Color(nsColor: .windowBackgroundColor)` — 시스템 배경 추적
- `.ultraThinMaterial` — 플로팅 사이드바 반투명 배경 (AppKit `backgroundColor = .clear` + `isOpaque = false` 전제)

### 모서리 규칙

- **`.continuousRadius(N)`** View extension 사용 (`.clipShape(RoundedRectangle(cornerRadius: N, style: .continuous))`)
- deprecated `.cornerRadius()` 사용 금지

### 애니메이션 토큰

- `.dgFast` (0.15s) — 호버, 마이크로 인터랙션
- `.dgStandard` (0.25s) — 일반 전환
- `.dgSlow` (0.35s) — 모달, 토스트, 확장

### 공유 컴포넌트 (`SharedComponents.swift`)

| 컴포넌트 | 용도 |
|----------|------|
| `SheetNavHeader` | 모든 시트 상단 네비게이션 헤더 (취소/제목/액션) |
| `CardContainer` | 방 채팅 내 카드 래퍼 (accentColor + opacity 파라미터) |
| `AttachmentThumbnail` | 48x48 이미지 썸네일 + 삭제 버튼 |
| `SendButton` | 전송 버튼 (canSend/isLoading 상태) |
| `sectionLabel()` | 섹션 라벨 (caption, secondary) |
| `SettingsRow` | 라벨 + 컨텐츠 설정 행 |

---

## 확장 포인트

1. **새 프로바이더 추가**: `AIProvider` 프로토콜 구현 + `ProviderType` enum 케이스 추가 + `ProviderManager.createProvider()` 분기 추가
2. **스트리밍 응답**: `sendMessage()`를 `AsyncSequence` 반환으로 변경하면 토큰 단위 출력 가능
3. **마스터 프롬프트 커스터마이징**: EditAgentSheet에서 마스터 페르소나 수정 시 위임 전략도 변경됨
4. **에이전트 간 직접 통신**: 현재는 마스터를 통해서만 위임. `invite_agent` 도구로 방 내 에이전트 초대 가능
5. **새 도구 추가**: `ToolRegistry`에 `AgentTool` 추가 + `ToolExecutor.executeSingleTool()`에 case 추가
6. **MCP (Model Context Protocol)**: 현재 내장 도구 방식. 외부 MCP 서버 연동으로 확장 가능
7. **web_search 도구 구현**: 현재 placeholder. 실제 검색 API 연동 필요

---

## 파일별 코드량 (참고)

| 파일 | 줄수 | 역할 |
|------|------|------|
| FloatingSidebarView.swift | ~970 | 사이드바 + 슬래시 커맨드 + 이미지 첨부 + UtilityWindowManager |
| ChatViewModel.swift | ~890 | 핵심 오케스트레이션 + 이미지 첨부 지원 |
| RoomChatView.swift | ~460 | 방별 채팅 인터페이스 + 이미지 첨부 |
| ToolExecutor.swift | ~400 | 도구 호출 루프 + smartSend 2종 + web_fetch + invite_agent/list_agents |
| EditAgentSheet.swift | ~240 | 에이전트 편집 |
| AppDelegate.swift | ~320 | 윈도우/패널 관리 |
| ToolFormatConverter.swift | ~290 | 프로바이더별 도구/이미지 형식 변환 |
| AgentTool.swift | ~230 | 도구 시스템 타입 (ToolRegistry 11종 도구) |
| ChatView.swift | ~200 | 채팅 UI + 메시지 버블 (이미지 썸네일) |
| Agent.swift | ~160 | 에이전트 모델 (isMaster, 이미지, 전체 도구) |
| AddAgentSheet.swift | ~154 | 에이전트 등록 |
| AgentStore.swift | ~140 | 에이전트 상태 관리 + 마스터 생명주기 |
| ChatContentView.swift | ~130 | 공유 채팅 UI 컴포넌트 |
| ClaudeCodeProvider.swift | ~123 | CLI 실행 |
| ImageAttachment.swift | ~120 | 이미지 첨부 모델 (디스크 저장, MIME 판별) |
| ProviderConfig.swift | ~110 | 설정 모델 (Keychain 연동) |
| ChatWindowView.swift | ~110 | 독립 채팅 윈도우 |
| ProviderManager.swift | ~107 | 프로바이더 관리 |
| DependencyChecker.swift | ~100 | 의존성 체크 (온보딩) |
| AIProvider.swift | ~80 | 프로바이더 프로토콜 + Tool Use 확장 |
| AgentAvatarView.swift | ~72 | 아바타 컴포넌트 (2종 아이콘) |
| SuggestionCard.swift | ~72 | 제안 카드 |
| ChatMessage.swift | ~58 | 메시지 모델 (이미지 첨부 포함) |
| OpenAIProvider.swift | ~140 | OpenAI API + Tool Use + Vision |
| GoogleProvider.swift | ~130 | Gemini API + Tool Use + Vision |
| AnthropicProvider.swift | ~130 | Anthropic API + Tool Use + Vision |
| AddProviderSheet.swift | ~169 | 프로바이더 설정 |
| ProcessRunner.swift | ~40 | 테스트 가능 프로세스 실행기 (DI seam) |
| KeychainHelper.swift | ~40 | Keychain 헬퍼 |
| DOUGLASApp.swift | ~29 | 앱 진입점 |
| ToolExecutionContext.swift | ~16 | 도구 실행 컨텍스트 (Sendable) |

---

## 테스트

### 개요

- **프레임워크**: Swift Testing (`@Test`, `#expect`)
- **테스트 수**: 789개 (28 파일 + 3 헬퍼/모킹)
- **명령어**: `swift test`
- **커버리지**: 87% (테스트 가능 코드 기준, Views/App 제외)
- **모킹**: MockAIProvider, MockURLProtocol, ProcessRunner.handler, 격리 UserDefaults

### 테스트 구조

```
Tests/
├── Models/
│   ├── AgentTests.swift              # 22 tests — 초기화, 팩토리, Codable, 레거시 디코딩, imageData I/O, resolvedToolIDs (항상 전체 도구)
│   ├── AgentRoleTemplateTests.swift  # 19 tests — 템플릿 초기화, 레지스트리, resolvedPersona, Codable
│   ├── AgentToolTests.swift          # 32 tests — AgentTool/ToolCall/ToolResult Codable, ToolRegistry (11종 도구), ConversationMessage, Jira 도구
│   ├── ArtifactParserTests.swift     # 15 tests — 산출물 추출, 다중 산출물, 타입별 파싱, 블록 제거
│   ├── ChatMessageTests.swift        # 12 tests — 모든 MessageType, Codable 라운드트립, 이미지 첨부 호환
│   ├── ClaudeCodeInstallerTests.swift # 32 tests — detect/install (ProcessRunner mock), 경로 탐색, 상태 전이
│   ├── DependencyCheckerTests.swift  # 15 tests — allRequiredFound, checkAll, shellWhichAll (ProcessRunner mock)
│   ├── ImageAttachmentTests.swift    # 25 tests — MIME 판별, save/load 라운드트립, 크기 제한, 파일 확장자, tempFileURL
│   ├── JiraConfigTests.swift         # 28 tests — apiToken Keychain, authHeader, isConfigured, baseURL
│   ├── KeychainHelperTests.swift     # 23 tests — 파일 기반 저장/로드/삭제, 특수 문자, 에러 타입, 암호화 키 관리
│   ├── ProviderConfigTests.swift     # 23 tests — AuthMethod, Keychain 분리, 레거시 호환, isConnected, apiKey 라운드트립
│   ├── ProviderDetectorTests.swift   # 23 tests — DetectedProvider 모델, maskedKey, needsAPIKey, detectAll
│   ├── RoomStepTests.swift          # 16 tests — RoomStep 초기화, Codable (plain String/object/혼합 배열), 역호환, Equatable
│   ├── RoomTests.swift              # 65 tests — 상태 전이 (awaitingApproval 포함), 타이머, 토론 모드, 레거시 디코딩, RoomPlan/WorkLog Codable, QA/승인 필드
│   ├── RoomBriefingTests.swift      # 12 tests — RoomBriefing Codable, asContextString, Room 역호환
│   └── ToolExecutionContextTests.swift # 6 tests — 생성, empty, agentListString
├── ViewModels/
│   ├── AgentStoreTests.swift         # 25 tests — CRUD, 마스터 보호, updateMasterProvider
│   ├── ChatViewModelTests.swift      # 36 tests — 상태 관리, 메시지 격리, 로딩, 히스토리 필터
│   ├── ChatViewModelParsingTests.swift # 18 tests — JSON 추출, parseMasterResponse 전체 액션
│   ├── ChatViewModelIntegrationTests.swift # 26 tests — 위임 재시도, 체이닝, 요약, 알림, 메시지 영속화
│   ├── OnboardingViewModelTests.swift # 37 tests — Claude 셋업, 의존성 체크, 프로바이더 선택, 마스터 우선순위
│   ├── ProviderManagerTests.swift    # 23 tests — 팩토리, configureFromOnboarding, 영속화, connectedConfigs, mock 오버라이드
│   ├── RoomManagerTests.swift        # 54 tests — 방 생명주기, 에이전트 동기화, 워크플로우, 토론 과반, 계획 파싱
│   └── ToolExecutorTests.swift      # 57 tests — smartSend 분기, 도구 루프, 개별 도구 실행, invite_agent/list_agents, web_fetch, Jira 도구
├── Providers/
│   ├── ProviderTests.swift          # 62 tests — HTTP 검증, 인증, 전체 프로바이더 모킹, 이미지 첨부, tool result
│   ├── ToolFormatConverterTests.swift # 21 tests — OpenAI/Anthropic/Google 형식 변환, JSON Schema
│   └── ToolFormatConverterImageTests.swift # 8 tests — 프로바이더별 이미지 블록 변환 검증
├── Helpers/
│   └── TestHelpers.swift            # 팩토리 함수 (makeTestAgent, makeTestDefaults, makeTestRoom 등)
└── Mocks/
    ├── MockAIProvider.swift         # 가짜 프로바이더 (호출 추적 + Tool Use + 순차 응답)
    └── MockURLProtocol.swift        # URLProtocol 서브클래스 (HTTP 모킹)
```

### 테스트 DI 패턴

| 패턴 | 대상 | 방식 |
|------|------|------|
| `ProcessRunner.handler` | Process 실행 (ClaudeCode, DependencyChecker 등) | `nonisolated(unsafe) static var handler` — 테스트에서 클로저 주입 |
| `ProviderManager.testProviderOverrides` | AI 프로바이더 교체 | 인스턴스 딕셔너리 — `provider(named:)` 호출 시 우선 반환 |
| `ToolExecutor.urlSession` | HTTP 요청 (web_fetch) | `nonisolated(unsafe) static var urlSession` — MockURLProtocol 세션 주입 |
| `MockURLProtocol` | URLSession HTTP 응답 | `requestHandler` 클로저로 응답 제어 |

### 커버리지 요약

| 계층 | 테스트 수 | 주요 커버리지 |
|------|----------|-------------|
| Models | 397 | Agent, AgentRoleTemplate, AgentTool, ArtifactParser, ChatMessage, ClaudeCodeInstaller, DependencyChecker, DiscussionArtifact, ImageAttachment, JiraConfig, KeychainHelper, ProviderConfig, ProviderDetector, Room, RoomBriefing, RoomStep, ToolExecutionContext, BuildResult (QA 포함) |
| ViewModels | 302 | ChatViewModel (통합+파싱+상태), AgentStore, ProviderManager, RoomManager, OnboardingViewModel, ToolExecutor (Jira 도구 포함), BuildLoopRunner (QA 포함) |
| Providers | 91 | OpenAI, Anthropic, Google, Ollama, LM Studio, Custom, ClaudeCode, ToolFormatConverter (도구 + 이미지) |
| **합계** | **789** | 테스트 가능 코드 87% 라인 커버리지 (View/App 레이어는 UI 특성상 제외) |
