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

    @Test("WorkflowIntent — 전체 케이스 존재")
    func workflowIntentAllCases() {
        let all = WorkflowIntent.allCases
        #expect(all.count == 4)
        #expect(all.contains(.implementation))
        #expect(all.contains(.requirementsAnalysis))
        #expect(all.contains(.testPlanning))
        #expect(all.contains(.taskDecomposition))
    }

    @Test("WorkflowIntent rawValue")
    func workflowIntentRawValues() {
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

    // MARK: - requiredPhases

    @Test("implementation — 전체 7단계 포함")
    func implementationPhases() {
        let phases = WorkflowIntent.implementation.requiredPhases
        #expect(phases.count == 7)
        #expect(phases.contains(.assemble))
        #expect(phases.contains(.execute))
    }

    @Test("requirementsAnalysis — assemble/execute 미포함")
    func requirementsAnalysisPhases() {
        let phases = WorkflowIntent.requirementsAnalysis.requiredPhases
        #expect(!phases.contains(.assemble))
        #expect(!phases.contains(.execute))
        #expect(phases.contains(.intake))
        #expect(phases.contains(.clarify))
        #expect(phases.contains(.plan))
        #expect(phases.contains(.review))
    }

    @Test("testPlanning — assemble/execute 미포함")
    func testPlanningPhases() {
        let phases = WorkflowIntent.testPlanning.requiredPhases
        #expect(!phases.contains(.assemble))
        #expect(!phases.contains(.execute))
    }

    @Test("taskDecomposition — assemble/execute 미포함")
    func taskDecompositionPhases() {
        let phases = WorkflowIntent.taskDecomposition.requiredPhases
        #expect(!phases.contains(.assemble))
        #expect(!phases.contains(.execute))
    }

    // MARK: - includesExecution / includesAssembly

    @Test("implementation만 실행/팀구성 포함")
    func onlyImplementationIncludesAll() {
        #expect(WorkflowIntent.implementation.includesExecution == true)
        #expect(WorkflowIntent.implementation.includesAssembly == true)

        #expect(WorkflowIntent.requirementsAnalysis.includesExecution == false)
        #expect(WorkflowIntent.requirementsAnalysis.includesAssembly == false)

        #expect(WorkflowIntent.testPlanning.includesExecution == false)
        #expect(WorkflowIntent.testPlanning.includesAssembly == false)

        #expect(WorkflowIntent.taskDecomposition.includesExecution == false)
        #expect(WorkflowIntent.taskDecomposition.includesAssembly == false)
    }
}
