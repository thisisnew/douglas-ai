import Foundation

/// 채팅 입력에서 `@에이전트이름` 멘션을 파싱하는 유틸리티
enum MentionParser {

    /// 파싱 결과: 매칭된 에이전트 목록 + 멘션 제거된 순수 텍스트
    struct Result {
        let mentions: [Agent]
        let cleanText: String
    }

    /// 텍스트에서 `@이름` 멘션을 추출하고, 매칭된 멘션만 제거한 순수 텍스트 반환
    ///
    /// 2단계 매칭:
    /// 1. 전체 이름 매칭 (긴 이름 우선): `@백엔드 개발자` → "백엔드 개발자" (다중 단어 지원)
    /// 2. 접두어 매칭: `@번역` → "번역가" (단일 후보일 때만)
    static func parse(_ text: String, agents: [Agent]) -> Result {
        guard text.contains("@") else {
            return Result(mentions: [], cleanText: text)
        }

        var mentionedAgents: [Agent] = []
        var cleanText = text

        // Phase 1: 전체 이름 매칭 (긴 이름 우선 — greedy)
        let sortedAgents = agents.sorted { $0.name.count > $1.name.count }
        for agent in sortedAgents {
            let mention = "@\(agent.name)"
            while let range = cleanText.range(of: mention, options: .caseInsensitive) {
                // @ 앞이 문장 시작 또는 공백인 경우만 (이메일 오탐 방지)
                guard isWordBoundary(range.lowerBound, in: cleanText) else { break }

                if !mentionedAgents.contains(where: { $0.id == agent.id }) {
                    mentionedAgents.append(agent)
                }
                cleanText.removeSubrange(range)
            }
        }

        // Phase 2: 접두어 매칭 (남은 @패턴 → 단일 후보 시 매칭)
        let pattern = try! NSRegularExpression(pattern: "(?:^|\\s)@(\\S+)", options: [])
        var nsClean = cleanText as NSString
        var prefixMatches = pattern.matches(in: cleanText, range: NSRange(location: 0, length: nsClean.length))
        var rangesToRemove: [Range<String.Index>] = []

        for match in prefixMatches {
            guard match.numberOfRanges >= 2 else { continue }
            let nameRange = match.range(at: 1)
            let mentionName = nsClean.substring(with: nameRange).lowercased()

            let alreadyMentioned = Set(mentionedAgents.map(\.id))
            let candidates = agents.filter { agent in
                agent.name.lowercased().hasPrefix(mentionName) &&
                !alreadyMentioned.contains(agent.id)
            }
            if candidates.count == 1, let agent = candidates.first {
                mentionedAgents.append(agent)
                if let swiftRange = Range(match.range(at: 0), in: cleanText) {
                    rangesToRemove.append(swiftRange)
                }
            }
        }

        // 뒤에서부터 제거 (인덱스 밀림 방지)
        for range in rangesToRemove.reversed() {
            cleanText.removeSubrange(range)
        }

        cleanText = cleanText.trimmingCharacters(in: .whitespaces)
        while cleanText.contains("  ") {
            cleanText = cleanText.replacingOccurrences(of: "  ", with: " ")
        }

        return Result(mentions: mentionedAgents, cleanText: cleanText)
    }

    /// @ 위치가 문장 시작 또는 공백 뒤인지 확인
    private static func isWordBoundary(_ index: String.Index, in text: String) -> Bool {
        if index == text.startIndex { return true }
        return text[text.index(before: index)].isWhitespace
    }
}
