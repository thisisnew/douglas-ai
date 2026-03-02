# DOUGLAS

> 할 일이 있으면, 더글라스에게 시키세요.

macOS에서 동작하는 AI 비서입니다.
화면 옆 사이드바에 할 일을 입력하면, AI 전문가 팀이 알아서 처리합니다.

## 이런 걸 할 수 있어요

- 코드 작성, 버그 수정, 리팩토링
- 파일 읽기/쓰기, 터미널 명령 실행
- 리서치, 브레인스토밍, 문서 작성
- Jira 티켓 관리 (서브태스크 생성, 상태 변경)
- 이미지 분석

작업이 복잡하면 여러 AI 전문가를 자동으로 불러서 협업합니다.

## 설치

### 준비물

- **Mac** (macOS 14 Sonoma 이상)
- **Xcode Command Line Tools**
- **Node.js**

### 순서

**1) Xcode Command Line Tools 설치**

터미널을 엽니다 (`Cmd+Space` → "터미널" 입력 → Enter).

```bash
xcode-select --install
```

팝업이 뜨면 "설치"를 누르고 기다립니다. (이미 설치되어 있으면 넘어갑니다)

**2) Node.js 설치**

[nodejs.org](https://nodejs.org)에 접속해서 **LTS** 버전을 다운로드하고 설치합니다.

**3) DOUGLAS 빌드**

터미널에서 아래 3줄을 복사해서 붙여넣고 Enter를 누릅니다.

```bash
git clone https://github.com/thefarmersfront/douglas.git
cd douglas
./scripts/build-app.sh
```

처음 빌드할 때는 몇 분 걸립니다. `=== 완료! ===`가 나올 때까지 기다립니다.

**4) 앱 설치**

빌드가 끝나면 아래 명령을 실행합니다.

```bash
open dist/DOUGLAS.dmg
```

열린 창에서 DOUGLAS 아이콘을 Applications 폴더로 드래그합니다.

**5) 앱 실행**

Launchpad에서 DOUGLAS를 찾아 클릭합니다.

> **"확인되지 않은 개발자" 경고가 뜨면:**
>
> 1. **시스템 설정** 열기 (좌측 상단 Apple 메뉴)
> 2. **개인정보 보호 및 보안** 클릭
> 3. 아래쪽에 "DOUGLAS" 관련 메시지 옆 **"확인 없이 열기"** 클릭

## 초기 설정

앱을 처음 열면 설정 화면이 나타납니다.

### 1단계: Claude Code

DOUGLAS의 핵심 AI입니다. 앱이 자동으로 감지합니다.

- 이미 설치되어 있으면 → "다음" 클릭
- 설치 안 되어 있으면 → "설치" 버튼 클릭 (자동 설치)
- 설치 후 인증 필요 시 → 터미널에서 `claude` 입력 후 로그인
- 사용 안 하려면 → "건너뛰기" 클릭

### 2단계: AI 선택

추가로 사용할 AI를 고릅니다. 체크만 하면 됩니다.

### 3단계: API 키 입력

선택한 AI의 API 키를 입력합니다. 모르면 "나중에 설정"을 눌러도 됩니다.

API 키 받는 곳:
- **Anthropic** — [console.anthropic.com](https://console.anthropic.com)
- **OpenAI** — [platform.openai.com](https://platform.openai.com)
- **Google** — [aistudio.google.com](https://aistudio.google.com)

## 사용법

- 화면 오른쪽 사이드바에 할 일을 입력합니다
- `Cmd+Shift+E`로 사이드바를 열고 닫을 수 있습니다
- DOUGLAS가 질문하면 답해주세요 — 나머지는 알아서 합니다
