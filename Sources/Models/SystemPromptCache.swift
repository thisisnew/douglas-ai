import Foundation

/// 시스템 프롬프트 캐시 — 같은 에이전트+규칙 조합의 반복 생성 방지
struct SystemPromptCache {
    private var store: [String: String] = [:]

    /// 캐시 키 생성: agentID + activeRuleIDs 정렬 해시
    private func cacheKey(agentID: UUID, activeRuleIDs: Set<UUID>?) -> String {
        let rulesPart: String
        if let ids = activeRuleIDs {
            rulesPart = ids.map { $0.uuidString }.sorted().joined(separator: ",")
        } else {
            rulesPart = "all"
        }
        return "\(agentID.uuidString)|\(rulesPart)"
    }

    mutating func get(agentID: UUID, activeRuleIDs: Set<UUID>?) -> String? {
        store[cacheKey(agentID: agentID, activeRuleIDs: activeRuleIDs)]
    }

    mutating func set(_ prompt: String, agentID: UUID, activeRuleIDs: Set<UUID>?) {
        store[cacheKey(agentID: agentID, activeRuleIDs: activeRuleIDs)] = prompt
    }

    mutating func invalidateAll() {
        store.removeAll()
    }
}
