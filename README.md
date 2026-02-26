# AgentManager

macOS 네이티브 AI 에이전트 관리 데스크톱 앱.

마스터 에이전트가 사용자의 요청을 분석하여 적합한 서브 에이전트에게 자동으로 작업을 위임하는 **"사장님 모드"** 워크플로를 제공합니다.

![Platform](https://img.shields.io/badge/platform-macOS%2014+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Architecture](https://img.shields.io/badge/architecture-MVVM-green)

## 핵심 컨셉

사용자는 에이전트를 직접 골라서 시키지 않습니다. 사이드바에 타이핑하면 마스터 에이전트가 알아서 적합한 팀원(서브 에이전트)에게 분배합니다.

```
사용자: "블로그 글 하나 써줘"
  → 마스터가 분석 → 마케팅 에이전트에게 위임 → 방 생성 → 결과 취합
```

## 주요 기능

- **자동 위임**: 마스터가 요청을 분석하여 최적의 에이전트 조합으로 방을 구성
- **병렬 처리**: 여러 에이전트에게 동시에 작업 위임
- **순차 체이닝**: A의 결과를 B에게 전달하는 워크플로 체인
- **컨텍스트 공유**: 에이전트 간 대화 내역 참조
- **에이전트 제안**: 적합한 에이전트가 없으면 자동 생성 제안
- **플로팅 사이드바**: 화면 오른쪽에 항상 대기, 다른 앱 작업 방해 없음
- **글로벌 커맨드 바**: `⌘⇧A`로 어디서든 마스터에게 빠르게 접근
- **워즈니악 (유지보수 담당자)**: 앱 개선, 코드 수정, 버그 수정을 처리하는 내장 개발 에이전트

## 지원 AI 프로바이더

| 프로바이더 | 인증 방식 | 비고 |
|-----------|----------|------|
| Claude Code | CLI (키 불필요) | `claude` CLI 실행 |
| OpenAI | API Key | GPT-4o 등 |
| Google | API Key | Gemini 2.0 Flash 등 |

## 요구 사항

- macOS 14.0 (Sonoma) 이상
- Swift 5.9+
- Xcode 15+ 또는 Swift Toolchain

## 설치 및 실행

### 소스에서 빌드

```bash
git clone https://github.com/your-username/AgentManager.git
cd AgentManager

# 릴리즈 빌드
swift build -c release

# .app 번들 + DMG 생성
./scripts/build-app.sh
```

빌드 결과물은 `dist/AgentManager.app`에 생성됩니다.

### 직접 실행 (개발용)

```bash
swift run AgentManager
```

## 프로젝트 구조

```
AgentManager/
├── Package.swift               # SPM 패키지 정의
├── CLAUDE.md                   # 개발 규칙
├── ARCHITECTURE.md             # 코드 분석 문서
├── DEV_GUIDE.md                # 워즈니악 참조 개발 가이드
├── scripts/
│   └── build-app.sh            # .app 번들 → 코드서명 → DMG
├── AgentManager/               # 라이브러리 (AgentManagerLib)
│   ├── App/                    # AppDelegate, 윈도우 관리
│   ├── Models/                 # Agent, ChatMessage, ProviderConfig 등
│   ├── ViewModels/             # AgentStore, ChatViewModel, RoomManager 등
│   ├── Providers/              # AIProvider 프로토콜 + 구현체
│   └── Views/                  # SwiftUI 뷰
├── AgentManagerApp/            # 실행 타겟 (@main 진입점)
└── Tests/                      # 테스트 (220개)
```

## 아키텍처

MVVM 패턴 기반으로 구성되어 있습니다.

```
Models          ViewModels           Views
─────────       ──────────────       ──────────────
Agent       ←── AgentStore       ←── FloatingSidebarView
ChatMessage ←── ChatViewModel    ←── ChatView
Room        ←── RoomManager      ←── RoomListView
ProviderCfg ←── ProviderManager  ←── AddProviderSheet
ChangeRecord←── DevAgentManager  ←── ChangeHistoryView
                     │
              ┌──────┴──────┐
              │  Providers  │
              │ ClaudeCode  │
              │ OpenAI      │
              │ Google      │
              └─────────────┘
```

## 테스트

```bash
# 전체 테스트 실행
swift test

# 특정 테스트 실행
swift test --filter ChatViewModelParsingTests
```

## 단축키

| 단축키 | 동작 |
|--------|------|
| `⌘⇧A` | 글로벌 커맨드 바 토글 |
| `⌘⇧E` | 사이드바 토글 |
| `⌘⏎` | 메시지 전송 |

## 문서

- [ARCHITECTURE.md](./ARCHITECTURE.md) — 전체 코드 분석 및 구조 문서
- [DEV_GUIDE.md](./DEV_GUIDE.md) — 개발 규칙 및 워즈니악 참조 가이드
- [CLAUDE.md](./CLAUDE.md) — Claude Code 세션 규칙

## 라이선스

Private project.
