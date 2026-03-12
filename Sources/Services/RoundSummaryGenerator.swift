import Foundation

/// 라운드 종료 시 규칙 기반 RoundSummary 생성 (LLM 호출 없음)
enum RoundSummaryGenerator {

    /// 현재 라운드의 메시지 + DecisionLog에서 RoundSummary 생성
    /// - round: 라운드 번호 (0-based)
    /// - messages: 현재 라운드의 토론 메시지
    /// - decisionLog: 전체 DecisionLog (해당 라운드 필터)
    /// - userFeedback: 사용자 피드백 (없으면 nil)
    static func generate(
        round: Int,
        messages: [ChatMessage],
        decisionLog: [DecisionEntry],
        userFeedback: String?
    ) -> RoundSummary {
        let positions = extractPositions(from: messages)
        let agreements = extractAgreements(round: round, decisionLog: decisionLog)
        let disagreements = extractDisagreements(from: messages)

        return RoundSummary(
            round: round,
            agentPositions: positions,
            agreements: agreements,
            disagreements: disagreements,
            userFeedback: userFeedback
        )
    }

    // MARK: - 추출 로직

    /// 각 에이전트 발언의 첫 문장을 stance로 추출
    private static func extractPositions(from messages: [ChatMessage]) -> [AgentPosition] {
        messages.compactMap { msg -> AgentPosition? in
            guard msg.role == .assistant,
                  let agentName = msg.agentName,
                  !msg.content.isEmpty else { return nil }
            let stance = firstSentence(of: msg.content)
            return AgentPosition(agentName: agentName, stance: stance)
        }
    }

    /// DecisionLog에서 해당 라운드의 결정사항 추출
    private static func extractAgreements(round: Int, decisionLog: [DecisionEntry]) -> [String] {
        decisionLog
            .filter { $0.round == round }
            .map { $0.decision }
    }

    /// [반대], [우려] 태그가 포함된 발언에서 쟁점 추출
    private static func extractDisagreements(from messages: [ChatMessage]) -> [String] {
        var disagreements: [String] = []
        let pattern = #"\[(?:반대|우려)\]\s*(.+?)(?:\.|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return disagreements
        }

        for msg in messages where msg.role == .assistant {
            let content = msg.content
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            for match in matches {
                if let captureRange = Range(match.range(at: 1), in: content) {
                    let captured = String(content[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !captured.isEmpty {
                        disagreements.append(captured)
                    }
                }
            }
        }
        return disagreements
    }

    /// 텍스트의 첫 문장 추출 (마침표, 물음표, 느낌표 기준)
    private static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 마침표/물음표/느낌표로 끝나는 첫 문장
        if let endRange = trimmed.range(of: #"[.?!。]"#, options: .regularExpression) {
            return String(trimmed[trimmed.startIndex...endRange.lowerBound])
        }
        // 문장 부호 없으면 첫 줄 (최대 100자)
        let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
        if firstLine.count > 100 {
            return String(firstLine.prefix(100)) + "…"
        }
        return firstLine
    }
}
