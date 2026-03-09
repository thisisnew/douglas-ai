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

    // MARK: - WorkflowIntent (6종)

    @Test("WorkflowIntent — 전체 케이스 존재 (6종)")
    func workflowIntentAllCases() {
        let all = WorkflowIntent.allCases
        #expect(all.count == 6)
        #expect(all.contains(.quickAnswer))
        #expect(all.contains(.task))
        #expect(all.contains(.discussion))
        #expect(all.contains(.research))
        #expect(all.contains(.documentation))
        #expect(all.contains(.complex))
    }

    @Test("WorkflowIntent rawValue")
    func workflowIntentRawValues() {
        #expect(WorkflowIntent.quickAnswer.rawValue == "quickAnswer")
        #expect(WorkflowIntent.task.rawValue == "task")
        #expect(WorkflowIntent.discussion.rawValue == "discussion")
        #expect(WorkflowIntent.research.rawValue == "research")
        #expect(WorkflowIntent.documentation.rawValue == "documentation")
        #expect(WorkflowIntent.complex.rawValue == "complex")
    }

    @Test("WorkflowIntent displayName 비어있지 않음")
    func workflowIntentDisplayNames() {
        for intent in WorkflowIntent.allCases {
            #expect(!intent.displayName.isEmpty)
        }
    }

    @Test("WorkflowIntent displayName 정확한 값")
    func workflowIntentDisplayNameValues() {
        #expect(WorkflowIntent.quickAnswer.displayName == "질의응답")
        #expect(WorkflowIntent.task.displayName == "구현")
        #expect(WorkflowIntent.discussion.displayName == "토론")
        #expect(WorkflowIntent.research.displayName == "조사")
        #expect(WorkflowIntent.documentation.displayName == "문서화")
        #expect(WorkflowIntent.complex.displayName == "복합 요청")
    }

    @Test("WorkflowIntent iconName 비어있지 않음")
    func workflowIntentIconNames() {
        for intent in WorkflowIntent.allCases {
            #expect(!intent.iconName.isEmpty)
        }
    }

    @Test("WorkflowIntent subtitle 비어있지 않음")
    func workflowIntentSubtitles() {
        for intent in WorkflowIntent.allCases {
            #expect(!intent.subtitle.isEmpty)
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

    @Test("quickAnswer — understand → assemble → deliver")
    func quickAnswerPhases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(phases == [.understand, .assemble, .deliver])
    }

    @Test("task — understand → assemble → design → build → review → deliver")
    func taskPhases() {
        let phases = WorkflowIntent.task.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .build, .review, .deliver])
    }

    @Test("discussion — understand → assemble → design → deliver")
    func discussionPhases() {
        let phases = WorkflowIntent.discussion.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .deliver])
    }

    @Test("research — understand → assemble → design → deliver (조사 = design에서 수행)")
    func researchPhases() {
        let phases = WorkflowIntent.research.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .deliver])
    }

    @Test("documentation — understand → assemble → design → build → deliver (review 불필요)")
    func documentationPhases() {
        let phases = WorkflowIntent.documentation.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .build, .deliver])
    }

    @Test("complex — task와 동일한 풀 파이프라인")
    func complexPhases() {
        let phases = WorkflowIntent.complex.requiredPhases
        #expect(phases == WorkflowIntent.task.requiredPhases)
    }

    // MARK: - requiresDiscussion

    @Test("토론 필요: quickAnswer만 제외")
    func requiresDiscussion() {
        #expect(WorkflowIntent.quickAnswer.requiresDiscussion == false)
        #expect(WorkflowIntent.task.requiresDiscussion == true)
        #expect(WorkflowIntent.discussion.requiresDiscussion == true)
        #expect(WorkflowIntent.research.requiresDiscussion == true)
        #expect(WorkflowIntent.documentation.requiresDiscussion == true)
        #expect(WorkflowIntent.complex.requiresDiscussion == true)
    }

    // MARK: - phaseDisplayName (intent별 단계 이름 오버라이드)

    @Test("research — design='조사', deliver='결과 정리'")
    func researchPhaseDisplayName() {
        #expect(WorkflowIntent.research.phaseDisplayName(.design) == "조사")
        #expect(WorkflowIntent.research.phaseDisplayName(.deliver) == "결과 정리")
        // 오버라이드 없는 단계는 기본 displayName
        #expect(WorkflowIntent.research.phaseDisplayName(.understand) == WorkflowPhase.understand.displayName)
    }

    @Test("documentation — design='구조 설계', build='문서 작성', deliver='최종 정리'")
    func documentationPhaseDisplayName() {
        #expect(WorkflowIntent.documentation.phaseDisplayName(.design) == "구조 설계")
        #expect(WorkflowIntent.documentation.phaseDisplayName(.build) == "문서 작성")
        #expect(WorkflowIntent.documentation.phaseDisplayName(.deliver) == "최종 정리")
    }

    // MARK: - 레거시 호환 (Codable)

    @Test("레거시 intent → 새 타입으로 디코딩")
    func legacyIntentDecoding() throws {
        // research/documentation은 이제 고유 타입으로 디코딩
        let researchJSON = "\"research\"".data(using: .utf8)!
        #expect(try JSONDecoder().decode(WorkflowIntent.self, from: researchJSON) == .research)

        let documentationJSON = "\"documentation\"".data(using: .utf8)!
        #expect(try JSONDecoder().decode(WorkflowIntent.self, from: documentationJSON) == .documentation)

        // 나머지 레거시는 여전히 .task
        let taskLegacyValues = [
            "implementation",
            "requirementsAnalysis", "testPlanning",
            "taskDecomposition",
        ]
        for legacy in taskLegacyValues {
            let json = "\"\(legacy)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(WorkflowIntent.self, from: json)
            #expect(decoded == .task, "레거시 \(legacy) → .task 디코딩 실패")
        }
    }

    @Test("레거시 brainstorm → discussion 디코딩")
    func legacyBrainstormDecoding() throws {
        let json = "\"brainstorm\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkflowIntent.self, from: json)
        #expect(decoded == .discussion)
    }

    @Test("알 수 없는 intent 문자열 → 디코딩 에러")
    func unknownIntentDecoding() {
        let json = "\"somethingRandom\"".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(WorkflowIntent.self, from: json)
        }
    }

    // MARK: - phaseSummary

    @Test("phaseSummary — intake/intent 제외, intent별 이름 적용")
    func phaseSummary() {
        // research: 요청 분석 → 전문가 배정 → 조사 → 결과 정리
        #expect(WorkflowIntent.research.phaseSummary.contains("조사"))
        #expect(WorkflowIntent.research.phaseSummary.contains("결과 정리"))

        // documentation: ... → 구조 설계 → 문서 작성 → 최종 정리
        #expect(WorkflowIntent.documentation.phaseSummary.contains("구조 설계"))
        #expect(WorkflowIntent.documentation.phaseSummary.contains("문서 작성"))
    }
}
