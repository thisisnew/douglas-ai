import Foundation

/// Slack 메시지 포맷 ↔ 일반 텍스트 변환
enum SlackMessageParser {
    /// Slack 포맷 제거: <@U123> 멘션, <url|label> 등
    static func extractCleanText(_ text: String) -> String {
        var result = text

        // <@U...> 사용자 멘션 제거
        result = result.replacingOccurrences(
            of: "<@[A-Z0-9]+>",
            with: "",
            options: .regularExpression
        )

        // <url|label> → label
        result = result.replacingOccurrences(
            of: "<(https?://[^|>]+)\\|([^>]+)>",
            with: "$2",
            options: .regularExpression
        )

        // <url> → url
        result = result.replacingOccurrences(
            of: "<(https?://[^>]+)>",
            with: "$1",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DOUGLAS 응답을 Slack 표시용으로 포맷
    static func formatForSlack(content: String, agentName: String?) -> String {
        var text = content

        if let name = agentName {
            text = "*[\(name)]* \(text)"
        }

        // Slack 메시지 길이 제한 (4000자)
        if text.count > 3900 {
            text = String(text.prefix(3900)) + "\n...(truncated)"
        }

        return text
    }
}
