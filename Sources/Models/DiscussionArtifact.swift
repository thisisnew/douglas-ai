import Foundation

// MARK: - 산출물 타입

enum ArtifactType: String, Codable, CaseIterable {
    case apiSpec              = "api_spec"
    case testPlan             = "test_plan"
    case taskBreakdown        = "task_breakdown"
    case architectureDecision = "architecture_decision"
    case generic              = "generic"

    var displayName: String {
        switch self {
        case .apiSpec:               return "API 명세"
        case .testPlan:              return "테스트 계획"
        case .taskBreakdown:         return "작업 분해"
        case .architectureDecision:  return "아키텍처 결정"
        case .generic:               return "일반 산출물"
        }
    }

    var icon: String {
        switch self {
        case .apiSpec:               return "doc.text"
        case .testPlan:              return "checklist"
        case .taskBreakdown:         return "list.bullet.indent"
        case .architectureDecision:  return "building.columns"
        case .generic:               return "doc.richtext"
        }
    }
}

// MARK: - 토론 산출물

struct DiscussionArtifact: Identifiable, Codable {
    let id: UUID
    let type: ArtifactType
    let title: String
    let content: String         // 구조화된 마크다운 또는 JSON
    let producedBy: String      // 에이전트 이름
    let createdAt: Date
    var version: Int             // 같은 산출물 업데이트 시 증가

    init(
        id: UUID = UUID(),
        type: ArtifactType,
        title: String,
        content: String,
        producedBy: String,
        createdAt: Date = Date(),
        version: Int = 1
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.producedBy = producedBy
        self.createdAt = createdAt
        self.version = version
    }
}
