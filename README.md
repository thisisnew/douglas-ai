# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS 플로팅 사이드바에서 동작하는 멀티 에이전트 AI 협업 도구입니다.
사이드바에 할 일을 입력하면, DOUGLAS가 팀을 구성하고 계획을 세우고 실행까지 진행합니다.

![Platform](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Architecture](https://img.shields.io/badge/MVVM-green)

## 동작 방식

```
입력 → 요건 확인 → 팀 구성 → 분석 → 계획 → 실행 → 검토
```

1. 사이드바에 할 일을 입력합니다
2. DOUGLAS가 필요한 정보를 질문합니다
3. 작업에 맞는 전문 에이전트를 자동으로 소환합니다
4. 팀이 요구사항을 분석하고 실행 계획을 세웁니다
5. 사용자가 계획을 승인하면 에이전트들이 작업을 실행합니다
6. 결과를 검토하고 작업일지를 생성합니다

사용자가 에이전트를 직접 고를 필요가 없습니다. 단순한 요청이든 복잡한 요청이든, 동일한 프로세스를 거칩니다.

## 주요 기능

### 에이전트

- **자동 팀 구성** — 작업 내용에 따라 적합한 전문가를 자동으로 소환하고, 없으면 생성을 제안
- **작업 규칙** — 에이전트별 코딩 컨벤션, 브랜치 전략 등 구체적 지시사항 설정 (텍스트 직접 입력 또는 `.cursorrules` 등 파일 참조)
- **프로젝트 연동** — 디렉토리 연결, 빌드 루프, 프로젝트별 설정 (`playbook.json`)

### 도구 (Tool Use)

에이전트는 12종의 도구를 사용할 수 있습니다:

| 분류 | 도구 |
|------|------|
| 파일 | 읽기, 쓰기 |
| 실행 | 셸 명령 |
| 웹 | 검색, 페이지 가져오기 |
| 협업 | 에이전트 초대/목록, 에이전트 생성 제안, 사용자에게 질문 |
| Jira | 서브태스크 생성, 상태 변경, 코멘트 작성 |

### UI

- **플로팅 사이드바** — 다른 앱 위에 상시 표시, 드래그로 이동/리사이즈
- **실시간 진행 표시** — 작업 중 활동 로그를 클릭하여 상세 확인
- **글로벌 핫키** — `Cmd+Shift+E`로 어디서든 사이드바 토글
- **이미지 첨부** — 스크린샷 등을 첨부하여 Vision API로 분석

## 시작하기

### 1. AI 프로바이더 준비 (택 1)

| 방법 | 준비 |
|------|------|
| **Claude Code CLI** (권장) | `npm install -g @anthropic-ai/claude-code` 후 `claude` 로그인 (Node.js 18+ 필요) |
| **Anthropic API** | [console.anthropic.com](https://console.anthropic.com)에서 API Key 발급 |
| **OpenAI API** | [platform.openai.com](https://platform.openai.com)에서 API Key 발급 |
| **Google API** | [aistudio.google.com](https://aistudio.google.com)에서 API Key 발급 |

### 2. 설치

**DMG (일반 사용자)**

Releases에서 `DOUGLAS.dmg`를 다운로드하고 `Applications`에 드래그합니다.

> 최초 실행 시 macOS가 차단하면: `시스템 설정 > 개인정보 보호 및 보안 > "확인 없이 열기"`

**소스에서 빌드 (개발자)**

```bash
swift build -c release    # 빌드
swift run DOUGLAS          # 실행
./scripts/build-app.sh     # .app + DMG 생성
```

### 3. 온보딩

앱 실행 시 온보딩 가이드가 환경을 자동 감지하고 설정을 도와줍니다.

## 개발

```bash
swift build -c release    # 빌드 (커밋 전 필수)
swift test                # 테스트
```

### 프로젝트 구조

```
Sources/
├── App/            # 진입점, AppDelegate, 윈도우 관리
├── Models/         # 데이터 모델 (Agent, Room, ChatMessage 등)
├── ViewModels/     # 비즈니스 로직 (RoomManager, ToolExecutor 등)
├── Providers/      # AI 프로바이더 (Claude Code, Anthropic, OpenAI, Google)
└── Views/          # SwiftUI 뷰
```

### 커밋 규칙

```
[DG] <type>: <설명>
# type: feat, fix, refactor, style, docs
```

## 라이선스

Private project.
