import Foundation

// MARK: - 에이전트 매칭 (시스템 주도 Assembly)

/// 분석가가 산출한 역할 요구사항을 기존 에이전트와 매칭
enum AgentMatcher {

    /// 역할 요구사항을 기존 에이전트와 매칭
    /// 매칭 순서: ① roleTemplateID 정확 매칭 → ② persona 키워드 매칭 → ③ unmatched
    static func matchRoles(
        requirements: [RoleRequirement],
        agents: [Agent]
    ) -> [RoleRequirement] {
        var results = requirements
        var usedAgentIDs: Set<UUID> = []

        for i in results.indices {
            // ① roleTemplateID 기반 정확 매칭
            if let matched = findByTemplateID(roleName: results[i].roleName, agents: agents, excluding: usedAgentIDs) {
                results[i].matchedAgentID = matched.id
                results[i].status = .matched
                usedAgentIDs.insert(matched.id)
                continue
            }

            // ② persona 키워드 매칭
            if let matched = findByPersonaKeyword(roleName: results[i].roleName, agents: agents, excluding: usedAgentIDs) {
                results[i].matchedAgentID = matched.id
                results[i].status = .matched
                usedAgentIDs.insert(matched.id)
                continue
            }

            // ③ 매칭 실패
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

    /// roleTemplateID 기반 매칭 (템플릿 이름 ↔ 역할 이름)
    private static func findByTemplateID(roleName: String, agents: [Agent], excluding used: Set<UUID>) -> Agent? {
        let lowerRole = roleName.lowercased()

        // 빌트인 템플릿에서 역할 이름이 매칭되는 템플릿 ID 찾기
        let matchingTemplateIDs = AgentRoleTemplateRegistry.builtIn
            .filter { template in
                template.name.lowercased().contains(lowerRole) ||
                lowerRole.contains(template.name.lowercased()) ||
                template.id.replacingOccurrences(of: "_", with: " ").contains(lowerRole)
            }
            .map { $0.id }

        // 해당 템플릿 ID를 가진 에이전트 찾기
        return agents.first { agent in
            guard !used.contains(agent.id),
                  let templateID = agent.roleTemplateID else { return false }
            return matchingTemplateIDs.contains(templateID)
        }
    }

    /// persona 키워드 매칭
    private static func findByPersonaKeyword(roleName: String, agents: [Agent], excluding used: Set<UUID>) -> Agent? {
        let keywords = roleName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        guard !keywords.isEmpty else { return nil }

        // 키워드 매칭 점수 기반
        var bestMatch: (agent: Agent, score: Int)?

        for agent in agents where !used.contains(agent.id) {
            let lowerPersona = agent.persona.lowercased()
            let lowerName = agent.name.lowercased()
            var score = 0

            for keyword in keywords {
                if lowerPersona.contains(keyword) { score += 1 }
                if lowerName.contains(keyword) { score += 2 }  // 이름 매칭 가중치
            }

            if score > 0, score > (bestMatch?.score ?? 0) {
                bestMatch = (agent, score)
            }
        }

        return bestMatch?.agent
    }
}
