import Foundation

/// 토론 결과에서 ActionItems를 파싱/생성하는 서비스
struct ActionItemGenerator {

    /// briefing JSON에서 action_items 배열 파싱
    /// briefing에 "action_items" 키가 있으면 파싱, 없으면 nil
    static func parse(from jsonString: String) -> [ActionItem]? {
        guard let data = extractJSONData(from: jsonString) else { return nil }

        struct BriefingDTO: Decodable {
            let action_items: [ActionItemDTO]?

            // 기존 briefing 필드는 무시
            struct ActionItemDTO: Decodable {
                let description: String
                let suggested_agent: String?
                let priority: Int?
                let rationale: String?
                let dependencies: [Int]?
            }
        }

        guard let dto = try? JSONDecoder().decode(BriefingDTO.self, from: data),
              let items = dto.action_items, !items.isEmpty else {
            return nil
        }

        return items.map { item in
            ActionItem(
                description: item.description,
                suggestedAgentName: item.suggested_agent,
                priority: item.priority ?? 2,
                rationale: item.rationale,
                dependencies: item.dependencies
            )
        }
    }

    /// briefing 프롬프트에 action_items 필드를 추가하기 위한 JSON 스키마 조각
    static let actionItemsSchemaFragment = """
    "action_items": [
      {
        "description": "구체적 작업 설명",
        "suggested_agent": "담당 추천 에이전트 이름 (없으면 null)",
        "priority": 1,
        "rationale": "이 작업이 필요한 이유",
        "dependencies": [0]
      }
    ]
    """

    // MARK: - 내부

    private static func extractJSONData(from text: String) -> Data? {
        // JSON 블록 추출 (```json ... ``` 또는 { ... })
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards),
              start.lowerBound <= end.lowerBound else {
            return nil
        }
        let jsonString = String(text[start.lowerBound...end.lowerBound])
        return jsonString.data(using: .utf8)
    }
}
