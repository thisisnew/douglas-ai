import Testing
import Foundation
@testable import DOUGLAS

@Suite("PhaseTransition Tests")
struct PhaseTransitionTests {

    // MARK: - PhaseTransition 구조체

    @Test("PhaseTransition 생성 — from nil (초기 전이)")
    func createInitialTransition() {
        let t = PhaseTransition(from: nil, to: .understand)
        #expect(t.from == nil)
        #expect(t.to == .understand)
    }

    @Test("PhaseTransition 생성 — 일반 전이")
    func createNormalTransition() {
        let t = PhaseTransition(from: .understand, to: .assemble)
        #expect(t.from == .understand)
        #expect(t.to == .assemble)
    }

    @Test("PhaseTransition Codable 라운드트립")
    func codableRoundtrip() throws {
        let t = PhaseTransition(from: .design, to: .build)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PhaseTransition.self, from: data)
        #expect(decoded == t)
    }

    @Test("PhaseTransition Codable — from nil 라운드트립")
    func codableRoundtripFromNil() throws {
        let t = PhaseTransition(from: nil, to: .understand)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PhaseTransition.self, from: data)
        #expect(decoded.from == nil)
        #expect(decoded.to == .understand)
    }

    @Test("PhaseTransition Equatable")
    func equatable() {
        let a = PhaseTransition(from: .assemble, to: .design)
        let b = PhaseTransition(from: .assemble, to: .design)
        #expect(a == b)
    }

    // MARK: - canTransition (WorkflowIntent 확장)

    @Test("quickAnswer — nil → understand 허용")
    func quickAnswerInitial() {
        #expect(WorkflowIntent.quickAnswer.canTransition(from: nil, to: .understand) == true)
    }

    @Test("quickAnswer — understand → assemble 허용")
    func quickAnswerNext() {
        #expect(WorkflowIntent.quickAnswer.canTransition(from: .understand, to: .assemble) == true)
    }

    @Test("quickAnswer — assemble → deliver 허용")
    func quickAnswerFinal() {
        #expect(WorkflowIntent.quickAnswer.canTransition(from: .assemble, to: .deliver) == true)
    }

    @Test("quickAnswer — understand → deliver 거부 (건너뛰기 불가)")
    func quickAnswerSkipNotAllowed() {
        #expect(WorkflowIntent.quickAnswer.canTransition(from: .understand, to: .deliver) == false)
    }

    @Test("quickAnswer — nil → assemble 거부 (첫 단계 아님)")
    func quickAnswerWrongStart() {
        #expect(WorkflowIntent.quickAnswer.canTransition(from: nil, to: .assemble) == false)
    }

    @Test("task — 풀 파이프라인 순차 전이")
    func taskSequentialTransitions() {
        let phases: [WorkflowPhase] = [.understand, .assemble, .design, .build, .review, .deliver]
        // nil → understand
        #expect(WorkflowIntent.task.canTransition(from: nil, to: .understand) == true)
        // 순차 전이
        for i in 0..<(phases.count - 1) {
            #expect(
                WorkflowIntent.task.canTransition(from: phases[i], to: phases[i + 1]) == true,
                "\(phases[i]) → \(phases[i + 1]) should be allowed"
            )
        }
    }

    @Test("task — 역방향 전이 거부")
    func taskBackwardNotAllowed() {
        #expect(WorkflowIntent.task.canTransition(from: .build, to: .design) == false)
    }

    @Test("task — requiredPhases에 없는 단계 거부")
    func taskInvalidPhase() {
        // .plan은 task의 requiredPhases에 없음
        #expect(WorkflowIntent.task.canTransition(from: .understand, to: .plan) == false)
    }

    @Test("discussion — understand → assemble → design → deliver")
    func discussionTransitions() {
        #expect(WorkflowIntent.discussion.canTransition(from: nil, to: .understand) == true)
        #expect(WorkflowIntent.discussion.canTransition(from: .understand, to: .assemble) == true)
        #expect(WorkflowIntent.discussion.canTransition(from: .assemble, to: .design) == true)
        #expect(WorkflowIntent.discussion.canTransition(from: .design, to: .deliver) == true)
        // build는 discussion의 requiredPhases에 없음
        #expect(WorkflowIntent.discussion.canTransition(from: .design, to: .build) == false)
    }

    @Test("documentation — build 다음은 deliver (review 없음)")
    func documentationSkipsReview() {
        #expect(WorkflowIntent.documentation.canTransition(from: .build, to: .deliver) == true)
        #expect(WorkflowIntent.documentation.canTransition(from: .build, to: .review) == false)
    }

    // MARK: - WorkflowState.phaseTransitions 감사 기록

    @Test("WorkflowState — phaseTransitions 초기값 빈 배열")
    func initialPhaseTransitions() {
        let state = WorkflowState()
        #expect(state.phaseTransitions.isEmpty)
    }

    @Test("WorkflowState — phaseTransitions 추가")
    func appendPhaseTransition() {
        var state = WorkflowState()
        state.phaseTransitions.append(PhaseTransition(from: nil, to: .understand))
        state.phaseTransitions.append(PhaseTransition(from: .understand, to: .assemble))
        #expect(state.phaseTransitions.count == 2)
    }

    @Test("WorkflowState — phaseTransitions Codable 라운드트립")
    func phaseTransitionsCodable() throws {
        var state = WorkflowState(intent: .task, currentPhase: .design)
        state.phaseTransitions.append(PhaseTransition(from: nil, to: .understand))
        state.phaseTransitions.append(PhaseTransition(from: .understand, to: .assemble))
        state.phaseTransitions.append(PhaseTransition(from: .assemble, to: .design))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkflowState.self, from: data)
        #expect(decoded.phaseTransitions.count == 3)
        #expect(decoded.phaseTransitions[0].to == .understand)
        #expect(decoded.phaseTransitions[2].to == .design)
    }

    @Test("WorkflowState — 레거시 JSON(phaseTransitions 없음) 디코딩")
    func legacyDecodeWithoutTransitions() throws {
        // phaseTransitions 키가 없는 WorkflowState JSON
        let json = """
        {"autoDocOutput":false,"needsPlan":false,"completedPhases":[]}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkflowState.self, from: data)
        #expect(decoded.phaseTransitions.isEmpty)
    }
}
