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

    @Test("quickAnswer — clarify 없이 4단계")
    func quickAnswerPhases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(phases.count == 4)
        #expect(!phases.contains(.clarify))
        #expect(!phases.contains(.plan))
        #expect(phases.contains(.execute))
    }

    @Test("task — clarify 포함 5단계 (plan은 동적 삽입)")
    func taskPhases() {
        let phases = (WorkflowIntent.task).requiredPhases
        #expect(phases.count == 5)
        #expect(phases.contains(.clarify))
        #expect(!phases.contains(.plan))  // plan은 needsPlan에 의해 동적 삽입
        #expect(phases.contains(.execute))
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

    @Test("실행 포함 여부 — 모든 Intent가 execute 포함")
    func includesExecution() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.includesExecution == true)
        }
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
