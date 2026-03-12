---
description: 구현 (브랜치 생성 + TDD + 코드 작성)
---

# 구현

> 브랜치 생성 + TDD + 구현 통합 (Plan Agent + 직접 수행)

---

## 동작

### 1. 반드시 브랜치 생성 (자동)

```bash
# develop에서 pr 브랜치 생성
git checkout develop
git pull origin develop
git checkout -b pr/IBS-{번호}

# pr에서 feature 브랜치 생성
git checkout -b feature/IBS-{번호}
```

**브랜치명 규칙**: 티켓번호만 사용 (설명 없음)
- `pr/IBS-1234`
- `feature/IBS-1234`

### 2. TDD 사이클 (자동)

#### 유연한 TDD
- 테스트와 구현을 함께 진행
- 핵심 로직에 대한 테스트 우선
- 실용적 접근

#### 테스트 컨벤션
```java
@DisplayName("{한글 설명}")
class {한글_클래스명} {
    @Test
    @DisplayName("{한글 테스트 설명}")
    void should{동작}_when{조건}() {
        // Arrange
        // Act
        // Assert
    }
}
```

### 3. 구현 (자동)

analysis.md의 구현 방향에 따라 코드 작성

---

## 구현 원칙

### 1. 최소 변경
- 요청된 기능만 구현
- 불필요한 리팩토링 금지
- 기존 패턴 준수

### 2. Hexagonal Architecture
- Domain: 비즈니스 로직
- Adapters: 외부 연동
- Application: 유스케이스

### 3. @Transactional 규칙
- UseCase 레이어에만 사용
- Service, Repository에는 사용 X

---

## 완료 후 처리

### 1. 테스트 전체 통과 확인

```bash
./gradlew :sub-module:inbound-domain:test
```

```markdown
# 세션 상태

ticket: {티켓번호}
phase: implementation
last_updated: {현재시간 ISO 8601}
```
---

## 롤백

문제 발생 시:
```bash
git checkout -- {파일명}    # 특정 파일
git checkout -- .           # 전체
```