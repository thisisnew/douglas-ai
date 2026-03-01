import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkflowPhase & WorkflowIntent Tests")
struct WorkflowIntentTests {

    // MARK: - WorkflowPhase

    @Test("WorkflowPhase — 전체 케이스 존재")
    func workflowPhaseAllCases() {
        let all = WorkflowPhase.allCases
        #expect(all.count == 7)
        #expect(all.contains(.intake))
        #expect(all.contains(.intent))
        #expect(all.contains(.clarify))
        #expect(all.contains(.assemble))
        #expect(all.contains(.plan))
        #expect(all.contains(.execute))
        #expect(all.contains(.review))
    }

    @Test("WorkflowPhase rawValue")
    func workflowPhaseRawValues() {
        #expect(WorkflowPhase.intake.rawValue == "intake")
        #expect(WorkflowPhase.intent.rawValue == "intent")
        #expect(WorkflowPhase.clarify.rawValue == "clarify")
        #expect(WorkflowPhase.assemble.rawValue == "assemble")
        #expect(WorkflowPhase.plan.rawValue == "plan")
        #expect(WorkflowPhase.execute.rawValue == "execute")
        #expect(WorkflowPhase.review.rawValue == "review")
    }

    @Test("WorkflowPhase displayName 비어있지 않음")
    func workflowPhaseDisplayNames() {
        for phase in WorkflowPhase.allCases {
            #expect(!phase.displayName.isEmpty)
        }
    }

    @Test("WorkflowPhase Codable 라운드트립")
    func workflowPhaseCodable() throws {
        for phase in WorkflowPhase.allCases {
            let data = try JSONEncoder().encode(phase)
            let decoded = try JSONDecoder().decode(WorkflowPhase.self, from: data)
            #expect(decoded == phase)
        }
    }

    // MARK: - WorkflowIntent

    @Test("WorkflowIntent — 전체 케이스 존재 (8종)")
    func workflowIntentAllCases() {
        let all = WorkflowIntent.allCases
        #expect(all.count == 8)
        #expect(all.contains(.quickAnswer))
        #expect(all.contains(.research))
        #expect(all.contains(.brainstorm))
        #expect(all.contains(.documentation))
        #expect(all.contains(.implementation))
        #expect(all.contains(.requirementsAnalysis))
        #expect(all.contains(.testPlanning))
        #expect(all.contains(.taskDecomposition))
    }

    @Test("WorkflowIntent rawValue")
    func workflowIntentRawValues() {
        #expect(WorkflowIntent.quickAnswer.rawValue == "quickAnswer")
        #expect(WorkflowIntent.research.rawValue == "research")
        #expect(WorkflowIntent.brainstorm.rawValue == "brainstorm")
        #expect(WorkflowIntent.documentation.rawValue == "documentation")
        #expect(WorkflowIntent.implementation.rawValue == "implementation")
        #expect(WorkflowIntent.requirementsAnalysis.rawValue == "requirementsAnalysis")
        #expect(WorkflowIntent.testPlanning.rawValue == "testPlanning")
        #expect(WorkflowIntent.taskDecomposition.rawValue == "taskDecomposition")
    }

    @Test("WorkflowIntent displayName 비어있지 않음")
    func workflowIntentDisplayNames() {
        for intent in WorkflowIntent.allCases {
            #expect(!intent.displayName.isEmpty)
        }
    }

    @Test("WorkflowIntent Codable 라운드트립")
    func workflowIntentCodable() throws {
        for intent in WorkflowIntent.allCases {
            let data = try JSONEncoder().encode(intent)
            let decoded = try JSONDecoder().decode(WorkflowIntent.self, from: data)
            #expect(decoded == intent)
        }
    }

    // MARK: - requiredPhases: 모든 Intent에 공통 프리픽스 확인

    @Test("모든 Intent에 intake, intent, clarify, assemble 공통 포함")
    func allIntentsShareCommonPrefix() {
        for intent in WorkflowIntent.allCases {
            let phases = intent.requiredPhases
            #expect(phases.contains(.intake))
            #expect(phases.contains(.intent))
            #expect(phases.contains(.clarify))
            #expect(phases.contains(.assemble))
            #expect(phases.contains(.review))
        }
    }

    @Test("implementation — 전체 7단계 포함")
    func implementationPhases() {
        let phases = WorkflowIntent.implementation.requiredPhases
        #expect(phases.count == 7)
        #expect(phases.contains(.plan))
        #expect(phases.contains(.execute))
    }

    @Test("quickAnswer — Plan 스킵, Execute 포함")
    func quickAnswerPhases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(!phases.contains(.plan))
        #expect(phases.contains(.execute))
        #expect(phases.count == 6) // intake, intent, clarify, assemble, execute, review
    }

    @Test("brainstorm — Plan 포함, Execute 미포함")
    func brainstormPhases() {
        let phases = WorkflowIntent.brainstorm.requiredPhases
        #expect(phases.contains(.plan))
        #expect(!phases.contains(.execute))
    }

    @Test("research — Plan + Execute 포함")
    func researchPhases() {
        let phases = WorkflowIntent.research.requiredPhases
        #expect(phases.contains(.plan))
        #expect(phases.contains(.execute))
    }

    @Test("requirementsAnalysis — Plan 포함, Execute 미포함")
    func requirementsAnalysisPhases() {
        let phases = WorkflowIntent.requirementsAnalysis.requiredPhases
        #expect(phases.contains(.plan))
        #expect(!phases.contains(.execute))
    }

    // MARK: - PlanMode

    @Test("PlanMode 분기 올바름")
    func planModeMapping() {
        #expect(WorkflowIntent.quickAnswer.planMode == .skip)
        #expect(WorkflowIntent.brainstorm.planMode == .lite)
        #expect(WorkflowIntent.requirementsAnalysis.planMode == .lite)
        #expect(WorkflowIntent.testPlanning.planMode == .lite)
        #expect(WorkflowIntent.taskDecomposition.planMode == .lite)
        #expect(WorkflowIntent.research.planMode == .exec)
        #expect(WorkflowIntent.documentation.planMode == .exec)
        #expect(WorkflowIntent.implementation.planMode == .exec)
    }

    // MARK: - requiresDiscussion / requiresApproval

    @Test("토론 필요: brainstorm, implementation만")
    func requiresDiscussion() {
        #expect(WorkflowIntent.brainstorm.requiresDiscussion == true)
        #expect(WorkflowIntent.implementation.requiresDiscussion == true)
        #expect(WorkflowIntent.quickAnswer.requiresDiscussion == false)
        #expect(WorkflowIntent.research.requiresDiscussion == false)
        #expect(WorkflowIntent.documentation.requiresDiscussion == false)
    }

    @Test("승인 필요: implementation만")
    func requiresApproval() {
        #expect(WorkflowIntent.implementation.requiresApproval == true)
        #expect(WorkflowIntent.quickAnswer.requiresApproval == false)
        #expect(WorkflowIntent.brainstorm.requiresApproval == false)
        #expect(WorkflowIntent.research.requiresApproval == false)
    }

    // MARK: - includesExecution / includesAssembly

    @Test("모든 Intent가 assembly 포함")
    func allIncludeAssembly() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.includesAssembly == true)
        }
    }

    @Test("실행 포함 여부")
    func includesExecution() {
        // Execute 포함
        #expect(WorkflowIntent.quickAnswer.includesExecution == true)
        #expect(WorkflowIntent.research.includesExecution == true)
        #expect(WorkflowIntent.documentation.includesExecution == true)
        #expect(WorkflowIntent.implementation.includesExecution == true)

        // Execute 미포함
        #expect(WorkflowIntent.brainstorm.includesExecution == false)
        #expect(WorkflowIntent.requirementsAnalysis.includesExecution == false)
        #expect(WorkflowIntent.testPlanning.includesExecution == false)
        #expect(WorkflowIntent.taskDecomposition.includesExecution == false)
    }
}
