---
description: 코드 분석 + 지식 추출
---

# 코드 분석

> 코드 탐색 + 패턴 발견

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

`./analysis.md`:

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