import Testing
import Foundation
@testable import DOUGLAS

@Suite("RoleRequirement Tests")
struct RoleRequirementTests {

    // MARK: - 초기화

    @Test("RoleRequirement 기본 초기화")
    func defaultInit() {
        let r = RoleRequirement(roleName: "백엔드 개발자")
        #expect(r.roleName == "백엔드 개발자")
        #expect(r.reason == "")
        #expect(r.priority == .required)
        #expect(r.matchedAgentID == nil)
        #expect(r.status == .pending)
    }

    @Test("RoleRequirement 전체 파라미터 초기화")
    func fullInit() {
        let agentID = UUID()
        let id = UUID()
        let r = RoleRequirement(
            id: id,
            roleName: "QA 엔지니어",
            reason: "테스트 자동화 필요",
            priority: .optional,
            matchedAgentID: agentID,
            status: .matched
        )
        #expect(r.id == id)
        #expect(r.roleName == "QA 엔지니어")
        #expect(r.reason == "테스트 자동화 필요")
        #expect(r.priority == .optional)
        #expect(r.matchedAgentID == agentID)
        #expect(r.status == .matched)
    }

    // MARK: - Priority

    @Test("Priority rawValue")
    func priorityRawValues() {
        #expect(RoleRequirement.Priority.required.rawValue == "required")
        #expect(RoleRequirement.Priority.optional.rawValue == "optional")
    }

    @Test("Priority Codable 라운드트립")
    func priorityCodable() throws {
        for p in [RoleRequirement.Priority.required, .optional] {
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(RoleRequirement.Priority.self, from: data)
            #expect(decoded == p)
        }
    }

    // MARK: - MatchStatus

    @Test("MatchStatus rawValue")
    func matchStatusRawValues() {
        #expect(RoleRequirement.MatchStatus.pending.rawValue == "pending")
        #expect(RoleRequirement.MatchStatus.matched.rawValue == "matched")
        #expect(RoleRequirement.MatchStatus.suggested.rawValue == "suggested")
        #expect(RoleRequirement.MatchStatus.unmatched.rawValue == "unmatched")
    }

    @Test("MatchStatus Codable 라운드트립")
    func matchStatusCodable() throws {
        for s in [RoleRequirement.MatchStatus.pending, .matched, .suggested, .unmatched] {
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(RoleRequirement.MatchStatus.self, from: data)
            #expect(decoded == s)
        }
    }

    // MARK: - Codable

    @Test("RoleRequirement Codable 라운드트립")
    func codableRoundTrip() throws {
        let r = RoleRequirement(
            roleName: "프론트엔드",
            reason: "UI 작업",
            priority: .required,
            status: .unmatched
        )
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(RoleRequirement.self, from: data)
        #expect(decoded.id == r.id)
        #expect(decoded.roleName == "프론트엔드")
        #expect(decoded.reason == "UI 작업")
        #expect(decoded.priority == .required)
        #expect(decoded.status == .unmatched)
        #expect(decoded.matchedAgentID == nil)
    }

    @Test("RoleRequirement Codable — matchedAgentID 포함")
    func codableWithAgent() throws {
        let agentID = UUID()
        let r = RoleRequirement(
            roleName: "DevOps",
            priority: .optional,
            matchedAgentID: agentID,
            status: .matched
        )
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(RoleRequirement.self, from: data)
        #expect(decoded.matchedAgentID == agentID)
        #expect(decoded.status == .matched)
    }

    @Test("RoleRequirement Identifiable — 고유 ID")
    func identifiable() {
        let a = RoleRequirement(roleName: "A")
        let b = RoleRequirement(roleName: "A")
        #expect(a.id != b.id)
    }

    // MARK: - status 변경

    @Test("RoleRequirement status 변경 가능")
    func statusMutation() {
        var r = RoleRequirement(roleName: "개발자")
        #expect(r.status == .pending)

        r.status = .matched
        r.matchedAgentID = UUID()
        #expect(r.status == .matched)
        #expect(r.matchedAgentID != nil)

        r.status = .unmatched
        r.matchedAgentID = nil
        #expect(r.status == .unmatched)
        #expect(r.matchedAgentID == nil)
    }
}
