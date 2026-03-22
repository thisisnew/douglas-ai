import Foundation

/// 의도별 어휘를 캡슐화하는 Value Object
/// IntentClassifier에서 키워드 사전(도메인 지식)과 점수 계산(도메인 로직)을 분리 (SRP)
///
/// 사용법:
///   let score = IntentVocabulary.research.score(tokens: tokens, fullText: text, bigrams: bigrams)
///   let matched = score >= IntentVocabulary.research.threshold
struct IntentVocabulary: Equatable {

    /// 어간 + 가중치 쌍
    struct ScoredStem: Equatable {
        let stem: String
        let weight: Int
    }

    let intent: WorkflowIntent
    let positives: [ScoredStem]
    let negatives: [ScoredStem]
    let threshold: Int

    /// 주어진 토큰/텍스트에 대한 점수 계산
    func score(tokens: [String], fullText: String, bigrams: [String]) -> Int {
        var total = 0

        for keyword in positives {
            if stemMatches(keyword.stem, tokens: tokens, fullText: fullText, bigrams: bigrams) {
                total += keyword.weight
            }
        }

        for negative in negatives {
            if stemMatches(negative.stem, tokens: tokens, fullText: fullText, bigrams: bigrams) {
                total += negative.weight // weight는 이미 음수
            }
        }

        return total
    }

    /// positive 키워드만 합산한 점수 (complex 감지용 — negatives 무시)
    func positiveOnlyScore(tokens: [String], fullText: String, bigrams: [String]) -> Int {
        var total = 0
        for keyword in positives {
            if stemMatches(keyword.stem, tokens: tokens, fullText: fullText, bigrams: bigrams) {
                total += keyword.weight
            }
        }
        return total
    }

    /// 어간 매칭 공통 로직
    private func stemMatches(_ stem: String, tokens: [String], fullText: String, bigrams: [String]) -> Bool {
        tokens.contains { token in
            token.hasPrefix(stem) || token == stem
        } || fullText.contains(stem)
        || bigrams.contains(where: { $0.hasPrefix(stem) || $0 == stem })
    }

    /// threshold 충족 여부
    func matches(tokens: [String], fullText: String, bigrams: [String]) -> Bool {
        score(tokens: tokens, fullText: fullText, bigrams: bigrams) >= threshold
    }
}

// MARK: - 어휘 사전 (Factory)

extension IntentVocabulary {

    /// 전체 어휘 사전
    static let all: [IntentVocabulary] = [
        .quickAnswer, .discussion, .research, .documentation, .task
    ]

    // MARK: quickAnswer — 단순 질문/정보 확인

    static let quickAnswer = IntentVocabulary(
        intent: .quickAnswer,
        positives: [
            // 의문사 (4점: 단독으로 quickAnswer 확정 가능)
            .init(stem: "뭐", weight: 4), .init(stem: "뭘", weight: 4),
            .init(stem: "뭔", weight: 4), .init(stem: "무슨", weight: 4),
            .init(stem: "몇", weight: 3), .init(stem: "어디", weight: 3),
            .init(stem: "언제", weight: 3), .init(stem: "누가", weight: 3),
            .init(stem: "왜", weight: 3),
            .init(stem: "어떻", weight: 2), .init(stem: "어떤", weight: 2),
            // 설명 요청
            .init(stem: "알려", weight: 3), .init(stem: "설명", weight: 4),
            // 의미/뜻
            .init(stem: "뜻", weight: 4), .init(stem: "의미", weight: 4),
            .init(stem: "차이", weight: 2),
        ],
        negatives: [
            // 멀티스텝 연결 키워드 → quickAnswer 억제 (복합 요청 패턴)
            .init(stem: "찾고", weight: -3), .init(stem: "추적", weight: -3),
            .init(stem: "분석해", weight: -2), .init(stem: "조사해", weight: -2),
            .init(stem: "구현", weight: -3), .init(stem: "만들어", weight: -3),
            .init(stem: "작성해", weight: -2), .init(stem: "코딩", weight: -3),
        ],
        threshold: 4  // 3→4: "알려줘" 단독(3)은 LLM 폴백, 의문사+설명(4+)은 quickAnswer 확정
    )

    // MARK: discussion — 의견 교환, 브레인스토밍

    static let discussion = IntentVocabulary(
        intent: .discussion,
        positives: [
            // 의견/생각 요청
            .init(stem: "어떻게 생각", weight: 5), .init(stem: "생각해", weight: 4),
            .init(stem: "의견", weight: 3), .init(stem: "관점", weight: 3),
            .init(stem: "견해", weight: 3),
            // 토론/브레인스토밍
            .init(stem: "토론", weight: 4), .init(stem: "브레인스토밍", weight: 4),
            .init(stem: "brainstorm", weight: 4), .init(stem: "아이디어", weight: 3),
            .init(stem: "회의", weight: 3),
            // 비교/판단
            .init(stem: "검토", weight: 4), .init(stem: "리뷰", weight: 4),
            .init(stem: "review", weight: 4), .init(stem: "피드백", weight: 4),
            .init(stem: "장단점", weight: 4), .init(stem: "좋을까", weight: 3),
            .init(stem: "어떨까", weight: 3), .init(stem: "어떤 게 나을", weight: 4),
            .init(stem: "나을까", weight: 4), .init(stem: "낫지", weight: 4),
            .init(stem: "뭐가 나을", weight: 4), .init(stem: "뭐가 좋", weight: 4),
            .init(stem: "괜찮을까", weight: 4), .init(stem: "고민", weight: 4),
            // 전망/트렌드
            .init(stem: "트렌드", weight: 4), .init(stem: "전망", weight: 3),
            .init(stem: "미래", weight: 2),
            // 지식 탐색
            .init(stem: "알고싶", weight: 2),
            // 작업 도출/분석 (시나리오 2)
            .init(stem: "작업도출", weight: 6), .init(stem: "할일정리", weight: 6),
            .init(stem: "태스크파악", weight: 6),
            .init(stem: "무슨작업", weight: 5), .init(stem: "어떤작업", weight: 5),
            .init(stem: "작업목록", weight: 5),
            .init(stem: "뭘해야", weight: 5), .init(stem: "해야할것", weight: 5),
            .init(stem: "해야할일", weight: 5),
        ],
        negatives: [
            .init(stem: "구현", weight: -3), .init(stem: "코딩", weight: -3),
            .init(stem: "배포", weight: -3), .init(stem: "커밋", weight: -3),
        ],
        threshold: 4
    )

    // MARK: research — 자료 수집, 비교, 정리

    static let research = IntentVocabulary(
        intent: .research,
        positives: [
            // 기존
            .init(stem: "조사", weight: 5), .init(stem: "리서치", weight: 5),
            .init(stem: "research", weight: 5),
            .init(stem: "서베이", weight: 4), .init(stem: "survey", weight: 4),
            // 신규 (시나리오 5: "비교해서 정리해줘")
            .init(stem: "비교", weight: 5), .init(stem: "사례", weight: 3),
            .init(stem: "레퍼런스", weight: 4), .init(stem: "벤치마크", weight: 4),
            // 조사 맥락의 정리
            .init(stem: "알아봐", weight: 4), .init(stem: "찾아봐", weight: 4),
            .init(stem: "찾고", weight: 4), .init(stem: "추적", weight: 4),
            .init(stem: "파악", weight: 4), .init(stem: "살펴", weight: 3),
            .init(stem: "확인해", weight: 3),
        ],
        negatives: [],
        threshold: 4
    )

    // MARK: documentation — 문서 파일 작성

    static let documentation = IntentVocabulary(
        intent: .documentation,
        positives: [
            // 기존
            .init(stem: "기획서", weight: 5), .init(stem: "문서작성", weight: 5),
            .init(stem: "문서화", weight: 5),
            .init(stem: "prd", weight: 5), .init(stem: "제안서", weight: 5),
            .init(stem: "보고서", weight: 5),
            .init(stem: "스펙", weight: 4),
            // 신규 (시나리오 6, 10: "명세서/초안/목차/발표자료" 누락)
            .init(stem: "명세서", weight: 5), .init(stem: "초안", weight: 4),
            .init(stem: "소개글", weight: 4), .init(stem: "안내문", weight: 4),
            .init(stem: "목차", weight: 4), .init(stem: "발표자료", weight: 5),
            .init(stem: "슬라이드", weight: 4), .init(stem: "매뉴얼", weight: 5),
            .init(stem: "이메일", weight: 4), .init(stem: "메일", weight: 4),
            .init(stem: "공문", weight: 4), .init(stem: "레터", weight: 4),
            // 문서 포맷 키워드 (포맷 + "만들어/정리" = 문서 생성)
            .init(stem: "pdf", weight: 5), .init(stem: "워드", weight: 4),
            .init(stem: "엑셀", weight: 4), .init(stem: "한글", weight: 3),
            .init(stem: "hwp", weight: 4), .init(stem: "pptx", weight: 4),
            .init(stem: "ppt", weight: 4), .init(stem: "xlsx", weight: 4),
            .init(stem: "docx", weight: 4),
        ],
        negatives: [
            // 코딩/구현 맥락이면 documentation이 아님
            .init(stem: "구현", weight: -3), .init(stem: "코딩", weight: -3),
            .init(stem: "빌드", weight: -3), .init(stem: "배포", weight: -3),
        ],
        threshold: 4
    )

    // MARK: task — 코딩, 구현, 수정, 배포

    static let task = IntentVocabulary(
        intent: .task,
        positives: [
            // 분석 (research와 겹침 — task는 "코드 분석" 맥락에서만)
            .init(stem: "찾아", weight: 2),
            // 요건/테스트/태스크
            .init(stem: "요건", weight: 3), .init(stem: "요구사항", weight: 3),
            .init(stem: "requirements", weight: 3),
            .init(stem: "테스트", weight: 3), .init(stem: "테스트계획", weight: 4),
            .init(stem: "테스트케이스", weight: 4), .init(stem: "test plan", weight: 4),
            .init(stem: "tc", weight: 3),
            .init(stem: "설계", weight: 4), .init(stem: "전략", weight: 3),
            .init(stem: "아키텍처", weight: 4), .init(stem: "architecture", weight: 4),
            .init(stem: "작업분해", weight: 3), .init(stem: "task breakdown", weight: 3),
            .init(stem: "쪼개", weight: 2),
            // 정리/작성 (범용)
            .init(stem: "정리", weight: 3), .init(stem: "작성", weight: 3),
            // 번역
            .init(stem: "번역", weight: 4), .init(stem: "translate", weight: 4),
            .init(stem: "翻訳", weight: 4),
            // 요약
            .init(stem: "요약", weight: 4), .init(stem: "summarize", weight: 4),
            .init(stem: "summary", weight: 4),
            // 변환/포맷
            .init(stem: "바꿔", weight: 3), .init(stem: "변환", weight: 4),
            .init(stem: "convert", weight: 4), .init(stem: "컨버트", weight: 4),
            // 문서 포맷 (documentation과 겹침 — task는 "코드로 pdf 생성" 맥락에서만)
            .init(stem: "pdf", weight: 2), .init(stem: "워드", weight: 2),
            .init(stem: "엑셀", weight: 2),
            .init(stem: "word", weight: 2), .init(stem: "excel", weight: 2),
            .init(stem: "한글", weight: 2), .init(stem: "hwp", weight: 2),
            .init(stem: "markdown", weight: 3), .init(stem: "마크다운", weight: 3),
            // 코딩/개발/빌드
            .init(stem: "구현", weight: 4), .init(stem: "개발", weight: 4),
            .init(stem: "코딩", weight: 5), .init(stem: "coding", weight: 5),
            .init(stem: "만들어", weight: 4), .init(stem: "빌드", weight: 4),
            .init(stem: "build", weight: 4),
            .init(stem: "수정", weight: 4), .init(stem: "버그", weight: 5),
            .init(stem: "bug", weight: 5),
            .init(stem: "리팩토", weight: 4), .init(stem: "refactor", weight: 4),
            .init(stem: "배포", weight: 4), .init(stem: "deploy", weight: 4),
            .init(stem: "fix", weight: 5), .init(stem: "implement", weight: 4),
            .init(stem: "커밋", weight: 3), .init(stem: "commit", weight: 3),
            .init(stem: "pr ", weight: 2), .init(stem: "push", weight: 2),
            // 신규 SQL (이전 분석 B: "ddl 보고 쿼리 짜줘")
            .init(stem: "쿼리", weight: 4), .init(stem: "sql", weight: 4),
            .init(stem: "ddl", weight: 4), .init(stem: "데이터베이스", weight: 3),
        ],
        negatives: [
            .init(stem: "토론", weight: -3), .init(stem: "의견", weight: -2),
            .init(stem: "브레인스토밍", weight: -3), .init(stem: "어떻게생각", weight: -3),
            .init(stem: "조사해", weight: -2), .init(stem: "찾아봐", weight: -2),
            // 문서 포맷/유형 키워드가 있으면 task가 아님
            .init(stem: "제안서", weight: -3), .init(stem: "보고서", weight: -3),
            .init(stem: "기획서", weight: -3), .init(stem: "명세서", weight: -3),
            .init(stem: "정리해", weight: -2),
        ],
        threshold: 4  // 다른 intent와 동일 (3이면 task 과적합)
    )
}
