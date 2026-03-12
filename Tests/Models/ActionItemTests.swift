import Testing
import Foundation
@testable import DOUGLAS

@Suite("ActionItem Tests")
struct ActionItemTests {

    @Test("ActionItem 기본 생성")
    func basicCreation() {
        let item = ActionItem(description: "API 설계")
        #expect(item.description == "API 설계")
        #expect(item.priority == 2)  // 기본값
        #expect(item.suggestedAgentName == nil)
        #expect(item.rationale == nil)
        #expect(item.dependencies == nil)
    }

    @Test("ActionItem 전체 필드")
    func fullCreation() {
        let item = ActionItem(
            description: "UI 구현",
            suggestedAgentName: "프론트엔드",
            priority: 1,
            rationale: "사용자 경험 우선",
            dependencies: [0]
        )
        #expect(item.suggestedAgentName == "프론트엔드")
        #expect(item.priority == 1)
        #expect(item.rationale == "사용자 경험 우선")
        #expect(item.dependencies == [0])
    }

    @Test("ActionItem Identifiable — UUID 자동 생성")
    func identifiable() {
        let a = ActionItem(description: "A")
        let b = ActionItem(description: "B")
        #expect(a.id != b.id)
    }

    @Test("ActionItem Equatable")
    func equatable() {
        let id = UUID()
        let a = ActionItem(id: id, description: "같은 항목")
        let b = ActionItem(id: id, description: "같은 항목")
        #expect(a == b)
    }

    @Test("ActionItem Codable")
    func codable() throws {
        let item = ActionItem(
            description: "테스트 작성",
            suggestedAgentName: "QA",
            priority: 1,
            rationale: "품질 보장",
            dependencies: [0, 1]
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(decoded.description == item.description)
        #expect(decoded.suggestedAgentName == item.suggestedAgentName)
        #expect(decoded.priority == item.priority)
        #expect(decoded.dependencies == item.dependencies)
    }

    @Test("ActionItem 의존성 체인")
    func dependencyChain() {
        let items = [
            ActionItem(description: "API 설계", priority: 1),
            ActionItem(description: "UI 구현", priority: 2, dependencies: [0]),
            ActionItem(description: "통합 테스트", priority: 3, dependencies: [0, 1]),
        ]
        #expect(items[0].dependencies == nil)
        #expect(items[1].dependencies == [0])
        #expect(items[2].dependencies == [0, 1])
    }
}
