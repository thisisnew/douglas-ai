import Foundation

/// ActionItem → 에이전트 배정 서비스
/// suggestedAgentName을 에이전트 ID로 매핑
struct AgentAssigner {

    /// suggestedAgentName → agentID 매핑
    /// 매핑 우선순위:
    /// 1. 명시적 에이전트 이름 (완전 일치)
    /// 2. agentResponsibilities 역할 매칭
    /// 3. 에이전트 이름 부분 매칭 폴백
    static func resolve(
        name: String?,
        stepText: String,
        agents: [(id: UUID, name: String)],
        responsibilities: [String: String]? = nil
    ) -> UUID? {
        guard !agents.isEmpty else { return nil }

        // 1. 명시적 이름 완전 일치
        if let name = name {
            let lower = name.lowercased()
            if let match = agents.first(where: { $0.name.lowercased() == lower }) {
                return match.id
            }

            // 2. agentResponsibilities에서 역할 매칭
            if let responsibilities = responsibilities {
                for (agentName, responsibility) in responsibilities {
                    if responsibility.lowercased().contains(lower) || lower.contains(agentName.lowercased()) {
                        if let match = agents.first(where: { $0.name == agentName }) {
                            return match.id
                        }
                    }
                }
            }

            // 3. 부분 매칭 폴백
            if let match = agents.first(where: {
                $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased())
            }) {
                return match.id
            }
        }

        // 4. 이름 없으면 stepText에서 역할 키워드 매칭 시도
        let stepLower = stepText.lowercased()
        if let responsibilities = responsibilities {
            for (agentName, responsibility) in responsibilities {
                let keywords = responsibility.lowercased().components(separatedBy: .whitespacesAndNewlines)
                    .filter { $0.count >= 2 }
                if keywords.contains(where: { stepLower.contains($0) }) {
                    if let match = agents.first(where: { $0.name == agentName }) {
                        return match.id
                    }
                }
            }
        }

        return nil
    }
}
