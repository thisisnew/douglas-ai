import Foundation

/// 태스크 텍스트와 규칙 name+summary를 키워드 매칭하여 활성 규칙 선택
struct WorkRuleMatcher {

    /// 규칙 매칭 — LLM 호출 없이 순수 텍스트 기반
    ///
    /// 1. `isAlwaysActive` 규칙 → 무조건 포함
    /// 2. 각 규칙의 name + summary에서 키워드 추출 (2글자 이상)
    /// 3. 태스크 텍스트에 키워드가 하나라도 포함되면 활성화
    /// 4. 매칭 결과가 isAlwaysActive만이면 → 전체 규칙 포함 (안전 폴백)
    static func match(rules: [WorkRule], taskText: String) -> Set<UUID> {
        guard !rules.isEmpty else { return [] }

        let normalizedTask = taskText.lowercased()
        var matched: Set<UUID> = []
        var hasAlwaysActive = false

        for rule in rules {
            if rule.isAlwaysActive {
                matched.insert(rule.id)
                hasAlwaysActive = true
                continue
            }

            let source = "\(rule.name) \(rule.summary)".lowercased()
            let keywords = extractKeywords(from: source)

            for keyword in keywords {
                if normalizedTask.contains(keyword) {
                    matched.insert(rule.id)
                    break
                }
            }
        }

        // 폴백: alwaysActive 외에 매칭된 게 없으면 전체 포함
        let dynamicMatches = hasAlwaysActive ? matched.count - rules.filter(\.isAlwaysActive).count : matched.count
        if dynamicMatches == 0 {
            return Set(rules.map(\.id))
        }

        return matched
    }

    /// 텍스트에서 매칭용 키워드 추출 (2글자 이상, 소문자)
    private static func extractKeywords(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "·,;/|"))

        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count >= 2 }
    }
}
