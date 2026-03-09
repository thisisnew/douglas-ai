import Foundation
import NaturalLanguage

// MARK: - Pre-Intent 라우팅

/// 사용자 입력의 사전 분류 결과 (intent 분류 전)
enum PreIntentRoute: Equatable {
    case empty                           // 텍스트 없음 + 파일 없음 → 무시
    case fileOnly                        // 텍스트 없음 + 파일만 → "뭘 할까요?" 대기
    case command(CommandType)            // 명시적 명령 ("에이전트 불러와" 등)
    case classified(WorkflowIntent)      // quickAnswer 또는 task
    case ambiguous                       // 분류 불가 → 사용자 선택 UI
}

/// 시스템 커맨드 종류
enum CommandType: Equatable {
    case summonAgent(name: String?)      // "에이전트 불러와" / "OO에이전트 소환해"
}

// MARK: - Intent 분류기

/// 사용자 요청의 의도를 분류하는 2단계 분류기
/// 1단계: NLTokenizer + 가중치 점수 기반 즉시 판별
/// 2단계: LLM 분류 (점수 판별 실패 시)
enum IntentClassifier {

    // MARK: - Pre-Intent 라우팅

    /// 사전 라우팅: intent 분류 전에 특수 케이스 처리
    static func preRoute(_ text: String, hasAttachments: Bool) -> PreIntentRoute {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) 빈 입력
        if trimmed.isEmpty {
            return hasAttachments ? .fileOnly : .empty
        }

        // 2) 커맨드 감지
        if let command = detectCommand(trimmed) {
            return .command(command)
        }

        // 3) 기존 quickClassify로 intent 분류
        if let intent = quickClassify(trimmed) {
            return .classified(intent)
        }

        // 4) 분류 불가 → task가 기본값
        //    단, 짧은 입력(15자 미만)이면서 작업 키워드가 없으면 quickAnswer
        if trimmed.count < 15 {
            let taskKeywords = ["해줘", "해봐", "만들", "고쳐", "수정", "추가", "삭제", "변경", "작성", "개발", "구현", "분석", "조사"]
            let hasTaskKeyword = taskKeywords.contains(where: { trimmed.contains($0) })
            if !hasTaskKeyword {
                return .classified(.quickAnswer)
            }
        }
        return .classified(.task)
    }

    /// 커맨드 감지: "에이전트 불러와" 등 시스템 조작 명령
    private static func detectCommand(_ text: String) -> CommandType? {
        let lower = text.lowercased()

        // 에이전트 소환 패턴 (전체 문장이 소환 명령인 경우만)
        let summonPatterns = [
            "에이전트 불러", "에이전트 가져", "에이전트를 불러", "에이전트를 가져",
            "에이전트 소환", "에이전트를 소환", "에이전트 초대", "에이전트를 초대",
        ]
        // 전체 문장이 짧고(40자 미만) 소환 패턴을 포함해야 커맨드로 인식
        // → "에이전트가 불러오는 방법 알려줘" 같은 질문을 오인하지 않도록
        if lower.count < 40, summonPatterns.contains(where: { lower.contains($0) }) {
            // 에이전트 이름 추출 시도 (ex: "QA에이전트 불러와" → "QA")
            let name = extractAgentName(from: lower)
            return .summonAgent(name: name)
        }
        return nil
    }

    /// 소환 명령에서 에이전트 이름 추출
    private static func extractAgentName(from text: String) -> String? {
        // "OO에이전트" 패턴에서 OO 추출
        if let range = text.range(of: "에이전트") {
            let prefix = String(text[text.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { return prefix }
        }
        return nil
    }

    // MARK: - 키워드 사전 (어간 기반, 가중치 포함)

    /// 키워드 → 가중치. 어간(stem) 기반으로 정의하여 한국어 어미 변형을 prefix 매칭으로 커버
    /// 예: "요약" → "요약해줘", "요약해서", "요약해봐" 모두 매칭
    private struct ScoredKeywords {
        /// (어간, 가중치) 배열. 가중치가 높을수록 해당 intent에 강한 신호
        let stems: [(stem: String, weight: Int)]
        /// 이 intent의 최소 점수 임계값
        let threshold: Int
    }

    /// intent별 키워드 사전 (WORKFLOW_SPEC §4.1: 5-카테고리 + complex는 LLM에서만 판별)
    private static let intentKeywords: [(intent: WorkflowIntent, keywords: ScoredKeywords)] = [
        // quickAnswer: 단순 질문 / 정보 확인 (짧은 텍스트에서만 유효)
        (.quickAnswer, ScoredKeywords(stems: [
            // 의문사
            ("뭐", 3), ("뭘", 3), ("뭔", 3), ("무슨", 3),
            ("몇", 2), ("어디", 2), ("언제", 2), ("누가", 2), ("왜", 2),
            ("어떻", 2), ("어떤", 2),
            // 설명 요청
            ("알려", 3), ("설명", 3),
            // 의미/뜻
            ("뜻", 3), ("의미", 3), ("차이", 2),
        ], threshold: 3)),

        // discussion: 의견 교환, 브레인스토밍, 관점 탐색
        (.discussion, ScoredKeywords(stems: [
            // 의견/생각 요청
            ("어떻게 생각", 5), ("생각해", 4), ("의견", 3), ("관점", 3), ("견해", 3),
            // 토론/브레인스토밍
            ("토론", 4), ("브레인스토밍", 4), ("brainstorm", 4), ("아이디어", 3),
            ("회의", 3),
            // 비교/판단
            ("장단점", 3), ("좋을까", 3), ("어떨까", 3), ("어떤 게 나을", 4),
            // 전망/트렌드 — 의견 프레임
            ("트렌드", 4), ("전망", 3), ("미래", 2),
            // 지식 탐색
            ("알고싶", 2),
        ], threshold: 4)),

        // research: 자료 수집, 검색, 비교, 정리 (WORKFLOW_SPEC §4.1)
        (.research, ScoredKeywords(stems: [
            ("조사", 5), ("리서치", 5), ("research", 5),
            ("서베이", 4), ("survey", 4),
        ], threshold: 4)),

        // documentation: 문서 파일 작성 (WORKFLOW_SPEC §4.1)
        (.documentation, ScoredKeywords(stems: [
            ("기획서", 5), ("문서작성", 5), ("문서화", 5),
            ("prd", 5), ("제안서", 5), ("보고서", 5),
            ("스펙", 4),
        ], threshold: 4)),

        // task: 코딩, 구현, 수정, 배포 등 구현 작업
        (.task, ScoredKeywords(stems: [
            // 분석/비교
            ("분석", 4), ("비교", 3), ("찾아", 2),
            // 자문/상담
            ("자문", 3), ("상담", 3), ("조언", 3), ("컨설팅", 3), ("consulting", 3),
            ("궁금", 2),
            // 요건/테스트/태스크
            ("요건", 3), ("요구사항", 3), ("requirements", 3),
            ("테스트", 3), ("테스트계획", 4), ("테스트케이스", 4), ("test plan", 4), ("tc", 3),
            ("설계", 4), ("전략", 3), ("아키텍처", 4), ("architecture", 4),
            ("작업분해", 3), ("task breakdown", 3), ("쪼개", 2),
            // 정리/작성 (범용)
            ("정리", 3), ("작성", 3),
            // 번역
            ("번역", 4), ("translate", 4), ("翻訳", 4),
            // 요약
            ("요약", 4), ("summarize", 4), ("summary", 4),
            // 변환/포맷
            ("바꿔", 3), ("변환", 4), ("convert", 4), ("컨버트", 4),
            // 문서 포맷
            ("pdf", 5), ("워드", 4), ("엑셀", 4),
            ("word", 4), ("excel", 4), ("한글", 3), ("hwp", 4),
            ("markdown", 3), ("마크다운", 3),
            // 코딩/개발/빌드
            ("구현", 4), ("개발", 3), ("코딩", 5), ("coding", 5),
            ("만들어", 3), ("빌드", 4), ("build", 4),
            ("수정", 3), ("버그", 5), ("bug", 5),
            ("리팩토", 4), ("refactor", 4),
            ("배포", 4), ("deploy", 4),
            ("fix", 5), ("implement", 4),
            ("커밋", 3), ("commit", 3), ("pr ", 2), ("push", 2),
        ], threshold: 3)),
    ]

    // MARK: - NLTokenizer 기반 분류

    /// NLTokenizer + 가중치 점수 기반 즉시 분류. 판별 불가 시 nil 반환
    static func quickClassify(_ task: String) -> WorkflowIntent? {
        let text = task.lowercased()
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)

        // 인사말/간단한 대화: quickAnswer로 즉시 반환
        // 짧은 텍스트(20자 미만)이면서 인사말 패턴이면 quickAnswer
        if trimmed.count < 20 {
            let greetings = [
                "안녕", "반갑", "하이", "헬로", "hello", "hi ", "hey",
                "좋은 아침", "좋은 저녁", "굿모닝", "굿나잇",
                "잘 지내", "오랜만", "수고",
                "ㅎㅇ", "ㅎㅎ", "ㅋㅋ", "감사", "고마워", "땡큐", "thank",
            ]
            if greetings.contains(where: { text.contains($0) }) {
                return .quickAnswer
            }
        }

        // Jira/외부 URL만 넣은 경우: 의도를 알 수 없으므로 사용자에게 선택하게 함
        if containsTicketURL(text) && !hasExplicitUserIntent(text) {
            return nil
        }

        // 짧은 단순 변환 요청 (< 30자): 번역/요약/추출 등은 quickAnswer — 6단계 불필요
        // 단, 복합 지표(pdf, 파일 생성 등)가 있으면 task로 유지
        if task.count < 30 {
            let simpleTransformKeywords = ["번역", "translate", "요약", "summarize", "추출", "extract"]
            let complexIndicators = ["pdf", "워드", "엑셀", "word", "excel", "만들어", "파일", "문서", "보고서", "작성", "코드", "개발", "구현"]
            let hasSimpleTransform = simpleTransformKeywords.contains(where: { text.contains($0) })
            let hasComplex = complexIndicators.contains(where: { text.contains($0) })
            if hasSimpleTransform && !hasComplex {
                return .quickAnswer
            }
        }

        // NLTokenizer로 토큰 추출
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }

        // 각 intent별 점수 계산
        var scores: [(intent: WorkflowIntent, score: Int)] = []

        for entry in intentKeywords {
            var score = 0

            // quickAnswer는 긴 텍스트에서 약화 (100자 이상이면 점수 반감)
            let lengthPenalty = (entry.intent == .quickAnswer && task.count >= 100) ? 0.5 : 1.0

            for keyword in entry.keywords.stems {
                // 어간 prefix 매칭: 토큰이 keyword.stem으로 시작하거나, 전체 텍스트에 keyword.stem 포함
                let matched = tokens.contains { token in
                    token.hasPrefix(keyword.stem) || token == keyword.stem
                } || text.contains(keyword.stem)

                if matched {
                    score += keyword.weight
                }
            }

            let adjustedScore = Int(Double(score) * lengthPenalty)
            if adjustedScore >= entry.keywords.threshold {
                scores.append((entry.intent, adjustedScore))
            }
        }

        // 최고 점수 intent 반환 (동점이면 task > quickAnswer 우선)
        guard !scores.isEmpty else { return nil }
        let maxScore = scores.max(by: { a, b in
            if a.score != b.score { return a.score < b.score }
            return intentPriority(a.intent) < intentPriority(b.intent)
        })
        return maxScore?.intent
    }

    /// intent 우선순위 (동점 해소용): task > documentation > research > discussion > quickAnswer
    private static func intentPriority(_ intent: WorkflowIntent) -> Int {
        switch intent {
        case .complex:       return 5
        case .task:          return 4
        case .documentation: return 3
        case .research:      return 2
        case .discussion:    return 2
        case .quickAnswer:   return 1
        }
    }

    /// NLTokenizer로 텍스트를 단어 토큰으로 분리
    private static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            if token.count >= 1 {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }

    // MARK: - LLM 기반 분류

    /// LLM을 사용하여 의도 분류. 실패 시 quickAnswer 폴백
    static func classifyWithLLM(
        task: String,
        provider: any AIProvider,
        model: String
    ) async -> WorkflowIntent {
        let systemPrompt = """
        당신은 사용자 요청 분류기입니다. 아래 카테고리 중 하나만 출력하세요.

        카테고리:
        - quickAnswer: 단순 질문, 정보 확인, 뜻/의미 질문 (짧은 답변으로 끝나는 것)
        - discussion: 의견 요청, 브레인스토밍, 관점 탐색, 장단점 비교, 트렌드/전망에 대한 의견 교환
        - research: 자료 수집, 검색, 비교 정리, 사례 조사, 레퍼런스 탐색
        - documentation: 문서 파일 작성 — 기획서, 보고서, 제안서, PRD, 스펙, 회의록
        - task: 코딩, 개발, 버그 수정, 구현, 배포, 리팩토링, 번역, 요약, 문서 변환(PDF/Word 등)
        - complex: 둘 이상의 작업 모드가 혼합된 요청 (예: "조사하고 문서로 정리해줘")

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
            return .quickAnswer
        }
    }

    // MARK: - 헬퍼

    private static func parseIntent(from text: String) -> WorkflowIntent {
        switch text {
        case "quickanswer", "quick_answer":     return .quickAnswer
        case "task":                            return .task
        case "discussion":                      return .discussion
        case "brainstorm":                      return .discussion
        case "research":                        return .research
        case "documentation":                   return .documentation
        case "complex":                         return .complex
        // 레거시 매핑: LLM이 옛 이름을 반환할 경우 task
        case "implementation":                  return .task
        case "requirementsanalysis",
             "requirements_analysis":           return .task
        case "testplanning", "test_planning":   return .task
        case "taskdecomposition",
             "task_decomposition":              return .task
        default:                                return .quickAnswer
        }
    }

    // MARK: - TaskBrief 생성 (Plan C)

    /// LLM을 사용하여 사용자 요청에서 TaskBrief를 생성
    /// - userHasExplicitIntent: 사용자가 URL/파일 외에 구체적 작업 의도를 명시했는지 여부
    static func generateTaskBrief(
        task: String,
        intakeContext: String?,
        clarifySummary: String?,
        userHasExplicitIntent: Bool = true,
        provider: any AIProvider,
        model: String
    ) async -> TaskBrief? {
        let clarificationGuideline: String
        if !userHasExplicitIntent {
            clarificationGuideline = """
            needsClarification 기준:
            - 사용자가 URL이나 파일만 제공하고 구체적 작업을 명시하지 않았습니다.
            - 반드시 needsClarification: true로 설정하세요.
            - questions에 "이 내용을 바탕으로 어떤 작업을 진행할까요? (예: 기획, 개발, 분석, 요약 등)" 같은 질문을 포함하세요.
            """
        } else {
            clarificationGuideline = """
            needsClarification 기준:
            - false (기본값): 요청이 충분히 명확하여 바로 작업 가능
            - URL이나 외부 데이터와 함께 구체적 작업 요청이 있는 경우: false
            - true: 핵심 정보가 누락되어 작업 진행 불가 (수신인, 대상 시스템, 필수 파라미터 등)
            - true일 때 questions에 최대 2개의 구체적 한국어 질문을 포함하세요.

            **절대 clarification하지 않을 것:**
            - "~에 대해 조사해줘", "~에 대해 정리해줘", "~에 대해 알아봐줘" 패턴:
              대상이 무엇인지 조사/리서치하는 것 자체가 작업의 핵심.
              사용자에게 "~가 무엇인가요?"라고 되묻지 마세요. 직접 조사하세요.
            - 사용자가 모르는 것을 알아달라는 요청에 사용자에게 설명을 요구하는 것은 금지.
            - URL/Jira 링크와 함께 작업 요청이 있는 경우: 바로 진행. API 접근, 인증, 권한에 대해 묻지 마세요.
              필요한 데이터는 이미 시스템이 수집했습니다.
            """
        }

        let systemPrompt = """
        사용자의 작업 요청을 분석하여 구조화된 작업 브리프(JSON)를 생성하세요.
        반드시 한국어로 작성하세요. 아래 JSON 형식으로만 출력하세요. 다른 텍스트를 포함하지 마세요.

        {
          "goal": "작업의 핵심 목표 (1-2문장)",
          "constraints": ["제약조건1", "제약조건2"],
          "successCriteria": ["성공기준1", "성공기준2"],
          "nonGoals": ["이 작업에서 하지 않을 것"],
          "overallRisk": "low 또는 medium 또는 high",
          "outputType": "code 또는 document 또는 message 또는 analysis 또는 data 또는 design 또는 answer",
          "needsClarification": false,
          "questions": []
        }

        \(clarificationGuideline)

        overallRisk 기준:
        - low: 읽기 전용, 분석, 설명, 번역, 내부 문서 작성
        - medium: 로컬 파일 수정, 코드 생성, 내부 코드 리팩토링
        - high: 외부 시스템 변경 (Jira, 배포, API 호출, 메시지 발송)

        outputType 기준:
        - code: 소스코드 생성/수정
        - document: 문서, 보고서, 기획서
        - message: 이메일, 메시지, 대응문
        - analysis: 분석 결과, 리서치
        - data: 데이터 처리, 변환, 시각화
        - design: UI/UX 설계
        - answer: 단순 답변, 설명
        """

        var context = task
        if let intake = intakeContext, !intake.isEmpty {
            context = "\(task)\n\n\(intake)"
        }
        if let summary = clarifySummary, !summary.isEmpty {
            context = "요약: \(summary)\n\n\(context)"
        }

        do {
            let response = try await provider.sendMessage(
                model: model,
                systemPrompt: systemPrompt,
                messages: [("user", context)]
            )
            return parseTaskBrief(from: response)
        } catch {
            return nil
        }
    }

    /// JSON 응답에서 TaskBrief 파싱
    private static func parseTaskBrief(from text: String) -> TaskBrief? {
        // JSON 블록 추출 (```json ... ``` 또는 { ... })
        let jsonString: String
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) {
            jsonString = String(text[start.lowerBound...end.upperBound])
        } else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }

        struct BriefDTO: Decodable {
            let goal: String
            let constraints: [String]?
            let successCriteria: [String]?
            let nonGoals: [String]?
            let overallRisk: String?
            let outputType: String?
            let needsClarification: Bool?
            let questions: [String]?
        }

        guard let dto = try? JSONDecoder().decode(BriefDTO.self, from: data) else { return nil }

        return TaskBrief(
            goal: dto.goal,
            constraints: dto.constraints ?? [],
            successCriteria: dto.successCriteria ?? [],
            nonGoals: dto.nonGoals ?? [],
            overallRisk: RiskLevel(rawValue: dto.overallRisk ?? "low") ?? .low,
            outputType: OutputType(rawValue: dto.outputType ?? "answer") ?? .answer,
            needsClarification: dto.needsClarification ?? false,
            questions: Array((dto.questions ?? []).prefix(2))
        )
    }

    /// Jira/이슈 트래커 URL 포함 여부
    private static func containsTicketURL(_ text: String) -> Bool {
        let patterns = ["atlassian.net/browse/", "jira.", "github.com/", "/issues/", "/pull/"]
        return patterns.contains(where: { text.contains($0) })
    }

    /// 사용자가 URL 외에 명시적 의도를 작성했는지 (ex: "이거 구현해", "분석해줘")
    static func hasExplicitUserIntent(_ text: String) -> Bool {
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
        return withoutURLs.count > 2
    }
}
