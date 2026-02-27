# DOUGLAS

macOS 플로팅 사이드바 기반 AI 에이전트 매니저.

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
- **Tool Use** — 파일 읽기/쓰기, 셸 실행, 에이전트 초대 등 6종 도구
- **이미지 첨부 + Vision** — 이미지를 첨부하여 Vision API로 분석
- **플로팅 사이드바** — 다른 앱 위에 떠 있으며, 드래그로 자유 이동
- **글로벌 핫키** — `⌘⇧E` 사이드바 토글, `⌘⇧A` 커맨드 바
- **온보딩** — 첫 실행 시 필요 환경(Node.js, Git 등) 자동 체크

## 지원 프로바이더

| 프로바이더 | 인증 | 비고 |
|-----------|------|------|
| Claude Code | CLI | `claude` CLI 직접 실행 |
| Anthropic | API Key | Claude 모델 (Tool Use 지원) |
| OpenAI | API Key | GPT-4o 등 (Tool Use 지원) |
| Google | API Key | Gemini 모델 (Tool Use 지원) |

## 빌드 및 실행

```bash
# 요구사항: macOS 14+, Swift 5.9+

# 빌드
swift build -c release

# .app + DMG 생성
./scripts/build-app.sh

# 개발 실행
swift run DOUGLAS
```

## 프로젝트 구조

```
DOUGLAS/
├── Package.swift          # SPM 정의
├── scripts/build-app.sh   # 앱 번들 + 코드서명 + DMG
├── DOUGLAS/               # DOUGLASLib (소스)
│   ├── App/               # AppDelegate, 윈도우/패널 관리
│   ├── Models/            # Agent, Room, ChatMessage, ProviderConfig
│   ├── ViewModels/        # AgentStore, ChatViewModel, RoomManager
│   ├── Providers/         # AIProvider 프로토콜 + 구현체
│   └── Views/             # SwiftUI 뷰
├── DOUGLASApp/            # @main 진입점
└── Tests/                 # 테스트
```

## 단축키

| 키 | 동작 |
|----|------|
| `⌘⇧E` | 사이드바 토글 |
| `⌘⇧A` | 글로벌 커맨드 바 |
| `⌘⏎` | 메시지 전송 |

## 테스트

```bash
swift test
swift test --filter ChatViewModelParsingTests
```

## 라이선스

Private project.
