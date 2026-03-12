import Foundation

// MARK: - 포지션 추론 서비스

/// Agent의 workModes + persona 키워드에서 적합한 WorkflowPosition을 추론하는 도메인 서비스
/// Model(Agent)이 NLP 로직을 직접 갖지 않도록 분리
enum PositionInferenceService {

    // MARK: - workModes → Position 매핑
    private static let workModeMapping: [WorkMode: Set<WorkflowPosition>] = [
        .plan: [.planner, .architect],
        .create: [.implementer, .writer],
        .execute: [.implementer],
        .review: [.reviewer, .auditor],
        .research: [.researcher, .analyst],
    ]

    // MARK: - persona 키워드 → Position 매핑
    private static let personaMapping: [(keywords: [String], position: WorkflowPosition)] = [
        (["번역", "translat"], .translator),
        (["qa", "테스트", "test"], .tester),
        (["법", "legal", "컴플라이언스"], .auditor),
        (["pm", "기획", "관리"], .coordinator),
        (["아키텍", "architect", "설계"], .architect),
        (["데이터", "분석", "analy"], .analyst),
        (["콘텐츠", "content", "문서"], .writer),
    ]

    /// workModes + persona 키워드에서 적합한 WorkflowPosition 추론
    static func inferPositions(workModes: Set<WorkMode>, persona: String) -> Set<WorkflowPosition> {
        var positions: Set<WorkflowPosition> = []

        // workModes 기반
        for mode in workModes {
            if let mapped = workModeMapping[mode] {
                positions.formUnion(mapped)
            }
        }

        // persona 키워드 보정
        let lower = persona.lowercased()
        for mapping in personaMapping {
            if mapping.keywords.contains(where: { lower.contains($0) }) {
                positions.insert(mapping.position)
            }
        }

        return positions
    }
}
