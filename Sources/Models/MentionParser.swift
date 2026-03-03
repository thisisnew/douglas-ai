import Foundation

/// 채팅 입력에서 `@에이전트이름` 멘션을 파싱하는 유틸리티
enum MentionParser {

    /// 파싱 결과: 매칭된 에이전트 목록 + 멘션 제거된 순수 텍스트
    struct Result {
        let mentions: [Agent]
        let cleanText: String
    }

    /// `@이름` 패턴 (문장 시작 또는 공백 뒤에서만 매칭 — 이메일 등 오탐 방지)
    private static let mentionPattern = try! NSRegularExpression(
        pattern: "(?:^|\\s)@(\\S+)",
        options: []
    )

    /// 텍스트에서 `@이름` 멘션을 추출하고, 매칭된 멘션만 제거한 순수 텍스트 반환
    /// - Parameters:
    ///   - text: 사용자 입력 원문
    ///   - agents: 매칭 대상 에이전트 목록 (보통 subAgents)
    /// - Returns: 매칭된 에이전트 + 멘션 제거된 텍스트
    static func parse(_ text: String, agents: [Agent]) -> Result {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = mentionPattern.matches(in: text, range: range)

        guard !matches.isEmpty else {
            return Result(mentions: [], cleanText: text)
        }

        var mentionedAgents: [Agent] = []
        // 매칭된 멘션의 전체 범위 (제거용) — 뒤에서부터 처리
        var rangesToRemove: [NSRange] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let nameRange = match.range(at: 1)
            let mentionName = nsText.substring(with: nameRange)

            if let agent = resolveAgent(name: mentionName, from: agents) {
                // 중복 방지
                if !mentionedAgents.contains(where: { $0.id == agent.id }) {
                    mentionedAgents.append(agent)
                }
                rangesToRemove.append(match.range(at: 0))
            }
            // 미매칭: rangesToRemove에 추가 안 함 → 원문 유지
        }

        // 멘션 제거 (뒤에서부터 제거하여 인덱스 밀림 방지)
        var cleanText = text
        for range in rangesToRemove.reversed() {
            if let swiftRange = Range(range, in: cleanText) {
                cleanText.removeSubrange(swiftRange)
            }
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespaces)
        // 연속 공백 정리
        while cleanText.contains("  ") {
            cleanText = cleanText.replacingOccurrences(of: "  ", with: " ")
        }

        return Result(mentions: mentionedAgents, cleanText: cleanText)
    }

    /// 이름으로 에이전트 매칭 (정확 → 접두어 순)
    private static func resolveAgent(name: String, from agents: [Agent]) -> Agent? {
        let lowered = name.lowercased()

        // 1) 정확 매칭
        if let exact = agents.first(where: { $0.name.lowercased() == lowered }) {
            return exact
        }

        // 2) 접두어 매칭 (축약 허용: "번역" → "번역가")
        let prefixMatches = agents.filter { $0.name.lowercased().hasPrefix(lowered) }
        if prefixMatches.count == 1 {
            return prefixMatches.first
        }

        return nil
    }
}
