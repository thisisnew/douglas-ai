import Testing
import Foundation
@testable import DOUGLAS

@Suite("DebateClassifier Tests")
struct DebateClassifierTests {

    // MARK: - adversarial modifier

    @Test("adversarial modifier → dialectic 강제")
    func adversarialForces() {
        let mode = DebateClassifier.classify(
            topic: "API 스펙 확인",
            agentRoles: ["백엔드", "프론트엔드"],
            modifiers: [.adversarial]
        )
        #expect(mode == .dialectic)
    }

    // MARK: - 역할 겹침 기반

    @Test("같은 도메인 에이전트 → dialectic")
    func sameRoleDialectic() {
        let mode = DebateClassifier.classify(
            topic: "시스템 설계 논의",
            agentRoles: ["백엔드 개발자", "서버 엔지니어", "API 설계자"]
        )
        #expect(mode == .dialectic)
    }

    @Test("보완적 역할 → collaborative")
    func complementaryCollaborative() {
        let mode = DebateClassifier.classify(
            topic: "새 기능 개발 논의",
            agentRoles: ["백엔드 개발자", "프론트엔드 개발자", "디자이너"]
        )
        #expect(mode == .collaborative)
    }

    @Test("보완적 역할 + 조율 주제 → coordination")
    func complementaryCoordination() {
        let mode = DebateClassifier.classify(
            topic: "작업 분담하고 일정 확정하자",
            agentRoles: ["백엔드", "프론트엔드"]
        )
        #expect(mode == .coordination)
    }

    // MARK: - 주제 키워드 기반

    @Test("비교/선택 주제 + 보완적 역할 → collaborative (관점 결합이 대립보다 유용)")
    func comparisonTopicComplementary() {
        let mode = DebateClassifier.classify(
            topic: "REST vs GraphQL 어떤 게 나을까",
            agentRoles: ["백엔드", "프론트엔드"]
        )
        #expect(mode == .collaborative)
    }

    @Test("비교/선택 주제 + 겹치는 역할 → dialectic")
    func comparisonTopicOverlapping() {
        let mode = DebateClassifier.classify(
            topic: "REST vs GraphQL 어떤 게 나을까",
            agentRoles: ["백엔드 개발자", "서버 엔지니어", "API 설계자"]
        )
        #expect(mode == .dialectic)
    }

    @Test("아키텍처 주제 + 보완적 역할 → collaborative")
    func architectureTopicComplementary() {
        let mode = DebateClassifier.classify(
            topic: "아키텍처 설계 방향",
            agentRoles: ["백엔드", "프론트엔드"]
        )
        #expect(mode == .collaborative)
    }

    @Test("분담/일정 주제 → coordination")
    func scheduleTopic() {
        let mode = DebateClassifier.classify(
            topic: "각자 맡아서 일정 잡자",
            agentRoles: ["백엔드", "프론트엔드"]
        )
        #expect(mode == .coordination)
    }

    @Test("중립 주제 + 보완 역할 → collaborative")
    func neutralTopicComplementary() {
        let mode = DebateClassifier.classify(
            topic: "새 기능 기획",
            agentRoles: ["기획자", "디자이너", "개발자"]
        )
        #expect(mode == .collaborative)
    }

    // MARK: - 역할 겹침도 단위 테스트

    @Test("roleOverlapScore: 모두 같은 도메인 → high")
    func overlapHigh() {
        let score = DebateClassifier.roleOverlapScore(["백엔드", "서버 개발자", "API 엔지니어"])
        #expect(score == .high)
    }

    @Test("roleOverlapScore: 모두 다른 도메인 → low")
    func overlapLow() {
        let score = DebateClassifier.roleOverlapScore(["백엔드", "프론트엔드", "디자이너"])
        #expect(score == .low)
    }

    @Test("roleOverlapScore: 에이전트 1명 → low")
    func overlapSingle() {
        let score = DebateClassifier.roleOverlapScore(["백엔드"])
        #expect(score == .low)
    }

    // MARK: - 주제 키워드 단위 테스트

    @Test("analyzeTopicKeywords: vs 포함 → dialectic")
    func topicVs() {
        #expect(DebateClassifier.analyzeTopicKeywords("REST vs GraphQL") == .dialectic)
    }

    @Test("analyzeTopicKeywords: 분담 → coordination")
    func topicDivision() {
        #expect(DebateClassifier.analyzeTopicKeywords("작업 분담하자") == .coordination)
    }

    @Test("analyzeTopicKeywords: 키워드 없음 → neutral")
    func topicNeutral() {
        #expect(DebateClassifier.analyzeTopicKeywords("새 기능 기획") == .neutral)
    }

    // MARK: - 엣지 케이스

    @Test("빈 역할 목록 → 보완적(low) + dialectic 주제 → collaborative")
    func emptyRoles() {
        let mode = DebateClassifier.classify(
            topic: "아키텍처 선택",
            agentRoles: []
        )
        #expect(mode == .collaborative)  // 역할 low + dialectic → collaborative
    }

    @Test("빈 주제 + 보완 역할 → collaborative")
    func emptyTopic() {
        let mode = DebateClassifier.classify(
            topic: "",
            agentRoles: ["백엔드", "프론트엔드"]
        )
        #expect(mode == .collaborative)
    }

    // MARK: - normalizeRole 최장 키워드 매칭 (간접 검증)

    @Test("roleOverlapScore: 'UI/UX 디자이너' → design 도메인 (frontend 아님)")
    func normalizeRole_uiuxDesigner_matchesDesign() {
        // "UI/UX 디자이너"와 "디자인 전문가"는 같은 design 도메인 → high overlap
        let overlap = DebateClassifier.roleOverlapScore(["UI/UX 디자이너", "디자인 전문가"])
        #expect(overlap == .high)
    }

    @Test("roleOverlapScore: '백엔드 개발자'와 '프론트 디자이너' → 서로 다른 도메인")
    func normalizeRole_backendVsFrontDesigner_lowOverlap() {
        let overlap = DebateClassifier.roleOverlapScore(["백엔드 개발자", "프론트엔드 디자이너"])
        #expect(overlap == .low)
    }
}
