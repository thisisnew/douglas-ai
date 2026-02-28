import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentMatcher Tests")
struct AgentMatcherTests {

    // MARK: - Helpers

    private func makeAgent(
        name: String,
        persona: String,
        workingRules: WorkingRulesSource? = nil
    ) -> Agent {
        Agent(
            name: name,
            persona: persona,
            providerName: "TestProvider",
            modelName: "test-model",
            workingRules: workingRules
        )
    }

    // MARK: - matchRoles

    @Test("matchRoles — 에이전트 없으면 모두 unmatched")
    func matchRolesNoAgents() {
        let requirements = [
            RoleRequirement(roleName: "백엔드 개발자"),
            RoleRequirement(roleName: "QA 엔지니어")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [])
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .unmatched })
    }

    @Test("matchRoles — 이름 키워드 매칭")
    func matchRolesByName() {
        let agent = makeAgent(name: "백엔드 개발자", persona: "서버 개발 전문")
        let requirements = [
            RoleRequirement(roleName: "백엔드")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        #expect(results[0].status == .matched)
        #expect(results[0].matchedAgentID == agent.id)
    }

    @Test("matchRoles — persona 키워드 매칭")
    func matchRolesByPersona() {
        let agent = makeAgent(
            name: "프론트엔드 개발자",
            persona: "React, TypeScript, UI 개발 전문"
        )
        let requirements = [
            RoleRequirement(roleName: "프론트엔드")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        #expect(results[0].status == .matched)
        #expect(results[0].matchedAgentID == agent.id)
    }

    @Test("matchRoles — 작업 규칙 키워드 매칭")
    func matchRolesByWorkingRules() {
        let agent = makeAgent(
            name: "개발자",
            persona: "코드 작성 전문",
            workingRules: WorkingRulesSource(inlineText: "React 컴포넌트는 함수형으로 작성. TypeScript 필수.")
        )
        let requirements = [
            RoleRequirement(roleName: "React")
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        #expect(results[0].status == .matched)
    }

    @Test("matchRoles — 에이전트 중복 사용 불가")
    func matchRolesNoDuplicateAgent() {
        let agent = makeAgent(name: "개발자", persona: "백엔드 개발 전문")
        let requirements = [
            RoleRequirement(roleName: "백엔드"),
            RoleRequirement(roleName: "백엔드")  // 같은 역할 두 번
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: [agent])
        let matched = results.filter { $0.status == .matched }
        #expect(matched.count == 1)  // 에이전트 하나이므로 하나만 매칭
    }

    @Test("matchRoles — 여러 에이전트 매칭")
    func matchRolesMultiple() {
        let agents = [
            makeAgent(name: "백엔드", persona: "서버 개발"),
            makeAgent(name: "프론트", persona: "UI 개발"),
        ]
        let requirements = [
            RoleRequirement(roleName: "백엔드"),
            RoleRequirement(roleName: "프론트"),
        ]
        let results = AgentMatcher.matchRoles(requirements: requirements, agents: agents)
        let matched = results.filter { $0.status == .matched }
        #expect(matched.count == 2)
    }

    // MARK: - coverageRatio

    @Test("coverageRatio — 필수 역할 없으면 1.0")
    func coverageNoRequired() {
        let requirements = [
            RoleRequirement(roleName: "보조", priority: .optional, status: .unmatched)
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    @Test("coverageRatio — 전체 매칭 시 1.0")
    func coverageFullMatch() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .required, status: .matched),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    @Test("coverageRatio — 절반 매칭 시 0.5")
    func coverageHalf() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .required, status: .unmatched),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 0.5)
    }

    @Test("coverageRatio — suggested도 매칭으로 인정")
    func coverageSuggested() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .suggested),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    @Test("coverageRatio — optional은 계산에서 제외")
    func coverageOptionalExcluded() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .optional, status: .unmatched),
        ]
        #expect(AgentMatcher.coverageRatio(requirements) == 1.0)
    }

    // MARK: - checkMinimumCoverage

    @Test("checkMinimumCoverage — 50% 이상이면 true")
    func minimumCoveragePass() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .matched),
            RoleRequirement(roleName: "B", priority: .required, status: .unmatched),
        ]
        #expect(AgentMatcher.checkMinimumCoverage(requirements) == true)
    }

    @Test("checkMinimumCoverage — 50% 미만이면 false")
    func minimumCoverageFail() {
        let requirements = [
            RoleRequirement(roleName: "A", priority: .required, status: .unmatched),
            RoleRequirement(roleName: "B", priority: .required, status: .unmatched),
            RoleRequirement(roleName: "C", priority: .required, status: .matched),
        ]
        // 1/3 ≈ 0.33 < 0.5
        #expect(AgentMatcher.checkMinimumCoverage(requirements) == false)
    }

    @Test("checkMinimumCoverage — 빈 목록이면 true")
    func minimumCoverageEmpty() {
        #expect(AgentMatcher.checkMinimumCoverage([]) == true)
    }

    // MARK: - parseRoleRequirements

    @Test("parseRoleRequirements — 기본 파싱")
    func parseBasic() {
        let content = """
        - [필수] 백엔드 개발자: API 서버 구축
        - [선택] DevOps: CI/CD 파이프라인
        """
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 2)
        #expect(results[0].roleName == "백엔드 개발자")
        #expect(results[0].reason == "API 서버 구축")
        #expect(results[0].priority == .required)
        #expect(results[1].roleName == "DevOps")
        #expect(results[1].priority == .optional)
    }

    @Test("parseRoleRequirements — 사유 없는 항목")
    func parseNoReason() {
        let content = "- [필수] 프론트엔드"
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 1)
        #expect(results[0].roleName == "프론트엔드")
        #expect(results[0].reason == "")
    }

    @Test("parseRoleRequirements — 빈 문자열")
    func parseEmpty() {
        let results = AgentMatcher.parseRoleRequirements(from: "")
        #expect(results.isEmpty)
    }

    @Test("parseRoleRequirements — 잘못된 형식 무시")
    func parseInvalidFormat() {
        let content = """
        이것은 일반 텍스트
        - 대괄호 없음
        - [필수] 유효한 항목: 포함
        """
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 1)
        #expect(results[0].roleName == "유효한 항목")
    }

    @Test("parseRoleRequirements — 알 수 없는 태그는 required 기본값")
    func parseUnknownTag() {
        let content = "- [중요] 리드 개발자: 총괄"
        let results = AgentMatcher.parseRoleRequirements(from: content)
        #expect(results.count == 1)
        #expect(results[0].priority == .required)  // 기본값
    }
}
