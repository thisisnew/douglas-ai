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
- 에이전트별 도구 설정: `Agent.capabilityPreset` + `Agent.enabledToolIDs`로 결정
- `ToolExecutor.smartSend()`: 도구 미사용 에이전트나 미지원 프로바이더는 자동으로 기존 `sendMessage()` 폴백
- 도구 루프 최대 반복: 10회 (`ToolExecutor.maxIterations`)
- ClaudeCodeProvider는 `supportsToolCalling = false` (CLI가 자체 도구 보유)

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
- `swift test` — 전체 테스트 실행 (709개)
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

---

## ARCHITECTURE.md 동기화 규칙

- 새 파일 추가 → 프로젝트 구조 섹션에 추가
- 새 ViewModel → 핵심 컴포넌트 섹션에 설명 추가
- 새 View → 뷰 레이어 섹션에 설명 추가
- Provider 변경 → Provider 테이블 업데이트
- 해결된 이슈 → 해결된 기술 이슈 섹션에 추가
