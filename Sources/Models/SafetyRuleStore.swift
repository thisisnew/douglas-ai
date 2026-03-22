import Foundation

/// 프로젝트 안전 규칙을 UserDefaults에 저장/로드
enum SafetyRuleStore {
    private static let key = "projectSafetyRules"

    static func loadRules() -> [SafetyRule] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SafetyRule].self, from: data)) ?? []
    }

    static func saveRules(_ rules: [SafetyRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func addRule(_ rule: SafetyRule) {
        var rules = loadRules()
        rules.append(rule)
        saveRules(rules)
    }

    static func removeRule(id: UUID) {
        var rules = loadRules()
        rules.removeAll { $0.id == id }
        saveRules(rules)
    }
}
