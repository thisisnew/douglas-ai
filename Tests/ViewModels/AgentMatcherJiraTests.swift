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

    // MARK: - Jira 도메인 힌트 → 에이전트 매칭 보너스

    @Test("도메인 힌트 → 매칭 에이전트 confidence 상승")
    func domainHints_boostMatchingAgent() {
        // "개발자"라는 일반적 roleName 사용 → 힌트 없이는 skillTags 매칭이 약함
        let backend = Self.makeAgent(name: "서버 엔지니어", skillTags: ["spring", "jpa", "api"], workModes: [.execute, .create])
        let unrelated = Self.makeAgent(name: "마케터", skillTags: ["마케팅", "광고"], workModes: [.create])
        // evidence가 roleName 동의어 확장과 겹치지 않도록 설정
        let hints = [JiraDomainDetector.DomainHint(domain: "백엔드", evidence: ["api", "spring"])]

        let (agentWithHint, confWithHint) = AgentMatcher.matchByTags(
            roleName: "서버 엔지니어", agents: [backend, unrelated], excluding: [],
            jiraDomainHints: hints
        )
        let (_, confNoHint) = AgentMatcher.matchByTags(
            roleName: "서버 엔지니어", agents: [backend, unrelated], excluding: []
        )

        #expect(agentWithHint?.id == backend.id)
        #expect(confWithHint > confNoHint)
    }

    @Test("도메인 힌트 → 무관 에이전트에 영향 없음")
    func domainHints_noEffectOnUnrelatedAgent() {
        let frontend = Self.makeAgent(name: "프론트엔드 개발자", skillTags: ["react", "css", "화면"], workModes: [.create])
        let backendHints = [JiraDomainDetector.DomainHint(domain: "백엔드", evidence: ["api", "서버"])]

        let (_, confWithHint) = AgentMatcher.matchByTags(
            roleName: "화면 개발자", agents: [frontend], excluding: [],
            jiraDomainHints: backendHints
        )
        let (_, confNoHint) = AgentMatcher.matchByTags(
            roleName: "화면 개발자", agents: [frontend], excluding: []
        )

        // 백엔드 힌트가 프론트엔드 에이전트 스코어에 영향 없음
        #expect(confWithHint == confNoHint)
    }

    @Test("빈 도메인 힌트 → 보너스 없음")
    func emptyDomainHints_noBonus() {
        let agent = Self.makeAgent(name: "백엔드 개발자", skillTags: ["backend", "api"], workModes: [.execute])

        let (_, confEmpty) = AgentMatcher.matchByTags(
            roleName: "개발자", agents: [agent], excluding: [],
            jiraDomainHints: []
        )
        let (_, confNone) = AgentMatcher.matchByTags(
            roleName: "개발자", agents: [agent], excluding: []
        )

        #expect(confEmpty == confNone)
    }
}
