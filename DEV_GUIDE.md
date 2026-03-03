# DOUGLAS 개발 가이드 (DEV_GUIDE)

이 문서는 DOUGLAS의 개발 규칙서입니다.

---

## 프로젝트 구조

```
DOUGLAS/
├── Package.swift                  # SPM, macOS 14+
├── scripts/build-app.sh           # 빌드 → .app → 코드서명 → DMG
├── ARCHITECTURE.md                # 전체 코드 분석 문서
├── DEV_GUIDE.md                   # 이 파일 (개발 규칙)
├── CLAUDE.md                      # Claude Code 세션 규칙
└── Sources/
    ├── App/                       # @main 진입점, AppDelegate
    ├── Models/                    # 데이터 모델 (Agent, ChatMessage, AgentTool, ImageAttachment, ProviderConfig, ToolExecutionContext, DependencyChecker, ProcessRunner)
    ├── ViewModels/                # 비즈니스 로직 (AgentStore, ChatViewModel, ToolExecutor, ProviderManager, RoomManager)
    ├── Providers/                 # AI 프로바이더 (AIProvider 프로토콜, ToolFormatConverter, Claude/OpenAI/Google/Anthropic)
    └── Views/                     # SwiftUI 뷰
```

## 코딩 규칙

### 아키텍처
- **MVVM 패턴**: Models / ViewModels / Views / Providers
- 모든 ViewModel: `@MainActor class: ObservableObject`
- 모든 Model: `Identifiable, Codable`
- 의존성 주입: `@EnvironmentObject`

### 윈도우 관리
- 팝업: `UtilityWindowManager.shared.open()` 사용 (`.sheet()` 금지)
- 채팅 윈도우: 독립 `NSWindow`, `isReleasedWhenClosed = false`
- 사이드바: `NSPanel` (nonactivatingPanel, utilityWindow), 화면 오른쪽 고정

### 데이터 저장
- 에이전트/프로바이더 설정: `UserDefaults`
- API 키: `KeychainHelper`
- 이미지: `~/Library/Application Support/DOUGLAS/avatars/`
- 채팅 기록: `~/Library/Application Support/DOUGLAS/chats/`
- 이미지 첨부: `~/Library/Application Support/DOUGLAS/attachments/`

### 에이전트 매니페스트 (.douglas 파일)
에이전트를 플랫폼 무관한 JSON으로 내보내기/가져오기하는 이식 포맷.

**파일 구조** (`.douglas` 확장자, 내부는 JSON):
```json
{
  "formatVersion": 1,
  "exportedAt": "2026-03-03T14:30:00Z",
  "exportedFrom": "DOUGLAS",
  "agents": [{
    "name": "백엔드 개발자",
    "persona": "시스템 프롬프트...",
    "isMaster": false,
    "providerType": "OpenAI",
    "preferredModel": "gpt-4o",
    "workingRules": "resolve된 규칙 텍스트 또는 null",
    "avatarBase64": "PNG base64 또는 null"
  }]
}
```

**Export 규칙**:
- `workingRules`: `resolve()` 호출로 파일 내용까지 인라인화 (파일 경로는 이식 불가)
- `referenceProjectPaths`: 제외 (머신 종속)
- `status`, `errorMessage`: 제외 (런타임 전용)
- `id`: 제외 (import 시 새 UUID 발급)
- API 키: 절대 포함하지 않음

**Import 규칙**:
- 마스터 에이전트(`isMaster=true`)는 건너뜀
- 이름 중복 시 "(2)", "(3)" 등 접미어 자동 추가
- `workingRules`는 `inlineText`로만 복원

**관련 코드**: `AgentManifest` (모델), `AgentPorter` (Export/Import 로직)

### UI 텍스트
- 한국어 (앱 내 모든 사용자 대면 텍스트)
- 코드 주석은 한국어/영어 혼용 가능

### 역호환
- 새 필드 추가 시 반드시 `decodeIfPresent` + 기본값 사용
- `CodingKeys`에 명시적으로 나열

### 역할 템플릿 관례
- 새 템플릿 추가: `AgentRoleTemplateRegistry.builtIn` 배열에 `AgentRoleTemplate` 추가
- 프로바이더별 힌트: `providerHints["openAI"]`, `providerHints["anthropic"]`, `providerHints["google"]`
- `resolvedPersona(for:)`: basePersona + 프로바이더 힌트 조합
- 레거시 별칭: `template(for:)`에서 `"jira_analyst"` → `requirementsAnalyst`, `"qa_engineer"` → `qaTestAutomation` 매핑
- 빌트인 9종: requirements_analyst, backend_dev, frontend_dev, qa_test_automation, qa_exploratory, qa_security, qa_code_review, tech_writer, devops_engineer

### 에이전트 생성 제안 관례
- 분석가가 `suggest_agent_creation` 도구로 에이전트 생성 제안
- `RoomAgentSuggestion`이 `Room.pendingAgentSuggestions`에 추가됨
- 사용자가 `AgentSuggestionCard`에서 승인/거부
- 승인 시 `RoomManager.approveAgentSuggestion()` → Agent 생성 + 방 초대
- `Room.needsUserAttention`: 승인 대기 or pending suggestion → 방 목록에 "확인 필요" 뱃지

### 마스터 라우팅 관례
- 분석가 에이전트 존재 시: 복잡한 작업 → 분석가 우선 위임 (분석가가 팀 빌딩 담당)
- 분석가 부재 시: `suggest_agent`로 분석가 생성 제안
- 단순 작업: 해당 에이전트에 직접 delegate

### 토론 산출물 관례
- 산출물 블록 형식: `` ```artifact:<type> title="제목"\n내용\n``` ``
- type 종류: `api_spec`, `test_plan`, `task_breakdown`, `architecture_decision`, `generic`
- `ArtifactParser.extractArtifacts(from:producedBy:)`: 메시지에서 산출물 자동 추출
- `ArtifactParser.stripArtifactBlocks(from:)`: 채팅 표시용 블록 제거
- 같은 type+title의 산출물이 이미 있으면 version 자동 증가

### 컨텍스트 압축 관례
- 토론 종료 → `generateBriefing()` → JSON 브리핑 → `Room.briefing`
- 계획 수립: 브리핑 + 산출물만 전달 (전체 히스토리 대신)
- 실행 단계: `buildRoomHistory(limit: 5)` — 브리핑 + 최근 5개 메시지만
- 브리핑 없으면 기존 히스토리 폴백 (역호환)

### Tool Use (도구) 관례
- 새 도구 추가: `ToolRegistry.allTools`에 `AgentTool` 추가 + `ToolExecutor.executeSingleTool()`에 case 추가
- 도구 정의는 `AgentTool`로 프로바이더 무관하게 정의, 프로바이더별 형식 변환은 `ToolFormatConverter` 담당
- 모든 에이전트는 전체 도구 보유 (`Agent.resolvedToolIDs == ToolRegistry.allToolIDs`)
- `ToolExecutor.smartSend()`: 도구 미사용 에이전트나 미지원 프로바이더는 자동으로 기존 `sendMessage()` 폴백
- 도구 루프 최대 반복: 10회 (`ToolExecutor.maxIterations`)
- ClaudeCodeProvider는 `supportsToolCalling = false` (CLI가 자체 도구 보유)
- `ToolExecutionContext`에 `suggestAgentCreation` 콜백 — `suggest_agent_creation` 도구 실행 시 방에 제안 추가
- 빌드/QA 루프는 시스템이 하드코딩하지 않음 — 에이전트가 계획에서 직접 shell_exec으로 처리

---

## 필수 규칙: 모든 작업 후 반드시 수행

1. **빌드 검증**: `swift build -c release` 성공 확인
2. **Git 커밋**: 아래 형식으로 커밋
3. **ARCHITECTURE.md 업데이트**: 구조 변경 시 해당 섹션 수정
4. **이 문서 업데이트**: 규칙/관례 변경 시 반영

## 커밋 메시지 형식

```
[AM] <type>: <한줄 설명>

<상세 내용 (선택)>

Files changed:
- path/to/file1.swift
- path/to/file2.swift
```

**type 종류**: feat (기능), fix (버그), refactor (리팩토링), style (UI), docs (문서)

---

## 코지 게임 UI 스타일 가이드

### 기본 원칙
- 기본 테마는 `.cozyGame` — 따뜻한 크림/파스텔 톤 + 둥근 모서리 + 소프트 그림자
- 모든 폰트는 SF Rounded (`.fontDesign(.rounded)` 전역 적용됨)
- 뷰에서 색상은 반드시 `@Environment(\.colorPalette) private var palette` 사용

### 버튼 스타일
- 주요 액션 버튼: `CozyButtonStyle(.accent)` 사용 (3D 눌림 효과)
- 보조 버튼: `CozyButtonStyle(.cream)`, `.blue`, `.green`
- 시트 액션 버튼은 모두 `CozyButtonStyle` 적용

### 패널/카드
- 카드형 컨테이너: `palette.panelGradient` 배경 + `palette.cardBorder.opacity(0.2)` stroke
- 모서리 반경: `DesignTokens.CozyGame.cardRadius` (16) 또는 `panelRadius` (18)
- 그림자: `palette.sidebarShadow` + radius 4~6, y: 2

### 구분선
- `Divider()` 대신 그라데이션 구분선 사용:
  ```swift
  Rectangle()
      .fill(LinearGradient(colors: [.clear, palette.cardBorder.opacity(0.3), .clear],
                           startPoint: .leading, endPoint: .trailing))
      .frame(height: 1)
  ```

### 입력 필드
- 모서리: `DesignTokens.CozyGame.cardRadius`
- 테두리: `palette.cardBorder.opacity(0.3)` stroke (1px)
- 배경: 소프트 패널 그라데이션

### 애니메이션
- 상호작용 전환: `.dgSpring` (response: 0.35, dampingFraction: 0.7)
- 바운스 효과: `.dgBounce` (response: 0.4, dampingFraction: 0.6)
- 기존 `.easeInOut` 사용도 허용 (미세 전환에 한함)

### 아바타
- `RoundedRectangle(cornerRadius: size * 0.28)` 사용 (원형 아님)
- 소프트 border: `palette.avatarBorder.opacity(0.4)`

### 프로그레스 바
- `CozyProgressBar(value:total:)` 사용 — 둥근 트랙 + 그라데이션 fill

---

## 플러그인 개발 가이드

### 새 플러그인 만들기

1. `Sources/Plugins/{Name}/` 디렉토리 생성
2. `DougPlugin` 프로토콜 구현:
   ```swift
   @MainActor
   final class MyPlugin: DougPlugin {
       let info = PluginInfo(id: "my-plugin", name: "내 플러그인", ...)
       private(set) var isActive = false
       let configFields: [PluginConfigField] = [...]

       func configure(context: PluginContext) { /* 컨텍스트 저장 */ }
       func activate() async -> Bool { /* 연결/초기화 */ }
       func deactivate() async { /* 정리 */ }
       func handle(event: PluginEvent) async { /* 이벤트 처리 */ }
   }
   ```
3. `PluginManager.discoverPlugins()`에 인스턴스 추가
4. 테스트 작성 (`Tests/Plugins/`)

### 규칙

- **비밀 값은 `isSecret: true`**: `PluginConfigStore`가 KeychainHelper로 암호화 저장
- **`PluginContext`만 사용**: RoomManager/AgentStore 직접 참조 금지
- **`@MainActor` 필수**: 플러그인 프로토콜이 MainActor 바운드
- **비활성 시 리소스 해제**: `deactivate()`에서 WebSocket/타이머 등 정리

### 사용 가능한 이벤트 (PluginEvent)

| 이벤트 | 시점 |
|--------|------|
| `.roomCreated(roomID, title)` | 방 생성 직후 |
| `.roomCompleted(roomID, title)` | 워크플로우 완료 시 |
| `.roomFailed(roomID, title)` | 워크플로우 실패 시 |
| `.messageAdded(roomID, message)` | 메시지 추가 시 (모든 역할) |
| `.workflowPhaseChanged(roomID, phase)` | 워크플로우 단계 전환 시 |

### 플러그인 빌더 (노코드 생성)

설정 → 플러그인 → "만들기" 버튼으로 `PluginBuilderSheet` 시트를 열 수 있다.

- **3가지 액션 타입**: webhook (curl POST), shell (쉘 명령), notification (osascript)
- **생성 흐름**: 이름/설명 입력 → 이벤트 토글 → 액션 설정 → "만들기" → 자동 설치
- **ScriptGenerator**: `HandlerConfig` → 쉘 스크립트 자동 생성
- **PluginSlug**: 한국어 이름 → ASCII 슬러그 (Foundation `StringTransform.toLatin + .stripDiacritics`)
- **에디터 링크**: 생성된 플러그인의 "스크립트 열기" 버튼으로 Finder에서 직접 편집 가능
- 생성된 플러그인은 `~/Library/Application Support/DOUGLAS/Plugins/{id}/`에 저장

---

## 보안 규칙

### API 키 관리
- API 키는 **반드시 HTTP 헤더**로 전송 (URL 쿼리스트링 금지)
  - Google: `x-goog-api-key` 헤더
  - OpenAI/Anthropic: `Authorization: Bearer` 헤더
- 키 로컬 저장: `KeychainHelper` 사용 (ChaChaPoly 암호화)
- 키 없는 프로바이더 요청: `guard let key ... else { throw AIProviderError.noAPIKey }` — 빈 문자열 폴백 금지

### 파일 시스템 접근 (ToolExecutor)
- `file_read`/`file_write` 도구는 반드시 `isPathAllowed()` 검증 후 실행
- 허용 경로: `$HOME` 하위, `/tmp`, `/var/folders` (NSTemporaryDirectory)
- 차단 경로: `/etc`, `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `~/.ssh`, `~/.gnupg`, `~/Library/Keychains`
- 경로 해석: `URL.standardized`로 심링크·`../` 해석 후 검증

### Force Unwrap 금지
- `applicationSupportDirectory` 등 시스템 경로에 `.first!` 사용 금지
- `guard let ... else { return }` 또는 기본값 폴백 패턴 사용

---

## 테스트 규칙

### 명령어
- `swift test` — 전체 테스트 실행 (789개)
- `swift test --enable-code-coverage` — 커버리지 포함 실행
- `xcrun llvm-cov report ...` — 커버리지 리포트 조회

### 테스트 프레임워크
- **Swift Testing** (`@Test`, `#expect`, `@Suite`, `.serialized`)
- XCTest 아님 — `import Testing` 사용

### DI 패턴 (테스트 가능성)

**ProcessRunner** (`Sources/Models/ProcessRunner.swift`):
- `Process()` 직접 사용 금지 → `ProcessRunner.run()` 사용
- 테스트에서 `ProcessRunner.handler = { ... }` 로 mock 주입
- 반드시 `defer { ProcessRunner.handler = nil }` 로 정리

**ProviderManager.testProviderOverrides**:
- `provider(named:)` 호출 시 인스턴스 딕셔너리에서 우선 반환
- 인스턴스 레벨이므로 병렬 테스트 안전 (static 아님)
- 사용: `providerManager.testProviderOverrides["OpenAI"] = mockProvider`

**ToolExecutor.urlSession**:
- `URLSession.shared` 직접 사용 대신 `ToolExecutor.urlSession` 사용
- 테스트에서 MockURLProtocol 기반 세션 주입
- `defer { ToolExecutor.urlSession = .shared }` 로 정리

### MockURLProtocol 주의사항
- `MockURLProtocol.requestHandler`는 전역 static → 병렬 테스트 간 경쟁 조건 발생
- HTTP 모킹 테스트 스위트는 반드시 `.serialized` 사용
- 다른 스위트와 동시 실행 시에도 충돌 가능 → 네트워크 의존 테스트는 최소화

### 테스트 헬퍼 (`Tests/Helpers/TestHelpers.swift`)
- `makeTestAgent()`, `makeTestDefaults()`, `makeTestRoom()` 등 팩토리 함수
- `makeTestProviderConfig()` — 격리된 ProviderConfig 생성
- 테스트 간 격리를 위해 항상 새 `UserDefaults(suiteName:)` 사용

### 모킹 (`Tests/Mocks/`)
- `MockAIProvider`: `sendMessageResult`, `sendMessageResults` (순차), `fetchModelsResult`
- `MockURLProtocol`: `requestHandler` 클로저로 HTTP 응답 제어

---

## 빌드 루프 (Phase B)

### BuildLoopRunner
- `runBuild(command:, workingDirectory:)` — ProcessRunner.run() 사용, nvm/homebrew PATH 자동 설정
- 빌드 출력 15,000자 초과 시 앞부분(3,000) + 뒷부분(12,000) 보존 (에러는 보통 뒤에 있으므로)
- `buildFixPrompt()` — 빌드 오류를 에이전트에게 전달하는 프롬프트 생성

### 프로젝트 경로 규칙
- `Room.projectPath` — 방 생성 시 선택한 프로젝트 디렉토리 경로
- `ToolExecutor.resolvePath()` — 상대 경로를 projectPath 기준으로 해석 (`src/main.swift` → `/path/to/project/src/main.swift`)
- `isPathAllowed(_, projectPath:)` — projectPath도 허용 경로에 추가
- `executeShellExec` — `working_directory` 미지정 시 projectPath를 기본값으로 사용

### FileWriteTracker
- Swift `actor` — 병렬 에이전트 실행 시 파일 쓰기 충돌 감지
- 단계(step)별 `reset()` 호출로 초기화
- 충돌 발생 시 `.error` 타입 시스템 메시지로 경고

### 빌드 명령 자동 감지
CreateRoomSheet에서 프로젝트 디렉토리 선택 시 다음 파일로 빌드 명령 자동 감지:
- `Package.swift` → `swift build`
- `package.json` → `npm run build`
- `Makefile` → `make`
- `Cargo.toml` → `cargo build`
- `build.gradle` / `build.gradle.kts` → `./gradlew build`

### 테스트 명령 자동 감지
CreateRoomSheet에서 프로젝트 디렉토리 선택 시 다음 파일로 테스트 명령 자동 감지:
- `Package.swift` → `swift test`
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `build.gradle` / `build.gradle.kts` → `./gradlew test`

---

## QA 루프 (Phase C)

### QAResult / QALoopStatus
- `QAResult` — `BuildResult`와 동일 구조 (success, output, exitCode, timestamp)
- `QALoopStatus` — idle, testing, analyzing, passed, failed

### QA 루프 실행 흐름
- 빌드 루프 성공 후 `Room.testCommand`가 있으면 자동 실행
- `BuildLoopRunner.runTests(command:, workingDirectory:)` — runBuild와 동일 패턴
- 실패 시 `qaFixPrompt()` → QA 에이전트(`roleTemplateID == "qa_engineer"`)에게 수정 요청 → 재테스트 (최대 `maxQARetries`회)
- `qaAgentID(in:)` — QA 역할 에이전트 우선 선택, 없으면 첫 에이전트

---

## 승인 게이트 (Phase C)

### RoomStep
- `RoomPlan.steps: [RoomStep]` — 기존 `[String]`에서 변경
- `RoomStep(text:, requiresApproval:)` — 승인 필요 플래그
- `ExpressibleByStringLiteral` 지원 — `"단계"` 문자열 리터럴 사용 가능
- 커스텀 Codable: plain String ↔ `{"text":..., "requires_approval":true}` 혼합 지원

### 승인 흐름
- `executeRoomWork()`에서 `step.requiresApproval == true` 감지
- `.awaitingApproval` 상태 전환 + `.approvalRequest` 메시지 전송
- `CheckedContinuation`으로 비동기 일시 정지
- `approveStep(roomID:)` → `.inProgress` 복귀, `rejectStep(roomID:)` → `.failed`
- `deleteRoom()` / `completeRoom()` — 대기 중인 continuation 자동 해제 (누수 방지)

---

## Jira 쓰기 도구 (Phase C)

### 3개 도구
- `jira_create_subtask` — POST `/rest/api/3/issue`, parent_key에서 projectKey 추론
- `jira_update_status` — GET transitions → 대소문자 무시 이름 매칭 → POST
- `jira_add_comment` — POST ADF 형식 코멘트

### 공통
- `makeJiraRequest(path:method:body:)` — JiraConfig.shared 인증 + JSON 헤더
- Jira 미설정 시 에러 메시지 반환

---

## ARCHITECTURE.md 동기화 규칙

- 새 파일 추가 → 프로젝트 구조 섹션에 추가
- 새 ViewModel → 핵심 컴포넌트 섹션에 설명 추가
- 새 View → 뷰 레이어 섹션에 설명 추가
- Provider 변경 → Provider 테이블 업데이트
- 해결된 이슈 → 해결된 기술 이슈 섹션에 추가
