import Foundation

/// Research 에이전트 조사 계획 — 순서 + 서브태스크 분해
struct ResearchPlan {
    let orderedAgents: [Agent]
    let subtasks: [String: String]  // agentName → 해당 에이전트의 서브태스크 (없으면 원본 사용)
}

/// Research 에이전트 조사 계획 수립 — 순수 도메인 서비스
/// 순서 결정 + 태스크 분해를 LLM 1회 호출로 동시 수행
enum ResearchOrderService {

    /// LLM 기반 조사 계획 수립 (순서 + 서브태스크 분해)
    /// 실패 시 휴리스틱 폴백 (원본 태스크 그대로 전달)
    static func planResearch(
        task: String,
        agents: [Agent],
        provider: AIProvider,
        model: String
    ) async -> ResearchPlan {
        guard agents.count >= 2 else {
            return ResearchPlan(orderedAgents: agents, subtasks: [:])
        }

        let agentNames = agents.map(\.name)

        let systemPrompt = """
        당신은 조사 진행자입니다. 조사 요청을 전문가별 서브태스크로 분해하고 최적의 조사 순서를 결정하세요.

        원칙:
        - 정보를 먼저 발견하는 전문가가 먼저 조사합니다.
        - 나중 순서의 전문가는 앞선 전문가의 결과를 참고할 수 있습니다.
        - 각 서브태스크는 해당 전문가의 전문 영역에 한정하세요.
        - 앞 전문가에게는 "찾기/확인"만, 뒤 전문가에게는 "추적/구현 찾기"를 맡기세요.
          예: "API 찾고 쿼리 알려줘" → 프론트엔드: "화면에서 API URL과 파라미터 찾기", 백엔드: "해당 API의 실제 쿼리 구현 찾기"

        반드시 아래 JSON 형식으로만 응답하세요:
        {"order": ["에이전트1", "에이전트2"], "subtasks": {"에이전트1": "서브태스크1", "에이전트2": "서브태스크2"}, "reason": "이유 (1문장)"}
        """

        let userMessage = "[조사 요청] \(task)\n\n[전문가 목록] \(agentNames.joined(separator: ", "))"

        do {
            let response = try await provider.sendRouterMessage(
                model: model,
                systemPrompt: systemPrompt,
                messages: [("user", userMessage)]
            )
            if let plan = parseResearchPlan(from: response, agents: agents, agentNames: agentNames) {
                return plan
            }
        } catch {
            // LLM 실패 → 휴리스틱 폴백
        }

        return ResearchPlan(orderedAgents: heuristicOrder(agents: agents), subtasks: [:])
    }

    // MARK: - 파싱

    /// LLM 응답에서 ResearchPlan 파싱
    private static func parseResearchPlan(from response: String, agents: [Agent], agentNames: [String]) -> ResearchPlan? {
        // JSON 추출 (코드블록 지원)
        guard let orderedNames = DiscussionOrderParser.parse(from: response, agentNames: agentNames) else { return nil }
        let reordered = orderedNames.compactMap { name in agents.first(where: { $0.name == name }) }
        guard reordered.count == agents.count else { return nil }

        // subtasks 파싱
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subtasksRaw = json["subtasks"] as? [String: String] else {
            // order는 파싱 성공, subtasks만 실패 → order만 사용
            return ResearchPlan(orderedAgents: reordered, subtasks: [:])
        }

        return ResearchPlan(orderedAgents: reordered, subtasks: subtasksRaw)
    }

    /// LLM 응답에서 JSON 블록 추출
    private static func extractJSON(from response: String) -> String {
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            return String(response[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            return String(response[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}") {
            return String(response[start...end])
        }
        return response
    }

    // MARK: - 레거시 호환

    /// 순서만 결정 (기존 determineOrder 호환)
    static func determineOrder(
        task: String,
        agents: [Agent],
        provider: AIProvider,
        model: String
    ) async -> [Agent] {
        let plan = await planResearch(task: task, agents: agents, provider: provider, model: model)
        return plan.orderedAgents
    }

    // MARK: - 휴리스틱

    /// 휴리스틱 폴백: 프론트엔드 에이전트 먼저 (안정 정렬)
    static func heuristicOrder(agents: [Agent]) -> [Agent] {
        agents.sorted { a, b in
            let aIsFE = isFrontendAgent(a.name)
            let bIsFE = isFrontendAgent(b.name)
            if aIsFE && !bIsFE { return true }
            if !aIsFE && bIsFE { return false }
            return false
        }
    }

    /// 프론트엔드 에이전트 감지
    static func isFrontendAgent(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("프론트엔드") || lower.contains("frontend") || lower.contains("ui")
    }
}
