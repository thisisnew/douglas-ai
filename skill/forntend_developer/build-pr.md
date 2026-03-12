---
description: 커밋 & PR 생성
---

# 커밋 & PR 생성

> 빌드 + 테스트 + 커밋 + PR (선 작업)

## 동작

### 1. 빌드 & 테스트 (자동)

```bash
npm run serve
```

### 2. 커밋 (자동)

```bash
git add .
git commit -m "{prefix}: [IBS-{번호}] {설명}
```

### 3. PR 생성 (자동)

```bash
git push -u origin feature/IBS-{번호}

gh pr create \
  --base pr/IBS-{번호} \
  --head feature/IBS-{번호} \
  --title "{prefix}: [IBS-{번호}] {설명}" \
  --body "$(cat <<'EOF'
## Summary
- {변경 사항 요약}

## Related Issue
- IBS-{번호}

## Test plan
- [ ] 단위 테스트 통과
- [ ] 빌드 성공

EOF
)"
```

## 커밋 메시지 컨벤션

### Prefix 결정

| 작업 유형 | Prefix |
|-----------|--------|
| 새 기능 | feat |
| 기존 기능 변경 | modify |
| 버그 수정 | hotfix |
| 리팩토링 | refactor |
| 설정 변경 | config |

### 형식

```
{prefix}: [IBS-{번호}] {설명}
```