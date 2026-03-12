import Foundation

// MARK: - 포지션 슬롯

/// intent별 필요 포지션 1개
struct PositionSlot {
    let position: WorkflowPosition
    let priority: RoleRequirement.Priority
}

// MARK: - 포지션 템플릿

/// WorkflowIntent별 필요 포지션 목록 생성
enum PositionTemplate {
    static func slots(for intent: WorkflowIntent) -> [PositionSlot] {
        switch intent {
        case .task:
            return [
                PositionSlot(position: .implementer, priority: .required),
                PositionSlot(position: .reviewer, priority: .optional),
            ]
        case .complex:
            return [
                PositionSlot(position: .architect, priority: .required),
                PositionSlot(position: .implementer, priority: .required),
                PositionSlot(position: .reviewer, priority: .optional),
            ]
        case .discussion:
            return [
                PositionSlot(position: .analyst, priority: .required),
                PositionSlot(position: .advisor, priority: .required),
            ]
        case .research:
            return [
                PositionSlot(position: .researcher, priority: .required),
                PositionSlot(position: .analyst, priority: .optional),
            ]
        case .documentation:
            return [
                PositionSlot(position: .writer, priority: .required),
                PositionSlot(position: .reviewer, priority: .optional),
            ]
        case .quickAnswer:
            return [
                PositionSlot(position: .advisor, priority: .required),
            ]
        }
    }
}
