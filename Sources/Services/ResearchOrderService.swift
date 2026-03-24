import Foundation

/// Research 에이전트 조사 순서 결정 — 순수 도메인 서비스
/// determineTurn2Order() 패턴 재사용: LLM 기반 순서 결정 + 휴리스틱 폴백
enum ResearchOrderService {

    /// LLM 기반 조사 순서 결정
    /// 안건을 분석하여 "정보 생산자 → 소비자" 순서로 배치
    /// 실패 시 휴리스틱 폴백
    static func determineOrder(
        task: String,
        agents: [Agent],
        provider: AIProvider,
        model: String
    ) async -> [Agent] {
        guard agents.count >= 2 else { return agents }

        let systemPrompt = """
        당신은 조사 진행자입니다. 아래 조사 요청과 전문가 목록을 보고, 최적의 조사 순서를 결정하세요.

        원칙:
        - 정보를 먼저 발견하는 전문가가 먼저 조사합니다.
        - 의존 관계: 화면 → API → 쿼리 체인에서, 화면을 담당하는 전문가가 먼저.
        - 나중에 조사하는 전문가는 앞선 결과를 참고하여 더 정확한 조사가 가능합니다.
          예: "API 찾고 쿼리 알려줘" → 프론트엔드(API 발견) 먼저, 백엔드(쿼리 조사) 나중
          예: "DB 스키마 확인하고 API 설계해줘" → 백엔드 먼저, 프론트엔드 나중

        반드시 아래 JSON 형식으로만 응답하세요:
        {"order": ["에이전트1", "에이전트2", ...], "reason": "순서 결정 이유 (1문장)"}
        """

        let agentNames = agents.map(\.name)
        let userMessage = "[조사 요청] \(task)\n\n[전문가 목록] \(agentNames.joined(separator: ", "))"

        do {
            let response = try await provider.sendRouterMessage(
                model: model,
                systemPrompt: systemPrompt,
                messages: [("user", userMessage)]
            )
            if let orderedNames = DiscussionOrderParser.parse(from: response, agentNames: agentNames) {
                let reordered = orderedNames.compactMap { name in agents.first(where: { $0.name == name }) }
                if reordered.count == agents.count {
                    return reordered
                }
            }
        } catch {
            // LLM 실패 → 휴리스틱 폴백
        }

        return heuristicOrder(agents: agents)
    }

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
