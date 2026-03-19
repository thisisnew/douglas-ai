import Testing
import Foundation
@testable import DOUGLAS

@Suite("SemanticMatcher Tests")
struct SemanticMatcherTests {

    // MARK: - Helpers

    private func makeAgent(
        name: String,
        persona: String,
        skillTags: [String] = []
    ) -> Agent {
        Agent(
            name: name,
            persona: persona,
            providerName: "TestProvider",
            modelName: "test-model",
            skillTags: skillTags
        )
    }

    /// 실제로 벡터가 생성되는 에이전트+롤을 확인하는 헬퍼
    private func findWorkingPair(_ matcher: SemanticMatcher) -> (agent: Agent, roleName: String)? {
        // 영어 단어는 NLEmbedding에서 벡터가 있을 가능성이 높음
        let candidates = [
            (makeAgent(name: "backend developer", persona: "server development expert"), "backend"),
            (makeAgent(name: "software engineer", persona: "programming and coding"), "software"),
            (makeAgent(name: "data scientist", persona: "machine learning analysis"), "data"),
        ]
        for (agent, role) in candidates {
            matcher.updateCache(for: agent)
            let score = matcher.similarity(roleName: role, agent: agent)
            if score > 0 {
                return (agent, role)
            }
        }
        return nil
    }

    // MARK: - Role Vector Cache

    @Test("similarity — 같은 roleName 반복 호출 시 동일 결과 (캐시)")
    func roleVectorCacheHit() {
        let matcher = SemanticMatcher()
        guard matcher.isAvailable,
              let (agent, roleName) = findWorkingPair(matcher) else { return }

        let score1 = matcher.similarity(roleName: roleName, agent: agent)
        let score2 = matcher.similarity(roleName: roleName, agent: agent)

        #expect(score1 == score2)
    }

    @Test("clearRoleVectorCache — 캐시 클리어 후에도 정상 작동")
    func clearRoleVectorCache() {
        let matcher = SemanticMatcher()
        guard matcher.isAvailable,
              let (agent, roleName) = findWorkingPair(matcher) else { return }

        let scoreBefore = matcher.similarity(roleName: roleName, agent: agent)
        matcher.clearRoleVectorCache()
        let scoreAfter = matcher.similarity(roleName: roleName, agent: agent)

        #expect(scoreBefore == scoreAfter)
    }

    // MARK: - Batch Similarity

    @Test("batchSimilarity — 여러 에이전트에 대해 한 번에 계산")
    func batchSimilarity() {
        let matcher = SemanticMatcher()
        guard matcher.isAvailable else { return }

        let agent1 = makeAgent(name: "backend developer", persona: "server development")
        let agent2 = makeAgent(name: "frontend developer", persona: "UI development")
        matcher.updateCache(for: agent1)
        matcher.updateCache(for: agent2)

        let roleName = "backend"
        let results = matcher.batchSimilarity(roleName: roleName, agents: [agent1, agent2])

        // 배치 결과와 개별 결과가 동일해야 함
        let individual1 = matcher.similarity(roleName: roleName, agent: agent1)
        let individual2 = matcher.similarity(roleName: roleName, agent: agent2)

        if let r1 = results[agent1.id] {
            #expect(r1 == individual1)
        }
        if let r2 = results[agent2.id] {
            #expect(r2 == individual2)
        }
    }

    @Test("batchSimilarity — 빈 에이전트 목록")
    func batchSimilarityEmpty() {
        let matcher = SemanticMatcher()
        let results = matcher.batchSimilarity(roleName: "backend", agents: [])
        #expect(results.isEmpty)
    }

    @Test("roleVectorCacheCount — 캐시 크기 추적")
    func roleVectorCacheCount() {
        let matcher = SemanticMatcher()
        guard matcher.isAvailable,
              let (agent, roleName) = findWorkingPair(matcher) else { return }

        matcher.clearRoleVectorCache()
        #expect(matcher.roleVectorCacheCount == 0)

        _ = matcher.similarity(roleName: roleName, agent: agent)
        #expect(matcher.roleVectorCacheCount >= 1)

        matcher.clearRoleVectorCache()
        #expect(matcher.roleVectorCacheCount == 0)
    }

    @Test("roleVectorCache — computeDocumentVector 호출 횟수 절감 확인")
    func cacheReducesComputation() {
        let matcher = SemanticMatcher()
        guard matcher.isAvailable else { return }

        // 10개 에이전트에 같은 roleName으로 similarity 호출
        var agents: [Agent] = []
        for i in 0..<10 {
            let agent = makeAgent(name: "agent\(i)", persona: "test persona \(i)")
            matcher.updateCache(for: agent)
            agents.append(agent)
        }

        // 캐시 초기화 후 batch로 한 번에 계산
        matcher.clearRoleVectorCache()
        let batchResults = matcher.batchSimilarity(roleName: "test", agents: agents)

        // roleName 벡터는 1번만 계산됨 (캐시 크기 = 1)
        #expect(matcher.roleVectorCacheCount <= 1)
        _ = batchResults // suppress unused warning
    }
}
