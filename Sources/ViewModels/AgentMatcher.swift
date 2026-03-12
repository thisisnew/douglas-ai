import Foundation

// MARK: - 에이전트 매칭 (시스템 주도 Assembly)

/// 역할 요구사항을 기존 에이전트와 매칭 (키워드 + NLEmbedding 시맨틱 하이브리드)
enum AgentMatcher {

    /// NLEmbedding 기반 시맨틱 매처 (캐시 포함)
    static let semanticMatcher = SemanticMatcher()

    /// 역할 요구사항을 기존 에이전트와 매칭 (Plan C: 3단 가중치 + 신뢰도 임계값)
    static func matchRoles(
        requirements: [RoleRequirement],
        agents: [Agent],
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        taskBrief: TaskBrief? = nil
    ) -> [RoleRequirement] {
        var results = requirements
        var usedAgentIDs: Set<UUID> = []

        for i in results.indices {
            let (agent, confidence) = matchByTags(
                roleName: results[i].roleName,
                agents: agents,
                excluding: usedAgentIDs,
                intent: intent,
                documentType: documentType,
                taskBrief: taskBrief
            )

            results[i].confidence = confidence

            if let agent {
                results[i].matchedAgentID = agent.id
                if confidence >= 0.7 {
                    results[i].status = .matched       // 자동 선택
                } else if confidence >= 0.5 {
                    results[i].status = .suggested      // 사용자 확인 필요
                } else {
                    results[i].status = .unmatched      // 제외
                    results[i].matchedAgentID = nil
                }
                if results[i].status == .matched || results[i].status == .suggested {
                    usedAgentIDs.insert(agent.id)
                }
            } else {
                results[i].status = .unmatched
            }
        }

        return results
    }

    /// 필수 역할 중 매칭된 비율 (0.0 ~ 1.0)
    static func coverageRatio(_ requirements: [RoleRequirement]) -> Double {
        let required = requirements.filter { $0.priority == .required }
        guard !required.isEmpty else { return 1.0 }
        let matched = required.filter { $0.status == .matched || $0.status == .suggested }
        return Double(matched.count) / Double(required.count)
    }

    /// 최소 커버리지 (필수 역할 50%+) 충족 여부
    static func checkMinimumCoverage(_ requirements: [RoleRequirement]) -> Bool {
        coverageRatio(requirements) >= 0.5
    }

    /// artifact:role_requirements 산출물에서 RoleRequirement 파싱
    static func parseRoleRequirements(from content: String) -> [RoleRequirement] {
        // 형식: "- [필수] 역할이름: 사유" 또는 "- [선택] 역할이름: 사유"
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [") else { return nil }

            let priority: RoleRequirement.Priority
            if trimmed.contains("[필수]") {
                priority = .required
            } else if trimmed.contains("[선택]") {
                priority = .optional
            } else {
                priority = .required  // 기본값
            }

            // "] " 이후 텍스트에서 "역할: 사유" 추출
            guard let bracketEnd = trimmed.range(of: "] ") else { return nil }
            let remaining = String(trimmed[bracketEnd.upperBound...])

            let parts = remaining.split(separator: ":", maxSplits: 1)
            let roleName = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
            let reason = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            guard !roleName.isEmpty else { return nil }
            return RoleRequirement(roleName: roleName, reason: reason, priority: priority)
        }
    }

    // MARK: - 동의어 사전 (개선안 E)

    /// 약어/영문/한국어 동의어 그룹 — 같은 배열 내 키워드는 동의어
    private static let synonymGroups: [[String]] = [
        ["fe", "프론트엔드", "프론트", "frontend", "front-end"],
        ["be", "백엔드", "백앤드", "backend", "back-end", "서버"],
        ["devops", "인프라", "sre", "클라우드", "cloud", "배포"],
        ["qa", "테스트", "test", "품질", "quality"],
        ["pm", "기획", "기획자", "product", "프로덕트"],
        ["ux", "ui", "디자인", "design", "디자이너"],
        ["ml", "ai", "머신러닝", "딥러닝", "데이터"],
        ["security", "보안", "인증", "auth"],
        ["dba", "데이터베이스", "db", "database"],
        ["문서", "docs", "documentation", "테크니컬라이팅"],
    ]

    /// 키워드를 동의어로 확장 (원본 포함)
    static func expandSynonyms(_ keywords: [String]) -> [String] {
        var expanded = Set(keywords)
        for kw in keywords {
            let lower = kw.lowercased()
            for group in synonymGroups {
                if group.contains(where: { $0 == lower }) {
                    expanded.formUnion(group)
                }
            }
        }
        return Array(expanded)
    }

    // MARK: - 키워드 필터

    /// 범용 접미사 여부 확인 (외부에서 사전 매칭 시 사용)
    static func isGenericSuffix(_ keyword: String) -> Bool {
        genericSuffixes.contains(keyword)
    }

    /// 매칭에서 제외할 범용 접미사 (false positive 방지)
    private static let genericSuffixes: Set<String> = [
        "전문가", "개발자", "엔지니어", "담당자", "관리자", "분석가", "설계자", "디자이너",
        "expert", "developer", "engineer", "manager", "analyst", "designer"
    ]

    /// 도메인 키워드 (documentation intent에서 역할명 키워드에서 제외)
    private static let domainKeywords: Set<String> = [
        "백엔드", "프론트엔드", "프론트", "인프라", "데이터", "모바일",
        "ios", "android", "웹", "backend", "frontend", "mobile", "devops",
        "서버", "클라이언트", "db", "database", "cloud", "클라우드"
    ]

    /// Plan C: 3단 가중치 태그 매칭 + 0-1 정규화 신뢰도
    /// 반환: (최고 매칭 에이전트, 신뢰도 0.0~1.0)
    static func matchByTags(
        roleName: String,
        agents: [Agent],
        excluding used: Set<UUID>,
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        taskBrief: TaskBrief? = nil
    ) -> (Agent?, Double) {
        var keywords = roleName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !genericSuffixes.contains($0) }

        // 동의어 확장 (개선안 E): "FE" → ["fe", "프론트엔드", "frontend", ...]
        // 정규화 기준은 원본 키워드 수 (확장으로 분모가 커지는 것 방지)
        let originalKeywordCount = keywords.count
        keywords = expandSynonyms(keywords).filter { $0.count >= 2 && !genericSuffixes.contains($0) }

        if documentType != nil {
            keywords = keywords.filter { !domainKeywords.contains($0) }
        }

        let hasKeywords = !keywords.isEmpty
        let preferredKWs = documentType?.preferredKeywords ?? []
        let useSemanticScoring = semanticMatcher.isAvailable

        guard hasKeywords || useSemanticScoring else { return (nil, 0) }

        // 가중치 상수 (Plan C: 5/2/3)
        let tier1Weight: Double = 5.0  // skillTags 직접 매칭
        let tier2Weight: Double = 2.0  // workModes
        let tier3Weight: Double = 3.0  // 키워드 + 시맨틱 폴백

        var bestMatch: (agent: Agent, confidence: Double)?

        for agent in agents where !used.contains(agent.id) {
            // --- Tier 1: skillTags 직접 매칭 (가중치 5) ---
            var tier1Score: Double = 0
            if hasKeywords, !agent.skillTags.isEmpty {
                let lowerTags = agent.skillTags.map { $0.lowercased() }
                var tagHits = 0
                for keyword in keywords {
                    if lowerTags.contains(where: { $0.contains(keyword) || keyword.contains($0) }) {
                        tagHits += 1
                    }
                }
                for pkw in preferredKWs {
                    if lowerTags.contains(where: { $0.contains(pkw.lowercased()) }) {
                        tagHits += 1
                    }
                }
                let maxPossible = max(originalKeywordCount + preferredKWs.count, 1)
                tier1Score = min(Double(tagHits) / Double(maxPossible), 1.0)  // 0~1
            }

            // --- Tier 2: workModes 매칭 (가중치 2) ---
            // TaskBrief.outputType이 있으면 동적 가중치 (개선안 F)
            var tier2Score: Double = 0
            if !agent.workModes.isEmpty {
                if let outputType = taskBrief?.outputType {
                    // TaskBrief 기반 동적 workMode 가중치
                    switch outputType {
                    case .code:
                        if agent.workModes.contains(.execute) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.create) { tier2Score = 0.9 }
                        else if agent.workModes.contains(.review) { tier2Score = 0.4 }
                    case .document, .message:
                        if agent.workModes.contains(.create) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.review) || agent.workModes.contains(.research) { tier2Score = 0.5 }
                    case .analysis, .data:
                        if agent.workModes.contains(.research) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.review) { tier2Score = 0.7 }
                        else if agent.workModes.contains(.create) { tier2Score = 0.3 }
                    case .design:
                        if agent.workModes.contains(.create) { tier2Score = 1.0 }
                        else if agent.workModes.contains(.review) { tier2Score = 0.5 }
                    case .answer:
                        if agent.workModes.contains(.research) || agent.workModes.contains(.review) { tier2Score = 1.0 }
                    }
                } else if let intent = intent {
                    // 기존 intent 기반 폴백
                    switch intent {
                    case .task, .complex:
                        if agent.workModes.contains(.create) || agent.workModes.contains(.execute) {
                            tier2Score = 1.0
                        } else if agent.workModes.contains(.research) || agent.workModes.contains(.review) {
                            tier2Score = 0.5
                        }
                    case .research:
                        if agent.workModes.contains(.research) {
                            tier2Score = 1.0
                        } else if agent.workModes.contains(.review) {
                            tier2Score = 0.5
                        }
                    case .documentation:
                        if agent.workModes.contains(.create) {
                            tier2Score = 1.0
                        } else if agent.workModes.contains(.review) || agent.workModes.contains(.research) {
                            tier2Score = 0.5
                        }
                    case .quickAnswer, .discussion:
                        if agent.workModes.contains(.research) || agent.workModes.contains(.review) {
                            tier2Score = 1.0
                        }
                    }
                }
            }

            // --- Tier 3: 키워드 + 시맨틱 폴백 (가중치 2) ---
            var tier3Score: Double = 0
            if hasKeywords {
                let lowerPersona = agent.persona.lowercased()
                let lowerName = agent.name.lowercased()
                let lowerRules = (agent.workingRules.flatMap { $0.isEmpty ? nil : $0 }?.resolve() ?? "").lowercased()

                var kwHits = 0
                for keyword in keywords {
                    if lowerName.contains(keyword) { kwHits += 2 }
                    if lowerPersona.contains(keyword) { kwHits += 1 }
                    if lowerRules.contains(keyword) { kwHits += 1 }
                }
                for pkw in preferredKWs {
                    let lower = pkw.lowercased()
                    if lowerName.contains(lower) { kwHits += 1 }
                    if lowerPersona.contains(lower) { kwHits += 1 }
                }

                // 개선안 G: TaskBrief.goal 키워드 → 에이전트 매칭 보너스
                // goal의 핵심 키워드가 에이전트 name/persona에 있으면 추가 점수
                if let goal = taskBrief?.goal, !goal.isEmpty {
                    let goalKeywords = extractSemanticKeywords(from: goal)
                        .filter { $0.count >= 2 && !genericSuffixes.contains($0) }
                    for gkw in goalKeywords {
                        if lowerName.contains(gkw) { kwHits += 1 }
                        if lowerPersona.contains(gkw) { kwHits += 1 }
                    }
                }

                let maxKw = max((originalKeywordCount + preferredKWs.count) * 4, 1)
                let kwScore = min(Double(kwHits) / Double(maxKw), 1.0)

                if useSemanticScoring {
                    let rawSim = semanticMatcher.similarity(roleName: roleName, agent: agent)
                    let semScore = max(0, rawSim)  // 0~1
                    // 개선안 G: TaskBrief.goal도 시맨틱 매칭에 반영
                    var goalSemScore: Double = 0
                    if let goal = taskBrief?.goal, !goal.isEmpty {
                        goalSemScore = max(0, semanticMatcher.similarity(roleName: goal, agent: agent))
                    }
                    let combinedSem = goalSemScore > 0 ? semScore * 0.6 + goalSemScore * 0.4 : semScore
                    tier3Score = kwScore * 0.5 + combinedSem * 0.5
                } else {
                    tier3Score = kwScore
                }
            } else if useSemanticScoring {
                let rawSim = semanticMatcher.similarity(roleName: roleName, agent: agent)
                tier3Score = max(0, rawSim)
            }

            // --- 가중 합산 → 0~1 정규화 ---
            let totalWeight = tier1Weight + tier2Weight + tier3Weight
            let confidence = (tier1Score * tier1Weight + tier2Score * tier2Weight + tier3Score * tier3Weight) / totalWeight

            // skillTags가 비어있으면 Tier 1 무효 → Tier 2+3만으로 재계산
            let adjustedConfidence: Double
            if agent.skillTags.isEmpty {
                let fallbackWeight = tier2Weight + tier3Weight
                adjustedConfidence = (tier2Score * tier2Weight + tier3Score * tier3Weight) / fallbackWeight
            } else {
                adjustedConfidence = confidence
            }

            if adjustedConfidence > (bestMatch?.confidence ?? 0) {
                bestMatch = (agent, adjustedConfidence)
            }
        }

        return (bestMatch?.agent, bestMatch?.confidence ?? 0)
    }

    /// 레거시 호환: 기존 findByKeyword → matchByTags 위임
    private static func findByKeyword(
        roleName: String,
        agents: [Agent],
        excluding used: Set<UUID>,
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil
    ) -> Agent? {
        let (agent, confidence) = matchByTags(
            roleName: roleName, agents: agents, excluding: used,
            intent: intent, documentType: documentType
        )
        return confidence >= 0.3 ? agent : nil
    }

    // MARK: - Fallback 매칭 (LLM 역할 분석 실패 시)

    /// 작업 키워드 기반으로 가장 적합한 에이전트 탐색
    /// - quickAnswer/비개발 작업 시 개발자 에이전트 제외
    /// - task/complex intent + 코드 키워드 → 개발자 에이전트 보너스
    static func findBestFallbackMatch(
        task: String,
        agents: [Agent],
        intent: WorkflowIntent?
    ) -> Agent? {
        let taskKeywords = extractSemanticKeywords(from: task)
        let isQuickAnswer = intent == .quickAnswer
        let taskLower = task.lowercased()

        // 코드/구현 관련 키워드 감지 → 개발자 에이전트에 보너스
        let codeKeywords: Set<String> = ["코드", "구현", "개발", "코딩", "버그", "수정", "리팩토링", "배포",
                                          "code", "implement", "develop", "fix", "refactor", "deploy"]
        let isCodeTask = (intent == .task || intent == .complex) &&
            codeKeywords.contains(where: { taskLower.contains($0) })

        var bestMatch: (agent: Agent, score: Int)?
        for candidate in agents {
            if candidate.isDeveloperAgent && isQuickAnswer { continue }

            var score = 0
            let tags = candidate.skillTags.map { $0.lowercased() }
            for kw in taskKeywords {
                if tags.contains(where: { $0.contains(kw) || kw.contains($0) }) { score += 3 }
                if candidate.name.lowercased().contains(kw) { score += 2 }
                if candidate.persona.lowercased().contains(kw) { score += 1 }
            }

            // 코드 작업 + 개발자 에이전트 → 보너스 (직접 키워드 매칭 없어도 적합)
            if isCodeTask && candidate.isDeveloperAgent { score += 5 }

            if score > (bestMatch?.score ?? 0) {
                bestMatch = (candidate, score)
            }
        }
        return bestMatch?.agent
    }

    /// 이름으로 에이전트 탐색 (정확 매칭 또는 부분 포함)
    static func findByName(_ name: String, among agents: [Agent]) -> Agent? {
        let target = name.lowercased()
        return agents.first {
            let agentName = $0.name.lowercased()
            return agentName == target
                || agentName.contains(target)
                || target.contains(agentName)
        }
    }

    /// 작업에 적합한 에이전트 이름/페르소나 제안 (생성 제안용)
    static func suggestAgentProfile(
        for task: String,
        intent: WorkflowIntent?,
        taskBrief: TaskBrief? = nil
    ) -> (name: String, persona: String) {
        let lower = task.lowercased()
        if lower.contains("번역") || lower.contains("translate") {
            return ("번역 전문가", "다국어 번역 및 현지화 전문가입니다.")
        }
        if lower.contains("트렌드") || lower.contains("동향") {
            return ("트렌드 분석가", "기술 트렌드와 산업 동향을 분석하는 전문가입니다.")
        }
        if lower.contains("코드") || lower.contains("개발") || lower.contains("구현") {
            return ("소프트웨어 엔지니어", "소프트웨어 설계 및 구현 전문가입니다.")
        }
        if lower.contains("문서") || lower.contains("보고서") || lower.contains("작성") {
            return ("문서 작성 전문가", "보고서, 기획서 등 문서 작성 전문가입니다.")
        }
        if intent == .quickAnswer {
            return ("질의응답 전문가", "다양한 주제에 대해 정확하고 이해하기 쉽게 답변하는 범용 질의응답 전문가입니다.")
        }
        if let brief = taskBrief {
            let domain = brief.goal.prefix(30)
            let name = (brief.outputType == .answer || brief.outputType == .analysis)
                ? "리서치 전문가" : "\(intent?.displayName ?? "범용") 전문가"
            return (name, "\(domain) 관련 질문에 답변하고 분석하는 전문가입니다.")
        }
        return ("범용 전문가", "'\(String(task.prefix(60)))' 작업을 수행하는 전문가입니다.")
    }

    // MARK: - 유사 에이전트 탐지

    /// 새 에이전트 등록 시 유사한 기존 에이전트 탐지 (이름 + 페르소나 양방향 매칭)
    static func findSimilarAgents(
        name: String,
        persona: String,
        among agents: [Agent]
    ) -> [Agent] {
        let newKeywords = extractSemanticKeywords(from: "\(name) \(persona)")
        guard !newKeywords.isEmpty else { return [] }

        return agents.filter { agent in
            let agentText = "\(agent.name) \(agent.persona)".lowercased()
            let agentKeywords = extractSemanticKeywords(from: "\(agent.name) \(agent.persona)")
            let newText = "\(name) \(persona)".lowercased()

            // 양방향: 새→기존, 기존→새 (한쪽이라도 2개+ 겹치면 유사)
            let forward = newKeywords.filter { agentText.contains($0) }.count
            let reverse = agentKeywords.filter { newText.contains($0) }.count

            return max(forward, reverse) >= 2
        }
    }

    // MARK: - 의미 키워드 추출 (한국어 지원)

    /// 한국어 조사 제거 + 스크립트 경계 분리로 의미 키워드 추출
    static func extractSemanticKeywords(from text: String) -> [String] {
        let tokens = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var keywords: Set<String> = []

        for token in tokens {
            let parts = splitByScript(token)
            for part in parts {
                let subparts = part.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 2 }
                for sub in subparts {
                    let stemmed = stripKoreanSuffix(sub)
                    if stemmed.count >= 2 && !genericSuffixes.contains(stemmed) {
                        keywords.insert(stemmed)
                    }
                    // 원형도 보존 (접미사 제거 전 — 정확 매칭용)
                    if sub.count >= 2 && sub != stemmed && !genericSuffixes.contains(sub) {
                        keywords.insert(sub)
                    }
                }
            }
        }

        return Array(keywords)
    }

    /// 한글↔라틴 스크립트 경계에서 분리 (예: "react와" → ["react", "와"])
    private static func splitByScript(_ token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        var prevIsKorean: Bool?

        for char in token {
            let korean = isKoreanCharacter(char)
            if let prev = prevIsKorean, prev != korean, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(char)
            prevIsKorean = korean
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func isKoreanCharacter(_ char: Character) -> Bool {
        char.unicodeScalars.contains {
            (0xAC00...0xD7A3).contains($0.value) ||  // 완성형 한글
            (0x3131...0x3163).contains($0.value)      // 한글 자모
        }
    }

    /// 한국어 조사/어미 제거 (형태소 분석 경량 대체)
    private static func stripKoreanSuffix(_ word: String) -> String {
        for suffix in koreanStripSuffixes {
            if word.hasSuffix(suffix) {
                let stem = String(word.dropLast(suffix.count))
                if stem.count >= 2 { return stem }
            }
        }
        return word
    }

    /// 한국어 조사/접미사 리스트 (긴 접미사부터 — greedy 매칭)
    /// RoomManager+Workflow의 direct matching에서도 사용
    static let koreanStripSuffixes: [String] = [
        "입니다", "습니다", "합니다", "됩니다",
        "으로서", "으로써", "에서의", "한테서", "에게서",
        "에서", "까지", "부터", "으로", "께서", "이랑",
        "하는", "하고", "이며", "에게", "한테", "더러", "보고",
        "을", "를", "이", "가", "은", "는",
        "에", "의", "와", "과", "로", "도", "만", "께", "랑",
    ]
}
