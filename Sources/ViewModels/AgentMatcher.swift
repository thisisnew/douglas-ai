import Foundation

// MARK: - 에이전트 매칭 (시스템 주도 Assembly)

/// 역할 요구사항을 기존 에이전트와 매칭 (이름 + 페르소나 + 작업 규칙 키워드 기반)
enum AgentMatcher {

    /// 역할 요구사항을 기존 에이전트와 매칭
    static func matchRoles(
        requirements: [RoleRequirement],
        agents: [Agent],
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil
    ) -> [RoleRequirement] {
        var results = requirements
        var usedAgentIDs: Set<UUID> = []

        for i in results.indices {
            if let matched = findByKeyword(
                roleName: results[i].roleName,
                agents: agents,
                excluding: usedAgentIDs,
                intent: intent,
                documentType: documentType
            ) {
                results[i].matchedAgentID = matched.id
                results[i].status = .matched
                usedAgentIDs.insert(matched.id)
                continue
            }

            results[i].status = .unmatched
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

    /// 이름 + 페르소나 + 작업 규칙 키워드 기반 매칭
    private static func findByKeyword(
        roleName: String,
        agents: [Agent],
        excluding used: Set<UUID>,
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil
    ) -> Agent? {
        var keywords = roleName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !genericSuffixes.contains($0) }

        // Documentation intent: 도메인 키워드 제거 (백엔드/프론트엔드 등)
        if intent == .documentation {
            keywords = keywords.filter { !domainKeywords.contains($0) }
        }

        guard !keywords.isEmpty else { return nil }

        let preferredKWs = (intent == .documentation) ? (documentType?.preferredKeywords ?? []) : []

        var bestMatch: (agent: Agent, score: Int)?

        for agent in agents where !used.contains(agent.id) {
            let lowerPersona = agent.persona.lowercased()
            let lowerName = agent.name.lowercased()
            let lowerRules = (agent.workingRules.flatMap { $0.isEmpty ? nil : $0 }?.resolve() ?? "").lowercased()
            var score = 0

            for keyword in keywords {
                if lowerName.contains(keyword) { score += 3 }
                if lowerPersona.contains(keyword) { score += 2 }
                if lowerRules.contains(keyword) { score += 1 }
            }

            // Documentation preferredKeywords 보너스
            for pkw in preferredKWs {
                let lower = pkw.lowercased()
                if lowerName.contains(lower) { score += 2 }
                if lowerPersona.contains(lower) { score += 2 }
            }

            // 최소 점수 2 이상 (페르소나 키워드 매칭만으로도 충분)
            if score >= 2, score > (bestMatch?.score ?? 0) {
                bestMatch = (agent, score)
            }
        }

        return bestMatch?.agent
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

    /// 긴 접미사부터 시도 (greedy 매칭)
    private static let koreanStripSuffixes: [String] = [
        "입니다", "습니다", "합니다", "됩니다",
        "으로서", "으로써", "에서의",
        "에서", "까지", "부터", "으로",
        "하는", "하고", "이며", "에게",
        "을", "를", "이", "가", "은", "는",
        "에", "의", "와", "과", "로", "도", "만",
    ]
}
