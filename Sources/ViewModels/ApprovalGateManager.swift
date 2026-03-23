import Foundation

/// 워크플로우 승인/입력 게이트 관리 — continuation 소유권 단일화
///
/// RoomManager에서 분리된 7종 continuation 딕셔너리를 소유하며,
/// 워크플로우 페이즈가 사용자 입력을 기다릴 때 사용하는 wait/provide 쌍을 제공한다.
@MainActor
final class ApprovalGateManager {

    // MARK: - Continuation Storage

    var approvalContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    var userInputContinuations: [UUID: CheckedContinuation<String, Never>] = [:]
    var intentContinuations: [UUID: CheckedContinuation<WorkflowIntent, Never>] = [:]
    var docTypeContinuations: [UUID: CheckedContinuation<DocumentType, Never>] = [:]
    var teamConfirmationContinuations: [UUID: CheckedContinuation<Set<UUID>?, Never>] = [:]
    var suggestionContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    // MARK: - Approval Gate

    /// 승인 대기 — 사용자가 approve/reject할 때까지 블록
    func waitForApproval(roomID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            // 기존 continuation이 있으면 취소 처리 후 대체 (누수 방지)
            approvalContinuations.removeValue(forKey: roomID)?.resume(returning: false)
            approvalContinuations[roomID] = continuation
        }
    }

    func approve(roomID: UUID) {
        approvalContinuations.removeValue(forKey: roomID)?.resume(returning: true)
    }

    func reject(roomID: UUID) {
        approvalContinuations.removeValue(forKey: roomID)?.resume(returning: false)
    }

    func hasPendingApproval(for roomID: UUID) -> Bool {
        approvalContinuations[roomID] != nil
    }

    // MARK: - User Input Gate

    /// 사용자 입력 대기 — ask_user 도구, 토론 체크포인트 등
    func waitForUserInput(roomID: UUID) async -> String {
        await withCheckedContinuation { continuation in
            userInputContinuations.removeValue(forKey: roomID)?.resume(returning: "")
            userInputContinuations[roomID] = continuation
        }
    }

    func provideUserInput(roomID: UUID, input: String) {
        userInputContinuations.removeValue(forKey: roomID)?.resume(returning: input)
    }

    func hasPendingUserInput(for roomID: UUID) -> Bool {
        userInputContinuations[roomID] != nil
    }

    // MARK: - Intent Selection Gate

    func waitForIntent(roomID: UUID) async -> WorkflowIntent {
        await withCheckedContinuation { continuation in
            intentContinuations.removeValue(forKey: roomID)?.resume(returning: .quickAnswer)
            intentContinuations[roomID] = continuation
        }
    }

    func provideIntent(roomID: UUID, intent: WorkflowIntent) {
        intentContinuations.removeValue(forKey: roomID)?.resume(returning: intent)
    }

    // MARK: - Document Type Selection Gate

    func waitForDocType(roomID: UUID) async -> DocumentType {
        await withCheckedContinuation { continuation in
            docTypeContinuations.removeValue(forKey: roomID)?.resume(returning: .freeform)
            docTypeContinuations[roomID] = continuation
        }
    }

    func provideDocType(roomID: UUID, docType: DocumentType) {
        docTypeContinuations.removeValue(forKey: roomID)?.resume(returning: docType)
    }

    // MARK: - Team Confirmation Gate

    func waitForTeamConfirmation(roomID: UUID) async -> Set<UUID>? {
        await withCheckedContinuation { continuation in
            teamConfirmationContinuations.removeValue(forKey: roomID)?.resume(returning: nil)
            teamConfirmationContinuations[roomID] = continuation
        }
    }

    func confirmTeam(roomID: UUID, selectedIDs: Set<UUID>) {
        teamConfirmationContinuations.removeValue(forKey: roomID)?.resume(returning: selectedIDs)
    }

    func skipTeamConfirmation(roomID: UUID) {
        teamConfirmationContinuations.removeValue(forKey: roomID)?.resume(returning: nil)
    }

    // MARK: - Agent Suggestion Gate

    func waitForSuggestionResponse(roomID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            suggestionContinuations.removeValue(forKey: roomID)?.resume(returning: false)
            suggestionContinuations[roomID] = continuation
        }
    }

    func approveSuggestion(roomID: UUID) {
        suggestionContinuations.removeValue(forKey: roomID)?.resume(returning: true)
    }

    func rejectSuggestion(roomID: UUID) {
        suggestionContinuations.removeValue(forKey: roomID)?.resume(returning: false)
    }

    // MARK: - Lifecycle

    /// 방 삭제/완료 시 모든 pending continuation 정리 (leak 방지)
    func cancelAll(for roomID: UUID) {
        approvalContinuations.removeValue(forKey: roomID)?.resume(returning: false)
        userInputContinuations.removeValue(forKey: roomID)?.resume(returning: "")
        intentContinuations.removeValue(forKey: roomID)?.resume(returning: .quickAnswer)
        docTypeContinuations.removeValue(forKey: roomID)?.resume(returning: .freeform)
        teamConfirmationContinuations.removeValue(forKey: roomID)?.resume(returning: nil)
        suggestionContinuations.removeValue(forKey: roomID)?.resume(returning: false)
    }
}
