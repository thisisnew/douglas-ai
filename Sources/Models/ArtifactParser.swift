import Foundation

// MARK: - 산출물 파서

enum ArtifactParser {

    // 정규식을 한 번만 컴파일 (매 호출마다 컴파일하면 성능 낭비)
    private static let extractRegex = try? NSRegularExpression(
        pattern: "```artifact:(\\w+)(?:\\s+title=\"([^\"]*?)\")?\\s*\\n([\\s\\S]*?)```"
    )
    private static let stripRegex = try? NSRegularExpression(
        pattern: "```artifact:\\w+(?:\\s+title=\"[^\"]*?\")?\\s*\\n[\\s\\S]*?```"
    )

    /// 메시지에서 artifact 블록 추출. 없으면 빈 배열 반환.
    ///
    /// 형식: ```artifact:<type> title="<title>"\n<content>\n```
    static func extractArtifacts(from content: String, producedBy: String) -> [DiscussionArtifact] {
        guard let regex = extractRegex else { return [] }

        let nsString = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match -> DiscussionArtifact? in
            guard match.numberOfRanges >= 4 else { return nil }

            let typeStr = nsString.substring(with: match.range(at: 1))
            let title: String
            if match.range(at: 2).location != NSNotFound {
                title = nsString.substring(with: match.range(at: 2))
            } else {
                title = typeStr
            }
            let body = nsString.substring(with: match.range(at: 3))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let type = ArtifactType(rawValue: typeStr) ?? .generic

            return DiscussionArtifact(
                type: type,
                title: title,
                content: body,
                producedBy: producedBy
            )
        }
    }

    /// artifact 블록을 메시지 텍스트에서 제거하고 나머지 텍스트 반환
    static func stripArtifactBlocks(from content: String) -> String {
        guard let regex = stripRegex else { return content }
        let nsString = content as NSString
        let result = regex.stringByReplacingMatches(
            in: content,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
