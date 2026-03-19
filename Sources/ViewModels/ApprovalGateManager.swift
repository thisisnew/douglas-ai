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
            approvalContinuations[roomID] = continuation
        }
    }

    /// 승인
    func approve(roomID: UUID) {
        approvalContinuations.removeValue(forKey: roomID)?.resume(returning: true)
    }

    /// 거부
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
            userInputContinuations[roomID] = continuation
        }
    }

    /// 사용자 입력 제공
    func provideUserInput(roomID: UUID, input: String) {
        userInputContinuations.removeValue(forKey: roomID)?.resume(returning: input)
    }

    func hasPendingUserInput(for roomID: UUID) -> Bool {
        userInputContinuations[roomID] != nil
    }

    // MARK: - Intent Selection Gate

    /// Intent 선택 대기
    func waitForIntent(roomID: UUID) async -> WorkflowIntent {
        await withCheckedContinuation { continuation in
            intentContinuations[roomID] = continuation
        }
    }

    /// Intent 제공
    func provideIntent(roomID: UUID, intent: WorkflowIntent) {
        intentContinuations.removeValue(forKey: roomID)?.resume(returning: intent)
    }

    // MARK: - Document Type Selection Gate

    /// 문서 유형 선택 대기
    func waitForDocType(roomID: UUID) async -> DocumentType {
        await withCheckedContinuation { continuation in
            docTypeContinuations[roomID] = continuation
        }
    }

    /// 문서 유형 제공
    func provideDocType(roomID: UUID, docType: DocumentType) {
        docTypeContinuations.removeValue(forKey: roomID)?.resume(returning: docType)
    }

    // MARK: - Team Confirmation Gate

    /// 팀 구성 확인 대기 — nil이면 건너뜀
    func waitForTeamConfirmation(roomID: UUID) async -> Set<UUID>? {
        await withCheckedContinuation { continuation in
            teamConfirmationContinuations[roomID] = continuation
        }
    }

    /// 팀 확정
    func confirmTeam(roomID: UUID, selectedIDs: Set<UUID>) {
        teamConfirmationContinuations.removeValue(forKey: roomID)?.resume(returning: selectedIDs)
    }

    /// 팀 구성 건너뜀
    func skipTeamConfirmation(roomID: UUID) {
        teamConfirmationContinuations.removeValue(forKey: roomID)?.resume(returning: nil)
    }

    // MARK: - Agent Suggestion Gate

    /// 에이전트 생성 제안 승인 대기
    func waitForSuggestionResponse(roomID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            suggestionContinuations[roomID] = continuation
        }
    }

    /// 에이전트 생성 제안 승인
    func approveSuggestion(roomID: UUID) {
        suggestionContinuations.removeValue(forKey: roomID)?.resume(returning: true)
    }

    /// 에이전트 생성 제안 거부
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
