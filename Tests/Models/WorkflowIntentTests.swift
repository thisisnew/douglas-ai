import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkflowPhase & WorkflowIntent Tests")
struct WorkflowIntentTests {

    // MARK: - WorkflowPhase

    @Test("WorkflowPhase — 전체 케이스 존재")
    func workflowPhaseAllCases() {
        let all = WorkflowPhase.allCases
        #expect(all.count == 6)
        #expect(all.contains(.intake))
        #expect(all.contains(.intent))
        #expect(all.contains(.clarify))
        #expect(all.contains(.assemble))
        #expect(all.contains(.plan))
        #expect(all.contains(.execute))
    }

    @Test("WorkflowPhase rawValue")
    func workflowPhaseRawValues() {
        #expect(WorkflowPhase.intake.rawValue == "intake")
        #expect(WorkflowPhase.intent.rawValue == "intent")
        #expect(WorkflowPhase.clarify.rawValue == "clarify")
        #expect(WorkflowPhase.assemble.rawValue == "assemble")
        #expect(WorkflowPhase.plan.rawValue == "plan")
        #expect(WorkflowPhase.execute.rawValue == "execute")
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

    @Test("WorkflowIntent — 전체 케이스 존재 (3종)")
    func workflowIntentAllCases() {
        let all = WorkflowIntent.allCases
        #expect(all.count == 3)
        #expect(all.contains(.quickAnswer))
        #expect(all.contains(.research))
        #expect(all.contains(.implementation))
    }

    @Test("WorkflowIntent rawValue")
    func workflowIntentRawValues() {
        #expect(WorkflowIntent.quickAnswer.rawValue == "quickAnswer")
        #expect(WorkflowIntent.research.rawValue == "research")
        #expect(WorkflowIntent.implementation.rawValue == "implementation")
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
        }
    }

    @Test("implementation — 전체 6단계 포함")
    func implementationPhases() {
        let phases = WorkflowIntent.implementation.requiredPhases
        #expect(phases.count == 6)
        #expect(phases.contains(.plan))
        #expect(phases.contains(.execute))
    }

    @Test("quickAnswer — Plan 스킵, Execute 포함")
    func quickAnswerPhases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(!phases.contains(.plan))
        #expect(phases.contains(.execute))
        #expect(phases.count == 5) // intake, intent, clarify, assemble, execute
    }

    @Test("research — Execute 포함, Plan 미포함")
    func researchPhases() {
        let phases = WorkflowIntent.research.requiredPhases
        #expect(!phases.contains(.plan))
        #expect(phases.contains(.execute))
    }

    // MARK: - PlanMode

    @Test("PlanMode 분기 올바름")
    func planModeMapping() {
        #expect(WorkflowIntent.quickAnswer.planMode == .skip)
        #expect(WorkflowIntent.research.planMode == .lite)
        #expect(WorkflowIntent.implementation.planMode == .exec)
    }

    // MARK: - requiresDiscussion / requiresApproval

    @Test("토론 필요: quickAnswer만 제외")
    func requiresDiscussion() {
        #expect(WorkflowIntent.quickAnswer.requiresDiscussion == false)
        #expect(WorkflowIntent.research.requiresDiscussion == true)
        #expect(WorkflowIntent.implementation.requiresDiscussion == true)
    }

    @Test("승인 필요: implementation만")
    func requiresApproval() {
        #expect(WorkflowIntent.implementation.requiresApproval == true)
        #expect(WorkflowIntent.quickAnswer.requiresApproval == false)
        #expect(WorkflowIntent.research.requiresApproval == false)
    }

    // MARK: - includesExecution / includesAssembly

    @Test("모든 Intent가 assembly 포함")
    func allIncludeAssembly() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.includesAssembly == true)
        }
    }

    @Test("실행 포함 여부 — 모든 Intent가 execute 포함")
    func includesExecution() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.includesExecution == true)
        }
    }

    // MARK: - 레거시 호환 (Codable)

    @Test("레거시 intent 문자열 → research로 디코딩")
    func legacyIntentDecoding() throws {
        let legacyValues = ["brainstorm", "requirementsAnalysis", "testPlanning", "taskDecomposition", "documentation"]
        for legacy in legacyValues {
            let json = "\"\(legacy)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(WorkflowIntent.self, from: json)
            #expect(decoded == .research, "레거시 \(legacy) → .research 디코딩 실패")
        }
    }

    @Test("알 수 없는 intent 문자열 → 디코딩 에러")
    func unknownIntentDecoding() {
        let json = "\"somethingRandom\"".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(WorkflowIntent.self, from: json)
        }
    }
}
