import Foundation

/// 토론 히스토리 빌드 — 이전 라운드 요약 + 현재 라운드 전문
enum DiscussionHistoryBuilder {

    /// 토론 히스토리 빌드 (이전 라운드는 RoundSummary 기반 압축)
    /// - currentRound: 현재 토론 라운드 (0-based)
    /// - roundSummaries: 이전 라운드 구조화 요약 (없으면 압축 안 함)
    /// - currentRoundMessages: 현재 라운드의 토론 메시지
    /// - currentAgentName: 현재 발언 에이전트 (자신=assistant, 타인=user)
    static func build(
        currentRound: Int,
        roundSummaries: [RoundSummary],
        currentRoundMessages: [ChatMessage],
        currentAgentName: String?
    ) -> [(role: String, content: String)] {
        var result: [(role: String, content: String)] = []

        // 이전 라운드 요약 주입
        for summary in roundSummaries where summary.round < currentRound {
            result.append((role: "user", content: "[시스템]: \(summary.asSummaryText)"))
        }

        // 현재 라운드 메시지 (전문)
        for msg in currentRoundMessages {
            let mapped = mapMessage(msg, currentAgentName: currentAgentName)
            result.append(mapped)
        }

        return result
    }

    /// ChatMessage → (role, content) 매핑 (자신=assistant, 타인=user)
    private static func mapMessage(_ msg: ChatMessage, currentAgentName: String?) -> (role: String, content: String) {
        var content = msg.content
        let role: String

        switch msg.role {
        case .user:
            role = "user"
        case .assistant:
            if let agentName = msg.agentName, agentName == currentAgentName {
                role = "assistant"
            } else {
                role = "user"
                content = "[\(msg.agentName ?? "에이전트")의 발언]: \(msg.content)"
            }
        case .system:
            role = "user"
            content = "[시스템]: \(msg.content)"
        }

        // 토큰 절감: 메시지당 최대 800자
        if content.count > 800 {
            content = String(content.prefix(800)) + "…"
        }

        return (role: role, content: content)
    }
}
