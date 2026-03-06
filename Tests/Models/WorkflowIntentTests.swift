import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkflowPhase & WorkflowIntent Tests")
struct WorkflowIntentTests {

    // MARK: - WorkflowPhase

    @Test("WorkflowPhase — 전체 케이스 존재")
    func workflowPhaseAllCases() {
        let all = WorkflowPhase.allCases
        #expect(all.count == 11)
        // 레거시
        #expect(all.contains(.intake))
        #expect(all.contains(.intent))
        #expect(all.contains(.clarify))
        #expect(all.contains(.assemble))
        #expect(all.contains(.plan))
        #expect(all.contains(.execute))
        // Plan C
        #expect(all.contains(.understand))
        #expect(all.contains(.design))
        #expect(all.contains(.build))
        #expect(all.contains(.review))
        #expect(all.contains(.deliver))
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

    @Test("WorkflowIntent — 전체 케이스 존재 (2종)")
    func workflowIntentAllCases() {
        let all = WorkflowIntent.allCases
        #expect(all.count == 2)
        #expect(all.contains(.quickAnswer))
        #expect(all.contains(WorkflowIntent.task))
    }

    @Test("WorkflowIntent rawValue")
    func workflowIntentRawValues() {
        #expect(WorkflowIntent.quickAnswer.rawValue == "quickAnswer")
        #expect((WorkflowIntent.task).rawValue == "task")
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

    @Test("quickAnswer — Plan C: understand → assemble → deliver")
    func quickAnswerPhases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(phases.count == 3)
        #expect(phases.contains(.understand))
        #expect(phases.contains(.assemble))
        #expect(phases.contains(.deliver))
    }

    @Test("task — Plan C: understand → assemble → design → build → review → deliver")
    func taskPhases() {
        let phases = (WorkflowIntent.task).requiredPhases
        #expect(phases.count == 6)
        #expect(phases.contains(.understand))
        #expect(phases.contains(.assemble))
        #expect(phases.contains(.design))
        #expect(phases.contains(.build))
        #expect(phases.contains(.review))
        #expect(phases.contains(.deliver))
    }

    // MARK: - requiresDiscussion

    @Test("토론 필요: quickAnswer만 제외")
    func requiresDiscussion() {
        #expect(WorkflowIntent.quickAnswer.requiresDiscussion == false)
        #expect((WorkflowIntent.task).requiresDiscussion == true)
    }

    // MARK: - includesExecution / includesAssembly

    @Test("모든 Intent가 assembly 포함")
    func allIncludeAssembly() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.includesAssembly == true)
        }
    }

    @Test("실행 포함 여부 — Plan C에서는 build/deliver로 대체")
    func includesExecution() {
        // Plan C: requiredPhases에 .execute가 없음 (build/deliver로 대체)
        #expect(WorkflowIntent.quickAnswer.includesExecution == false)
        #expect(WorkflowIntent.task.includesExecution == false)
    }

    // MARK: - 레거시 호환 (Codable)

    @Test("레거시 intent 문자열 → task로 디코딩")
    func legacyIntentDecoding() throws {
        let legacyValues = [
            "research", "implementation",
            "brainstorm", "requirementsAnalysis", "testPlanning",
            "taskDecomposition", "documentation",
        ]
        for legacy in legacyValues {
            let json = "\"\(legacy)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(WorkflowIntent.self, from: json)
            #expect(decoded == WorkflowIntent.task, "레거시 \(legacy) → .task 디코딩 실패")
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
