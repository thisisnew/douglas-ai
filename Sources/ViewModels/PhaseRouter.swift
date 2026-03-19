import Foundation

/// 워크플로우 페이즈 디스패치 — intent.requiredPhases를 순회하며 각 페이즈 실행을 위임
///
/// RoomManager+Workflow.swift의 executePhaseWorkflow 루프를 캡슐화.
/// 개별 phase executor 메서드는 RoomManager extension에 유지되며,
/// PhaseRouter는 "어떤 순서로 실행할지"만 결정한다.
enum PhaseRouter {

    /// 워크플로우 전체 타임아웃 (초)
    static let workflowTimeoutSeconds: TimeInterval = 600 // 10분

    /// 다음 실행할 phase를 결정 (현재 intent + 완료된 phases 기준)
    static func nextPhase(
        intent: WorkflowIntent,
        modifiers: Set<IntentModifier>,
        completedPhases: Set<WorkflowPhase>
    ) -> WorkflowPhase? {
        let phases = intent.requiredPhases(with: modifiers)
        return phases.first(where: { !completedPhases.contains($0) })
    }

    /// 타임아웃 초과 여부
    static func isTimedOut(since start: Date) -> Bool {
        Date().timeIntervalSince(start) > workflowTimeoutSeconds
    }
}
