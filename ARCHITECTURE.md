# DOUGLAS - 코드 분석 문서

## 개요

DOUGLAS는 **macOS 네이티브 AI 에이전트 관리 데스크톱 앱**이다.
화면 오른쪽 끝에 떠 있는 플로팅 사이드바에서 여러 AI 에이전트를 관리하고, 마스터 에이전트(PM/오케스트레이터)가 사용자 요청으로 방을 즉시 생성하여 요구사항 분석 → 전문가 초대 → 토론 → 실행까지 자동으로 진행한다.

**핵심 UX 컨셉 — "사장님 모드"**: 사용자는 에이전트를 직접 골라서 시키지 않는다.
사이드바에 타이핑하면 마스터(PM)가 즉시 방을 만들고, 요구사항을 확인한 뒤 적합한 전문가를 소환하여 작업을 진행한다.
사장님이 "야 이거 해" 하면 비서실장(마스터)이 방을 만들고 팀을 꾸려서 처리하는 구조.

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
│   │   └── UtilityWindowManager.swift # 유틸리티 윈도우 관리
│   ├── Models/
│   │   ├── Agent.swift              # 에이전트 모델 (이름, 페르소나, 이미지, isMaster, workingRules, referenceProjectPaths)
│   │   ├── AgentManifest.swift     # 에이전트 매니페스트 (.douglas 파일 포맷, Agent↔AgentEntry 변환)
│   │   ├── WorkingRules.swift       # 작업 규칙 (WorkingRulesSource — 인라인+파일 동시 지원)
│   │   ├── AgentTool.swift          # 도구 시스템 (AgentTool, ToolCall, ToolResult, ToolRegistry, ConversationMessage)
│   │   ├── ArtifactParser.swift     # 토론 산출물 파서 (artifact 블록 추출/제거)
│   │   ├── ChatMessage.swift        # 메시지 모델 (MessageType 포함: toolActivity, buildStatus, qaStatus, approvalRequest 등, FileAttachment 첨부)
│   │   ├── DiscussionArtifact.swift # 토론 산출물 모델 (ArtifactType, 버전 관리)
│   │   ├── FileAttachment.swift     # 파일 첨부 모델 (이미지+문서, 디스크 저장, base64 로드, MIME 판별)
│   │   ├── BuildResult.swift         # 빌드 결과 모델 + BuildLoopStatus + QAResult + QALoopStatus
│   │   ├── FileWriteTracker.swift   # 병렬 실행 파일 쓰기 충돌 감지 (actor)
│   │   ├── ToolExecutionContext.swift # 도구 실행 컨텍스트 (방/에이전트/프로젝트 정보 스냅샷, askUser, currentPhase)
│   │   ├── WorkflowIntent.swift    # 워크플로우 의도 (WorkflowPhase, WorkflowIntent 4종, PlanMode)
│   │   ├── IntentClassifier.swift # Intent 분류기 (규칙 기반 + LLM 폴백)
│   │   ├── DecisionLog.swift      # 토론 결정 로그 (DecisionEntry)
│   │   ├── WorkflowAssumption.swift # 가정 선언 (RiskLevel: low/medium/high) + UserAnswer
│   │   ├── ProjectPlaybook.swift   # 프로젝트 플레이북 (브랜치 전략, 테스트 정책, 프리셋 3종)
│   │   ├── IntakeData.swift        # Intake 입력 데이터 (InputSourceType, JiraTicketSummary)
│   │   ├── RoleRequirement.swift   # Assemble 역할 요구사항 (Priority, MatchStatus)
│   │   ├── DependencyChecker.swift  # 의존성 체크 (Node.js, Git, Homebrew)
│   │   ├── JiraConfig.swift          # Jira Cloud 연동 설정 (도메인, 이메일, API 토큰)
│   │   ├── ColorPalette.swift       # 테마 색상 팔레트 (48+ 시맨틱 컬러, panelGradient computed property)
│   │   ├── ThemePresets.swift       # 테마 프리셋 (ThemeID 5종: cozyGame/pastel/dark/warmCozy/custom)
│   │   ├── ProviderConfig.swift     # 프로바이더 설정 (AuthMethod, ProviderType, isConnected)
│   │   ├── ProviderDetector.swift   # 시스템 AI 프로바이더 자동 감지
│   │   ├── ClaudeCodeInstaller.swift # Claude Code CLI 설치/검증 유틸리티
│   │   ├── PluginTemplate.swift     # 플러그인 빌더 모델 (PluginActionType, HandlerConfig, ScriptGenerator, PluginSlug)
│   │   ├── ProcessRunner.swift      # 테스트 가능한 프로세스 실행기 (DI seam)
│   │   ├── Room.swift               # 프로젝트 방 모델 (상태 전이, 타이머, 토론 모드, RoomBriefing, RoomStep 승인 게이트)
│   │   └── KeychainHelper.swift     # 파일 기반 API 키 저장 (Keychain 레거시 마이그레이션)
│   ├── ViewModels/
│   │   ├── AgentStore.swift         # 에이전트 CRUD, 마스터 생명주기
│   │   ├── AgentPorter.swift        # 에이전트 매니페스트 Export/Import (NSSavePanel/NSOpenPanel)
│   │   ├── ChatViewModel.swift      # 메시지 전송, 마스터 오케스트레이션
│   │   ├── OnboardingViewModel.swift # 첫 실행 온보딩 (의존성 체크 + Claude 설정 + 프로바이더 선택)
│   │   ├── ProviderManager.swift    # 프로바이더 설정 관리
│   │   ├── BuildLoopRunner.swift     # 빌드/테스트 실행 + 수정 프롬프트 생성 엔진
│   │   ├── RoomManager.swift        # 프로젝트 방 생명주기, 6단계 워크플로우, 승인/입력 게이트
│   │   ├── AgentMatcher.swift       # 시스템 주도 에이전트 매칭 (templateID → persona 키워드 → unmatched)
│   │   ├── ThemeManager.swift       # 테마 관리 (기본값: .cozyGame, UserDefaults 저장, 커스텀 팔레트)
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
│   ├── Plugins/
│   │   ├── Core/
│   │   │   ├── DougPlugin.swift        # 플러그인 프로토콜 + 이벤트 타입 (PluginEvent, PluginConfigField)
│   │   │   ├── PluginContext.swift      # 플러그인용 시스템 파사드 (Room/Agent 안전 API)
│   │   │   ├── PluginManager.swift     # 플러그인 라이프사이클 관리 (@MainActor ObservableObject)
│   │   │   └── PluginConfiguration.swift # 플러그인 설정 저장 (UserDefaults + KeychainHelper)
│   │   └── Slack/
│   │       ├── SlackPlugin.swift        # Slack 연동 플러그인 (DougPlugin 구현체)
│   │       ├── SlackSocketConnection.swift # Slack Socket Mode WebSocket 연결
│   │       ├── SlackMessageParser.swift   # Slack 메시지 ↔ 일반 텍스트 변환
│   │       └── SlackChannelRoomMapper.swift # Slack 채널 ↔ Room 양방향 매핑
│   └── Views/
│       ├── FloatingSidebarView.swift # 팀 로스터 + 마스터 채팅 사이드바 UI
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
│       ├── AgentAvatarView.swift    # 둥근 사각 아바타 (마스터/서브 아이콘 분기, 그라데이션 폴백)
│       ├── DesignTokens.swift       # 디자인 시스템 (색상, 타이포, 간격, 모서리, 애니메이션, 윈도우 크기, CozyGame 토큰)
│       ├── CozyGameComponents.swift # 코지 게임 UI 컴포넌트 (CozyButtonStyle, CozyPanelModifier, CozyProgressBar 등)
│       ├── ThemeEnvironment.swift   # 테마 환경 (ThemedView, colorPalette EnvironmentKey, .fontDesign(.rounded) 전역 적용)
│       ├── ThemeSettingsView.swift  # 테마 설정 뷰 (테마 카드 프리뷰, 커스텀 색상 선택)
│       ├── SettingsTabView.swift   # 통합 설정 윈도우 (API 설정 / 테마 / 플러그인 탭)
│       ├── SharedComponents.swift   # 공유 UI 컴포넌트 (SheetNavHeader, CardContainer, SendButton 등)
│       ├── ProgressActivityBubble.swift # 확장형 진행 버블 (활동 로그 인라인 표시)
│       ├── TypingIndicator.swift    # 타이핑 인디케이터 (점 바운스 애니메이션, 경과 시간 표시)
│       ├── ToastView.swift          # 임시 알림 오버레이
│       ├── PluginBuilderSheet.swift # 노코드 플러그인 빌더 (폼 → 스크립트 자동 생성)
│       └── PluginSettingsView.swift # 플러그인 관리 UI (활성화 토글, 설정 에디터, 빌더 연결)
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
4개의 핵심 객체를 생성/관리: `agentStore`, `providerManager`, `chatVM`, `roomManager`

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

### 2. AgentStore (`ViewModels/AgentStore.swift`)

에이전트 목록의 CRUD와 상태 관리를 담당한다.

- 앱 시작 시 마스터 에이전트 자동 생성 보장
- 모든 에이전트 상태를 `.idle`로 초기화 (이전 세션 잔여 상태 제거)
- 마스터 에이전트는 삭제 불가
- 기존 워즈니악 에이전트 자동 마이그레이션 제거
- `minimizedAgentIDs`: 도크에 최소화된 채팅 창 추적
- `subAgents`: 마스터를 제외한 일반 에이전트 필터

**masterSystemPrompt()**: 마스터 에이전트의 PM/오케스트레이터 역할 프롬프트
- 요구사항 분석, 전문가 식별, 팀 구성, 토론 조율
- 직접 작업 수행 금지 원칙
- 정보 부족 시 사용자에게 질문하라는 핵심 원칙

### 3. ChatViewModel (`ViewModels/ChatViewModel.swift`)

사용자 메시지의 진입점. 마스터와 서브 에이전트의 메시지 처리를 분기한다.

**마스터 메시지 처리** (`handleMasterMessage`):
- LLM 호출 없이 즉시 방 생성 → 마스터가 방의 첫 에이전트로 참여
- Jira URL 사전 조회 (`enrichTaskWithJira`)
- RoomManager를 통해 워크플로우 자동 시작

**서브 에이전트 메시지 처리** (`handleAgentMessage`):
- 프로바이더 API를 통한 직접 대화 (`ToolExecutor.smartSend`)
- 도구 호출 지원 (도구 활동 실시간 표시)

**이미지 첨부 지원**:
- `sendMessage(attachments:)`: 이미지 첨부 메시지 전송
- `buildConversationHistory()`: 이미지 포함 `[ConversationMessage]` 빌드
- 이미지가 있으면 `smartSend(conversationMessages:)` 오버로드 사용

**메시지 영속화**:
- `~/Library/Application Support/DOUGLAS/chats/` 디렉토리에 에이전트별 JSON 저장
- `saveMessages()` / `loadMessages()`로 앱 재시작 시 복원
- `pruneOrphanedChats()`: 존재하지 않는 에이전트의 채팅 기록 자동 정리

**데이터 정리 정책** (AppDelegate 시작 시 실행):
- 에이전트 삭제 시: 아바타 이미지 + 채팅 기록 + 첨부 파일 일괄 삭제 (`onAgentRemoved` 콜백)
- 완료된 방 프루닝: 최근 30개만 유지, 초과분은 첨부 파일과 함께 삭제 (`pruneCompletedRooms`)
- 고아 파일 정리: 디코드 실패 JSON, 미참조 첨부 이미지 자동 삭제 (`cleanupOrphanedData`)

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
- **스트리밍**: `supportsStreaming`, `sendMessageStreaming(onChunk:)` — SSE 기반 실시간 텍스트 전송. `SSEParser.consume(bytes:extractChunk:onChunk:)` 공용 유틸리티. Anthropic/OpenAI/Google 3개 프로바이더 지원, ClaudeCode는 폴백.

### 속도 최적화

- **SSE 스트리밍** (`sendMessageStreaming`): 전체 응답 경로(즉답/소로분석/토론/복명복창/1:1채팅)에서 placeholder 메시지 생성 → 청크마다 `updateMessageContent`로 실시간 업데이트. `ToolExecutor.smartSend`에 `onStreamChunk` 콜백 추가로 도구 미사용 경로에서 자동 스트리밍.
- **도구 병렬 실행** (`ToolExecutor.executeToolCallsInParallel`): 모델이 반환한 다중 도구 호출을 `withTaskGroup`으로 동시 실행. 인덱스 기준 정렬 후 순서 보장.
- **모델 티어링**: `ProviderType.defaultLightModelName` (OpenAI→gpt-4o-mini, Google→gemini-2.0-flash, Anthropic→claude-haiku-4-5). `ProviderManager.lightModelName(for:)` 헬퍼. 적용 대상: IntentClassifier, routeQuickAnswer, executeAssemblePhase, generateBriefing.
- **발산 라운드 병렬화**: `.diverge` 라운드에서 `generateDiscussionResponse` + `withTaskGroup`으로 에이전트 동시 실행. 수렴/합의는 순차 유지.

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

### AgentManifest (`Models/AgentManifest.swift`)

에이전트를 플랫폼 무관한 JSON `.douglas` 파일로 내보내기/가져오기하는 이식 포맷.

```swift
struct AgentManifest: Codable {
    let formatVersion: Int       // 1부터 시작
    let exportedAt: Date         // ISO8601
    let exportedFrom: String     // "DOUGLAS"
    let agents: [AgentEntry]     // 에이전트 목록
}
struct AgentEntry: Codable {
    let name, persona, providerType, preferredModel: String
    let isMaster: Bool
    let workingRules: String?    // resolve()된 인라인 텍스트
    let avatarBase64: String?    // PNG base64
}
```

- **Export**: `Agent → AgentEntry` 변환 (workingRules 해석, 이미지 base64 인코딩)
- **Import**: `AgentEntry → Agent` 변환 (새 UUID 발급, 마스터 skip, 이름 중복 해결)
- **AgentPorter** (`ViewModels/AgentPorter.swift`): NSSavePanel/NSOpenPanel을 통한 파일 UI

### ChatMessage (`Models/ChatMessage.swift`)

```swift
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole        // user / assistant / system
    let content: String
    let agentName: String?       // 응답한 에이전트 이름
    let timestamp: Date
    var messageType: MessageType // text / delegation / summary / chainProgress / suggestion / error / discussionRound / toolActivity
    let attachments: [FileAttachment]?   // 파일 첨부 (이미지+문서, Vision/Document API용)
    let activityGroupID: UUID?   // 부모 .progress 메시지 ID (활동 그룹핑)
}
```

- `init(from decoder:)`: messageType, attachments, activityGroupID가 없는 기존 데이터와 역호환 (`.text` 기본값, `nil`)
- MessageType에 따라 채팅 버블의 색상, 아이콘, 테두리가 달라짐
- `attachments`: 파일 첨부 시 메시지 버블에 이미지 썸네일 또는 문서 아이콘 표시
- `activityGroupID`: `.toolActivity` 메시지가 부모 `.progress` 메시지에 소속됨을 표시. 메인 채팅에서는 숨기고, progress 버블 확장 시 인라인 표시

### FileAttachment (`Models/FileAttachment.swift`)

```swift
struct FileAttachment: Codable, Identifiable {
    let id: UUID
    let filename: String            // UUID.ext (디스크 저장용)
    let originalFilename: String?   // 원래 파일 이름 (표시용)
    let mimeType: String            // "image/jpeg", "application/pdf", "text/plain" 등
    let fileSizeBytes: Int
}
```

- 지원 파일: 이미지(JPEG/PNG/GIF/WebP) + 문서(PDF/TXT/CSV/JSON/MD/XML/YAML/HTML/CSS) + 코드(JS/TS/Swift/Python/Shell)
- 디스크 저장: `~/Library/Application Support/DOUGLAS/attachments/{filename}`
- `save(data:mimeType:originalFilename:)`: 데이터를 디스크에 저장하고 메타데이터 반환
- `loadBase64()` / `loadData()` / `loadTextContent()`: API 호출 시점에 디스크에서 로드
- `delete()`: 디스크 파일 삭제
- `mimeType(for:)`: 매직바이트로 판별 (이미지+PDF), `mimeType(forExtension:)`: 확장자로 판별 (텍스트/코드)
- `detectMimeType(for:data:)`: 매직바이트 우선 → 확장자 fallback 통합 판별
- `isImage`, `displayName`, `fileIcon`: UI 렌더링 헬퍼
- 크기 제한: 파일당 최대 20MB
- `FileAttachmentError`: `.fileTooLarge`, `.unsupportedFormat`
- `typealias ImageAttachment = FileAttachment` (하위 호환)

### WorkingRulesSource (`Models/WorkingRules.swift`) — struct

```swift
struct WorkingRulesSource: Codable, Equatable {
    var inlineText: String     // 직접 입력한 텍스트 규칙
    var filePaths: [String]    // 파일 경로 참조 (여러 건, 예: .cursorrules)

    func resolve() -> String   // 인라인 + 파일 내용 합산 반환
    var displaySummary: String // UI 요약
    var isEmpty: Bool
}
```

- 에이전트 생성 시 **필수 입력** (마스터 제외)
- **인라인 텍스트 + 파일 참조 동시 사용 가능** (양분 아님, 합산)
- persona = 역할 정체성, workingRules = 구체적 작업 지시사항으로 분리
- `Agent.resolvedSystemPrompt`: persona + rules를 결합한 최종 시스템 프롬프트
- 파일은 실행 시점에 읽어 항상 최신 규칙 반영
- 레거시 enum 포맷(`inline(String)`, `filePath(String)`) 자동 마이그레이션

### DiscussionArtifact (`Models/DiscussionArtifact.swift`)

```swift
struct DiscussionArtifact: Identifiable, Codable {
    let id: UUID
    let type: ArtifactType      // api_spec, test_plan, task_breakdown, architecture_decision, assumptions, role_requirements, generic
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
    let suggestAgentCreation: @Sendable (RoomAgentSuggestion) async -> Bool
    let projectPaths: [String]
    let currentAgentID: UUID?
    let currentAgentName: String?
    let fileWriteTracker: FileWriteTracker?
    let askUser: @Sendable (String, String?, [String]?) async -> String
    let currentPhase: WorkflowPhase?
}
```

- 도구 실행 시 필요한 방/에이전트 컨텍스트의 **스냅샷**
- `Sendable`로 `@MainActor` 경계를 안전하게 통과
- `inviteAgent` / `suggestAgentCreation` / `askUser`: `@Sendable` 클로저, MainActor에서 실행
- `askUser`: CheckedContinuation 기반 블로킹 — 사용자 답변까지 대기
- `currentPhase`: ask_user 도구의 Clarify 단계 제한에 사용
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
  - 키 파일 쓰기 실패 시 `throws` 전파 (사일런트 키 손실 방지)
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

| 상태 | 색상 | 설명 |
|------|------|------|
| `planning` | 보라 | 실행 전 모든 준비 단계 (intake~plan). UI 라벨은 `currentPhase` 기반 동적 표시 |
| `inProgress` | 주황 | 계획에 따라 작업 실행 중 |
| `awaitingApproval` | 노랑 | Human-in-the-loop 승인 게이트 |
| `awaitingUserInput` | 시안 | ask_user 도구로 사용자 질문 대기 |
| `completed` | 초록 | 모든 단계 완료 |
| `failed` | 빨강 | 오류 또는 승인 거부로 중단 |

`planning` 상태의 동적 라벨 (`Room.phaseLabel`, `currentPhase` 기반):
| currentPhase | 라벨 |
|---|---|
| intake/intent/assemble | 준비 중 |
| clarify | 요건 확인 |
| plan (토론 라운드 > 0) | 토론 중 (NR) |
| plan (계획 수립) | 계획 중 |
| execute | 실행 중 |

상태 전이:
```
planning → awaitingApproval (토론 후 사용자 승인)
    │              │
    │              ├→ planning (승인 → 계획 수립)
    │              └→ failed (거부)
    │
    ├→ awaitingUserInput (ask_user 질문)
    │              │
    │              ├→ planning (답변 수신)
    │              └→ failed
    │
    ├→ inProgress → completed
    │      │
    │      ├→ awaitingApproval → inProgress (단계 승인)
    │      │                   → failed (거부)
    │      ├→ awaitingUserInput → inProgress (답변 수신)
    │      └→ failed
    ├→ completed
    └→ failed
```

`isActive` = `planning` | `inProgress` | `awaitingApproval` | `awaitingUserInput` (에이전트 상태 계산에 사용)

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
- **바쁨 표시 강화**: 빨간 그림자 + 굵은 테두리(2.5pt) + 이름 아래 "바쁨 N건" 캡슐 뱃지 + 방 수 뱃지 빨간색
- 에이전트 클릭 → 별도 채팅 윈도우 열기 (직접 대화)
- 우클릭 컨텍스트 메뉴: 편집/정보/삭제
- 20개 이상 에이전트도 가로 스크롤로 수용

**마스터 채팅 영역**:
- `ScrollViewReader` + `LazyVStack` + `MessageBubble`로 메시지 표시
- 웰컴 메시지: "무엇을 시킬까요?"
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

**마크다운 렌더링**: 에이전트 응답은 `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)`로 렌더링. `normalizeMarkdown()` 후처리: 헤더(`###`)→볼드(`**`), 구분선(`---`/`===`) 제거, `**[이름]**` 단독줄 제거, 연속 빈 줄 축소. 사용자 메시지는 plain text 유지.

이미지 첨부가 있는 메시지: 텍스트 위에 이미지 썸네일 그리드 표시 (최대 180x120pt)

### ProgressActivityBubble (`Views/ProgressActivityBubble.swift`)

`.progress` 메시지를 확장형 버블로 렌더링:
- **접힌 상태**: 기존 캡슐 스타일 + 활동 개수 뱃지 + 화살표 (클릭으로 토글)
- **펼친 상태**: 소속된 `.toolActivity` 메시지들을 시간순으로 인라인 표시 (도구 호출/결과, 아이콘 구분, 타임스탬프)
- `activityGroupID`로 부모-자식 관계 연결: `.toolActivity` 메시지의 `activityGroupID`가 `.progress` 메시지의 `id`와 일치
- 메인 채팅에서는 `activityGroupID != nil`인 메시지를 필터링하여 숨김

### AgentAvatarView (`Views/AgentAvatarView.swift`)

재사용 가능한 원형 아바타 컴포넌트:
- hasImage 있으면 → 파일시스템에서 이미지 로드 → 원형 클립
- 마스터 에이전트 (imageData 없음) → 번들 `douglas_profile.png` 사용 → 뇌 아이콘은 최종 fallback
- 일반 에이전트 → `person.crop.circle` (파란색)

`pickAgentImage()` 유틸: NSOpenPanel → PNG/JPEG 선택 → 128x128 리사이즈 → 파일시스템 저장

### EditAgentSheet (`Views/EditAgentSheet.swift`)

에이전트 편집 시트:
- 아바타: 이미지 선택/제거
- 이름: 마스터는 수정 불가 (LabeledContent)
- 페르소나: TextEditor
- 프로바이더/모델: Picker (동적 모델 목록 로딩)

### 통합 설정 윈도우 (`Views/SettingsTabView.swift`)

기존 분산된 설정 (API 설정 윈도우, 테마 팝오버, 플러그인 팝오버)을 **3탭 통합 윈도우**로 병합:
- **API 설정** 탭: AddProviderSheet(isEmbedded: true) — Claude Code, OpenAI, Google, Jira Cloud
- **테마** 탭: ThemeSettingsView(isEmbedded: true) — 프리셋 3종 + 커스텀 색상
- **플러그인** 탭: PluginSettingsView(isEmbedded: true) — 빌트인/외부 플러그인 관리

헤더의 "설정" 버튼 하나로 진입. `UtilityWindowManager`에 `pluginManager` 환경 주입 추가.

### 헤더 버튼 디자인 (`CuteHeaderButtonStyle`)

사이드바 헤더 버튼을 코지 게임 톤에 맞는 파스텔 컬러 귀여운 스타일로 교체:
- 3개 버튼: 추가(민트), 일지(앰버), 설정(라벤더)
- 각 버튼: 아이콘 + 라벨, 파스텔 배경, 호버 글로우, 스프링 눌림 효과

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

## 빠른 접근 방법 요약

| 방법 | 단축키/동작 | 대상 | 용도 |
|------|------------|------|------|
| **사이드바** | 마우스 오른쪽 끝 8px | 마스터 | 기본 채팅 인터페이스 |
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

모든 에이전트는 전체 12종 도구에 접근 가능 (프리셋 제한 없음).

| ID | 이름 | 설명 |
|----|------|------|
| `file_read` | 파일 읽기 | 지정 경로 파일 내용 읽기 (50K자 제한) |
| `file_write` | 파일 쓰기 | 지정 경로에 파일 작성 |
| `shell_exec` | 셸 실행 | zsh 명령어 실행 (30K자 출력 제한) |
| `web_search` | 웹 검색 | 웹 검색 (미구현 placeholder) |
| `web_fetch` | 웹 페이지 가져오기 | URL → HTML 가져오기 + Jira REST API 티켓 조회 (JiraConfig 연동) |
| `invite_agent` | 에이전트 초대 | 방에 다른 에이전트를 런타임 초대 (params: agent_name, reason) |
| `list_agents` | 에이전트 목록 | 등록된 서브 에이전트 목록 조회 (params: 없음) |
| `ask_user` | 사용자 질문 | Clarify 단계에서만 사용 가능. 사용자에게 질문 (params: question, context?, options?) |
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
- **경로 검증**: `isPathAllowed()` — `$HOME`, `/tmp`, 시스템 임시 디렉토리만 허용. `.ssh`, `.gnupg`, `Library/Keychains` 차단. 심링크 해석(`resolvingSymlinksInPath`)으로 우회 방지. 디렉토리 단위 프리픽스 매칭(`/` 슬래시 구분).
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
| `ChatViewModel.swift` | `handleAgentMessage` → `ToolExecutor.smartSend()` (이미지 포함 시 conversationMessages 오버로드) |
| `RoomManager.swift` | `sendUserMessage`, `executeStep` → `ToolExecutor.smartSend()` + `ToolExecutionContext` 전달 (invite_agent/list_agents 지원) |

**방 워크플로우** (`startRoomWorkflow`): 항상 Intent 기반 `executePhaseWorkflow` 실행. `room.intent == nil`이면 `.implementation`을 phase 계산 기본값으로 사용하되, `executeIntentPhase`에서 사용자 선택으로 교체됨.

**범용 워크플로우 (Intent 기반 적응형)**:
```
사용자 입력 → Intent 분류 (규칙 + LLM) → 방 생성
  → ① Intake: 입력 파싱 (Jira fetch, URL 감지)
  → ② Intent: 작업 유형 표시
  → ③ Clarify: 복명복창 (DOUGLAS가 이해한 내용 요약 → 사용자 컨펌까지 무한 루프)
  → ④ Assemble: 전문가 초대 (역할 매칭 + 생성 제안)
  → ⑤~⑦: Intent별 분기 (PlanMode에 따라)
```

- **Intent 분류** (`IntentClassifier`): 규칙 기반 즉시 분류 (`quickClassify`) → 실패 시 LLM 분류 (`classifyWithLLM`). `quickClassify`가 nil(판단 불가)이면 `executeIntentPhase`에서 LLM 추천 intent와 함께 **IntentSelectionCard** UI를 표시하여 사용자가 4종 intent 중 선택. `pendingIntentSelection` + `intentContinuations`으로 비동기 게이트 구현. 분류 실패 시 `.quickAnswer` 폴백 (가장 가벼운 워크플로우).
- **복명복창 Clarify** (`executeClarifyPhase`): DOUGLAS가 요청을 요약 → 사용자 승인/거부 → 거부 시 피드백 반영 재요약 → 승인까지 무한 반복. 승인 시 `room.clarifySummary`에 저장 → 이후 토론/브리핑/계획 프롬프트에서 의도 앵커링용으로 참조.
- **PlanMode 분기** (`executePlanPhase`):
  - `.skip`: Plan 단계 건너뜀 (quickAnswer)
  - `.lite`: 토론(필요 시) + 산출물 정리만 (research)
  - `.exec`: 토론(필요 시) + 계획 수립 + 승인(implementation만) (documentation, implementation)
- **토론 알고리즘** (`executeDiscussion`): 발산→수렴→합의 = 1사이클. 매 사이클 후 사용자 체크포인트 (DiscussionCheckpointCard). 사용자 피드백 시 새 사이클, "진행"(빈 입력) 시 브리핑으로. 사이클 무제한 (사용자 주도 종료). `DiscussionRoundType`: `.diverge`(발산) / `.converge`(수렴) / `.conclude`(합의) — 각 라운드마다 목적별 프롬프트 지시. 모든 에이전트 프롬프트에 `clarifySummary` 앵커링 포함. **발산 라운드 병렬화**: `.diverge` 라운드에서 모든 에이전트가 동일 히스토리 스냅샷 기준으로 동시 실행 (`generateDiscussionResponse` + `withTaskGroup`). 수렴/합의는 순차 유지.
- **quickAnswer** (`executeQuickAnswer`): 전문가 1명이 도구 포함 즉답
- **실행 시 마스터 제외** (`executingAgentIDs`): `agent.isMaster`이면 실행 대상에서 제외
- **계획 수립**: 전문가가 생성 (마스터 제외). 계획 JSON은 사용자에게 숨김.
- **DecisionLog**: 토론 중 `[합의: 내용]` 태그 파싱 → `Room.decisionLog`에 기록
- **에이전트 참조 프로젝트** (`Agent.referenceProjectPaths`): 에이전트별로 참조 프로젝트 디렉토리를 여러 건 등록. 방에 초대 시 `addAgent(_:to:silent:)`에서 방의 `projectPaths`에 자동 병합. `silent: true` 시 참여 시스템 메시지 생략 (호출부에서 커스텀 메시지 표시 시 중복 방지).
- **방 shortID** (`Room.shortID`): UUID 앞 6자 소문자. 방 헤더(`RoomChatView`)와 방 목록(`RoomListView`)에 표시.
- **CLI WebFetch 차단**: `ClaudeCodeProvider.sendMessage()`에서 `--disallowed-tools WebFetch` 적용

**승인 게이트** (`executeRoomWork`): `step.requiresApproval == true`이면 `.awaitingApproval` 상태 전환 + `CheckedContinuation`으로 비동기 일시 정지. `approveStep(roomID:)` / `rejectStep(roomID:)` 호출 시 continuation resume.

**Plan 승인 루프** (`executePlanExec`): implementation Plan 승인 시 거부 → 피드백 추출 → `requestPlan(previousPlan:feedback:)`로 재계획 → 다시 승인 카드 표시 (무제한). 이전 계획과 사용자 피드백이 재계획 프롬프트에 주입됨.

**승인 카드 UI** (`ApprovalCard`): 분석 결과 확인 + 추가 요구사항 입력 TextEditor + "승인"/"수정 요청" 버튼. 추가 입력이 있으면 "추가 후 승인" 표시. "수정 요청" 클릭 시 피드백이 방 메시지에 기록된 후 `rejectStep()`으로 재계획 트리거.

**전문가 Solo 분석** (`executeSoloAnalysis`): 전문가 1명만 배정된 방에서 토론 대신 혼자 분석하여 결과 공유. `executePlanLite`/`executePlanExec`에서 `specialistCount == 1`일 때 자동 호출.

**후속 사이클** (`launchFollowUpCycle`): 완료/실패 방에서 사용자 후속 질문 시 방 재활성화 → Intent 재분류 → clarify부터 워크플로우 재실행 (복명복창 포함). 규칙 기반 quickAnswer 확정 + 에이전트 변동 없으면 clarify/assemble 스킵 (즉답 빠른 경로). `previousCycleAgentCount`로 에이전트 추가/제거 감지.

**`@` 멘션** (`MentionParser`): 사용자가 `@에이전트이름 메시지` 형태로 에이전트를 직접 초대. `sendUserMessage` 시작 시 파싱 → `addAgent` → 멘션 제거된 순수 텍스트로 워크플로우 진행. 정확 매칭 + 접두어 매칭 지원 (ex: `@번역` → `번역가`). 미매칭 멘션은 원문 유지. RoomChatView에서 `@` 입력 시 에이전트 자동완성 팝오버 표시. **멘션 라우팅 우선권**: 멘션된 에이전트 ID를 `mentionedAgentIDsByRoom`에 저장 → `executeQuickAnswer`/`executeSoloAnalysis`에서 LLM 라우팅보다 우선 사용 (소비 후 삭제).

**quickAnswer 경량 라우팅** (`routeQuickAnswer`): 전문가 2명 이상인 방에서 즉답 시 (멘션 없는 경우), 마스터가 질문에 최적인 전문가 1명을 지명하여 답변. LLM 1회 경량 호출.

**대상 경로 감지**: 코딩 관련 키워드가 포함된 요청에 파일 경로가 없으면 → `.awaitingUserInput`으로 전환 → 사용자에게 대상 파일/경로 질문 → 답변을 분석 결과에 추가.

**실패 자동 감지** (`executeRoomWork`):
- 단계 실행 실패(에러): `executeStep()` 반환값 `false` → 즉시 `.failed` 전환 + 중단.
- 반복 응답 감지: 연속 단계에서 Jaccard 단어 유사도 > 60% → 에이전트가 stuck 상태로 판단 → `.failed` 전환 + 중단. (`wordOverlapSimilarity()`)

**작업일지**: `executeRoomWork()` 완료 시 `generateWorkLog()` → 상태 전환 순서. `completeRoom()` (수동 완료)에서도 작업일지 생성.

**QA 루프** (`runQALoop`): 빌드 루프 성공 후 `testCommand`가 있으면 자동 실행. `BuildLoopRunner.runTests()` → 실패 시 QA 에이전트(이름/페르소나에 "QA" 키워드 포함)에게 수정 프롬프트 → 재테스트 (최대 `maxQARetries`회).

**컨텍스트 압축**: 토론 종료 후 `generateBriefing()`이 전체 히스토리를 JSON 브리핑으로 압축. 브리핑/계획 프롬프트에 `clarifySummary`(원래 사용자 요청) 포함 → 탈선 방지.
- 계획 수립: 브리핑 + 산출물만 전달 (40msg → ~500토큰) + 원래 요청 앵커
- 실행 단계: 브리핑 + 최근 5개 메시지 (`buildRoomHistory(limit: 5)`)
- 브리핑 없으면 기존 히스토리 폴백

**토론 산출물**: `executeDiscussionTurn()`에서 응답 파싱 → `ArtifactParser.extractArtifacts()` → `Room.artifacts` 저장. 같은 type+title이면 버전 증가.

토론 턴 등 텍스트 전용 호출은 `sendMessage()` (tools: []) 유지.

---

## 개발 로드맵

### Phase A — 기반 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| A-1 | ~~Agent Role Template 시스템~~ → Working Rules로 대체 (Phase H) | ✅ |
| A-2 | 토론 산출물 구조화 (artifact 블록 자동 추출, 버전 관리) | ✅ |
| A-3 | 컨텍스트 요약/압축 전달 메커니즘 (RoomBriefing) | ✅ |

### Phase B — 개발 루프 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| B-1 | **프로젝트 디렉토리 연동**: 방 생성 시 `projectPaths` 지정 (복수 디렉토리 지원) → 상대 경로 해석(첫 번째 기준), `isPathAllowed` 전체 경로 허용, `shell_exec` 기본 workDir(첫 번째). `Room.projectPaths: [String]`, `Room.buildCommand` 추가. CreateRoomSheet에 복수 디렉토리 선택 + 빌드 명령 자동 감지 UI. | ✅ |
| B-2 | **빌드→에러→수정 자율 루프**: `BuildLoopRunner.runBuild()` → 실패 시 에이전트에게 수정 프롬프트 → 재빌드 (최대 `maxBuildRetries`회). `BuildResult`, `BuildLoopStatus` 모델. `RoomManager.runBuildLoop()` 통합. BuildStatusCard UI. | ✅ |
| B-3 | **병렬 실행 파일 충돌 감지**: `FileWriteTracker` actor — 에이전트별 파일 쓰기 기록, 동일 파일 다중 에이전트 수정 시 충돌 경고. `ToolExecutionContext`에 `currentAgentID`, `fileWriteTracker` 추가. 단계별 충돌 초기화. | ✅ |

### Phase C — 통합 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| C-1 | **Jira 깊은 연동**: `jira_create_subtask`(서브태스크 생성), `jira_update_status`(상태 전이), `jira_add_comment`(ADF 코멘트) 3개 쓰기 도구 추가. 모든 에이전트에 포함. `makeJiraRequest()` 공통 인증 헬퍼. | ✅ |
| C-2 | **Human-in-the-loop 승인 게이트**: `RoomStep` 구조체 (plain String + object 혼합 Codable). `RoomStatus.awaitingApproval` 추가. `CheckedContinuation`으로 비동기 일시 정지. ApprovalCard UI. | ✅ |
| C-3 | **QA 자동 검증**: `QAResult`/`QALoopStatus` 모델. `BuildLoopRunner.runTests()` + `qaFixPrompt()`. `RoomManager.runQALoop()` — 빌드 성공 후 테스트 자동 실행, 실패 시 QA 에이전트가 수정 루프. 테스트 명령 자동 감지. | ✅ |

### Phase D — 분석가 중심 워크플로우 재구조화 → Phase G에서 대체됨

> Phase D/F는 분석가를 중간 레이어로 사용했으나, Phase G에서 마스터가 직접 PM/오케스트레이터 역할을 수행하도록 대체됨.

### Phase G — 마스터 = PM 오케스트레이터 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| G-1 | **마스터 LLM 라우팅 제거**: `handleMasterMessage()`에서 LLM 호출 없이 즉시 방 생성. `MasterAction`, `parseMasterResponse`, `extractJSON`, `handleDelegation`, `handleChain`, `generateSummary`, `masterFallbackResponse` 등 ~500줄 삭제. | ✅ |
| G-2 | **분석가 자동 생성 제거**: `ensureAnalystExists()`, `createDefaultAnalyst()` 삭제. 마스터가 직접 트리아지 수행. | ✅ |
| G-3 | **RoomManager 마스터 기반**: `isAnalystLed()` → `isMasterLed()`, `executingAgentIDs()` 마스터 제외, 토론에서 마스터 PM 프롬프트 사용. | ✅ |
| G-4 | **SuggestionCard 제거**: 사이드바 에이전트 제안 카드 삭제 (방 내 `AgentSuggestionCard`는 유지). | ✅ |
| G-5 | **masterSystemPrompt 간소화**: PM/오케스트레이터 역할 프롬프트 (JSON 형식 불필요). | ✅ |

### Phase H — 작업 규칙 (Working Rules) ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| H-1 | **WorkingRulesSource 모델**: 인라인 텍스트 + 파일 참조(여러 건) 동시 지원 struct. `resolve()`로 합산 반환. 레거시 enum 자동 마이그레이션. | ✅ |
| H-2 | **Agent.workingRules 필드**: 마스터는 nil, 서브 에이전트는 필수 입력. `resolvedSystemPrompt`로 persona + rules 결합. | ✅ |
| H-3 | **역할 템플릿 제거**: `AgentRoleTemplate`, `AgentRoleTemplateRegistry`, `TemplateCategory` 삭제. AgentAvatarView/AgentMatcher에서 템플릿 참조 제거. | ✅ |
| H-4 | **AddAgentSheet/EditAgentSheet UI**: 인라인 + 파일 참조 동시 표시 (Segmented Picker 제거). 규칙 비어있으면 저장 불가. 에이전트 로스터 드래그 앤 드롭 재정렬. | ✅ |
| H-5 | **시스템 프롬프트 주입 변경**: RoomManager/ChatViewModel 6+ 위치에서 `agent.persona` → `agent.resolvedSystemPrompt`. | ✅ |
| H-6 | **트리아지 자동 생성 → 제안**: 매칭 실패 시 에이전트 자동 생성 대신 `RoomAgentSuggestion` 생성. AgentSuggestionCard 승인 시 AddAgentSheet 열기. | ✅ |

### Phase E — Intent 기반 범용 워크플로우 ✅ 완료 (v2 리팩토링)

| 항목 | 내용 | 상태 |
|------|------|------|
| E-1 | **WorkflowIntent 4종 + PlanMode**: quickAnswer, research, documentation, implementation. `PlanMode` (skip/lite/exec)로 Plan 단계 동작 분기. 레거시 8종(brainstorm 등) → Codable 마이그레이션으로 research 흡수. | ✅ |
| E-2 | **IntentClassifier**: 규칙 기반 키워드 즉시 분류 → LLM 폴백. `ChatViewModel.handleMasterMessage`에서 방 생성 전 호출. | ✅ |
| E-3 | **복명복창 Clarify**: DOUGLAS가 이해한 내용 요약 → 사용자 승인까지 무한 루프. 거부 시 피드백 반영 재요약. | ✅ |
| E-4 | **DecisionLog**: 토론 중 `[합의: 내용]` 파싱 → `DecisionEntry` 기록. `Room.decisionLog` 저장. | ✅ |
| E-5 | **PlanMode 분기**: `.skip`(quickAnswer), `.lite`(research 산출물형), `.exec`(documentation/implementation 실행형). | ✅ |
| E-6 | **레거시 제거**: `legacyStartRoomWorkflow` 삭제. `intent == nil` → `.quickAnswer` 폴백 (가벼운 워크플로우 우선). | ✅ |
| E-7 | **ArtifactType 확장**: `researchReport`, `brainstormResult`, `document` 추가. | ✅ |

**6단계 워크플로우 (모든 Intent 공통 프리픽스)**:
```
① Intake ── 입력 파싱 (Jira fetch, URL 감지, IntakeData 저장, 플레이북 로드)
② Intent ── 작업 유형 표시 (방 생성 시 IntentClassifier가 분류)
③ Clarify ─ 복명복창 (DOUGLAS 요약 → 사용자 컨펌까지 무한 루프)
④ Assemble ─ 전문가 초대 (AgentMatcher → 미매칭 시 생성 제안)
⑤ Plan ──── PlanMode 분기: exec(토론→계획→승인) — 토론: 발산→수렴→합의 사이클(무제한) + 사용자 체크포인트
⑥ Execute ── quickAnswer(즉답) / research(토론→브리핑) / 표준 실행(단계별)
```

**Intent별 경로**:
| Intent | PlanMode | clarify | 토론 | 승인 | 실행 |
|--------|----------|---------|------|------|------|
| quickAnswer | skip | O | - | - | 즉답 |
| research | lite | O | O | - | 토론/정리 |
| documentation | exec | O | O | - | O |
| implementation | exec | O | O | O | O |

**역호환**: `room.intent == nil` → `.quickAnswer` 자동 폴백. 레거시 저장 데이터의 brainstorm/requirementsAnalysis/testPlanning/taskDecomposition → `.research` 자동 마이그레이션 (커스텀 Codable). 모든 새 Room 필드는 `decodeIfPresent` + 기본값.

**Plan 승인 피드백 루프** (E-8~E-11):
- `requestPlan(previousPlan:feedback:)`: 거부된 이전 계획과 사용자 피드백을 재계획 프롬프트에 주입.
- `executePlanExec` 승인 while 루프: 거부 → 피드백 추출 → 재계획 → 다시 승인 카드 (무제한).
- `executeSoloAnalysis`: 전문가 1명 Solo 분석 (토론 대신). plan-lite/plan-exec에서 `specialistCount == 1`일 때 자동 호출.
- `launchFollowUpCycle`: 완료/실패 방 후속 질문 → 방 재활성화 → assemble부터 경량 워크플로우.
- `Room.canTransition`: `.completed → .planning`, `.failed → .planning` 전이 추가.

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
| `DesignTokens.CozyGame` | 코지 게임 UI 토큰: `panelRadius(18)`, `buttonRadius(14)`, `cardRadius(16)`, `borderWidth(2.5)`, `panelShadowRadius(10)`, `panelShadowY(4)`, `progressBarHeight(14)`, `progressBarRadius(7)` |
| `DesignTokens.Sidebar` | 사이드바 전용: `cornerRadius`, `shadowOpacity`, `shadowRadius` |
| `DesignTokens.Layout` | 사이드바/로스터/상태 표시 레이아웃 상수 |

### 다크모드 대응 패턴

- `Color.primary.opacity(N)` — 라이트(검정) ↔ 다크(흰색) 자동 적응
- `Color(nsColor: .windowBackgroundColor)` — 시스템 배경 추적
- `.ultraThinMaterial` — 플로팅 사이드바 반투명 배경 (AppKit `backgroundColor = .clear` + `isOpaque = false` 전제)

### 모서리 규칙

- **`.continuousRadius(N)`** View extension 사용 (`.clipShape(RoundedRectangle(cornerRadius: N, style: .continuous))`)
- deprecated `.cornerRadius()` 사용 금지

### 테마 시스템

| 파일 | 역할 |
|------|------|
| `Models/ColorPalette.swift` | 48+ 시맨틱 컬러 구조체 + `panelGradient` computed property |
| `Models/ThemePresets.swift` | `ThemeID` enum (5종) + 각 테마별 정적 팔레트 |
| `ViewModels/ThemeManager.swift` | `@MainActor ObservableObject` — 테마 선택/저장, currentPalette 발행 |
| `Views/ThemeEnvironment.swift` | `ThemedView` 래퍼 — `@Environment(\.colorPalette)` 전파 + `.fontDesign(.rounded)` 전역 적용 |
| `Views/ThemeSettingsView.swift` | 테마 카드 UI — 프리뷰 스와치, 커스텀 색상 선택 |

**ThemeID 5종**: `.cozyGame` (기본값), `.pastel`, `.dark`, `.warmCozy`, `.custom`

**코지 게임 테마 특징**:
- SF Rounded 폰트 (`.fontDesign(.rounded)` 전역)
- 크림/파스텔 그라데이션 배경 (`panelGradient`)
- 소프트 shadow + 둥근 모서리 (radius 14~18)
- 3D 버튼 효과 (하단 그림자 + 눌림 offset)

**테마 적용 흐름**: `ThemeManager.currentPalette` → `ThemedView` → `@Environment(\.colorPalette)` → 모든 하위 뷰

### 애니메이션 토큰

- `.dgFast` (0.15s) — 호버, 마이크로 인터랙션
- `.dgStandard` (0.25s) — 일반 전환
- `.dgSlow` (0.35s) — 모달, 토스트, 확장
- `.dgSpring` — spring(response: 0.35, dampingFraction: 0.7) — 코지 게임 바운스
- `.dgBounce` — spring(response: 0.4, dampingFraction: 0.6) — 강한 바운스

### 공유 컴포넌트 (`SharedComponents.swift`)

| 컴포넌트 | 용도 |
|----------|------|
| `SheetNavHeader` | 모든 시트 상단 네비게이션 헤더 (취소/제목/액션) |
| `CardContainer` | 방 채팅 내 카드 래퍼 (accentColor + opacity 파라미터) |
| `AttachmentThumbnail` | 48x48 이미지 썸네일 + 삭제 버튼 |
| `SendButton` | 전송 버튼 (canSend/isLoading 상태) |
| `sectionLabel()` | 섹션 라벨 (caption, secondary) |
| `SettingsRow` | 라벨 + 컨텐츠 설정 행 |

### 코지 게임 UI 컴포넌트 (`CozyGameComponents.swift`)

| 컴포넌트 | 용도 |
|----------|------|
| `CozyButtonStyle` | 3D 눌림 효과 게임 스타일 버튼 (variants: `.accent`, `.cream`, `.blue`, `.green`) |
| `CozyPanelModifier` | 그라데이션 배경 + 소프트 테두리 + 드롭 섀도 패널 (`.cozyPanel()` modifier) |
| `CozyProgressBar` | 둥근 게임 스타일 프로그레스 바 (그라데이션 fill + 상단 하이라이트) |
| `CozyToggle` | 둥근 pill 모양 토글 스위치 |
| `CozyCheckbox` | 둥근 사각 체크박스 |

### ColorPalette 확장 (코지 게임 UI 색상)

`panelGradientStart/End`, `buttonShadow`, `cardBorder`, `progressHighlight`, `avatarBorder` — 패널 그라데이션, 카드 테두리, 프로그레스 하이라이트 등 코지 게임 스타일 전용 색상. `palette.panelGradient` computed property로 LinearGradient 편의 접근.

---

## 플러그인 시스템

### 아키텍처

```
┌─ PluginManager (@MainActor ObservableObject) ─────────────┐
│  plugins: [any DougPlugin]                                 │
│  activePluginIDs: Set<String>                             │
│  configure(roomManager:, agentStore:)                     │
│  dispatch(_ event: PluginEvent)                           │
└───────────────────────────────────────────────────────────┘
        │                           ▲
        │ configure(context:)       │ pluginEventDelegate closure
        ▼                           │
┌─ DougPlugin Protocol ─┐    ┌─ RoomManager ─┐
│  info: PluginInfo      │    │  appendMessage → .messageAdded
│  activate() → Bool     │    │  createRoom → .roomCreated
│  deactivate()          │    │  완료/실패 → .roomCompleted/.roomFailed
│  handle(event:)        │    └───────────────┘
└────────────────────────┘
        │
        ▼
┌─ PluginContext (파사드) ─┐
│  createRoom()            │
│  sendUserMessage()       │
│  room(for:) / activeRooms()
│  masterAgent() / subAgents()
└──────────────────────────┘
```

### 핵심 파일

| 파일 | 역할 |
|------|------|
| `Plugins/Core/DougPlugin.swift` | 프로토콜 + PluginEvent + PluginConfigField |
| `Plugins/Core/PluginContext.swift` | 플러그인에 노출되는 안전한 시스템 API |
| `Plugins/Core/PluginManager.swift` | 발견 → 설정 → 활성화/비활성화 라이프사이클 |
| `Plugins/Core/PluginConfiguration.swift` | 일반값(UserDefaults) + 비밀값(KeychainHelper) 저장 |

### 이벤트 흐름

1. RoomManager에서 `pluginEventDelegate?(.event)` 호출 (클로저 — 플러그인 존재 무지)
2. AppDelegate가 `roomManager.pluginEventDelegate = { pluginManager.dispatch($0) }` 연결
3. PluginManager가 모든 활성 플러그인에 `handle(event:)` 브로드캐스트

### 플러그인 추가 방법

1. `Sources/Plugins/{Name}/` 디렉토리 생성
2. `DougPlugin` 프로토콜 구현 (`info`, `configFields`, `activate/deactivate`, `handle`)
3. `PluginManager.discoverPlugins()`에 인스턴스 추가
4. 빌드 & 테스트

### 플러그인 빌더 (Plugin Builder)

`PluginBuilderSheet` — 비개발자도 폼 UI로 스크립트 플러그인을 생성할 수 있다.

- **3가지 노코드 액션**: 웹훅 전송, 쉘 명령, macOS 알림
- **ScriptGenerator**: 액션 설정 → sh 스크립트 자동 생성
- **PluginSlug**: 한국어 이름 → ASCII 슬러그 변환 (Foundation `StringTransform.toLatin`)
- **PluginManager.createPlugin()**: 디렉토리 생성 + plugin.json/스크립트 쓰기 + 자동 로드
- **에디터 링크**: 생성 후 "스크립트 열기"로 Finder에서 직접 수정 가능

### Slack 플러그인

첫 번째 플러그인. Slack Socket Mode(WebSocket)로 멘션/키워드에 반응하여 Room 생성·메시지 주입, 결과를 Slack 스레드로 응답.

- **Socket Mode**: `apps.connections.open` → `URLSessionWebSocketTask` (외부 라이브러리 불필요)
- **트리거**: Bot 멘션 (`app_mention`) + 커스텀 키워드 패턴
- **매핑**: `SlackChannelRoomMapper` — 채널 ID ↔ Room ID 양방향, UserDefaults 영속화
- **설정**: Bot Token / App-Level Token (KeychainHelper 암호화), 트리거 패턴, 채널 필터

---

## 확장 포인트

1. **새 프로바이더 추가**: `AIProvider` 프로토콜 구현 + `ProviderType` enum 케이스 추가 + `ProviderManager.createProvider()` 분기 추가
2. **마스터 프롬프트 커스터마이징**: EditAgentSheet에서 마스터 페르소나 수정 시 위임 전략도 변경됨
4. **에이전트 간 직접 통신**: 현재는 마스터를 통해서만 위임. `invite_agent` 도구로 방 내 에이전트 초대 가능
5. **새 도구 추가**: `ToolRegistry`에 `AgentTool` 추가 + `ToolExecutor.executeSingleTool()`에 case 추가
6. **MCP (Model Context Protocol)**: 현재 내장 도구 방식. 외부 MCP 서버 연동으로 확장 가능
7. **web_search 도구 구현**: 현재 placeholder. 실제 검색 API 연동 필요
8. **새 플러그인 추가**: `DougPlugin` 프로토콜 구현 + `PluginManager.discoverPlugins()`에 등록 (Discord, GitHub Webhook, Jira 등)

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
| FileAttachment.swift | ~220 | 파일 첨부 모델 (이미지+문서, 디스크 저장, MIME 판별) |
| ProviderConfig.swift | ~110 | 설정 모델 (Keychain 연동) |
| ChatWindowView.swift | ~110 | 독립 채팅 윈도우 |
| ProviderManager.swift | ~107 | 프로바이더 관리 |
| DependencyChecker.swift | ~100 | 의존성 체크 (온보딩) |
| AIProvider.swift | ~80 | 프로바이더 프로토콜 + Tool Use 확장 |
| AgentAvatarView.swift | ~72 | 아바타 컴포넌트 (2종 아이콘) |
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
│   ├── AgentManifestTests.swift     # 14 tests — 매니페스트 라운드트립, Agent↔Entry 변환, 이름 중복, 마스터 skip, 전방 호환
│   ├── WorkingRulesTests.swift       # WorkingRulesSource — resolve, isEmpty, displaySummary, Codable
│   ├── AgentToolTests.swift          # 32 tests — AgentTool/ToolCall/ToolResult Codable, ToolRegistry (11종 도구), ConversationMessage, Jira 도구
│   ├── ArtifactParserTests.swift     # 15 tests — 산출물 추출, 다중 산출물, 타입별 파싱, 블록 제거
│   ├── ChatMessageTests.swift        # 12 tests — 모든 MessageType, Codable 라운드트립, 이미지 첨부 호환
│   ├── ClaudeCodeInstallerTests.swift # 32 tests — detect/install (ProcessRunner mock), 경로 탐색, 상태 전이
│   ├── DependencyCheckerTests.swift  # 15 tests — allRequiredFound, checkAll, shellWhichAll (ProcessRunner mock)
│   ├── FileAttachmentTests.swift     # 35+ tests — MIME 판별(매직바이트+확장자), save/load, 크기 제한, 파일 확장자, isImage, displayName, fileIcon, loadTextContent, 하위호환
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
│   ├── ChatViewModelTests.swift      # 상태 관리, 메시지 격리, 로딩, 히스토리 필터
│   ├── ChatViewModelIntegrationTests.swift # 방 생성, 서브 에이전트 대화, 오류, 알림, 메시지 영속화
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
| Models | 397 | Agent, WorkingRules, AgentTool, ArtifactParser, ChatMessage, ClaudeCodeInstaller, DependencyChecker, DiscussionArtifact, FileAttachment, JiraConfig, KeychainHelper, ProviderConfig, ProviderDetector, Room, RoomBriefing, RoomStep, ToolExecutionContext, BuildResult (QA 포함) |
| ViewModels | 302 | ChatViewModel (통합+파싱+상태), AgentStore, ProviderManager, RoomManager, OnboardingViewModel, ToolExecutor (Jira 도구 포함), BuildLoopRunner (QA 포함) |
| Providers | 91 | OpenAI, Anthropic, Google, Ollama, LM Studio, Custom, ClaudeCode, ToolFormatConverter (도구 + 이미지 + 문서) |
| **합계** | **789** | 테스트 가능 코드 87% 라인 커버리지 (View/App 레이어는 UI 특성상 제외) |
