# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS 플로팅 사이드바에서 동작하는 멀티 에이전트 AI 협업 도구입니다.
사이드바에 할 일을 입력하면, DOUGLAS가 팀을 구성하고 계획을 세우고 실행까지 진행합니다.

## 동작 방식

1. 사이드바에 할 일을 입력합니다
2. DOUGLAS가 필요하면 추가 정보를 질문합니다
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

**할 수 있는 것들**
- 파일 읽기/쓰기, 셸 명령 실행
- 웹 검색 및 페이지 가져오기
- Jira 티켓 관리 (서브태스크 생성, 상태 변경, 코멘트)
- 이미지 첨부 및 분석
- 작업 중 사용자에게 직접 질문

**사이드바**
- 다른 앱 위에 상시 표시, 드래그로 이동/리사이즈
- `Cmd+Shift+E`로 어디서든 토글
- 작업 진행 상황을 실시간으로 확인

## 시작하기

### 1. AI 서비스 연결 (택 1)

| 방법 | 준비 |
|------|------|
| **Claude Code** (권장) | `npm install -g @anthropic-ai/claude-code` 후 `claude` 로그인 |
| **Anthropic API** | [console.anthropic.com](https://console.anthropic.com)에서 API Key 발급 |
| **OpenAI API** | [platform.openai.com](https://platform.openai.com)에서 API Key 발급 |
| **Google API** | [aistudio.google.com](https://aistudio.google.com)에서 API Key 발급 |

### 2. 설치

Releases에서 `DOUGLAS.dmg`를 다운로드하고 `Applications`에 드래그합니다.

> 최초 실행 시 macOS가 차단하면: `시스템 설정 > 개인정보 보호 및 보안 > "확인 없이 열기"`

### 3. 실행

앱을 실행하면 온보딩 가이드가 환경을 자동 감지하고 설정을 도와줍니다.

---

## 개발

```bash
swift build -c release    # 빌드
swift test                # 테스트
swift run DOUGLAS          # 실행
./scripts/build-app.sh     # .app + DMG 생성
```

macOS 14+, Swift 5.9+
