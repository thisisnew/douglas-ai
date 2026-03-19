import Testing
import Foundation
@testable import DOUGLAS

@Suite("PhaseRouter 페이즈 시퀀스")
struct PhaseRouterTests {

    @Test("quickAnswer — understand → assemble → deliver")
    func quickAnswer_phases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(phases == [.understand, .assemble, .deliver])
    }

    @Test("task — understand → assemble → design → build → review → deliver")
    func task_phases() {
        let phases = WorkflowIntent.task.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .build, .review, .deliver])
    }

    @Test("discussion — understand → assemble → design → deliver")
    func discussion_phases() {
        let phases = WorkflowIntent.discussion.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .deliver])
    }

    @Test("documentation — understand → assemble → design → build → deliver (review 없음)")
    func documentation_phases() {
        let phases = WorkflowIntent.documentation.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .build, .deliver])
    }

    @Test("withExecution modifier — discussion에 build+review 추가")
    func withExecution_addsPhases() {
        let phases = WorkflowIntent.discussion.requiredPhases(with: [.withExecution])
        #expect(phases.contains(.build))
        #expect(phases.contains(.review))
    }

    @Test("outputOnly modifier — build+review 제거")
    func outputOnly_removesPhases() {
        let phases = WorkflowIntent.task.requiredPhases(with: [.outputOnly])
        #expect(!phases.contains(.build))
        #expect(!phases.contains(.review))
    }

    @Test("phase 순차 전이 검증 — task")
    func canTransition_task() {
        let intent = WorkflowIntent.task
        #expect(intent.canTransition(from: nil, to: .understand) == true)
        #expect(intent.canTransition(from: .understand, to: .assemble) == true)
        #expect(intent.canTransition(from: .assemble, to: .design) == true)
        #expect(intent.canTransition(from: .design, to: .build) == true)
        #expect(intent.canTransition(from: .build, to: .review) == true)
        #expect(intent.canTransition(from: .review, to: .deliver) == true)
    }

    @Test("phase 비순차 전이 거부")
    func canTransition_invalid() {
        let intent = WorkflowIntent.task
        #expect(intent.canTransition(from: nil, to: .design) == false)  // 첫 단계가 아님
        #expect(intent.canTransition(from: .understand, to: .build) == false)  // 건너뜀
    }

    @Test("타임아웃 상수 존재")
    func timeoutConstant() {
        #expect(PhaseRouter.workflowTimeoutSeconds == 600)
    }
}
