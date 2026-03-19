import Testing
import Foundation
@testable import DOUGLAS

@Suite("AgentMatcher Jira issueType 매칭")
struct AgentMatcherJiraTests {

    private static func makeAgent(name: String, skillTags: [String] = [], workModes: Set<WorkMode> = []) -> Agent {
        Agent(
            name: name,
            persona: "\(name) 전문가입니다.",
            providerName: "test",
            modelName: "test",
            skillTags: skillTags,
            workModes: workModes
        )
    }

    @Test("Bug issueType → tester/reviewer 에이전트 보너스")
    func bugIssueType_prefersTestAgent() {
        let tester = Self.makeAgent(name: "QA 엔지니어", skillTags: ["qa", "test", "버그"], workModes: [.review])
        let developer = Self.makeAgent(name: "백엔드 개발자", skillTags: ["backend", "api"], workModes: [.execute])

        let score = AgentMatcher.jiraIssueTypeBonus(issueType: "Bug", agent: tester)
        let devScore = AgentMatcher.jiraIssueTypeBonus(issueType: "Bug", agent: developer)

        #expect(score > devScore)
    }

    @Test("Story issueType → implementer 에이전트 보너스")
    func storyIssueType_prefersImplementer() {
        let developer = Self.makeAgent(name: "백엔드 개발자", skillTags: ["backend"], workModes: [.execute, .create])
        let tester = Self.makeAgent(name: "QA 엔지니어", skillTags: ["qa"], workModes: [.review])

        let devScore = AgentMatcher.jiraIssueTypeBonus(issueType: "Story", agent: developer)
        let qaScore = AgentMatcher.jiraIssueTypeBonus(issueType: "Story", agent: tester)

        #expect(devScore > qaScore)
    }

    @Test("알 수 없는 issueType → 보너스 0")
    func unknownIssueType_noBonus() {
        let agent = Self.makeAgent(name: "범용", skillTags: ["general"])
        let score = AgentMatcher.jiraIssueTypeBonus(issueType: "Unknown", agent: agent)
        #expect(score == 0)
    }
}
