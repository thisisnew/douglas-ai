import Foundation

/// 사용자 요청의 의도를 분류하는 2단계 분류기
/// 1단계: 규칙 기반 즉시 판별 (정규식 패턴 매칭)
/// 2단계: LLM 분류 (규칙 판별 실패 시)
enum IntentClassifier {

    // MARK: - 정규식 패턴 (어간 기반, 한국어 어미 변형 자동 커버)

    /// (패턴, intent) 튜플 — 순서대로 평가, 먼저 매칭된 것이 승리
    private static let rules: [(pattern: String, intent: WorkflowIntent, maxLength: Int?, excludeAction: Bool)] = [
        // quickAnswer: 단순 질문 / 번역 / 정보 확인
        // 어간 "뭐/뭘/뭔" + 임의 어미, 의문 어미 "까|지|냐|나|가|야" 등
        (
            "뭐[야냐지임에요가는데니까란]|뭘[까]?|뭔[가데지]|"
            + "알려[줘주달]|설명[해좀]|"
            + "번역|translate|翻訳|"
            + "몇[개번째]?\\s|어디[서에]?\\s|언제|누가|왜\\s|"
            + "어떻[게던]|어떤|차이[가점]|"
            + "[이건뭔]가[요]?|[일될건]까",
            .quickAnswer, 100, true
        ),
        // brainstorm
        (
            "브레인스토밍|아이디어|brainstorm|"
            + "토론[하을]|회의[하을]|의견[을이]?\\s|같이\\s?생각",
            .brainstorm, nil, false
        ),
        // research (자문/상담/조언/궁금 포함)
        (
            "조사[해하]?|리서치|research|트렌드|"
            + "비교[해하]|분석[해하]|찾아[봐보]|서베이|survey|"
            + "자문|상담|조언|컨설팅|consulting|"
            + "알고\\s?싶|궁금",
            .research, nil, true
        ),
        // documentation
        (
            "기획서|문서\\s?작성|문서화|prd|스펙|"
            + "제안서|보고서|정리[해하]|작성[해하]",
            .documentation, nil, false  // excludeCoding은 별도 체크
        ),
        // implementation (강한 코딩 신호)
        (
            "구현[해하]?|개발[해하]\\s|코딩|만들어[줘봐]?|빌드[해하]?|"
            + "수정[해하]|버그|리팩토[링]?|배포[해하]?|"
            + "fix|implement|deploy|refactor",
            .implementation, nil, false
        ),
        // testPlanning
        ("테스트\\s?계획|test\\s?plan", .testPlanning, nil, false),
        // requirementsAnalysis
        ("요건\\s?분석|요구\\s?사항|requirements", .requirementsAnalysis, nil, false),
        // taskDecomposition
        ("작업\\s?분[해해]|task\\s?breakdown|쪼개", .taskDecomposition, nil, false),
    ]

    /// 컴파일된 정규식 캐시 (앱 생명주기 동안 1회만 생성)
    private static let compiledRules: [(regex: NSRegularExpression, intent: WorkflowIntent, maxLength: Int?, excludeAction: Bool)] = {
        rules.compactMap { rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, rule.intent, rule.maxLength, rule.excludeAction)
        }
    }()

    // MARK: - 규칙 기반 즉시 분류

    /// 정규식 패턴 매칭으로 즉시 분류. 판별 불가 시 nil 반환
    static func quickClassify(_ task: String) -> WorkflowIntent? {
        let text = task.lowercased()

        // Jira/외부 URL만 넣은 경우: 의도를 알 수 없으므로 사용자에게 선택하게 함
        if containsTicketURL(text) && !hasExplicitUserIntent(text) {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)

        for rule in compiledRules {
            // 글자 수 제한 체크
            if let maxLen = rule.maxLength, task.count >= maxLen { continue }

            // 정규식 매칭
            guard rule.regex.firstMatch(in: text, range: range) != nil else { continue }

            // action 키워드 제외 조건
            if rule.excludeAction && matchesPattern(text, pattern: actionPattern) { continue }

            // documentation은 코딩 키워드와 겹치면 스킵
            if rule.intent == .documentation && matchesPattern(text, pattern: codingPattern) { continue }

            return rule.intent
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

    // MARK: - 제외 조건 패턴 (컴파일 캐시)

    private static let actionPattern: NSRegularExpression? =
        try? NSRegularExpression(pattern: "구현[해하]?|개발[해하]\\s|만들어|코딩|수정[해하]|빌드|배포", options: .caseInsensitive)

    private static let codingPattern: NSRegularExpression? =
        try? NSRegularExpression(pattern: "코[드딩]|구현|개발|빌드|\\.swift|\\.ts|\\.py", options: .caseInsensitive)

    private static func matchesPattern(_ text: String, pattern: NSRegularExpression?) -> Bool {
        guard let pattern = pattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.firstMatch(in: text, range: range) != nil
    }

    /// Jira/이슈 트래커 URL 포함 여부
    private static func containsTicketURL(_ text: String) -> Bool {
        let patterns = ["atlassian.net/browse/", "jira.", "github.com/", "/issues/", "/pull/"]
        return patterns.contains(where: { text.contains($0) })
    }

    /// 사용자가 URL 외에 명시적 의도를 작성했는지 (ex: "이거 구현해", "분석해줘")
    private static func hasExplicitUserIntent(_ text: String) -> Bool {
        // Jira 첨부 데이터(--- Jira 티켓 내용 ... --- 끝 ---) 제거 후 사용자 입력만 확인
        let userText: String
        if let jiraStart = text.range(of: "--- jira") {
            userText = String(text[text.startIndex..<jiraStart.lowerBound])
        } else {
            userText = text
        }
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        // URL만 있고 다른 텍스트가 거의 없으면 명시적 의도 없음
        let withoutURLs = trimmed.replacingOccurrences(
            of: "https?://[^\\s]+",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutURLs.count > 5
    }
}
