# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS 플로팅 사이드바 기반 멀티 에이전트 AI 협업 도구.

마스터 에이전트에게 지시하면, 알아서 서브 에이전트를 골라 방(Room)을 만들고, 작업을 위임하고, 결과를 취합합니다.

![Platform](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Architecture](https://img.shields.io/badge/MVVM-green)

## 동작 방식

```
사용자 → 사이드바에 입력 → 마스터 에이전트가 분석
  → 적합한 서브 에이전트 선택 → 방 생성 → 작업 위임 → 결과 취합
```

사용자가 에이전트를 직접 고르지 않습니다. 마스터가 판단합니다.

## 주요 기능

- **자동 위임** — 마스터가 요청을 분석하여 서브 에이전트 조합으로 방 구성
- **병렬 / 순차 처리** — 여러 에이전트 동시 투입 또는 A→B 체이닝
- **Tool Use** — 파일 읽기/쓰기, 셸 실행, 웹 검색/가져오기, 에이전트 초대, Jira 연동 등 11종 도구
- **Jira 연동** — Jira Cloud 티켓 조회 + 서브태스크 생성 + 상태 변경 + 코멘트 작성
- **이미지 첨부 + Vision** — 이미지를 첨부하여 Vision API로 분석
- **플로팅 사이드바** — 다른 앱 위에 떠 있으며, 드래그로 자유 이동
- **글로벌 핫키** — `⌘⇧E` 사이드바 토글
- **역할 템플릿** — 요구사항 분석가, 백엔드/프론트엔드 개발자, QA 4종, 테크라이터, DevOps 등 9종 빌트인 프리셋
- **프로젝트 방** — 디렉토리 연동, 빌드 루프, 승인 게이트, 토론→계획→실행 워크플로우
- **온보딩** — 첫 실행 시 환경(Node.js, Git 등) + Claude Code 자동 감지, 완료 후 사이드바 자동 시작

## 지원 프로바이더

| 프로바이더 | 인증 | 비고 |
|-----------|------|------|
| Claude Code | CLI | `claude` CLI 직접 실행 |
| Anthropic | API Key | Claude 모델 (Tool Use 지원) |
| OpenAI | API Key | GPT-4o 등 (Tool Use 지원) |
| Google | API Key | Gemini 모델 (Tool Use 지원) |
| Ollama | 없음 | 로컬 모델 (llama3 등) — 비활성 |
| LM Studio | 없음 | 로컬 모델 — 비활성 |

## 설치 및 실행

### DMG로 설치 (일반 사용자)

1. `./scripts/build-app.sh` 실행 후 `dist/DOUGLAS.dmg` 획득
2. DMG를 열고 `DOUGLAS.app`을 `Applications`로 드래그
3. 최초 실행 시 macOS가 차단하면:
   - `시스템 설정 → 개인정보 보호 및 보안 → "확인 없이 열기"` 클릭
   - 또는 터미널에서: `xattr -cr /Applications/DOUGLAS.app`
4. 앱 실행 → 온보딩 가이드가 자동으로 시작됨

### 소스에서 빌드 (개발자)

```bash
# 요구사항: macOS 14+, Swift 5.9+

# 빌드
swift build -c release

# .app + DMG 생성
./scripts/build-app.sh

# 개발 실행
swift run DOUGLAS
```

## 사전 준비

앱은 첫 실행 시 온보딩에서 아래 항목을 자동 감지합니다. 미리 준비하면 셋업이 빨라집니다.

### 마스터 에이전트 (택 1)

| 방법 | 준비 | 비고 |
|------|------|------|
| **Claude Code CLI** (권장) | `npm install -g @anthropic-ai/claude-code` 후 `claude` 로그인 | Node.js 18+ 필요 |
| **Anthropic API** | [console.anthropic.com](https://console.anthropic.com)에서 API Key 발급 | Claude 모델 사용 |
| **OpenAI API** | [platform.openai.com](https://platform.openai.com)에서 API Key 발급 | GPT-4o 등 |
| **Google API** | [aistudio.google.com](https://aistudio.google.com)에서 API Key 발급 | Gemini 모델 |

### 의존성 (선택)

- **Node.js 18+** — Claude Code CLI 사용 시 필수. [nvm](https://github.com/nvm-sh/nvm) 또는 `brew install node`
- **Git** — Tool Use(셸 실행) 기능에서 활용
- **Homebrew** — 의존성 자동 설치 시 활용

### 환경변수 (선택)

터미널에서 실행(`swift run`)할 때만 자동 감지됩니다. Dock/Finder에서 실행 시에는 온보딩에서 직접 입력하세요.

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GOOGLE_API_KEY="AI..."
```

## 프로젝트 구조

```
DOUGLAS/
├── Package.swift          # SPM 정의
├── scripts/build-app.sh   # 앱 번들 + 코드서명 + DMG
├── Sources/               # 소스
│   ├── App/               # @main 진입점, AppDelegate, 윈도우/패널 관리
│   ├── Models/            # Agent, Room, ChatMessage, ProviderConfig, JiraConfig
│   ├── ViewModels/        # AgentStore, ChatViewModel, RoomManager, ToolExecutor
│   ├── Providers/         # AIProvider 프로토콜 + 구현체 (8파일)
│   └── Views/             # SwiftUI 뷰 (18개)
└── Tests/                 # 800+ 테스트
```

## 단축키

| 키 | 동작 |
|----|------|
| `⌘⇧E` | 사이드바 토글 |
| `⌘⏎` | 메시지 전송 |

## 테스트

```bash
swift test
swift test --filter ChatViewModelParsingTests
```

## 라이선스

Private project.
