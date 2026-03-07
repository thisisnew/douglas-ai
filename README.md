# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS 화면 옆에 항상 떠 있는 **멀티에이전트 AI 비서**입니다.
메뉴바에 상주하면서, 필요할 때 사이드바를 열어 대화하면 됩니다.
작업이 복잡하면 AI 전문가 여러 명이 자동으로 팀을 이뤄 처리합니다.

## 이런 걸 할 수 있어요

- 코드 작성, 수정, 개선
- 파일 정리, 폴더 관리
- 웹 검색, 자료 조사
- 브레인스토밍, 문서 작성
- 사진/스크린샷/PDF 분석 (드래그앤드롭으로 첨부)
- 여러 전문가 AI가 협업하는 복합 작업
- Jira 연동 (티켓 조회, 서브태스크 생성, 상태 변경)
- Slack 연동 (채널 메시지 수신/발송)

한 줄로 지시하면 알아서 계획을 세우고, 필요하면 질문하고, 결과를 보여줍니다.

---

## 설치

### 준비물

- **Mac** (macOS 14 Sonoma 이상)

### 순서

**1) 다운로드**

[최신 릴리즈](https://github.com/thefarmersfront/douglas/releases/latest)에서 **DOUGLAS.dmg** 를 다운로드합니다.

**2) 앱 설치**

다운로드한 `DOUGLAS.dmg`를 더블클릭하면 창이 열립니다.
DOUGLAS 아이콘을 Applications 폴더로 드래그합니다.

**3) 앱 실행**

Launchpad에서 DOUGLAS를 찾아 클릭합니다.

> **"확인되지 않은 개발자" 경고가 뜨면:**
>
> 1. **시스템 설정** 열기 (좌측 상단 Apple 메뉴)
> 2. **개인정보 보호 및 보안** 클릭
> 3. 아래쪽에 "DOUGLAS" 관련 메시지 옆 **"확인 없이 열기"** 클릭

## 초기 설정

앱을 처음 열면 설정 화면이 나타납니다.

### 1단계: Claude Code

DOUGLAS의 핵심 AI입니다. 앱이 자동으로 감지합니다.

- 이미 설치되어 있으면 → "다음" 클릭
- 설치 안 되어 있으면 → "설치" 버튼 클릭 (자동 설치)
- 설치 후 인증 필요 시 → 터미널에서 `claude` 입력 후 로그인
- 사용 안 하려면 → "건너뛰기" 클릭

### 2단계: AI 선택

추가로 사용할 AI를 고릅니다. 체크만 하면 됩니다.

### 3단계: API 키 입력

선택한 AI의 API 키를 입력합니다. 모르면 "나중에 설정"을 눌러도 됩니다.

API 키 받는 곳:
- **Anthropic** — [console.anthropic.com](https://console.anthropic.com)
- **OpenAI** — [platform.openai.com](https://platform.openai.com)
- **Google** — [aistudio.google.com](https://aistudio.google.com)

---

## 사용법

### 기본 조작

DOUGLAS는 메뉴바(화면 상단 오른쪽)에 아이콘으로 상주합니다.

| 동작 | 결과 |
|------|------|
| 아이콘 **클릭** | 사이드바 열기/닫기 |
| 아이콘 **더블클릭** | 사이드바를 화면 오른쪽 끝으로 이동 |
| 아이콘 **우클릭** | 메뉴 (종료 등) |

사이드바 하단의 입력창에 할 일을 적고 Enter를 누르면 DOUGLAS가 작업을 시작합니다.
DOUGLAS가 질문하면 답해주세요 — 나머지는 알아서 합니다.

### 방 (Room)

DOUGLAS가 작업을 처리할 때 **방**이 만들어집니다. 방은 하나의 작업 단위입니다.

- 사이드바 중간에 방 목록이 보입니다
- **"+ 새 방"** 버튼으로 직접 방을 만들 수도 있습니다 (에이전트 선택 + 파일 첨부 가능)
- 상단 필터 탭으로 상태별로 볼 수 있습니다: 전체 / 진행 / 완료 / 실패
- 검색창에 키워드를 입력하면 방 제목과 대화 내용에서 검색합니다
- 방을 클릭하면 별도 창에서 자세한 내용을 볼 수 있습니다

### 에이전트 팀

사이드바 상단에 에이전트(AI 전문가) 목록이 가로로 나열됩니다.

- **"+"** 버튼으로 새 전문가를 추가할 수 있습니다
- 각 전문가에게 역할과 성격을 지정할 수 있습니다
- 전문가를 **우클릭**하면 수정/정보/삭제 메뉴가 나옵니다
- 드래그해서 순서를 바꿀 수 있습니다
- 상태 표시: 초록(대기) / 주황(작업 중) / 빨강(바쁨)

복잡한 작업을 지시하면 DOUGLAS가 자동으로 적합한 전문가를 방에 초대해서 협업합니다.

### `/@` 멘션으로 전문가 호출

대화 중 특정 전문가를 직접 부르고 싶으면 `/@`를 입력하세요.

- `/@번역가 이거 뭐야?` → 번역가가 방에 초대되어 바로 답변
- `/@번역` 처럼 이름 앞부분만 입력해도 자동 매칭됩니다
- `/@` 입력 시 전문가 목록이 자동완성으로 뜹니다
- 한 메시지에 여러 명을 동시에 호출할 수도 있습니다: `/@번역가 /@백엔드 이거 봐줘`

### 파일 첨부

- 입력창 왼쪽의 첨부 버튼을 클릭하거나
- 파일을 입력창에 **드래그앤드롭**하면 첨부됩니다
- 지원: JPG, PNG, GIF, WebP, PDF, TXT, CSV, JSON, MD, XML, YAML, HTML, CSS, Swift, JS, TS, Python, Shell 등

### 테마 변경

사이드바 상단의 설정에서 테마를 바꿀 수 있습니다.

- **코지 게임** — 둥글둥글한 게임 느낌 (기본)
- **파스텔** — 부드러운 라벤더-핑크 톤
- **다크** — 어두운 배경
- **따뜻한** — 따뜻한 톤
- **커스텀** — 직접 액센트 색상을 골라서 사용

### 단축키

| 단축키 | 기능 |
|--------|------|
| `Cmd+Shift+E` | 사이드바 열기/닫기 (어떤 앱에서든 동작) |
| `Enter` | 메시지 전송 |
| `Shift+Enter` | 줄바꿈 |

### 사이드바 위치 이동

사이드바 상단 영역을 **드래그**하면 원하는 위치로 옮길 수 있습니다.
드래그하는 동안 사이드바가 다른 창 위로 올라오고, 놓으면 다시 뒤로 내려갑니다.

---

## 팁

- **구체적으로 지시할수록 결과가 좋습니다.** "이거 고쳐줘" 보다 "로그인 페이지에서 비밀번호 입력 후 엔터 치면 아무 반응이 없는 문제 해결해줘"가 낫습니다.
- **DOUGLAS가 질문하면 꼭 답해주세요.** 작업 방향을 잡기 위해 확인하는 겁니다.
- 작업 기록은 사이드바 상단의 **시계 아이콘**으로 확인할 수 있습니다.
- API 키 변경은 사이드바 상단의 **톱니바퀴 아이콘**에서 할 수 있습니다.

## 종료

메뉴바 아이콘을 **우클릭** → **"종료"** 를 클릭합니다.

---

## 아키텍처 (개발자용)

### 기술 스택

| 항목 | 기술 |
|------|------|
| 플랫폼 | macOS 14+ (Sonoma) |
| 언어 | Swift 5.9 |
| UI | SwiftUI + AppKit (NSPanel, NSWindow) |
| 빌드 | Swift Package Manager (SPM) |
| 배포 | .app 번들 → .dmg (Ad-hoc 코드 서명) |
| 테스트 | Swift Testing (835+ 테스트) |
| 린트 | SwiftLint |
| CI | GitHub Actions (태그/수동 트리거, macOS runner) |

### MVVM 패턴

```
┌─────────────────┐     ┌────────────────────┐     ┌───────────────────┐
│     Models       │ ←── │    ViewModels       │ ←── │      Views        │
│                  │     │                    │     │                   │
│ Room + 값 객체   │     │ RoomManager (3파일) │     │ FloatingSidebarView│
│ Agent            │     │ ChatViewModel      │     │ RoomChatView      │
│ ChatMessage      │     │ AgentStore         │     │ ChatView          │
│ AgentTool        │     │ ProviderManager    │     │ CreateRoomSheet   │
│ WorkflowIntent   │     │ ToolExecutor       │     │ SettingsTabView   │
│ IntentClassifier │     │ BuildLoopRunner    │     │ OnboardingView    │
└─────────────────┘     └────────────────────┘     └───────────────────┘
                               │
                       ┌───────┴────────┐
                       │   Providers    │
                       │                │
                       │ ClaudeCode     │
                       │ OpenAI         │
                       │ Anthropic      │
                       │ Google         │
                       └────────────────┘
```

**데이터 흐름**:
- `EnvironmentObject`로 전역 상태 공유: `AgentStore`, `ProviderManager`, `ChatViewModel`, `RoomManager`
- `UserDefaults`로 영속성 보장 (에이전트 목록, 프로바이더 설정, 방 데이터)
- `KeychainHelper` (ChaChaPoly 암호화)로 API 키 보안 저장
- 파일시스템으로 채팅 이력, 에이전트 이미지, 첨부 파일 영속화 (`~/Library/Application Support/DOUGLAS/`)

---

### 프로젝트 구조

```
DOUGLAS/
├── Package.swift                        # SPM 패키지 정의
├── Makefile                             # 빌드/테스트/린트 통합 진입점
├── CLAUDE.md                            # 개발 규칙
├── ARCHITECTURE.md                      # 코드 분석 문서
├── WORKFLOW_SPEC.md                     # 워크플로우 명세서
├── DEV_GUIDE.md                         # 개발 가이드
├── scripts/
│   ├── build-app.sh                     # .app → .dmg 빌드
│   ├── pre-commit                       # pre-commit 훅 (빌드+린트)
│   └── commit-msg                       # 커밋 메시지 형식 검증
├── Sources/
│   ├── App/                             # 앱 진입점, AppDelegate, 윈도우 관리
│   ├── Models/                          # 도메인 모델 (43개 파일)
│   ├── ViewModels/                      # 비즈니스 로직 (14개 파일)
│   ├── Providers/                       # AI 프로바이더 (6개 파일)
│   ├── Plugins/                         # 플러그인 시스템 (9개 파일)
│   └── Views/                           # UI 레이어 (28개 파일)
└── Tests/                               # 테스트 (835+ 테스트)
```

---

### 도메인 모델

#### Room (작업의 중심)

`Room`은 하나의 작업 단위를 나타내는 핵심 모델입니다. 사용자의 요청을 받아 에이전트를 배치하고, 토론 → 계획 → 실행 → 검토까지 전체 워크플로우를 관리합니다.

Room은 5개 **값 객체**로 도메인을 구조화합니다:

```
Room (926줄)
├── workflowState: WorkflowState        # intent, phase 추적
│   ├── intent: WorkflowIntent?         # quickAnswer / task / discussion
│   ├── currentPhase: WorkflowPhase?    # understand → assemble → design → build → review → deliver
│   ├── completedPhases: Set<WorkflowPhase>
│   ├── needsPlan: Bool
│   ├── documentType: DocumentType?
│   └── autoDocOutput: Bool
│
├── clarifyContext: ClarifyContext       # 복명복창 단계 컨텍스트
│   ├── intakeData: IntakeData?         # 입력 파싱 결과 (Jira 등)
│   ├── clarifySummary: String?         # DOUGLAS가 이해한 내용 요약
│   ├── clarifyQuestionCount: Int
│   ├── assumptions: [WorkflowAssumption]?
│   ├── userAnswers: [UserAnswer]?
│   ├── delegationInfo: DelegationInfo? # 에이전트 위임 정보
│   └── playbook: ProjectPlaybook?
│
├── projectContext: ProjectContext       # 프로젝트 연동 정보
│   ├── projectPaths: [String]
│   ├── worktreePath: String?
│   ├── buildCommand: String?
│   └── testCommand: String?
│
├── discussion: DiscussionSession       # 토론 세션
│   ├── currentRound: Int
│   ├── isCheckpoint: Bool
│   ├── decisionLog: [DecisionEntry]
│   ├── artifacts: [DiscussionArtifact]
│   └── briefing: RoomBriefing?
│
├── buildQA: BuildQAState               # 빌드/QA 루프 상태
│   ├── buildLoopStatus / buildRetryCount / maxBuildRetries / lastBuildResult
│   └── qaLoopStatus / qaRetryCount / maxQARetries / lastQAResult
│
├── approvalHistory: [ApprovalRecord]   # 승인/거부 이력
├── awaitingType: AwaitingType?         # 현재 대기 유형
├── requests: [DouglasRequest]          # 요청 생명주기 추적
├── followUpActions: [FollowUpAction]   # 후속 입력 분류
├── messages: [ChatMessage]             # 대화 내역
├── plan: RoomPlan?                     # 실행 계획 (버전 관리)
├── taskBrief: TaskBrief?               # 작업 요약
├── agentRoles: [String: RuntimeRole]   # 에이전트별 런타임 역할
├── deferredActions: [DeferredAction]   # 고위험 지연 실행 작업
└── workLog: WorkLog?                   # 작업 완료 일지
```

#### Agent

```swift
struct Agent: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String              // 에이전트 표시 이름
    var persona: String           // 시스템 프롬프트 (역할/성격)
    var providerName: String      // "Claude Code", "OpenAI", "Google", "Anthropic"
    var modelName: String         // "claude-sonnet-4-6", "gpt-4o" 등
    var status: AgentStatus       // idle / working / busy / error
    var isMaster: Bool            // 마스터 에이전트 여부
    var workingRules: WorkingRulesSource  // 작업 규칙 (인라인 + 파일 참조)
    var skillTags: [String]       // 기술 태그 (매칭용)
    var workModes: Set<WorkMode>  // 작업 모드 (analysis, code, document 등)
}
```

- 마스터(PM) 에이전트: 사용자 요청을 받아 방을 만들고 팀을 꾸리는 오케스트레이터
- 서브 에이전트: 전문 분야별 작업 수행자 (백엔드, 프론트엔드, QA, 기획 등)
- 12종 빌트인 프리셋 (`AgentPreset`)으로 빠른 생성 지원
- `.douglas` 파일로 에이전트 내보내기/가져오기 (`AgentManifest`)

#### WorkflowIntent (작업 의도 3종)

| Intent | 설명 | 워크플로우 단계 |
|--------|------|-----------------|
| `quickAnswer` | 단순 질문, 즉답 | understand → assemble → deliver |
| `task` | 분석/구현/문서 작성 등 복합 작업 | understand → assemble → design → build → review → deliver |
| `discussion` | 의견 교환, 브레인스토밍 | understand → assemble → design → deliver |

#### 승인 모델

| ApprovalType | 설명 |
|-------------|------|
| `clarifyApproval` | 복명복창 내용 승인 |
| `teamConfirmation` | 에이전트 구성 확인 |
| `planApproval` | 실행 계획 승인 |
| `stepApproval` | 개별 단계 승인 (고위험) |
| `lastStepConfirmation` | 마지막 단계 직전 확인 |
| `deliverApproval` | 고위험 작업 실행 승인 |
| `designApproval` | 설계/검토 단계 승인 |

모든 승인/거부 이벤트는 `ApprovalRecord`로 영속 기록됩니다.

#### 기타 주요 모델

| 모델 | 파일 | 역할 |
|------|------|------|
| `ChatMessage` | ChatMessage.swift | 메시지 (15종 MessageType, 파일 첨부, 도구 활동 추적) |
| `FileAttachment` | FileAttachment.swift | 파일 첨부 (이미지+문서, 디스크 저장, base64 로드, MIME 판별) |
| `AgentTool` | AgentTool.swift | 프로바이더 무관 도구 정의 (16종 내장 도구) |
| `IntentClassifier` | IntentClassifier.swift | Intent 분류 (규칙 기반 quickClassify → LLM 폴백) |
| `SemanticMatcher` | SemanticMatcher.swift | NLEmbedding 기반 에이전트 의미 유사도 매칭 |
| `DouglasRequest` | DouglasRequest.swift | 요청 생명주기 (IntentClassification, ConfidenceLevel) |
| `FollowUpAction` | FollowUpAction.swift | 후속 입력 분류 (6종 FollowUpType) |

---

### 워크플로우

#### 전체 흐름

사용자의 모든 요청은 아래 6단계 **상태 머신 기반** 워크플로우로 처리됩니다:

```
Understand ─→ Assemble ─→ Design ─→ Build ─→ Review ─→ Deliver
  (입력 분석,    (에이전트     (토론 +      (단계별    (검토자     (최종 전달,
   intent 분류,   매칭 +       계획 수립     실행)     리뷰)      작업 일지)
   복명복창)      팀 확인)     + 승인)
```

#### Understand 단계 (intake + intent + clarify)

1. **Intake**: 입력 파싱 (Jira URL → 티켓 정보 자동 조회 등)
2. **Intent 분류**: 규칙 기반 키워드 스코어링 → LLM 폴백 → `quickAnswer` / `task` / `discussion`
3. **Clarify (복명복창)**: DOUGLAS가 이해한 내용 요약 → 사용자 확인까지 무한 루프. 불명확하면 재질문.

#### Assemble 단계

- LLM이 에이전트 역할 요구사항 분석 → 3-tier 가중치 매칭 (skillTags x5, workModes x2, keyword+semantic x3)
- 사용자 직접 지정(`delegationInfo.explicit`) 시 최우선 배정
- `directMatch`: 사용자 입력 텍스트에서 에이전트 이름 키워드 탐색
- 매칭 결과 → 사용자에게 팀 구성 확인 요청 (에이전트 추가/제거 가능)

#### Design 단계

- **토론 모드** (`discussion`): 라운드 기반 토론 → 결론/대안/쟁점 정리
- **작업 모드** (`task`): 사전 토론 → 브리핑 생성 → 실행 계획 수립 → 사용자 승인
- 토론 중 산출물은 `artifact` 블록으로 자동 추출 → 실행 단계에서 컨텍스트로 주입
- 계획 거부 시 `plan.version + 1`로 재계획

#### Build 단계

- 승인된 계획의 각 `RoomStep`을 순차 실행
- 단계별 `StepStatus` 추적 (pending → inProgress → completed/failed)
- `requiresApproval` 단계는 실행 전 사용자 승인 필요
- 마지막 단계 직전 필수 확인 ("여기까지 괜찮다면 승인해주시면 마무리하겠습니다")
- 빌드/QA 루프: 빌드 실패 시 자동 수정 → 재빌드 (최대 3회)

#### Review 단계

- Reviewer 역할 에이전트가 Build 결과물 검토
- 검토 결과 반영 → Creator가 수정

#### Deliver 단계

- 최종 산출물 전달
- 고위험 작업(DeferredAction)은 프리뷰 + 명시적 승인 후 실행
- 문서 산출물: 설정된 폴더에 자동 저장 또는 NSSavePanel
- 작업 일지(WorkLog) 자동 생성
- 후속 요청 가능 상태로 전환

#### 공식 케이스 (A~H)

| 케이스 | 설명 | Intent |
|--------|------|--------|
| **A. 질의응답** | 단일 에이전트/DOUGLAS 직접 응답 | quickAnswer |
| **B. 단일 에이전트 토론** | 심화 질의응답, 단독 검토 | discussion (1인) |
| **C. 복수 에이전트 토론** | 라운드 기반 토론 → 결론/대안/쟁점 정리 | discussion (복수) |
| **D. 단일 에이전트 구현** | 계획 → 승인 → 실행 → 최종 승인 | task (1인) |
| **E. 복수 에이전트 구현** | 사전 토론 → 계획 → 승인 → 실행 → 최종 승인 | task (복수) |
| **F. 문서 생성** | 문서 전문가가 최종 책임, 경로만 표시 | task (documentType) |
| **G. 후속처리** | 완료 후 같은 방에서 다른 모드로 확장 | (기존 intent 위에서) |
| **H. 요건 불명확** | 재질문 후 명확해질 때까지 실행 보류 | - |

---

### ViewModels

#### RoomManager (7,118줄, 3파일)

방의 전체 생명주기를 관리하는 핵심 ViewModel입니다.

| 파일 | 줄수 | 역할 |
|------|------|------|
| `RoomManager.swift` | ~2,092 | CRUD, 승인/입력 게이트(Continuation), 상태 관리, 영속화 |
| `RoomManager+Workflow.swift` | ~4,077 | 6단계 Phase 실행 메서드 (understand~deliver) |
| `RoomManager+Discussion.swift` | ~949 | 토론 실행 + 빌드/QA 루프 |

**WorkflowHost 프로토콜**: RoomManager 추상화로 테스트 mock 지원

```swift
protocol WorkflowHost: AnyObject {
    func room(for id: UUID) -> Room?
    func updateRoom(id: UUID, _ mutate: (inout Room) -> Void)
    func appendMessage(_ message: ChatMessage, to roomID: UUID)
    // + 게이트 관리, 의존성 노출
}
```

#### 기타 ViewModels

| ViewModel | 역할 |
|-----------|------|
| `ChatViewModel` | 사용자 메시지 진입점, 마스터 오케스트레이션, 메시지 영속화 |
| `AgentStore` | 에이전트 CRUD, 마스터 생명주기 |
| `ProviderManager` | 4개 AI 프로바이더 설정 관리 |
| `ToolExecutor` | 도구 호출 루프 (smartSend → executeWithTools, 최대 10회) |
| `BuildLoopRunner` | 빌드/테스트 실행 + 자동 수정 프롬프트 |
| `AgentMatcher` | 3-tier 가중치 에이전트 매칭 |
| `DocumentExporter` | 문서 파일 자동 저장 |
| `ThemeManager` | 테마 관리 (5종 프리셋 + 커스텀) |

---

### AI Provider 레이어

모든 프로바이더는 `AIProvider` 프로토콜을 구현합니다:

| 프로바이더 | 인증 | 특징 |
|-----------|------|------|
| **Claude Code** | CLI (키 불필요) | `claude` CLI 실행, NDJSON 스트리밍, 도구 활동 실시간 파싱 |
| **OpenAI** | API Key | GPT-4o/4o-mini, Tool Use, Vision |
| **Anthropic** | API Key | Claude 4/3.5, Tool Use, Vision |
| **Google** | API Key | Gemini 2.0/1.5, Tool Use, Vision |

**공통 기능**:
- SSE 스트리밍 (실시간 텍스트 출력)
- Tool Use (Function Calling) — 각 프로바이더 형식 자동 변환
- Vision (이미지 분석) — base64 인라인 이미지 블록
- 모델 티어링: 경량 모델(`defaultLightModelName`)을 분류/매칭/브리핑에 사용

---

### 도구 시스템 (16종)

모든 에이전트는 전체 도구에 접근 가능합니다:

| 도구 | 설명 |
|------|------|
| `file_read` | 파일 읽기 (50K자 제한) |
| `file_write` | 파일 쓰기 |
| `shell_exec` | zsh 명령어 실행 (30K자 출력 제한) |
| `web_search` | DuckDuckGo 웹 검색 (상위 8건) |
| `web_fetch` | URL 가져오기 + Jira REST API 자동 변환 |
| `invite_agent` | 방에 에이전트 런타임 초대 |
| `list_agents` | 등록된 에이전트 목록 조회 |
| `suggest_agent_creation` | 새 에이전트 생성 제안 |
| `ask_user` | 사용자에게 질문 (Clarify 단계 전용) |
| `code_search` | ripgrep 기반 코드 패턴 검색 |
| `code_symbols` | 프로젝트 심볼 정의 검색 (Swift/TS/JS/Python/Go/Rust) |
| `code_diagnostics` | 컴파일러/린터 실행 후 에러/경고 반환 |
| `code_outline` | 파일 구조 아웃라인 |
| `jira_create_subtask` | Jira 서브태스크 생성 |
| `jira_update_status` | Jira 상태 변경 |
| `jira_add_comment` | Jira 코멘트 작성 |

**경로 보안**: `$HOME`, `/tmp`만 허용. `.ssh`, `.gnupg`, `Library/Keychains` 차단. 심링크 우회 방지.

---

### 플러그인 시스템

`DougPlugin` 프로토콜 기반 확장 가능한 플러그인 아키텍처:

| 컴포넌트 | 역할 |
|----------|------|
| `PluginManager` | 플러그인 생명주기 관리 |
| `PluginContext` | 시스템 파사드 (Room/Agent 안전 API) |
| `ScriptPlugin` | 스크립트 기반 외부 플러그인 런타임 |

**내장 플러그인**:
- **Slack**: Socket Mode WebSocket 연결, 채널 ↔ Room 양방향 매핑, 메시지 파싱

---

### 상태 관리

#### Room 상태 (`RoomStatus`)

| 상태 | 색상 | 설명 |
|------|------|------|
| `planning` | 보라 | 준비 중 (intake~plan). UI 라벨은 currentPhase 기반 동적 표시 |
| `inProgress` | 주황 | 계획에 따라 실행 중 |
| `awaitingApproval` | 노랑 | 승인 게이트 대기 |
| `awaitingUserInput` | 시안 | ask_user 질문 대기 |
| `completed` | 초록 | 완료 |
| `failed` | 빨강 | 오류 또는 승인 거부 |

#### Agent 상태 (`AgentStatus`)

| 상태 | 색상 | 조건 |
|------|------|------|
| `idle` | 회색 | 활성 방 0개 |
| `working` | 주황 | 활성 방 1~2개 |
| `busy` | 빨강 | 활성 방 3개 이상 |
| `error` | 빨강 | 실행 중 오류 발생 |

---

## 소스에서 빌드 (개발자용)

일반 사용자는 위의 [설치](#설치) 섹션을 이용하세요. 소스 빌드는 개발에 참여하는 분만 필요합니다.

### 준비물

- **Xcode 15 이상** (Command Line Tools만으로는 빌드할 수 없습니다)
- **Node.js** LTS ([nodejs.org](https://nodejs.org))

> `xcode-select --install`로 설치하는 Command Line Tools와 **Xcode 앱**은 다릅니다.
> App Store에서 Xcode를 설치한 뒤 `sudo xcode-select -s /Applications/Xcode.app`을 실행하세요.

### 빌드

```bash
git clone https://github.com/thefarmersfront/douglas.git
cd douglas
make build          # swift build -c release
```

### 테스트

```bash
make test           # swift test (835+ 테스트)
```

### 린트

```bash
make lint           # SwiftLint
```

### 배포 빌드

```bash
./scripts/build-app.sh    # .app → 코드서명 → DMG 생성
```

빌드 완료 후 `dist/DOUGLAS.dmg`가 생성됩니다.

### Git 훅 설치

```bash
make install-hooks   # pre-commit (빌드+린트), commit-msg (형식 검증)
```

커밋 형식: `[DG] <type>: <설명>` (type: feat, fix, refactor, style, docs)
