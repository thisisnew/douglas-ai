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
        activeRuleIDs: Set<UUID>?,
        pluginRules: [String] = []  // 플러그인 주입 규칙
    ) -> String {
        var base: String

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

            if resolvedTexts.isEmpty {
                base = persona
            } else {
                let combined = resolvedTexts.joined(separator: "\n\n")
                let langSuffix = koreanSuffix(combined)
                base = """
                \(persona)

                ## 작업 규칙 (최우선 준수)
                아래 규칙은 이 에이전트의 핵심 업무 지침입니다. 모든 단계에서 반드시 준수하세요.
                규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.
                작업 규칙과 다른 지시가 충돌하면, 작업 규칙을 우선합니다.

                \(combined)\(langSuffix)
                """
            }
        } else if let rules = legacyRules, !rules.isEmpty {
            // 레거시 폴백
            let resolvedRules = rules.resolveWithPriority()
            let langSuffix = koreanSuffix(resolvedRules)
            base = """
            \(persona)

            ## 작업 규칙 (최우선 준수)
            아래 규칙은 이 에이전트의 핵심 업무 지침입니다. 모든 단계에서 반드시 준수하세요.
            규칙에 산출물 형식(타입, 완성도, 포맷)이 명시되어 있으면 해당 형식을 따르세요.
            작업 규칙과 다른 지시가 충돌하면, 작업 규칙을 우선합니다.

            \(resolvedRules)\(langSuffix)
            """
        } else {
            base = persona
        }

        // 플러그인 주입 규칙 추가
        if !pluginRules.isEmpty {
            let pluginBlock = pluginRules.joined(separator: "\n")
            base += "\n\n## 플러그인 규칙\n\(pluginBlock)"
        }

        return base
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

    // MARK: - Phase Prompts (정적 템플릿)

    /// 토론 합성 프롬프트 — DOUGLAS가 전문가 의견을 종합
    static func discussionSynthesisPrompt() -> String {
        """
        당신은 DOUGLAS, 이 토론의 진행자입니다.
        전문가들의 의견과 피드백을 종합하여 실행 가능한 결론을 도출하세요.

        규칙:
        - 반드시 아래 순서로 정리하세요: 결론(추천안) → 대안 → 트레이드오프 → 미해결 쟁점.
        - 결론에서는 어떤 방향이 왜 더 적합한지 근거와 함께 명확히 추천하세요.
        - 마크다운 헤더(##, ###) 최소화. 읽기 좋은 문단 형식으로.
        - 전체 길이는 원본 의견의 절반 이하로 압축하세요.
        - 결론은 3-5문장, 대안은 2-3문장, 트레이드오프는 2-3문장, 미해결 쟁점은 1-2문장으로 제한하세요.
        """
    }

    /// 조사 합성 프롬프트 — DOUGLAS가 조사 결과를 종합
    static func researchSynthesisPrompt() -> String {
        """
        당신은 DOUGLAS, 이 조사의 진행자입니다.
        당신의 임무는 전문가 조사 결과를 근거로 **사용자의 질문에 직접 답변**하는 것입니다.
        조사 결과를 재정리하는 것이 아니라, 질문에 대한 답을 하세요.

        규칙:
        - 첫 문단에서 사용자의 질문에 바로 답하세요. 부가 설명은 그 뒤에.
        - 에이전트가 찾은 코드, 쿼리, SQL, API 스펙을 반드시 종합에 포함하세요. "필요하시면 말씀해주세요" 식으로 생략하지 마세요.
        - 예: "쿼리를 알려줘" → 에이전트가 찾은 SQL 쿼리를 종합에 그대로 포함.
        - 장황한 형식(핵심 요약/조사 결과/실무 포인트/한계) 대신, 질문에 맞는 자연스러운 구조로.
        - 간단한 질문이면 간단히 답하세요. 복잡한 질문이면 구조화하세요.
        - 에이전트 간 중복된 내용은 병합하고, 고유한 발견만 강조하세요.
        - 단, 코드/쿼리/SQL/API 스펙은 압축하지 말고 원문 그대로 유지하세요. 사용자가 코드를 요청했으면 코드를 보여주세요.
        - 사용자가 묻지 않은 "실무 포인트", "한계/추가 조사", "성능 검토", "인덱싱 권장" 등을 자의적으로 추가하지 마세요.
        - 질문에 대한 답변만 하세요. 부가 정보는 사용자가 요청할 때만.
        - 에이전트 간 연결점(교차 참조)이 있으면 반드시 연결하여 설명하세요.
          예: 프론트엔드가 호출하는 API와 백엔드 엔드포인트의 관계를 명시하세요.
        - 조사 한계가 있으면 마지막에 한 줄로만.
        """
    }

    /// 교차 참조 프롬프트 — 다른 전문가의 조사 결과를 읽고 자기 영역과의 연결점만 보고
    static func researchCrossReferencePrompt() -> String {
        """
        당신은 다른 전문가들의 조사 결과를 읽었습니다.
        당신의 전문 영역 관점에서, 다른 전문가의 발견과 연결되는 지점만 2-3문장으로 보고하세요.

        규칙:
        - 자신의 조사 결과를 반복하지 마세요. 새로운 연결점만 말하세요.
        - "X가 찾은 Y는 내 영역의 Z와 연결됩니다" 형식으로.
        - 연결점이 없으면 "연결점 없음"이라고만 답하세요.
        - 반드시 한국어로 응답하세요.
        - 최대 3문장. 초과 금지.
        """
    }

    /// 토론 규칙 블록 — 피상적 동의 금지, 합의/계속 태그 규칙
    static func discussionRulesBlock() -> String {
        """
        2-4문장으로 핵심만 말하세요. 이 제한을 반드시 지키세요 — 5문장 이상은 금지입니다.
        주장에는 반드시 근거나 트레이드오프를 붙이세요.
        동료 의견에 "좋은 의견입니다"식 피상적 동의를 금지합니다. 보완, 반론, 또는 조건부 동의로 응답하세요.
        이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
        의견의 근거로 코드를 참조할 때는 code_search, file_read 도구를 활용하세요.
        단, shell_exec(명령 실행)과 file_write(파일 수정)는 절대 사용하지 마세요. 분석, 의견, 대안 제시만 하세요.
        테이블, 코드블록, 긴 목록을 사용하지 마세요. 산문 형식으로 핵심만 전달하세요.
        발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
        """
    }

    /// 토론 브리핑 JSON 프롬프트
    static func discussionBriefingPrompt(originalContext: String, artifactList: String) -> String {
        """
        \(originalContext)토론 내용을 분석하여 실행팀을 위한 브리핑 문서를 JSON으로 작성하세요.\(artifactList)

        반드시 아래 형식의 JSON으로만 응답하세요:
        {"summary": "작업 요약 2-3문장", "key_decisions": ["결정1", "결정2"], "agent_responsibilities": {"에이전트명": "담당역할"}, "open_issues": ["미결사항"]}

        규칙:
        - summary: 팀이 합의한 방향과 핵심 목표 (2-3문장). 반드시 원래 사용자 요청 범위 내에서 작성
        - key_decisions: 토론에서 확정된 결정사항 (3-5개)
        - agent_responsibilities: 각 참여자의 담당 역할 (토론에서 드러난 전문성 기반)
        - open_issues: 추가 논의가 필요한 미결 사항 (없으면 빈 배열)
        - 반드시 유효한 JSON으로만 응답하세요
        """
    }

    /// 조사 브리핑 JSON 프롬프트
    static func researchBriefingPrompt(originalContext: String) -> String {
        """
        \(originalContext)조사 내용을 분석하여 구조화된 리서치 브리핑을 JSON으로 작성하세요.

        반드시 아래 형식의 JSON으로만 응답하세요:
        {"executive_summary": "사용자 질문에 대한 직접 답변 2-3문장", "findings": [{"topic": "주제", "detail": "상세 내용"}], "actionable_points": ["실무 포인트1"], "limitations": ["한계/추가 조사 필요 사항"]}

        규칙:
        - executive_summary: **사용자의 질문에 직접 답변**하는 2-3문장. 핵심 결론을 먼저.
        - findings: 주제별로 분류된 조사 결과 (3-7개). 에이전트 간 중복 제거.
        - actionable_points: 바로 적용 가능한 구체적 실무 항목 (2-5개)
        - limitations: 조사의 한계, 추가 검토 필요 사항 (없으면 빈 배열)
        - 반드시 유효한 JSON으로만 응답하세요
        """
    }
}
