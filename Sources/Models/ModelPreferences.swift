import Foundation

/// 카테고리별 선호 모델 매핑 (UserDefaults 저장)
enum ModelPreferences {
    private static let defaultsKey = "ModelPreferences"

    struct Mapping: Codable, Equatable {
        var provider: String
        var model: String
    }

    /// 카테고리별 저장된 선호 매핑 로드
    static func preferred(for category: AgentCategory) -> Mapping? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: Mapping].self, from: data) else {
            return nil
        }
        return dict[category.rawValue]
    }

    /// 모든 카테고리의 매핑 로드
    static func all() -> [AgentCategory: Mapping] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: Mapping].self, from: data) else {
            return [:]
        }
        var result: [AgentCategory: Mapping] = [:]
        for (key, value) in dict {
            if let cat = AgentCategory(rawValue: key) {
                result[cat] = value
            }
        }
        return result
    }

    /// 카테고리별 매핑 저장
    static func set(_ mapping: Mapping?, for category: AgentCategory) {
        var dict = allRaw()
        if let mapping {
            dict[category.rawValue] = mapping
        } else {
            dict.removeValue(forKey: category.rawValue)
        }
        save(dict)
    }

    /// 전체 매핑 저장
    static func setAll(_ mappings: [AgentCategory: Mapping]) {
        var dict: [String: Mapping] = [:]
        for (cat, mapping) in mappings {
            dict[cat.rawValue] = mapping
        }
        save(dict)
    }

    /// 에이전트의 카테고리에 맞는 모델 오버라이드 적용
    /// 반환: (providerName, modelName) — 오버라이드 없으면 에이전트 원래 값
    static func resolvedModel(for agent: Agent) -> (provider: String, model: String) {
        let category = agent.resolvedCategory
        if let mapping = preferred(for: category) {
            return (mapping.provider, mapping.model)
        }
        return (agent.providerName, agent.modelName)
    }

    // MARK: - Private

    private static func allRaw() -> [String: Mapping] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: Mapping].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func save(_ dict: [String: Mapping]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
