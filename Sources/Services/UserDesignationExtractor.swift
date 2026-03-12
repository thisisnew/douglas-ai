import Foundation

/// 사용자 메시지에서 직접 지명한 에이전트/역할 추출 (개선안 H)
/// "백엔드/프론트/기획 관점에서" → ["백엔드", "프론트", "기획"]
struct UserDesignationExtractor {

    /// 사용자 메시지에서 역할 지명 패턴 추출
    /// - Returns: 추출된 역할 이름 배열 (없으면 빈 배열)
    static func extract(from message: String) -> [String] {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // 패턴 1: "A/B/C 관점에서" 또는 "A, B, C 관점에서"
        let viewpointPattern = extractBeforeKeyword(text, keywords: ["관점에서", "입장에서", "시각에서", "측면에서"])
        if !viewpointPattern.isEmpty { return viewpointPattern }

        // 패턴 2: "A, B, C로 토론" 또는 "A랑 B랑 C가"
        let participantPattern = extractBeforeKeyword(text, keywords: ["로 토론", "이랑", "랑", "으로 논의", "에게"])
        if !participantPattern.isEmpty { return participantPattern }

        // 패턴 3: "에이전트: A, B, C" 명시적 지정
        if let agentList = extractAfterKeyword(text, keywords: ["에이전트:", "에이전트 :", "agents:"]) {
            return agentList
        }

        return []
    }

    // MARK: - 내부

    /// "키워드" 앞의 슬래시/쉼표 구분 역할 추출
    private static func extractBeforeKeyword(_ text: String, keywords: [String]) -> [String] {
        for keyword in keywords {
            guard let range = text.range(of: keyword) else { continue }
            let before = String(text[text.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 마지막 절(문장 구분자 이후)만 사용
            let lastClause = before.components(separatedBy: CharacterSet(charactersIn: ".。!?"))
                .last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? before

            let roles = splitRoles(lastClause)
            if !roles.isEmpty { return roles }
        }
        return []
    }

    /// "키워드" 뒤의 역할 목록 추출
    private static func extractAfterKeyword(_ text: String, keywords: [String]) -> [String]? {
        for keyword in keywords {
            guard let range = text.range(of: keyword, options: .caseInsensitive) else { continue }
            let after = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let roles = splitRoles(after)
            if !roles.isEmpty { return roles }
        }
        return nil
    }

    /// 슬래시, 쉼표, "과/와/이랑/랑" 등으로 역할 분리
    private static func splitRoles(_ text: String) -> [String] {
        // 먼저 슬래시로 시도
        var parts = text.components(separatedBy: "/")
        if parts.count < 2 {
            // 쉼표로 시도
            parts = text.components(separatedBy: ",")
        }
        if parts.count < 2 {
            // "과", "와", "이랑", "랑"으로 시도
            parts = text.components(separatedBy: CharacterSet(charactersIn: " "))
                .filter { !["과", "와", "이랑", "랑", "그리고", "및"].contains($0) }
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 20 }  // 너무 긴 건 역할명이 아님
    }
}
