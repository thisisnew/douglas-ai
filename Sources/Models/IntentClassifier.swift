import Foundation

/// 사용자 요청의 의도를 분류하는 2단계 분류기
/// 1단계: 규칙 기반 즉시 판별 (키워드 매칭)
/// 2단계: LLM 분류 (규칙 판별 실패 시)
enum IntentClassifier {

    // MARK: - 규칙 기반 즉시 분류

    /// 키워드 매칭으로 즉시 분류. 판별 불가 시 nil 반환
    static func quickClassify(_ task: String) -> WorkflowIntent? {
        let lowered = task.lowercased()

        // quickAnswer: 단순 질문/번역
        let quickKeywords = ["뭐야", "뭐에요", "뭔가요", "알려줘", "알려주세요",
                             "번역", "translate", "翻訳",
                             "몇 ", "어디", "언제", "누가", "왜 "]
        if quickKeywords.contains(where: { lowered.contains($0) })
            && task.count < 100
            && !containsActionKeywords(lowered) {
            return .quickAnswer
        }

        // brainstorm
        let brainstormKeywords = ["브레인스토밍", "아이디어", "brainstorm",
                                  "토론하자", "회의하자", "의견", "같이 생각"]
        if brainstormKeywords.contains(where: { lowered.contains($0) }) {
            return .brainstorm
        }

        // research (자문/상담/조언도 리서치 계열)
        let researchKeywords = ["조사", "리서치", "research", "트렌드",
                                "비교해", "분석해", "찾아봐", "서베이", "survey",
                                "자문", "상담", "조언", "컨설팅", "consulting",
                                "알고싶", "알고 싶", "궁금"]
        if researchKeywords.contains(where: { lowered.contains($0) })
            && !containsActionKeywords(lowered) {
            return .research
        }

        // documentation
        let docKeywords = ["기획서", "문서 작성", "문서화", "PRD", "스펙",
                           "제안서", "보고서", "정리해", "작성해"]
        if docKeywords.contains(where: { lowered.contains($0) })
            && !containsCodingKeywords(lowered) {
            return .documentation
        }

        // implementation (강한 코딩 신호)
        let implKeywords = ["구현", "개발해", "코딩", "만들어", "빌드",
                            "수정해", "버그", "리팩토", "배포", "fix",
                            "implement", "deploy", "refactor"]
        if implKeywords.contains(where: { lowered.contains($0) }) {
            return .implementation
        }

        // 테스트 계획
        if lowered.contains("테스트 계획") || lowered.contains("test plan") {
            return .testPlanning
        }

        // 요건 분석
        if lowered.contains("요건 분석") || lowered.contains("requirements") {
            return .requirementsAnalysis
        }

        // 작업 분해
        if lowered.contains("작업 분해") || lowered.contains("task breakdown") || lowered.contains("쪼개") {
            return .taskDecomposition
        }

        return nil
    }

    // MARK: - LLM 기반 분류

    /// LLM을 사용하여 의도 분류. 실패 시 implementation 폴백
    static func classifyWithLLM(
        task: String,
        provider: any AIProvider,
        model: String
    ) async -> WorkflowIntent {
        let systemPrompt = """
        당신은 사용자 요청 분류기입니다. 아래 카테고리 중 하나만 출력하세요.

        카테고리:
        - quickAnswer: 단순 질문, 번역, 정보 확인 (짧은 답변으로 끝나는 것)
        - research: 조사, 리서치, 트렌드 분석, 비교 분석, 자문, 상담, 조언, 전문가 의견
        - brainstorm: 브레인스토밍, 아이디어 회의, 자유 토론
        - documentation: 기획서, 문서 작성, PRD, 보고서
        - implementation: 코딩, 개발, 버그 수정, 구현, 배포
        - requirementsAnalysis: 요건 분석, 요구사항 정리
        - testPlanning: 테스트 계획 수립
        - taskDecomposition: 작업 분해, 태스크 쪼개기

        카테고리 이름만 한 단어로 출력하세요. 다른 내용은 절대 출력하지 마세요.
        """

        do {
            let response = try await provider.sendMessage(
                model: model,
                systemPrompt: systemPrompt,
                messages: [("user", task)]
            )

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return parseIntent(from: trimmed)
        } catch {
            return .implementation
        }
    }

    // MARK: - 헬퍼

    private static func parseIntent(from text: String) -> WorkflowIntent {
        switch text {
        case "quickanswer", "quick_answer":     return .quickAnswer
        case "research":                        return .research
        case "brainstorm":                      return .brainstorm
        case "documentation":                   return .documentation
        case "implementation":                  return .implementation
        case "requirementsanalysis",
             "requirements_analysis":           return .requirementsAnalysis
        case "testplanning", "test_planning":   return .testPlanning
        case "taskdecomposition",
             "task_decomposition":              return .taskDecomposition
        default:                                return .implementation
        }
    }

    private static func containsActionKeywords(_ text: String) -> Bool {
        let actionWords = ["구현", "개발해", "개발하자", "개발 해", "만들어", "코딩", "수정", "빌드", "배포"]
        return actionWords.contains(where: { text.contains($0) })
    }

    private static func containsCodingKeywords(_ text: String) -> Bool {
        let codingWords = ["코드", "코딩", "구현", "개발", "빌드", ".swift", ".ts", ".py"]
        return codingWords.contains(where: { text.contains($0) })
    }
}
