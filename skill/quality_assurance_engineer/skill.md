---
name: qa-testcase-writer
description: >
  TestRail 호환 CSV 테스트 케이스 생성 스킬.
  트리거: (1) "테스트 케이스 만들어줘/작성해줘" (2) "TestRail CSV 생성" (3) "QA 테스트 설계"
  (4) Figma/Axure URL과 함께 테스트 요청 (5) Jira/Confluence 문서로 테스트 케이스 요청
  (6) 스크린샷/PPT/PDF 업로드 후 테스트 케이스 요청 (7) 웹사이트 URL로 테스트 케이스 요청.
  입력: Figma, Axure, Jira, Confluence, PPT, PDF, 스크린샷, 웹 URL 등 요구사항 문서.
  출력:
    - [기능명]_테스트케이스.csv - TestRail UI/UX 테스트케이스 업로드용
    - [기능명]_보안테스트케이스.csv - TestRail 보안 테스트케이스 업로드용
    - [기능명]_리스크분석.md - 위험 항목, 발생 가능성, 영향도, 완화 전략
    - [기능명]_질문.md - 불명확한 요구사항 질문 (우선순위별), 헤더에 요청 URL 포함
    - [기능명]_체크리스트.md - 커버리지 검증 체크리스트
---

# QA 테스트 케이스 작성 스킬

요구사항 문서를 분석하여 TestRail 호환 CSV 테스트 케이스를 생성한다.

## Trigger

다음과 같은 요청이 오면 이 스킬을 사용한다.

- "테스트 케이스 만들어줘"
- "테스트 케이스 작성해줘"
- "TestRail CSV 생성"
- "QA 테스트 설계"
- Figma URL과 함께 테스트 케이스 요청
- Axure URL과 함께 테스트 케이스 요청
- Jira/Confluence 문서 기반 테스트 케이스 요청
- PPT/PDF/스크린샷 업로드 후 테스트 케이스 요청
- 웹사이트 URL을 기준으로 테스트 케이스 요청

## Input

입력으로 받을 수 있는 요구사항 문서 유형:

- Figma URL
- Axure URL
- Jira 문서
- Confluence 문서
- PPT
- PDF
- 스크린샷
- 일반 웹 URL

## Output

아래 5개 파일을 반드시 생성한다.

1. `[기능명]_테스트케이스.csv`
2. `[기능명]_보안테스트케이스.csv`
3. `[기능명]_리스크분석.md`
4. `[기능명]_질문.md`
5. `[기능명]_체크리스트.md`