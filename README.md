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

## 워크플로우

방(Room) 생성 시 **Intent(목적)** 에 따라 7단계 상태기계가 동작합니다.

```
① Intake   ── 입력 파싱 (Jira URL 감지, 티켓 조회 등)
② Intent   ── 작업 목적 확인 (구현 / 요건 분석 / 테스트 계획 / 작업 분해)
③ Clarify  ── 결측치 질문 (최대 5개) + 미답 시 가정 선언
④ Assemble ── 분석가가 역할 산출 → 시스템이 에이전트 매칭/초대
⑤ Plan     ── 토론 + 계획 수립 (프로젝트 플레이북 주입)
⑥ Execute  ── 단계별 병렬 실행
⑦ Review   ── 검증 + 작업일지 생성
```

**Intent별 분기**: 구현은 전체 7단계, 요건 분석·테스트 계획·작업 분해는 Assemble/Execute를 건너뜁니다.

## 주요 기능

- **자동 위임** — 마스터가 요청을 분석하여 서브 에이전트 조합으로 방 구성
- **병렬 / 순차 처리** — 여러 에이전트 동시 투입 또는 A→B 체이닝
- **Tool Use** — 파일 읽기/쓰기, 셸 실행, 웹 검색/가져오기, 에이전트 초대/목록, Jira 연동(서브태스크·상태·코멘트), 에이전트 생성 제안, ask_user 등 12종 도구
- **Jira 연동** — Jira Cloud 티켓 조회 + 서브태스크 생성 + 상태 변경 + 코멘트 작성
- **이미지 첨부 + Vision** — 이미지를 첨부하여 Vision API로 분석
- **플로팅 사이드바** — 다른 앱 위에 떠 있으며, 드래그로 자유 이동
- **글로벌 핫키** — `⌘⇧E` 사이드바 토글
- **역할 템플릿** — 요구사항 분석가, 백엔드/프론트엔드 개발자, QA 4종, 테크라이터, DevOps 등 9종 빌트인 템플릿
- **프로젝트 방** — 디렉토리 연동, 빌드 루프, 승인 게이트
- **프로젝트 플레이북** — `{projectPath}/.douglas/playbook.json`으로 브랜치 전략, 기본 Intent, 코드 리뷰 정책 등 프로젝트별 설정
- **ask_user 도구** — Clarify 단계에서 에이전트가 사용자에게 직접 질문 (최대 5회)
- **시스템 주도 Assembly** — 분석가가 산출한 역할 요구사항을 시스템이 자동 매칭 (커버리지 50%+ 게이트)
- **온보딩** — 첫 실행 시 환경(Node.js, Git 등) + Claude Code 자동 감지, 완료 후 사이드바 자동 시작

## 방 상태 (RoomStatus)

| 상태 | 설명 |
|------|------|
| `planning` | 에이전트가 계획 수립 중 |
| `inProgress` | 작업 실행 중 |
| `awaitingApproval` | 사용자 승인 대기 (Human-in-the-loop) |
| `awaitingUserInput` | 사용자 입력 대기 (ask_user 도구) |
| `completed` | 작업 완료 |
| `failed` | 실패 |

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
│   ├── Models/            # 데이터 모델 (24파일)
│   │                        Agent, Room, ChatMessage, AgentTool,
│   │                        WorkflowIntent, ProjectPlaybook, RoleRequirement,
│   │                        DiscussionArtifact, JiraConfig, ProviderConfig 등
│   ├── ViewModels/        # 비즈니스 로직 (8파일)
│   │                        ChatViewModel, RoomManager, AgentStore,
│   │                        ToolExecutor, AgentMatcher, BuildLoopRunner,
│   │                        ProviderManager, OnboardingViewModel
│   ├── Providers/         # AIProvider 프로토콜 + 구현체 (8파일)
│   └── Views/             # SwiftUI 뷰 (18파일)
└── Tests/                 # 791개 테스트
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
