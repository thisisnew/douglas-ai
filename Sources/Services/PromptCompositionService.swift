import Foundation

// MARK: - 프롬프트 조합 서비스

/// Agent의 persona + 작업 규칙을 결합하여 시스템 프롬프트를 생성하는 도메인 서비스
/// Model(Agent)이 문자열 조합 로직을 직접 갖지 않도록 분리
enum PromptCompositionService {

    /// 활성 규칙만 포함한 시스템 프롬프트 생성
    /// - Parameters:
    ///   - persona: 에이전트 페르소나
    ///   - workRules: 신규 작업 규칙 레코드
    ///   - legacyRules: 레거시 작업 규칙 (workRules가 비어있을 때 폴백)
    ///   - activeRuleIDs: nil이면 전체 포함, Set이면 해당 규칙만
    static func compose(
        persona: String,
        workRules: [WorkRule],
        legacyRules: WorkingRulesSource?,
        activeRuleIDs: Set<UUID>?
    ) -> String {
        // 신규 workRules 우선
        if !workRules.isEmpty {
            let activeRules: [WorkRule]
            if let ids = activeRuleIDs {
                activeRules = workRules.filter { ids.contains($0.id) }
            } else {
                activeRules = workRules
            }

            let resolvedTexts = activeRules.compactMap { rule -> String? in
                let text = rule.resolve().trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

            guard !resolvedTexts.isEmpty else { return persona }

            let combined = resolvedTexts.joined(separator: "\n\n")
            let langSuffix = koreanSuffix(combined)
            return """
            \(persona)

            ## 작업 규칙 (최우선 준수)
            아래 규칙은 이 에이전트의 핵심 업무 지침입니다. 모든 단계에서 반드시 준수하세요.
            규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.
            작업 규칙과 다른 지시가 충돌하면, 작업 규칙을 우선합니다.

            \(combined)\(langSuffix)
            """
        }

        // 레거시 폴백
        guard let rules = legacyRules, !rules.isEmpty else {
            return persona
        }
        let resolvedRules = rules.resolveWithPriority()
        let langSuffix = koreanSuffix(resolvedRules)
        return """
        \(persona)

        ## 작업 규칙 (최우선 준수)
        아래 규칙은 이 에이전트의 핵심 업무 지침입니다. 모든 단계에서 반드시 준수하세요.
        규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.
        작업 규칙과 다른 지시가 충돌하면, 작업 규칙을 우선합니다.

        \(resolvedRules)\(langSuffix)
        """
    }

    /// 전체 규칙 포함 편의 메서드
    static func compose(
        persona: String,
        workRules: [WorkRule],
        legacyRules: WorkingRulesSource?
    ) -> String {
        compose(persona: persona, workRules: workRules, legacyRules: legacyRules, activeRuleIDs: nil)
    }

    // MARK: - Private

    private static func koreanSuffix(_ text: String) -> String {
        text.contains("한국어") ? "\n\n[필수] 반드시 한국어로 응답하세요. 영어 사용 금지." : ""
    }
}
