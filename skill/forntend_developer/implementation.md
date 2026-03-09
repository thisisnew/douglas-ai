---
description: 구현 (브랜치 생성 + 코드 작성)
---

# 구현

> 브랜치 생성 + TDD + 구현 통합 (Plan Agent + 직접 수행)

---

## 동작

### 1. 브랜치 생성 (자동)

```bash
# main에서 pr 브랜치 생성
git checkout main
git pull origin main
git checkout -b pr/IBS-{번호}

# pr에서 feature 브랜치 생성
git checkout -b feature/IBS-{번호}
```

**브랜치명 규칙**: 티켓번호만 사용 (설명 없음)
- `pr/IBS-1234`
- `feature/IBS-1234`

### 2. 구현 (자동)

## 구현 원칙

### 1. 최소 변경
- 요청된 기능만 구현
- 불필요한 리팩토링 금지
- 기존 패턴 준수

## 롤백

문제 발생 시:
```bash
git checkout -- {파일명}    # 특정 파일
git checkout -- .           # 전체
```