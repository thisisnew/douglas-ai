import Foundation

// MARK: - 에이전트 매칭 (시스템 주도 Assembly)

/// 역할 요구사항을 기존 에이전트와 매칭 (이름 + 페르소나 + 작업 규칙 키워드 기반)
enum AgentMatcher {

    /// 역할 요구사항을 기존 에이전트와 매칭
    static func matchRoles(
        requirements: [RoleRequirement],
        agents: [Agent]
    ) -> [RoleRequirement] {
        var results = requirements
        var usedAgentIDs: Set<UUID> = []

        for i in results.indices {
            if let matched = findByKeyword(roleName: results[i].roleName, agents: agents, excluding: usedAgentIDs) {
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

    // MARK: - Private

    /// 매칭에서 제외할 범용 접미사 (false positive 방지)
    private static let genericSuffixes: Set<String> = [
        "전문가", "개발자", "엔지니어", "담당자", "관리자", "분석가", "설계자", "디자이너",
        "expert", "developer", "engineer", "manager", "analyst", "designer"
    ]

    /// 이름 + 페르소나 + 작업 규칙 키워드 기반 매칭
    private static func findByKeyword(roleName: String, agents: [Agent], excluding used: Set<UUID>) -> Agent? {
        let keywords = roleName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !genericSuffixes.contains($0) }

        guard !keywords.isEmpty else { return nil }

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

            // 최소 점수 3 이상 (이름 매칭 1회 이상 필요, 페르소나만으로는 부족)
            if score >= 3, score > (bestMatch?.score ?? 0) {
                bestMatch = (agent, score)
            }
        }

        return bestMatch?.agent
    }
}
