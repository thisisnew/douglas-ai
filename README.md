# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS 플로팅 사이드바에서 동작하는 멀티 에이전트 AI 협업 도구입니다.
사이드바에 할 일을 입력하면, DOUGLAS가 팀을 구성하고 계획을 세우고 실행까지 진행합니다.

## 동작 방식

1. 사이드바에 할 일을 입력합니다
2. DOUGLAS가 의도를 파악하고, 필요하면 추가 정보를 질문합니다
3. 작업에 맞는 전문 에이전트를 자동으로 소환합니다
4. 팀이 요구사항을 분석하고 실행 계획을 세웁니다
5. 사용자가 계획을 승인하면 에이전트들이 작업을 수행합니다
6. 결과를 검토하고 작업일지를 생성합니다

에이전트를 직접 고를 필요 없이, 어떤 요청이든 동일한 흐름으로 처리됩니다.

## 주요 기능

**에이전트**
- 작업에 맞는 전문가를 자동으로 소환하고, 없으면 생성을 제안
- 에이전트별 작업 규칙 설정 (코딩 컨벤션, 브랜치 전략 등)
- 프로젝트 디렉토리 연결 및 자동 빌드 검증

**도구**
- 파일 읽기/쓰기, 셸 명령 실행
- 웹 페이지 가져오기 (Jira URL 자동 인증)
- Jira 티켓 관리 (서브태스크 생성, 상태 변경, 코멘트)
- 에이전트 초대 및 생성 제안
- 이미지 첨부 및 분석 (Vision 지원 모델)

**워크플로우**
- 8가지 의도 자동 분류: 간단한 질문, 리서치, 브레인스토밍, 문서화, 구현, 요구사항 분석, 테스트 계획, 작업 분해
- 의도별 플랜 모드 자동 선택 (skip / lite / exec)
- 단계별 승인 게이트 (계획 → 실행 → 검토)
- 토론 결과 자동 기록 (DecisionLog)

**사이드바**
- 다른 앱 위에 상시 표시, 드래그로 이동
- `Cmd+Shift+E`로 어디서든 토글
- 작업 진행 상황을 실시간으로 확인
- 메뉴바 아이콘으로 빠른 접근

## 지원하는 AI 프로바이더

| 프로바이더 | 인증 방식 | 비고 |
|-----------|----------|------|
| **Claude Code** (권장) | 없음 (CLI 기반) | 마스터 에이전트 기본값 |
| **OpenAI** | API Key (`OPENAI_API_KEY`) | GPT-4o 등 |
| **Anthropic** | API Key (`ANTHROPIC_API_KEY`) | Claude Sonnet 등 |
| **Google** | API Key (`GOOGLE_API_KEY` 또는 `GEMINI_API_KEY`) | Gemini 2.0 Flash 등 |

환경변수에 API 키가 설정되어 있으면 온보딩에서 자동으로 감지합니다.

---

## 설치

### 1. 사전 준비

macOS 14 (Sonoma) 이상이 필요합니다.

**Xcode Command Line Tools** (Swift 컴파일러, Git 포함):

터미널을 열고 (`Cmd+Space` → "터미널" 검색) 아래 명령을 실행합니다.

```bash
xcode-select --install
```

팝업이 나타나면 "설치"를 클릭하고 완료될 때까지 기다립니다.

**Node.js** (Claude Code CLI에 필요):

[nodejs.org](https://nodejs.org)에서 LTS 버전을 다운로드하여 설치합니다.
또는 Homebrew가 있으면 `brew install node`로 설치할 수 있습니다.

### 2. 빌드

터미널에서 아래 명령을 순서대로 실행합니다.

```bash
git clone https://github.com/thefarmersfront/douglas.git
cd douglas
./scripts/build-app.sh
```

첫 빌드는 수 분 걸릴 수 있습니다. 완료되면 `dist/` 폴더에 결과물이 생성됩니다.

### 3. 설치 및 실행

빌드가 끝나면 아래 명령으로 DMG를 엽니다.

```bash
open dist/DOUGLAS.dmg
```

DMG가 열리면 `DOUGLAS.app`을 `Applications` 폴더로 드래그합니다.

이후 Launchpad 또는 Applications 폴더에서 DOUGLAS를 실행합니다.

> **macOS가 앱을 차단하는 경우:**
> 1. **시스템 설정 > 개인정보 보호 및 보안**으로 이동
> 2. 하단에 "DOUGLAS이(가) 차단되었습니다" 메시지 옆 **"확인 없이 열기"** 클릭
> 3. 또는 Finder에서 앱을 **우클릭 > "열기"** 선택

### 4. 최초 실행 — 온보딩

앱을 처음 실행하면 온보딩 가이드가 나타납니다.

**1단계: Claude Code 설정**

DOUGLAS는 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)를 마스터 에이전트로 사용합니다.
앱이 자동으로 설치 여부를 감지하며, 설치되어 있지 않으면 앱 내에서 자동 설치할 수 있습니다.

설치 후 인증이 필요하면 터미널에서 `claude`를 한 번 실행하여 Anthropic 계정으로 로그인합니다.

> Claude Code 없이도 사용 가능합니다 — "건너뛰기"를 누르면 다른 AI 프로바이더를 마스터로 사용합니다.

**2단계: AI 프로바이더 선택**

서브 에이전트가 사용할 AI를 선택합니다 (OpenAI, Anthropic API, Google 등).
환경변수에 API 키(`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`)가 있으면 자동 감지됩니다.

**3단계: API 키 입력**

선택한 프로바이더의 API 키를 입력합니다. 나중에 설정할 수도 있습니다.

API 키 발급처:
- **Anthropic**: [console.anthropic.com](https://console.anthropic.com)
- **OpenAI**: [platform.openai.com](https://platform.openai.com)
- **Google**: [aistudio.google.com](https://aistudio.google.com)

---

## 개발

```bash
swift build -c release     # 릴리즈 빌드
swift build                # 디버그 빌드
swift test                 # 테스트 (740+ 테스트)
swift run DOUGLAS          # 실행
./scripts/build-app.sh     # .app 번들 + DMG 생성
```

### 요구사항

- macOS 14+, Swift 5.9+
- 외부 패키지 의존성 없음 (순수 Swift + macOS 네이티브 프레임워크)

### 프로젝트 구조

```
Sources/
├── App/          # 앱 진입점, 윈도우 관리 (NSPanel 사이드바)
├── Models/       # 데이터 모델, 도구, 워크플로우, 프로바이더 설정
├── ViewModels/   # 비즈니스 로직 (MVVM)
├── Providers/    # AI 프로바이더 구현 (Claude Code, OpenAI, Anthropic, Google)
├── Views/        # SwiftUI UI 컴포넌트
└── Resources/    # 앱 아이콘, 프로필 이미지

Tests/
├── Models/       # 모델 테스트
├── ViewModels/   # 뷰모델 테스트
├── Providers/    # 프로바이더 테스트
├── Mocks/        # MockAIProvider, MockURLProtocol
└── Helpers/      # 테스트 헬퍼 팩토리
```

### 아키텍처

- **MVVM**: Model → ViewModel → View
- **AI 프로바이더 추상화**: `AIProvider` 프로토콜 → 프로바이더별 구현
- **도구 시스템**: `AgentTool` 정의 → `ToolFormatConverter`로 프로바이더별 변환 → `ToolExecutor`에서 실행
- **워크플로우**: Intent 분류 → 7단계 (intake → intent → clarify → assemble → plan → execute → review)
- **테스트 DI**: `ProcessRunner.handler`, `MockURLProtocol`, `testProviderOverrides`

### 커밋 규칙

```
[DG] <type>: <설명>
```
type: `feat`, `fix`, `refactor`, `style`, `docs`
