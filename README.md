# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS 플로팅 사이드바 기반 멀티 에이전트 AI 협업 도구.

DOUGLAS(PM)에게 지시하면, 방(Room)을 만들어 요구사항을 확인하고 전문가를 소환하여 작업을 진행합니다.

![Platform](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Architecture](https://img.shields.io/badge/MVVM-green)

## 동작 방식

```
사용자 → 사이드바에 입력 → DOUGLAS(PM)가 즉시 방 생성
  → 요구사항 확인 → 전문가 초대 → 분석 → 계획 → 실행
```

사용자가 에이전트를 직접 고르지 않습니다. DOUGLAS가 PM/오케스트레이터로서 팀을 구성하고 작업을 진행합니다.

## 작업 플로우

```
                    ┌─────────────┐
                    │  사용자 입력  │
                    └──────┬──────┘
                           │
                           ▼
                ┌──────────────────┐
                │  ① Intake        │  입력 파싱 (Jira URL 감지,
                │     입력 수집     │  IntakeData 저장, 플레이북 로드)
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  ② Intent        │  작업 목적 확인
                │     의도 분류     │  (구현/분석/테스트/분해)
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  ③ Clarify       │  DOUGLAS가 사용자에게 질문
                │     요건 확인     │  (ask_user 도구, 최대 5개)
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐     ┌──────────────────┐
                │  ④ Assemble      │────▶│  에이전트 매칭     │
                │     팀 구성       │     │  (이름+persona+   │
                └────────┬─────────┘     │   workingRules)   │
                         │               └────────┬─────────┘
                         │                        │
                         │   ┌────────────────────┘
                         │   │ 매칭 실패 시
                         │   ▼
                         │  ┌──────────────────┐
                         │  │ 에이전트 생성 제안 │  사용자가 작업 규칙
                         │  │ (AgentSuggestion) │  설정 후 추가
                         │  └──────────────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  ⑤ Plan          │  분석 → 브리핑 생성
                │     계획 수립     │  → 승인 → 실행 계획 JSON
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  ⑥ Execute       │  전문가만 순차/병렬 실행
                │     실행          │  (DOUGLAS 제외)
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  ⑦ Review        │  작업일지 생성
                │     검토          │  빌드 루프 + QA 루프
                └──────────────────┘
```

**일관성 우선**: 단순/복잡 불문, 모든 요청이 동일한 프로세스를 거칩니다.

## 주요 기능

- **DOUGLAS PM/오케스트레이터** — 사이드바에 입력하면 DOUGLAS가 즉시 방 생성, 요구사항 확인, 전문가 소환
- **작업 규칙 (Working Rules)** — 에이전트별 구체적 작업 지시사항 (직접 입력 또는 파일 참조). 에이전트 생성 시 필수 입력
- **필수 분석** — DOUGLAS와 초대된 전문가가 요구사항을 공유하고 접근법 논의
- **Tool Use** — 파일 읽기/쓰기, 셸 실행, 웹 검색/가져오기, 에이전트 초대/목록, Jira 연동, 에이전트 생성 제안, ask_user 등 12종 도구
- **Jira 연동** — Jira Cloud 티켓 조회 + 서브태스크 생성 + 상태 변경 + 코멘트 작성
- **이미지 첨부 + Vision** — 이미지를 첨부하여 Vision API로 분석
- **플로팅 사이드바** — 다른 앱 위에 떠 있으며, 드래그로 자유 이동/리사이즈 (너비 320–800pt)
- **진행 상세 보기** — "하는 중..." 버블 클릭 시 도구 호출/API 요청 등 실시간 활동 로그 확장
- **타이핑 인디케이터** — 에이전트 작업 중 바운싱 애니메이션 + 에이전트 이름 표시
- **카드 애니메이션** — 제안/승인/입력 카드 등장 시 슬라이드+페이드 트랜지션
- **글로벌 핫키** — `Cmd+Shift+E` 사이드바 토글
- **프로젝트 방** — 디렉토리 연동, 빌드 루프, 승인 게이트
- **프로젝트 플레이북** — `{projectPath}/.douglas/playbook.json`으로 브랜치 전략, 기본 Intent, 코드 리뷰 정책 등 프로젝트별 설정
- **ask_user 도구** — 에이전트가 사용자에게 직접 질문
- **반복 응답 감지** — 에이전트의 연속 응답 유사도를 측정하여 고착 상태 자동 중단
- **온보딩** — 첫 실행 시 환경(Node.js, Git 등) + Claude Code 자동 감지, 완료 후 사이드바 자동 시작

## 에이전트 구조

```
┌─────────────────────────────────────────────┐
│                에이전트 (Agent)               │
├─────────────────────────────────────────────┤
│  이름 (name)         "백엔드 개발자"          │
│  역할 설명 (persona)  "Node.js API 전문..."   │
│  작업 규칙 (rules)    inline / filePath       │
│  프로바이더/모델       Anthropic / Claude      │
│  참조 프로젝트         ["/path/to/project"]    │
├─────────────────────────────────────────────┤
│  resolvedSystemPrompt = persona + rules      │
│  (실행 시점에 결합)                            │
└─────────────────────────────────────────────┘
```

- **persona**: 역할 정체성 ("당신은 백엔드 개발자입니다...")
- **작업 규칙**: 구체적 작업 지시사항 (코딩 컨벤션, 브랜치 전략, 금지 사항 등)
  - `직접 입력`: 텍스트로 규칙 작성
  - `파일 참조`: `.cursorrules`, CONTRIBUTING.md 등 파일 경로 지정 (실행 시점에 읽기)

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
   - `시스템 설정 > 개인정보 보호 및 보안 > "확인 없이 열기"` 클릭
   - 또는 터미널에서: `xattr -cr /Applications/DOUGLAS.app`
4. 앱 실행 후 온보딩 가이드가 자동으로 시작됨

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

### DOUGLAS 에이전트 (택 1)

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

## 프로젝트 구조

```
DOUGLAS/
├── Package.swift          # SPM 정의
├── scripts/build-app.sh   # 앱 번들 + 코드서명 + DMG
├── Sources/               # 소스
│   ├── App/               # @main 진입점, AppDelegate, 윈도우/패널 관리
│   ├── Models/            # 데이터 모델 (23파일)
│   │                        Agent, WorkingRules, Room, ChatMessage, AgentTool,
│   │                        WorkflowIntent, ProjectPlaybook, RoleRequirement,
│   │                        DiscussionArtifact, JiraConfig, ProviderConfig 등
│   ├── ViewModels/        # 비즈니스 로직 (8파일)
│   │                        ChatViewModel, RoomManager, AgentStore,
│   │                        ToolExecutor, AgentMatcher, BuildLoopRunner,
│   │                        ProviderManager, OnboardingViewModel
│   ├── Providers/         # AIProvider 프로토콜 + 구현체 (8파일)
│   └── Views/             # SwiftUI 뷰 (19파일)
└── Tests/                 # 테스트
```

## 단축키

| 키 | 동작 |
|----|------|
| `Cmd+Shift+E` | 사이드바 토글 |
| `Cmd+Enter` | 메시지 전송 |

## 테스트

```bash
swift test
```

## 라이선스

Private project.
