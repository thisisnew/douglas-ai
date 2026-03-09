---
description: Jira 브리핑 + 지식 추출
---

# Jira 브리핑

> 티켓 조회 + 지식 추출 (선 작업 패턴)

## 입력 파싱

다음 형식 모두 지원:

```
IBS-1234
https://kurly0521.atlassian.net/browse/IBS-1234
kurly0521.atlassian.net/browse/IBS-1234
```

**파싱 로직**:
1. 정규식 `IBS-\d+` 패턴 매칭
2. 매칭된 첫 번째 결과 사용
3. 매칭 실패 시 → "티켓번호를 찾을 수 없습니다" 오류

---

## 동작

### 1. 기존 지식 로드

작업 시작 전 `.claude/knowledge/` 파일들 참조:
- `domain/glossary.md` → 용어 자동 이해
- `domain/business-rules.md` → 관련 규칙 참조
- `codebase/patterns.md` → 관련 패턴 참조

### 2. 티켓 조회 (선 작업)

`mcp__mcp-atlassian__jira_get_issue` 사용하여 티켓 정보 조회

### 3. 브리핑 출력

```
[티켓 읽는 중...]

{티켓번호} 브리핑

[요약] {summary}
[배경] {description에서 추출한 배경}
[요구사항]
- {요구사항 1}
- {요구사항 2}

---
발견한 지식:

- 새 용어: "{용어}" = {설명}
  → domain/glossary.md에 추가

- 비즈니스 규칙: "{규칙}"
  → domain/business-rules.md에 추가

---
기존 지식 활용: (해당되는 경우만)

- "{관련 규칙}" 규칙 참조
  → 이 작업에도 동일하게 적용

---
1. 다음 (코드 분석)
2. 수정할래요
x. 나가기
```

---

## 지식 추출 규칙

### 용어 (glossary.md)
- 약어 발견 시 (NFA, RTV, D-1 등)
- 도메인 특화 용어 발견 시

### 비즈니스 규칙 (business-rules.md)
- "~해야 한다", "~만 가능" 등의 제약조건
- 날짜/수량/상태 관련 규칙

### 관련자 (stakeholders.md)
- 티켓에 언급된 담당자/팀

---

## 수정 요청 처리

사용자가 `2`를 선택하면:

```
어떤 부분을 수정할까요?
```

사용자 입력 후:
- 브리핑 업데이트
- 필요시 Jira 티켓에 코멘트 추가 (`mcp__mcp-atlassian__jira_add_comment`)
- 다시 선택지 제시

---

## 완료 후 처리

### 1. 지식 파일 업데이트

발견한 지식을 해당 파일에 추가:
- `.claude/knowledge/domain/glossary.md`
- `.claude/knowledge/domain/business-rules.md`
- `.claude/knowledge/domain/stakeholders.md`

### 2. 세션 상태 업데이트

`.claude/workspace/{티켓번호}/session.md`:

```markdown
# 세션 상태

ticket: {티켓번호}
phase: jira-briefing
last_updated: {현재시간 ISO 8601}
```

### 3. Compact 실행

사용자가 `1` 또는 `x` 선택 시 `/compact` 실행하여 컨텍스트 정리

### 4. 다음 단계 안내

```
1. 다음 (코드 분석)
2. 수정할래요
x. 나가기
```

---

## 프로젝트 키

Jira 프로젝트 키: `IBS`