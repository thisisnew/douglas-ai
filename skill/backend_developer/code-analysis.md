---
description: 코드 분석 + 지식 추출
---

# 코드 분석

> 코드 탐색 + 패턴 발견 (Explore Agent 활용)

## 동작

### 1. 기존 지식 로드

작업 시작 전 `.claude/knowledge/` 파일들 참조:
- `codebase/patterns.md` → 기존 패턴 참조
- `codebase/modules/` → 모듈 구조 참조
- `conventions/*.md` → 컨벤션 참조

### 2. 코드 탐색 (Explore Agent 사용)

```
Task tool 호출:
- subagent_type: "Explore"
- prompt: "Find files related to {키워드}, understand code flow, identify modification points"
- thoroughness: "medium" or "very thorough"
```

### 3. 분석 결과 출력

```
[분석 중...]

코드 분석 결과

[수정 대상]
- {파일경로}:{라인번호} - {설명}
- {파일경로}:{라인번호} - {설명}

[구현 방향]
- {수정 방법 1}
- {수정 방법 2}

[주의사항]
- {사이드이펙트}
- {테스트 수정 필요 여부}

---
발견한 지식:

- 모듈 구조:
  {모듈명}/
  ├── application/  ← UseCase 패턴
  └── domain/       ← DDD 스타일
  → codebase/modules/{모듈명}.md 업데이트

- 패턴: {발견한 패턴}
  → codebase/patterns.md에 추가

- 컨벤션: {발견한 컨벤션}
  → conventions/{관련파일}.md에 추가

---

---

## 지식 추출 규칙

### 모듈 구조 (codebase/modules/)
- 새 모듈 발견 시 구조 문서화
- 패키지 구조와 책임 기록

### 패턴 (codebase/patterns.md)
- Decorator, Strategy 등 디자인 패턴
- 프로젝트 특화 패턴

### 컨벤션
- `testing.md`: 테스트 네이밍, 구조
- `naming.md`: 클래스/메서드 네이밍
- `architecture.md`: 레이어 규칙, @Transactional 위치

---

## Hexagonal Architecture 고려사항

분석 시 레이어별 책임 확인:
- **Domain** (inbound-domain): 비즈니스 로직 핵심
- **Adapters** (inbound-persistence, inbound-external-api): 외부 연동
- **Application**: 유스케이스 조합

---

## 완료 후 처리

### 1. analysis.md 저장

`.claude/workspace/{티켓번호}/analysis.md`:

```markdown
# {티켓번호} 코드 분석

## 요약
한 줄 요약

## 수정 대상
- [ ] {파일경로}:{라인번호} - {설명}
- [ ] {파일경로}:{라인번호} - {설명}

## 구현 방향
- {구체적인 수정 방법}

## 주의사항
- {사이드이펙트}
- {테스트 수정 필요 여부}
```

### 2. 지식 파일 업데이트

발견한 지식을 해당 파일에 추가

### 3. 세션 상태 업데이트

`.claude/workspace/{티켓번호}/session.md`:

```markdown
# 세션 상태

ticket: {티켓번호}
phase: code-analysis
last_updated: {현재시간 ISO 8601}
```