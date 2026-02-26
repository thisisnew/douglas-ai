# CLAUDE.md - AgentManager 개발 규칙

## 핵심 규칙
**모든 작업은 문서 업데이트와 반드시 세트로 수행한다.**

## 빌드
- 코드 변경 후 반드시 `swift build -c release` 확인
- 빌드 실패 시 커밋 금지

## 문서
- ARCHITECTURE.md: 현재 코드 상태 반영 (구조 변경 시 필수 업데이트)
- DEV_GUIDE.md: 개발 규칙/관례 변경 시 업데이트

## Git
- 커밋 형식: `[Woz] <type>: <설명>`
- type: feat, fix, refactor, style, docs
- force push 금지
- 빌드 통과 후에만 커밋

## 프로젝트 정보
- Swift 5.9, macOS 14+ (SPM)
- MVVM 아키텍처
- 빌드: `swift build -c release`
- 배포: `scripts/build-app.sh`
