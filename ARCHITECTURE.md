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
├── Makefile                         # 빌드/테스트/린트 통합 진입점
├── .swift-version                   # 툴체인 버전 고정 (6.1.2)
├── .swiftlint.yml                   # SwiftLint 코드 스타일 규칙
├── .github/workflows/release.yml    # GitHub Actions (태그/수동 트리거)
├── CLAUDE.md                        # 개발 규칙 (문서 업데이트 필수, 빌드/커밋 규칙)
├── DEV_GUIDE.md                     # 개발 규칙 가이드
├── ARCHITECTURE.md                  # 이 문서 (코드 분석/구조)
├── scripts/
│   ├── build-app.sh                 # 빌드 → .app 번들 → 코드서명 → DMG 생성
│   ├── pre-commit                   # pre-commit 훅 (빌드+린트 검증)
│   └── commit-msg                   # commit-msg 훅 (메시지 형식 검증)
├── Sources/
│   ├── App/
│   │   ├── DOUGLASApp.swift         # @main 진입점
│   │   ├── AppDelegate.swift        # 사이드바 패널(400pt), 채팅 윈도우, 마우스 트래킹
│   │   ├── BundleExtension.swift    # Bundle.appModule — .app 배포 시 안전한 리소스 번들 접근
│   │   └── UtilityWindowManager.swift # 유틸리티 윈도우 관리
│   ├── Models/
│   │   ├── Agent.swift              # 에이전트 모델 (+ Plan C: skillTags, workModes, actionPermissions는 workModes에서 자동 추론, outputStyles 레거시)
│   │   ├── AgentManifest.swift     # 에이전트 매니페스트 (.douglas 포맷, Plan C 카드 필드 포함)
│   │   ├── AgentPreset.swift       # 12종 빌트인 에이전트 프리셋 (메타데이터 포함)
│   │   ├── WorkingRules.swift       # 작업 규칙 (WorkingRulesSource — 인라인+파일 동시 지원)
│   │   ├── AgentTool.swift          # 도구 시스템 (AgentTool + ToolRisk + requiredActionScope, ToolCall, ToolResult, ToolRegistry)
│   │   ├── ArtifactParser.swift     # 토론 산출물 파서 (artifact 블록 추출/제거)
│   │   ├── ChatMessage.swift        # 메시지 모델 (MessageType 포함: toolActivity, buildStatus, qaStatus, approvalRequest 등, FileAttachment 첨부)
│   │   ├── DiscussionArtifact.swift # 토론 산출물 모델 (ArtifactType, 버전 관리)
│   │   ├── FileAttachment.swift     # 파일 첨부 모델 (이미지+문서, 디스크 저장, base64 로드, MIME 판별)
│   │   ├── BuildResult.swift         # 빌드 결과 모델 + BuildLoopStatus + QAResult + QALoopStatus
│   │   ├── FileWriteTracker.swift   # 병렬 실행 파일 쓰기 충돌 감지 (actor)
│   │   ├── ToolExecutionContext.swift # 도구 실행 컨텍스트 (+ Plan C: agentPermissions)
│   │   ├── WorkflowIntent.swift    # 워크플로우 의도 (WorkflowPhase, WorkflowIntent 3종: quickAnswer/task/discussion)
│   │   ├── DocumentType.swift     # 문서 유형 (6종 + 섹션 템플릿, 문서화 요청 시 사용)
│   │   ├── DocumentRequestDetector.swift # 문서화 요청 감지 (NLTokenizer + LLM 폴백) + 포맷 변환 판별
│   │   ├── IntentClassifier.swift # Intent 분류기 (PreIntentRoute + 규칙 기반 + LLM 폴백)
│   │   ├── DecisionLog.swift      # 토론 결정 로그 (DecisionEntry)
│   │   ├── WorkflowAssumption.swift # 가정 선언 (RiskLevel: low/medium/high) + UserAnswer
│   │   ├── ProjectPlaybook.swift   # 프로젝트 플레이북 (브랜치 전략, 테스트 정책, 프리셋 3종)
│   │   ├── IntakeData.swift        # Intake 입력 데이터 (InputSourceType, JiraTicketSummary, asClarifyContextString 중립 컨텍스트)
│   │   ├── SemanticMatcher.swift  # NLEmbedding 기반 에이전트 의미 유사도 매칭 (한국어+영어 word embedding, 벡터 캐시)
│   │   ├── RoleRequirement.swift   # Assemble 역할 요구사항 (Priority, MatchStatus)
│   │   ├── DependencyChecker.swift  # 의존성 체크 (Node.js, Git, Homebrew)
│   │   ├── JiraConfig.swift          # Jira Cloud 연동 설정 (도메인, 이메일, API 토큰)
│   │   ├── ColorPalette.swift       # 테마 색상 팔레트 (48+ 시맨틱 컬러, panelGradient computed property)
│   │   ├── ThemePresets.swift       # 테마 프리셋 (ThemeID 5종: cozyGame/pastel/dark/warmCozy/custom)
│   │   ├── ProviderConfig.swift     # 프로바이더 설정 (AuthMethod, ProviderType, isConnected)
│   │   ├── ProviderDetector.swift   # 시스템 AI 프로바이더 자동 감지
│   │   ├── ClaudeCodeInstaller.swift # Claude Code CLI 설치/검증 유틸리티
│   │   ├── PluginTemplate.swift     # 플러그인 빌더 모델 (PluginActionType, HandlerConfig, ScriptGenerator, PluginSlug)
│   │   ├── ShellEnvironment.swift   # 셸 환경 캐싱 (NVM 경로 1회 스캔, PATH 병합, 실행 파일 탐색)
│   │   ├── ProcessRunner.swift      # 테스트 가능한 프로세스 실행기 (DI seam)
│   │   ├── Room.swift               # 프로젝트 방 모델 (+ Plan C: TaskBrief, agentRoles, deferredActions, RiskLevel, OutputType, RuntimeRole)
│   │   ├── ApprovalRecord.swift     # 승인 기록 모델 (ApprovalType, AwaitingType, ApprovalRecord)
│   │   ├── WorkflowState.swift     # 워크플로우 진행 상태 값 객체 (intent, phase 추적)
│   │   ├── ClarifyContext.swift    # 복명복창 컨텍스트 값 객체 (intake, summary, delegation)
│   │   ├── ProjectContext.swift    # 프로젝트 연동 컨텍스트 값 객체 (경로, 빌드/테스트 명령)
│   │   └── KeychainHelper.swift     # 파일 기반 API 키 저장 (Keychain 레거시 마이그레이션)
│   ├── ViewModels/
│   │   ├── AgentStore.swift         # 에이전트 CRUD, 마스터 생명주기
│   │   ├── AgentPorter.swift        # 에이전트 매니페스트 Export/Import (NSSavePanel/NSOpenPanel)
│   │   ├── ChatViewModel.swift      # 메시지 전송, 마스터 오케스트레이션
│   │   ├── OnboardingViewModel.swift # 첫 실행 온보딩 (의존성 체크 + Claude 설정 + 프로바이더 선택)
│   │   ├── ProviderManager.swift    # 프로바이더 설정 관리
│   │   ├── BuildLoopRunner.swift     # 빌드/테스트 실행 + 수정 프롬프트 생성 엔진
│   │   ├── RoomManager.swift        # 프로젝트 방 생명주기, 6단계 워크플로우, 승인/입력 게이트
│   │   ├── AgentMatcher.swift       # 시스템 주도 에이전트 매칭 (Plan C: 3-tier 가중치 — skillTags×5, workModes×2, keyword+semantic×3, 0-1 정규화 confidence, 임계값 0.7/0.5)
│   │   ├── DocumentExporter.swift   # 문서 산출물 파일 저장 (에이전트 생성 파일 탐지 → 고정 경로 자동저장 / NSSavePanel 폴백)
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
│       ├── AddAgentSheet.swift      # 에이전트 등록 시트 (가져오기는 AgentSettingsView로 이동)
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
│       ├── GeneralSettingsView.swift # 일반 설정 (문서 저장 폴더 등)
│       ├── AgentSettingsView.swift # 에이전트 설정 (내보내기 멀티 선택 / 가져오기)
│       ├── SettingsTabView.swift   # 통합 설정 윈도우 (일반 / API 설정 / 테마 / 플러그인 / 에이전트 탭)
│       ├── SharedComponents.swift   # 공유 UI 컴포넌트 (SheetNavHeader, CardContainer, SendButton 등)
│       ├── ProgressActivityBubble.swift # 확장형 진행 버블 (활동 로그 + contentPreview 확장)
│       ├── TypingIndicator.swift    # 타이핑 인디케이터 (한국어 도구명, contentPreview 확장, 최근 활동 요약)
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

**환영 메시지**:
- `addWelcomeMessageIfNeeded()`: 마스터 에이전트 채팅이 비어있으면 "안녕하세요! DOUGLAS입니다. 뭐든 요청해주세요!" 메시지 자동 추가

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
- **인스턴스 캐싱**: `provider(named:)`가 `providerCache` 딕셔너리에 인스턴스 캐싱. `updateConfig()` 시 해당 캐시 invalidate. Provider는 stateless(대화 상태 미보유)이므로 방 간 간섭 없음.

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
- **토론 병렬화**: 첫 라운드에서 `generateDiscussionResponse` + `withTaskGroup`으로 전문가 동시 실행. 이후 라운드는 순차(이전 발언 참고).

### ClaudeCodeProvider (`Providers/ClaudeCodeProvider.swift`)

가장 독특한 프로바이더. Claude Code CLI를 `ProcessRunner`로 실행한다.

- `findClaudePath()`: nvm, homebrew, local 등 다양한 경로에서 claude 바이너리 탐색
- `claude -p <prompt> --model <model>` 형태로 비대화형 실행
- 환경변수 `CLAUDECODE`를 제거하여 중첩 세션 감지 우회
- PATH에 nvm 경로 추가하여 node 의존성 해결
- 시스템 프롬프트 + 대화 히스토리를 단일 프롬프트로 조합
- **도구 활동 추적 + 텍스트 스트리밍**: `--output-format stream-json --verbose`로 NDJSON 스트리밍 → `StreamJsonHandler`가 `tool_use` 이벤트 + 텍스트 청크 실시간 파싱. `onToolActivity` 콜백으로 도구 활동 추적, `onTextChunk` 콜백으로 텍스트 스트리밍 (`--include-partial-messages`). `sendMessageStreaming()` 구현으로 Design/Plan/Review 단계에서도 실시간 텍스트 출력 지원. 도구명은 한국어 변환(`ToolActivityDetail.displayName`), `contentPreview`는 tool_use input에서 추출. `sendMessageWithSearch()`에도 `onToolActivity` 지원
- **도구 정책**: `sendMessage()` = 도구 활성화 (`--allowedTools Edit Write Bash Read Glob Grep`), `sendRouterMessage()` = 도구 비활성화 (`--tools ""`). 계획 수립(`requestPlan`), 브리핑 생성(`generateBriefing`), 작업일지(`generateWorkLog`)는 `sendRouterMessage` 사용 — 계획 승인 전 파일 수정/셸 실행 방지.

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
    let toolDetail: ToolActivityDetail?  // 도구 실행 상세 (파일 경로, 내용 미리보기)
}
```

- `init(from decoder:)`: messageType, attachments, activityGroupID, toolDetail이 없는 기존 데이터와 역호환 (`.text` 기본값, `nil`)
- MessageType에 따라 채팅 버블의 색상, 아이콘, 테두리가 달라짐
- `attachments`: 파일 첨부 시 메시지 버블에 이미지 썸네일 또는 문서 아이콘 표시
- `activityGroupID`: `.toolActivity` 메시지가 부모 `.progress` 메시지에 소속됨을 표시. 메인 채팅에서는 숨기고, progress 버블 확장 시 인라인 표시
- `toolDetail`: 도구 실행 시 구조화된 상세 정보 (`ToolActivityDetail` — 도구명, 파일 경로/명령어, 내용 미리보기 최대 2000자). progress 버블에서 클릭으로 펼쳐 확인 가능

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

### ApprovalRecord (`Models/ApprovalRecord.swift`)

승인/거부 이벤트의 영속적 기록. 워크플로우에서 발생하는 모든 승인 게이트를 추적한다.

- **ApprovalType** (7종): `clarifyApproval`, `teamConfirmation`, `planApproval`, `stepApproval`, `lastStepConfirmation`, `deliverApproval`, `designApproval`
- **AwaitingType** (10종): `clarification`, `agentConfirmation`, `planApproval`, `stepApproval`, `finalApproval`, `irreversibleStep`, `deliverApproval`, `designApproval`, `userFeedback`, `discussionCheckpoint`
- **ApprovalRecord**: `id`, `type`, `timestamp`, `approved`, `feedback?`, `stepIndex?`, `planVersion?`
- Room에 `approvalHistory: [ApprovalRecord]` + `awaitingType: AwaitingType?` 추가
- `RoomPlan.version`: 계획 거부 시 +1 증가, 재계획 추적
- `approveStep()`/`rejectStep()` 호출 시 자동 기록

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

### TypingIndicator / ProgressActivityBubble (도구 활동 표시)

에이전트 작업 진행 중 도구 활동을 실시간으로 표시:

**TypingIndicator** (`Views/TypingIndicator.swift`) — 메인 방 채팅의 진행 상태:
- **접힌 상태**: 바운스 애니메이션 + 상태 텍스트 + 최근 활동 요약(한국어 도구명 + 축약 경로) + 활동 개수 뱃지
- **펼친 상태**: 소속된 `.toolActivity` 메시지들을 시간순으로 표시 (한국어 도구명, 아이콘 구분, 타임스탬프)
- **도구 상세 펼치기**: `contentPreview`가 있는 활동 행 클릭 시 확장 — Edit 변경사항, Bash 명령어 전문, Grep 조건 등 (모노스페이스, 최대 150pt 높이)

**ProgressActivityBubble** (`Views/ProgressActivityBubble.swift`) — 완료된 활동 그룹 표시용:
- 동일한 2단계 확장 UI (접힘 → 활동 목록 → contentPreview)

**한국어 도구명**: `ToolActivityDetail.displayName` — Read→파일 읽기, Edit→파일 수정, Bash→명령 실행, Grep→내용 검색 등
**contentPreview 추출** (`StreamJsonHandler.extractContentPreview`): tool_use input에서 상세 정보 추출
- Edit: `old_string → new_string` diff
- Bash: 80자 초과 명령어 전문
- Write: 첫 10줄 미리보기
- Grep: 패턴 + 경로 + 필터 종합
- Read: offset/limit 범위 표시

**공통 구조**:
- `activityGroupID`로 부모-자식 관계 연결: `.toolActivity` 메시지의 `activityGroupID`가 `.progress` 메시지의 `id`와 일치
- 메인 채팅에서는 `activityGroupID != nil`인 메시지를 필터링하여 숨김
- 도구별 아이콘: Read → `doc.text`, Write → `doc.badge.plus`, Bash → `terminal`, WebFetch → `globe`, llm_call → `arrow.up.circle`

#### 전체 워크플로우 활동 추적 (`trackPhaseActivity`)

`RoomManager.trackPhaseActivity()` 헬퍼가 모든 LLM 호출을 자동으로 추적:
- `.progress` 부모 메시지 + `llm_call` 시작 활동 (프로바이더/모델명) + `llm_result`/`llm_error` 완료 활동 (소요시간)
- body 클로저에 `onToolActivity` 콜백을 전달하여 중간 도구 이벤트도 같은 그룹에 표시

적용 단계:
| 단계 | 메서드 | 도구 활동 |
|------|--------|-----------|
| 계획 수립 | `requestPlan()` | 없음 (sendRouterMessage) |
| 브리핑 | `generateBriefing()` | 없음 (sendRouterMessage) |
| 작업일지 | `generateWorkLog()` | 없음 (sendRouterMessage) |
| 사전 분석 | `executeSoloAnalysis()` | 없음 (useTools: false) |
| 질의응답 | `executeQuickAnswer()` | WebSearch/WebFetch 이벤트 |
| 실행 단계 | `executeStep()` | 전체 도구 이벤트 (기존) + 모델/시간 추가 |
| 토론 발언 (순차) | `executeDiscussionTurn()` | 수동 추적 (llm_call/llm_result) |
| 토론 발언 (병렬) | `generateDiscussionResponse()` | 수동 추적 (llm_call/llm_result) |

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

기존 분산된 설정을 **5탭 통합 윈도우**로 병합:
- **일반** 탭: GeneralSettingsView — 문서 저장 폴더 설정 (NSOpenPanel 폴더 선택, UserDefaults `documentSaveDirectory`)
- **API 설정** 탭: AddProviderSheet(isEmbedded: true) — Claude Code, OpenAI, Google, Jira Cloud
- **테마** 탭: ThemeSettingsView(isEmbedded: true) — 프리셋 3종 + 커스텀 색상
- **플러그인** 탭: PluginSettingsView(isEmbedded: true) — 빌트인/외부 플러그인 관리
- **에이전트** 탭: AgentSettingsView(isEmbedded: true) — 에이전트 내보내기(멀티 선택)/가져오기

문서 저장 경로가 설정되면 `DocumentExporter.saveDocument()`가 NSSavePanel 없이 해당 폴더에 자동 저장 (동일 파일명 시 `(2)`, `(3)` 자동 부여). 미설정 시 기존 NSSavePanel 동작.

`offerDocumentSave`는 2단계 우선순위로 동작:
1. **실제 파일 탐지** (`findActualDocumentFile`): 에이전트가 도구(file_write/Write)로 생성한 문서 파일 또는 응답 텍스트에 backtick으로 언급된 절대 경로를 탐색 → 파일 존재 확인 후 해당 경로 링크
2. **MD 폴백**: 실제 파일이 없으면 메시지 콘텐츠를 추출하여 `.md`로 저장

**문서 완료 카드**: 저장 완료 메시지는 `ChatMessage.documentURL` 필드가 설정된 `.phaseTransition` 시스템 메시지로 생성. `MessageBubble.documentCompletionView`가 파일 아이콘 + 클릭 가능 파일명 (`NSWorkspace.shared.open`) + 경로를 카드 형태로 표시.

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

모든 에이전트는 전체 16종 도구에 접근 가능 (프리셋 제한 없음).

| ID | 이름 | 설명 |
|----|------|------|
| `file_read` | 파일 읽기 | 지정 경로 파일 내용 읽기 (50K자 제한) |
| `file_write` | 파일 쓰기 | 지정 경로에 파일 작성 |
| `shell_exec` | 셸 실행 | zsh 명령어 실행 (30K자 출력 제한) |
| `web_search` | 웹 검색 | DuckDuckGo HTML 검색 (상위 8건) |
| `web_fetch` | 웹 페이지 가져오기 | URL → HTML 가져오기 + Jira REST API 티켓 조회 (JiraConfig 연동) |
| `invite_agent` | 에이전트 초대 | 방에 다른 에이전트를 런타임 초대 (params: agent_name, reason) |
| `list_agents` | 에이전트 목록 | 등록된 서브 에이전트 목록 조회 (params: 없음) |
| `suggest_agent_creation` | 에이전트 생성 제안 | 필요한 역할의 새 에이전트 생성 제안 (사용자 승인 필요) |
| `ask_user` | 사용자 질문 | Clarify 단계에서만 사용 가능. 사용자에게 질문 (params: question, context?, options?) |
| `jira_create_subtask` | Jira 서브태스크 생성 | 상위 이슈에 서브태스크 자동 생성 (params: parent_key, summary, project_key?) |
| `jira_update_status` | Jira 상태 변경 | 이슈 상태 전이 (params: issue_key, status_name) |
| `jira_add_comment` | Jira 코멘트 작성 | ADF 형식으로 코멘트 추가 (params: issue_key, comment) |
| **`code_search`** | **코드 검색** | **ripgrep 기반 코드 패턴 검색 — 정규식, 파일 글로브, 컨텍스트 라인, 대소문자 옵션** |
| **`code_symbols`** | **심볼 검색** | **프로젝트 심볼 정의 검색 — class/struct/func/enum/protocol/interface (Swift/TS/JS/Python/Go/Rust)** |
| **`code_diagnostics`** | **코드 진단** | **컴파일러/린터 실행 후 구조화된 에러/경고 반환 — SPM/TSC/ESLint/Cargo/Go Vet 자동 감지** |
| **`code_outline`** | **코드 구조** | **파일의 구조적 아웃라인 — 선언 트리 + 줄 번호 (Swift/TS/JS/Python/Go/Rust)** |

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

**진행자 아이덴티티**: 방 내 오케스트레이터 메시지(질문, 팀 확정 등)는 `agentName: masterAgentName`으로 마스터 에이전트(DOUGLAS) 아바타·이름과 함께 표시. `masterAgentName` computed property가 마스터 이름 제공.

**방 워크플로우** (`startRoomWorkflow`): 항상 Intent 기반 `executePhaseWorkflow` 실행. `room.intent == nil`이면 `.quickAnswer`를 phase 계산 기본값으로 사용하되, `executeIntentPhase`에서 사용자 선택으로 교체됨.

**Pre-Intent 라우팅** (`IntentClassifier.preRoute`): 방 생성 전 입력을 5가지로 분류:
- `.empty`: 텍스트+파일 없음 → 무시
- `.fileOnly`: 파일만 업로드 → intent=nil로 방 생성, 빈 task로 워크플로우 시작 → Understand 단계에서 사용자에게 작업 의도 질문 (2분 타임아웃)
- `.command(.summonAgent)`: "에이전트 불러와" 등 시스템 명령 → 안내 메시지 표시
- `.classified(intent)`: quickAnswer, task, discussion 확정 → 정상 워크플로우
- `.ambiguous`: 분류 불가 → intent=nil로 방 생성 (사용자 선택 UI)

**범용 워크플로우 (Intent 기반 적응형)**:
```
사용자 입력 → Pre-Intent 라우팅 → Intent 분류 (규칙 + LLM) → 방 생성
  → ① Intake: 입력 파싱 (Jira fetch, URL 감지)
  → ② Intent: 작업 유형 표시 (문서 요청 감지 시 autoDocOutput 설정)
  → ③ Clarify: 복명복창 (task만, quickAnswer·문서 요청은 스킵)
  → ④ Assemble: 전문가 초대 (문서 작업 → 직접 배정 | 그 외 → 역할 매칭 + 생성 제안)
  → ⑤ [needsPlan?] Plan: 동적 판단 후 토론→계획→승인 (assemble 완료 후 LLM 판별)
  → ⑥ Execute: quickAnswer(즉답) / task+needsPlan(계획 기반 실행) / task+!needsPlan(토론/분석+문서)
```

- **Intent 분류** (`IntentClassifier`): 2종 intent (quickAnswer / task). 규칙 기반 즉시 분류 (`quickClassify`) → 실패 시 LLM 분류 (`classifyWithLLM`). `quickClassify`가 nil(판단 불가)이면 `executeIntentPhase`에서 LLM 추천 intent와 함께 **IntentSelectionCard** UI를 표시하여 사용자가 2종 intent 중 선택. `pendingIntentSelection` + `intentContinuations`으로 비동기 게이트 구현. 분류 실패 시 `.quickAnswer` 폴백 (가장 가벼운 워크플로우). 레거시 research/implementation 문자열은 `.task`로 자동 마이그레이션.
- **문서화 요청 감지** (`DocumentRequestDetector`): 2단계 감지 — ① intent 확정 후 초기 task에서 패턴 감지, ② clarify 후 사용자 피드백에서 재감지 (`detectDocumentSignalFromMessages`). 감지 규칙: 문서 확장자/유형 키워드(md, pdf, 워드, 문서, 보고서 등) + 동작 어간(만들, 생성, 작성, 정리 등) 조합 → 문서 요청 판정. 동사 활용 대응을 위해 prefix 매칭 사용 (만들어줘→만들, 생성해줘→생성). 감지 시 `room.autoDocOutput = true` + `room.documentType` 설정 (suggestedDocType nil → .freeform 폴백). **문서 요청이 감지되면 clarify 단계 자동 스킵** (사용자 의도가 명확하므로 복명복창 불필요). **autoDocOutput이면 assemble에서 LLM 역할 분석 바이패스** → 문서 역량 에이전트(outputStyles.contains(.document) > skillTags > name 키워드 순) 직접 배정. task 완료 후 자동 문서화 (preferredKeywords 기반 최적 에이전트 선택) + NSSavePanel 저장 (클릭 가능 file:// 링크 제공). 후속 사이클에서도 "문서로 정리해줘" 등 감지 가능 (1차 키워드 + 2차 LLM 폴백).
- **복명복창 Clarify** (`executeClarifyPhase`): DOUGLAS가 요청을 요약 → 사용자 승인/거부 → 거부 시 피드백 반영 재요약 → 승인까지 무한 반복. 승인 시 `room.clarifySummary`에 저장 + `[delegation]` 블록 파싱 → `room.delegationInfo`(`DelegationInfo`)에 저장. explicit 타입이면 assemble에서 LLM 역할 분석 스킵 → 지정 에이전트만 배정. open이면 기존 흐름.
- **동적 Plan 판단** (`classifyNeedsPlan`): assemble 완료 후 2단계 판별. ① 키워드 기반 즉시 판별(`classifyNeedsPlanByKeywords`): clarifySummary+task에서 구현 키워드(수정/구현/fix/쿼리 등)와 분석 키워드(리서치/요약/번역 등)를 가중치 합산 — planScore≥5이면 즉시 true, noPlanScore≥5 && planScore<3이면 즉시 false. ② 키워드 애매 시 LLM 폴백: light model이 YES/NO 판별. 실패 시 false (안전한 기본값). 결과를 `room.needsPlan`에 저장.
- **Plan 실행** (`executePlanPhase`): needsPlan=true일 때만 호출. 전문가 2명+ → 토론 + 브리핑 + 계획 수립. 전문가 1명 → 계획 수립 (soloAnalysis 스킵, requestPlan이 직접 분석). 계획 표시 후 바로 실행 진입 (승인 게이트 제거).
- **토론 알고리즘** (`executeDiscussion`): 라운드별 자유 토론 (마스터 제외, 전문가만 참여). 매 라운드 후 사용자 체크포인트 (DiscussionCheckpointCard). 사용자 피드백 시 새 라운드, "진행"(빈 입력) 시 브리핑으로. 라운드 무제한 (사용자 주도 종료). 첫 라운드는 병렬 실행 (`generateDiscussionResponse` + `withTaskGroup`, 히스토리 스냅샷 기준), 이후 라운드는 순차 실행 (이전 발언 참고). 모든 에이전트 프롬프트에 `clarifySummary` 앵커링 포함.
- **Execute 분기** (`executeExecutePhase`): 2-way 분기:
  - quickAnswer → 전문가 1명 즉답 (도구 포함)
  - task + needsPlan → 계획 기반 단계별 실행 (`executeRoomWork`)
  - task + !needsPlan → 토론/분석 후 결과 정리 (전문가 2명+ 자유 토론+브리핑, 1명 soloAnalysis, autoDocOutput 시 자동 문서화)
- **실행 시 마스터 제외** (`executingAgentIDs`): `agent.isMaster`이면 실행 대상에서 제외
- **계획 수립**: 전문가가 생성 (마스터 제외). 계획 JSON은 사용자에게 숨김.
- **DecisionLog**: 토론 중 `[합의: 내용]` 태그 파싱 → `Room.decisionLog`에 기록
- **에이전트 참조 프로젝트** (`Agent.referenceProjectPaths`): 에이전트별로 참조 프로젝트 디렉토리를 여러 건 등록. 방에 초대 시 `addAgent(_:to:silent:)`에서 방의 `projectPaths`에 자동 병합. `silent: true` 시 참여 시스템 메시지 생략 (호출부에서 커스텀 메시지 표시 시 중복 방지).
- **방 shortID** (`Room.shortID`): UUID 앞 6자 소문자. 방 헤더(`RoomChatView`)와 방 목록(`RoomListView`)에 표시.
- **CLI WebFetch 차단**: `ClaudeCodeProvider.sendMessage()`에서 `--disallowed-tools WebFetch` 적용

**승인 게이트** (`executeRoomWork`): 첫 단계 + 마지막 단계 + 외부 영향 키워드(`hasExternalEffectKeywords`: PR, push, deploy, merge 등) 포함 단계에서 `.awaitingApproval` 상태 전환 + `CheckedContinuation`으로 비동기 일시 정지. `approveStep(roomID:)` / `rejectStep(roomID:)` 호출 시 continuation resume. **자동 승인 타이머**: 모든 리뷰 게이트에서 15초 카운트다운 후 자동 승인. 사용자가 "수정 요청" 클릭 시 타이머 취소 → 수동 응답 대기. **중간 단계 완료 표시**: 리뷰 게이트가 없는 중간 단계도 "단계 X 완료" 시스템 메시지를 표시하여 진행 흐름이 끊기지 않도록 함. **단계 카운트 동기화**: `setCurrentStep(stepIndex)`를 승인 게이트 전에 호출하여 이전 단계들이 즉시 체크 표시됨.

**Plan 승인 루프** (`executePlanPhase`): Plan 승인 시 거부 → 피드백 추출 → `requestPlan(previousPlan:feedback:)`로 재계획 → 다시 승인 카드 표시 (무제한). 이전 계획과 사용자 피드백이 재계획 프롬프트에 주입됨.

**승인 카드 UI** (`ApprovalCard`): 단계 결과 확인 + "승인"/"수정 요청" 버튼. 자동 승인 카운트다운 표시 (승인 버튼에 "15s" 형태). "수정 요청" 클릭 시 타이머 취소 → 피드백 입력 → `rejectStep()`으로 재계획 트리거.

**전문가 Solo 분석** (`executeSoloAnalysis`): 전문가 1명만 배정된 방에서 토론 대신 혼자 분석하여 결과 공유. task + !needsPlan 경로에서 `specialistCount == 1`일 때 자동 호출.

**후속 사이클** (`launchFollowUpCycle`): 완료/실패 방에서 사용자 후속 질문 시 방 재활성화 → 문서화 요청 감지(DocumentRequestDetector) → Intent 재분류 → clarify부터 워크플로우 재실행 (복명복창 포함). 문서화 요청 감지 시 `handleDocumentOutput()`으로 직접 문서 작성. 규칙 기반 quickAnswer 확정 + 에이전트 변동 없으면 clarify/assemble 스킵 (즉답 빠른 경로). `previousCycleAgentCount`로 에이전트 추가/제거 감지.

**`@` 멘션** (`MentionParser`): 사용자가 `@에이전트이름 메시지` 형태로 에이전트를 직접 초대. `sendUserMessage` 시작 시 파싱 → `addAgent` → 멘션 제거된 순수 텍스트로 워크플로우 진행. 정확 매칭 + 접두어 매칭 지원 (ex: `@번역` → `번역가`). 미매칭 멘션은 원문 유지. RoomChatView에서 `@` 입력 시 에이전트 자동완성 팝오버 표시. **멘션 라우팅 우선권**: 멘션된 에이전트 ID를 `mentionedAgentIDsByRoom`에 저장 → `executeQuickAnswer`/`executeSoloAnalysis`에서 LLM 라우팅보다 우선 사용 (소비 후 삭제).

**quickAnswer 경량 라우팅** (`routeQuickAnswer`): 전문가 2명 이상인 방에서 즉답 시 (멘션 없는 경우), 마스터가 질문에 최적인 전문가 1명을 지명하여 답변. LLM 1회 경량 호출.

**대상 경로 감지**: 코딩 관련 키워드가 포함된 요청에 파일 경로가 없으면 → `.awaitingUserInput`으로 전환 → 사용자에게 대상 파일/경로 질문 → 답변을 분석 결과에 추가.

**실패 자동 감지** (`executeRoomWork`):
- 단계 실행 실패(에러): `executeStep()` 반환값 `false` → 즉시 `.failed` 전환 + 중단.
- 반복 응답 감지: 연속 단계에서 Jaccard 단어 유사도 > 60% → 에이전트가 stuck 상태로 판단 → `.failed` 전환 + 중단. (`wordOverlapSimilarity()`)

**작업일지**: `executePhaseWorkflow()` 완료 후 `generateWorkLog()`를 fire-and-forget `Task`로 비동기 실행 — 완료 UI 즉시 표시. `completeRoom()` (수동 완료)에서도 동일하게 비동기 생성.

**QA 루프** (`runQALoop`): 빌드 루프 성공 후 `testCommand`가 있으면 자동 실행. `BuildLoopRunner.runTests()` → 실패 시 QA 에이전트(이름/페르소나에 "QA" 키워드 포함)에게 수정 프롬프트 → 재테스트 (최대 `maxQARetries`회).

**컨텍스트 압축**: 토론 종료 후 `generateBriefing()`이 전체 히스토리를 JSON 브리핑으로 압축. 브리핑/계획 프롬프트에 `clarifySummary`(원래 사용자 요청) 포함 → 탈선 방지.
- 계획 수립: 브리핑 + 산출물 프리뷰(200자) 전달 (40msg → ~500토큰) + 원래 요청 앵커
- 실행 단계: 브리핑 + 최근 5개 메시지 (`buildRoomHistory(limit: 5)`) + 산출물 전체 내용
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
| B-1 | **프로젝트 디렉토리 연동**: 방 생성 시 `projectPaths` 지정 (복수 디렉토리 지원) → 상대 경로 해석(첫 번째 기준), `isPathAllowed` 전체 경로 허용, `shell_exec` 기본 workDir(첫 번째). `Room.projectPaths: [String]`, `Room.buildCommand` 추가. CreateRoomSheet에 복수 디렉토리 선택 + 빌드 명령 자동 감지 UI. **Lazy Worktree 격리**: 동일 `projectPath`에 활성 방 2개 이상 시 후발 방에 `git worktree add`로 물리적 디렉토리 분리. `Room.worktreePath`, `effectiveProjectPath`, `effectiveProjectPaths` computed. 방 완료/삭제 시 `git worktree remove` 자동 정리. 앱 재시작 시 잔여 worktree 정리. worktree 경로: `{projectPath}/.douglas/worktrees/{roomShortID}/`. | ✅ |
| B-2 | **빌드→에러→수정 자율 루프**: `BuildLoopRunner.runBuild()` → 실패 시 에이전트에게 수정 프롬프트 → 재빌드 (최대 `maxBuildRetries`회). `BuildResult`, `BuildLoopStatus` 모델. `RoomManager.runBuildLoop()` 통합. BuildStatusCard UI. | ✅ |
| B-3 | **병렬 실행 파일 충돌 감지**: `FileWriteTracker` actor — 에이전트별 파일 쓰기 기록, 동일 파일 다중 에이전트 수정 시 충돌 경고. `ToolExecutionContext`에 `currentAgentID`, `fileWriteTracker` 추가. 단계별 충돌 초기화. | ✅ |

### Phase C — 통합 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| C-1 | **Jira 깊은 연동**: `jira_create_subtask`(서브태스크 생성), `jira_update_status`(상태 전이), `jira_add_comment`(ADF 코멘트) 3개 쓰기 도구 추가. 모든 에이전트에 포함. `makeJiraRequest()` 공통 인증 헬퍼. | ✅ |
| C-2 | **Human-in-the-loop 승인 게이트**: `RoomStep` 구조체 (plain String + object 혼합 Codable). `RoomStatus.awaitingApproval` 추가. `CheckedContinuation`으로 비동기 일시 정지. ApprovalCard UI. `ApprovalRecord`로 승인/거부 이력 영속 기록. `AwaitingType`으로 대기 종류 구분. `RoomPlan.version`으로 계획 거부 시 버전 추적. | ✅ |
| C-3 | **QA 자동 검증**: `QAResult`/`QALoopStatus` 모델. `BuildLoopRunner.runTests()` + `qaFixPrompt()`. `RoomManager.runQALoop()` — 빌드 성공 후 테스트 자동 실행, 실패 시 QA 에이전트가 수정 루프. 테스트 명령 자동 감지. | ✅ |

### Phase D — 분석가 중심 워크플로우 재구조화 → Phase G에서 대체됨

> Phase D/F는 분석가를 중간 레이어로 사용했으나, Phase G에서 마스터가 직접 PM/오케스트레이터 역할을 수행하도록 대체됨.

### Phase G — 마스터 = PM 오케스트레이터 ✅ 완료

| 항목 | 내용 | 상태 |
|------|------|------|
| G-1 | **마스터 LLM 라우팅 제거**: `handleMasterMessage()`에서 LLM 호출 없이 즉시 방 생성. `MasterAction`, `parseMasterResponse`, `extractJSON`, `handleDelegation`, `handleChain`, `generateSummary`, `masterFallbackResponse` 등 ~500줄 삭제. | ✅ |
| G-2 | **분석가 자동 생성 제거**: `ensureAnalystExists()`, `createDefaultAnalyst()` 삭제. 마스터가 직접 트리아지 수행. | ✅ |
| G-3 | **RoomManager 마스터 기반**: `isAnalystLed()` → `isMasterLed()`, `executingAgentIDs()` 마스터 제외, 토론에서 마스터 제외(전문가만 자유 토론). | ✅ |
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

### Phase E — Intent 기반 범용 워크플로우 ✅ 완료 (v3: 2-Intent + 동적 Plan)

| 항목 | 내용 | 상태 |
|------|------|------|
| E-1 | **WorkflowIntent 3종**: quickAnswer, task, discussion. discussion = 의견 교환/브레인스토밍 (Build/Review 스킵, Design 내 DOUGLAS 종합). 레거시 brainstorm → `.discussion` 마이그레이션. | ✅ |
| E-2 | **IntentClassifier + PreIntentRoute**: 규칙 기반 키워드 즉시 분류 → LLM 폴백. `ChatViewModel.handleMasterMessage`에서 `preRoute()`로 Pre-Intent 라우팅 (empty/fileOnly/command/classified/ambiguous). | ✅ |
| E-3 | **복명복창 Clarify**: DOUGLAS가 이해한 내용 요약 → 사용자 승인까지 무한 루프. 거부 시 피드백 반영 재요약. | ✅ |
| E-4 | **DecisionLog**: 토론 중 `[합의: 내용]` 파싱 → `DecisionEntry` 기록. `Room.decisionLog` 저장. | ✅ |
| E-5 | **동적 Plan**: `classifyNeedsPlan()` — assemble 완료 후 LLM이 plan 필요 여부 판별. `room.needsPlan`에 저장. true → plan phase 인라인 실행. | ✅ |
| E-6 | **레거시 제거**: `legacyStartRoomWorkflow` 삭제. `executePlanLite`/`executePlanExec` 삭제 → `executePlanPhase` 하나로 통합. | ✅ |
| E-7 | **ArtifactType 확장**: `researchReport`, `brainstormResult`, `document` 추가. | ✅ |

**Plan C: 새 6단계 워크플로우** (런타임 구현 완료):
```
① Understand ─ intake+intent+TaskBrief 통합 (clarify 루프 제거, needsClarification → 최대 2회 질문 + 30초 타임아웃)
              파일만 업로드(빈 task) 시 작업 의도 질문 후 대기 (2분 타임아웃)
              bare URL(명시적 의도 없음) 시 needsClarification 강제 true → 작업 목적 질문
② Assemble ── 3-tier 가중치 에이전트 매칭 (Tier1: skillTags×5, Tier2: workModes×2, Tier3: keyword+semantic×3)
              confidence 0.7↑ 자동, 0.5~0.7 사용자확인, 0.5↓ 제외 + RuntimeRole 사전배정 + 팀 확정 메시지(Role 표시)
③ Design ──── **통합 토론 프로토콜**: discussion/task 모두 동일한 토론 수행
              멀티에이전트: 병렬 의견 제시 → 사용자 체크포인트 → 상호 피드백 → 사용자 체크포인트 → DOUGLAS 종합
              1인+discussion → `executeSoloDiscussion` (JSON 계획 없이 자연어 분석)
              1인+task → `executeSoloDesign` (구조화 플랜)
              task intent: 토론 결과 기반 계획 생성 → `awaitPlanApproval` (사용자 승인 루프)
              1인 플랜 세분화 규칙: 1산출물=1단계, 구현/테스트/PR 별개 분할
④ Build ───── step 루프: low/medium=자동실행, high=DeferredAction
              도구 레벨: deferHighRiskTools=true → external 도구도 DeferredAction으로 수집
              **라이브 협업**: step 간 사용자 메시지 체크 → 다음 step fullTask에 주입
              도구 라운드 간 `fetchPendingUserMessages` 콜백으로 실시간 반영
⑤ Review ──── verdict 파싱 (PASS/FAIL/통과/불합격) + fail 시 Creator 수정 → 재검토 (최대 2회, 초과 시 자동 통과)
              1인 → `executeSoloReview` (자기 검토: FAIL 시 자기 수정 1회 → 재검토 → 자동 PASS)
⑥ Deliver ─── DeferredAction 프리뷰 + 승인 → 실제 실행, 거부 → 취소, 무응답 → HOLD
```

**Intent별 경로**:
| Intent | 단계 |
|--------|------|
| quickAnswer | Understand → Assemble → Deliver |
| task | Understand → Assemble → Design → Build → Review → Deliver |
| discussion | Understand → Assemble → Design(토론+종합) → Deliver |

**discussion 워크플로우**: Design 단계 내에서 전문가 의견 수렴(병렬) → 상호 피드백(순차) → DOUGLAS 진행자 종합까지 완결. Build/Review 불필요.

**워크플로우 명세 (정본: `WORKFLOW_SPEC.md`)**:

상세 플로우, 상태 전이, 승인 모델, 예외 처리, UX 문구 원칙은 `WORKFLOW_SPEC.md` 참조.

| Case | 플로우 요약 |
|------|-------------|
| A. 질의응답 | 단일 에이전트/DOUGLAS 직접 응답. 신뢰도 HIGH 시 에이전트 확인 생략 가능 |
| B. 단일 에이전트 토론 | 심화 질의응답 수준의 단독 검토 |
| C. 복수 에이전트 토론 | 라운드 기반 토론 → 종료 조건 충족 시 결론/대안/쟁점 정리 |
| D. 단일 에이전트 구현 | 계획 → 승인(무한 루프) → 실행(실시간 사용자 개입) → 최종 승인 → 완료 |
| E. 복수 에이전트 구현 | 사전 토론 → 계획 → 승인 → 실행 → 최종 승인 → 완료 |
| F. 문서 생성 | 문서 전문가 최종 책임. "완료되었습니다." + 경로만 표시 |
| G. 후속처리 | 완료 후 같은 방에서 질의응답/토론/구현/문서화로 확장 가능 |
| H. 요건 불명확 | 재질문 후 명확해질 때까지 실행 보류 |

**레거시 호환**: 기존 6단계(intake→intent→clarify→assemble→plan→execute)도 그대로 동작.
`room.intent == nil` → `.quickAnswer` 폴백. 레거시 brainstorm → `.discussion`, 그 외 레거시 intent → `.task` 자동 마이그레이션.
모든 새 필드(`taskBrief`, `agentRoles`, `deferredActions`, Agent 5종 메타데이터)는 `decodeIfPresent` + 빈 기본값.

**에이전트 카드 (Plan C)**:
- `skillTags: [String]` — 매칭 시 가장 강한 신호 (Tier 1: weight 5)
- `workModes: Set<WorkMode>` — plan/create/execute/review/research (역할 배정 + 도구 권한 + 매칭 Tier 2)
- `outputStyles: Set<OutputStyle>` — 레거시 (매칭에서 제거됨, UI 비노출, 모델 필드만 유지)
- `actionPermissions: Set<ActionScope>` — workModes에서 자동 추론되는 computed property (비어있으면 모두 허용)
  - plan/research/review → readFiles, readWeb
  - create → + writeFiles
  - execute → + writeFiles, runCommands

**2-layer 안전 시스템**:
- Layer 1: 에이전트 `actionPermissions` (workModes 기반 자동 추론) — 도구별 `requiredActionScope` 대조
- Layer 2: `deferHighRiskTools` — Build 단계에서 external 도구 → DeferredAction으로 수집 (Deliver에서 실행)

**12종 빌트인 프리셋** (`AgentPreset.builtIn`): 백엔드/프론트엔드/QA/DevOps/기획자/리서처/문서작성자/마케터/디자이너/법무/데이터분석가/CS

**승인 게이트 정리**:
- **계획 승인**: `awaitPlanApproval` — 사용자 승인될 때까지 무한 루프 (거부 시 피드백 반영 재계획)
- **마지막 단계 승인**: Build step 루프에서 마지막 단계 직전 반드시 확인 요청 (거부 시 지정 단계로 롤백)
- **토론 체크포인트**: 토론 라운드마다 사용자 의견 입력 기회
- **팀 확인**: Assemble 후 에이전트 구성 확인 요청 (거부 시 직접 선택)
- **Deliver 승인**: DeferredAction 프리뷰 + 승인 (비가역 작업)
- **Clarify**: 요건 불명확 시 DOUGLAS가 재차 질문 (복명복창)
- `requestPlan(previousPlan:feedback:)`: 재계획 프롬프트 주입 (승인 루프에서 거부 시 사용)
- `executeSoloAnalysis`: 전문가 1명 Solo 분석 (토론 대신). task + !needsPlan에서 `specialistCount == 1`일 때 자동 호출.
- `executeSoloDiscussion`: 1인+discussion intent → JSON 없이 자연어 분석/의견 제시
- `executeSoloReview`: 1인 자기 검토 (Reviewer 페르소나로 Build 결과 검증, FAIL 시 자기 수정 1회)
- `executeStep` 문서 템플릿 주입: `documentType != nil`일 때 `documentType.templatePromptBlock()` + "이미 완성" 응답 금지 지침. Assemble에서 `documentType != nil`이면 1명 제한.

**Build 라이브 협업**:
- `ToolExecutionContext.fetchPendingUserMessages`: 도구 라운드 사이에 사용자 메시지 주입 (Anthropic/OpenAI/Google)
- `executeBuildPhase` step 간 체크: step 완료 → 다음 step의 `fullTask`에 "[사용자 추가 지시]" 추가 (ClaudeCode 포함 전 프로바이더)
- `MessageCheckpoint`: Sendable 래퍼로 메시지 소비 기준점 추적
- `launchFollowUpCycle`: 완료/실패 방 후속 질문 → 방 재활성화 → assemble부터 경량 워크플로우.
  - **순수 포맷 변환** (`isFormatConversionOnly`): "md로 만들어줘" 등 기존 대화 내용의 문서화 요청 → understand/design/build 전부 스킵, `handleDocumentOutput` 직접 호출.
  - **새 작업+문서**: "분석해서 md로 만들어" 등 실질적 새 작업 포함 → understand 실행하되 workLog 맥락 주입.
- `executeUnderstandPhase` TaskBrief 생성 시 workLog 컨텍스트를 intakeContext에 포함 (후속 사이클에서 대화 맥락 유지).
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
│  interceptTool(name:arguments:) → ToolInterceptResult    │
│  postProcessResponse(agentName:response:) → String       │
└───────────────────────────────────────────────────────────┘
        │                           ▲
        │ configure(context:)       │ pluginEventDelegate + interceptToolDelegate
        ▼                           │
┌─ DougPlugin Protocol ─┐    ┌─ RoomManager ─┐
│  info: PluginInfo      │    │  appendMessage → .messageAdded
│  activate() → Bool     │    │  createRoom → .roomCreated
│  deactivate()          │    │  완료/실패 → .roomCompleted/.roomFailed
│  handle(event:)        │    │  도구 실행 → .toolExecutionStarted/.Completed
│  interceptToolExecution│    │  파일 I/O → .fileWritten/.fileRead
│  postProcessResponse   │    └───────────────┘
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

**관찰 이벤트** (15종):
1. RoomManager/ToolExecutor에서 `dispatchPluginEvent(.event)` 호출
2. AppDelegate가 `roomManager.pluginEventDelegate = { pluginManager.dispatch($0) }` 연결
3. PluginManager가 모든 활성 플러그인에 `handle(event:)` 브로드캐스트

이벤트: roomCreated/Completed/Failed, messageAdded, workflowPhaseChanged, toolExecutionStarted/Completed, agentInvited/ResponseReceived, approvalRequested/Resolved, fileWritten/Read

**인터셉트 훅** (동작 변경 가능):
1. ToolExecutor가 도구 실행 전 `context.interceptTool(name, args)` 호출
2. AppDelegate가 `roomManager.pluginInterceptToolDelegate = { pluginManager.interceptTool(...) }` 연결
3. PluginManager가 활성 플러그인 순회, 첫 override/block 반환 시 도구 실행 대체/차단
4. `postProcessResponse`로 에이전트 응답 후처리도 가능

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
| AgentTool.swift | ~310 | 도구 시스템 타입 (ToolRegistry 16종 도구, 코드 인텔리전스 포함) |
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
