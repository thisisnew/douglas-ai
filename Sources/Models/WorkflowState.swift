import Foundation

/// 워크플로우 진행 상태 (intent, phase 추적)
struct WorkflowState: Codable, Equatable {
    var intent: WorkflowIntent?
    var documentType: DocumentType?
    var autoDocOutput: Bool
    var needsPlan: Bool
    var currentPhase: WorkflowPhase?
    var completedPhases: Set<WorkflowPhase>
    var activeRuleIDs: Set<UUID>?   // nil = 전체 규칙, Set = 매칭된 규칙만

    init(
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        autoDocOutput: Bool = false,
        needsPlan: Bool = false,
        currentPhase: WorkflowPhase? = nil,
        completedPhases: Set<WorkflowPhase> = [],
        activeRuleIDs: Set<UUID>? = nil
    ) {
        self.intent = intent
        self.documentType = documentType
        self.autoDocOutput = autoDocOutput
        self.needsPlan = needsPlan
        self.currentPhase = currentPhase
        self.completedPhases = completedPhases
        self.activeRuleIDs = activeRuleIDs
    }
}
