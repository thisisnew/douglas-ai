import Foundation

/// 워크플로우 진행 상태 (intent, phase 추적)
struct WorkflowState: Codable, Equatable {
    var intent: WorkflowIntent?
    var documentType: DocumentType?
    var autoDocOutput: Bool
    var needsPlan: Bool
    var currentPhase: WorkflowPhase?
    var completedPhases: Set<WorkflowPhase>

    init(
        intent: WorkflowIntent? = nil,
        documentType: DocumentType? = nil,
        autoDocOutput: Bool = false,
        needsPlan: Bool = false,
        currentPhase: WorkflowPhase? = nil,
        completedPhases: Set<WorkflowPhase> = []
    ) {
        self.intent = intent
        self.documentType = documentType
        self.autoDocOutput = autoDocOutput
        self.needsPlan = needsPlan
        self.currentPhase = currentPhase
        self.completedPhases = completedPhases
    }
}
