# AgentManager 개발 가이드 (DEV_GUIDE)

이 문서는 워즈니악(유지보수 담당자)이 참조하는 개발 규칙서입니다. 모델에 관계없이 이 규칙을 따릅니다.

---

## 프로젝트 구조

```
AgentManager/
├── Package.swift                  # SPM, macOS 14+
├── scripts/build-app.sh           # 빌드 → .app → 코드서명 → DMG
├── ARCHITECTURE.md                # 전체 코드 분석 문서
├── DEV_GUIDE.md                   # 이 파일 (개발 규칙)
├── CLAUDE.md                      # Claude Code 세션 규칙
└── AgentManager/
    ├── App/                       # 앱 진입점, AppDelegate
    ├── Models/                    # 데이터 모델 (Agent, ChatMessage, ProviderConfig, ChangeRecord)
    ├── ViewModels/                # 비즈니스 로직 (AgentStore, ChatViewModel, ProviderManager, DevAgentManager)
    ├── Providers/                 # AI 프로바이더 (AIProvider 프로토콜, Claude/OpenAI/Google)
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
- 이미지: `~/Library/Application Support/AgentManager/avatars/`
- 채팅 기록: `~/Library/Application Support/AgentManager/chats/`
- 변경 이력: `~/Library/Application Support/AgentManager/changes.json`

### UI 텍스트
- 한국어 (앱 내 모든 사용자 대면 텍스트)
- 코드 주석은 한국어/영어 혼용 가능

### 역호환
- 새 필드 추가 시 반드시 `decodeIfPresent` + 기본값 사용
- `CodingKeys`에 명시적으로 나열

---

## 필수 규칙: 모든 작업 후 반드시 수행

1. **빌드 검증**: `swift build -c release` 성공 확인
2. **Git 커밋**: 아래 형식으로 커밋
3. **ARCHITECTURE.md 업데이트**: 구조 변경 시 해당 섹션 수정
4. **이 문서 업데이트**: 규칙/관례 변경 시 반영
5. **변경 이력 기록**: ChangeRecord에 추가

## 커밋 메시지 형식

```
[Woz] <type>: <한줄 설명>

<상세 내용 (선택)>

Files changed:
- path/to/file1.swift
- path/to/file2.swift
```

**type 종류**: feat (기능), fix (버그), refactor (리팩토링), style (UI), docs (문서)

---

## ARCHITECTURE.md 동기화 규칙

- 새 파일 추가 → 프로젝트 구조 섹션에 추가
- 새 ViewModel → 핵심 컴포넌트 섹션에 설명 추가
- 새 View → 뷰 레이어 섹션에 설명 추가
- Provider 변경 → Provider 테이블 업데이트
- 해결된 이슈 → 해결된 기술 이슈 섹션에 추가
