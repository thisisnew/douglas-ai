import Foundation

/// 워크플로우 진행 상태 (intent, phase 추적)
struct WorkflowState: Equatable {
    var intent: WorkflowIntent?
    var documentType: DocumentType?
    var autoDocOutput: Bool
    var needsPlan: Bool
    var currentPhase: WorkflowPhase?
    var completedPhases: Set<WorkflowPhase>
    var activeRuleIDs: Set<UUID>?   // nil = 전체 규칙, Set = 매칭된 규칙만
    var modifiers: Set<IntentModifier>
    var phaseTransitions: [PhaseTransition]  // 단계 전이 감사 기록 — TODO: [P3] UI 노출 또는 export 기능 추가
    /// 각 페이즈 완료 시 요약 — 다음 페이즈에서 전체 히스토리 대신 참조 (토큰 최적화)
    var phaseSummaries: [WorkflowPhase: String]

    // MARK: - 도메인 메서드 (불변식 보호)

    /// 페이즈 전이 — 감사 기록 자동 추가
    mutating func advanceToPhase(_ next: WorkflowPhase) {
        let previous = currentPhase
        phaseTransitions.append(PhaseTransition(from: previous, to: next))
        currentPhase = next
    }

    /// 페이즈 완료 처리
    mutating func completePhase(_ phase: WorkflowPhase) {
        completedPhases.insert(phase)
    }

    /// 현재 페이즈 초기화 (워크플로우 완료/실패 시)
    mutating func clearCurrentPhase() {
        currentPhase = nil
    }

    /// 페이즈별 요약 저장
    mutating func recordPhaseSummary(phase: WorkflowPhase, summary: String) {
        phaseSummaries[phase] = summary
    }

    init(
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        autoDocOutput: Bool = false,
        needsPlan: Bool = false,
        currentPhase: WorkflowPhase? = nil,
        completedPhases: Set<WorkflowPhase> = [],
        activeRuleIDs: Set<UUID>? = nil,
        modifiers: Set<IntentModifier> = [],
        phaseTransitions: [PhaseTransition] = [],
        phaseSummaries: [WorkflowPhase: String] = [:]
    ) {
        self.intent = intent
        self.documentType = documentType
        self.autoDocOutput = autoDocOutput
        self.needsPlan = needsPlan
        self.currentPhase = currentPhase
        self.completedPhases = completedPhases
        self.activeRuleIDs = activeRuleIDs
        self.modifiers = modifiers
        self.phaseTransitions = phaseTransitions
        self.phaseSummaries = phaseSummaries
    }
}

// MARK: - Codable (하위 호환: phaseTransitions 누락 시 빈 배열)

extension WorkflowState: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intent = try container.decodeIfPresent(WorkflowIntent.self, forKey: .intent)
        documentType = try container.decodeIfPresent(DocumentType.self, forKey: .documentType)
        autoDocOutput = try container.decodeIfPresent(Bool.self, forKey: .autoDocOutput) ?? false
        needsPlan = try container.decodeIfPresent(Bool.self, forKey: .needsPlan) ?? false
        currentPhase = try container.decodeIfPresent(WorkflowPhase.self, forKey: .currentPhase)
        completedPhases = try container.decodeIfPresent(Set<WorkflowPhase>.self, forKey: .completedPhases) ?? []
        activeRuleIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .activeRuleIDs)
        modifiers = try container.decodeIfPresent(Set<IntentModifier>.self, forKey: .modifiers) ?? []
        phaseTransitions = try container.decodeIfPresent([PhaseTransition].self, forKey: .phaseTransitions) ?? []
        phaseSummaries = try container.decodeIfPresent([WorkflowPhase: String].self, forKey: .phaseSummaries) ?? [:]
    }
}
