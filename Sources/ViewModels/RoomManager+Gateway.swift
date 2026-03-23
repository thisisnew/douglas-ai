import Foundation

// MARK: - Gateway Extension
// 사용자 상호작용 게이트 로직 (승인, 선택, 입력 대기)
// RoomManager에서 분리하여 책임 명확화
//
// 포함 기능:
// 1. 승인 게이트 (approveStep, rejectStep, appendAdditionalInput)
// 2. 계획 편집 (updateStepText, deleteStep, addStep, moveStep)
// 3. 리뷰 자동 승인 타이머 (startReviewAutoApproval, cancelReviewAutoApproval)
// 4. Intent 선택 게이트 (selectIntent)
// 5. 문서 유형 선택 게이트 (selectDocType)
// 6. 팀 확인 게이트 (confirmTeam, startEditingTeam, toggleAgentInTeam, confirmEditedTeam, skipTeamConfirmation)
// 7. 사용자 입력 게이트 (answerUserQuestion, proceedDiscussion)

extension RoomManager {

    // MARK: - 승인 게이트

    /// 승인 대기 중인 단계를 승인
    func approveStep(roomID: UUID) {
        cancelReviewAutoApproval(roomID: roomID)
        let msg = ChatMessage(role: .user, content: "승인")
        appendMessage(msg, to: roomID)
        pluginEventDelegate?(.approvalResolved(roomID: roomID, approved: true))

        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            let approvalType = rooms[idx].awaitingType?.toApprovalType ?? .stepApproval
            let record = ApprovalRecord(
                type: approvalType,
                approved: true,
                stepIndex: rooms[idx].pendingApprovalStepIndex,
                planVersion: rooms[idx].plan?.version
            )
            rooms[idx].recordApproval(record)
        }

        if approvalGates.hasPendingApproval(for: roomID) {
            approvalGates.approve(roomID: roomID)
        } else {
            // 워크플로우 없음 (예전 방/앱 재시작) → 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            let task = rooms[idx].title
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: task)
        }
    }

    /// 승인 대기 중인 단계를 거부 (수정 요청)
    func rejectStep(roomID: UUID, feedback: String? = nil) {
        cancelReviewAutoApproval(roomID: roomID)
        let msg = ChatMessage(role: .system, content: "수정 요청")
        appendMessage(msg, to: roomID)
        pluginEventDelegate?(.approvalResolved(roomID: roomID, approved: false))

        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            let approvalType = rooms[idx].awaitingType?.toApprovalType ?? .stepApproval
            let record = ApprovalRecord(
                type: approvalType,
                approved: false,
                feedback: feedback,
                stepIndex: rooms[idx].pendingApprovalStepIndex,
                planVersion: rooms[idx].plan?.version
            )
            rooms[idx].recordApproval(record)
        }

        if approvalGates.hasPendingApproval(for: roomID) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            approvalGates.reject(roomID: roomID)
        } else {
            // 워크플로우 없음 (앱 재시작 등) → 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            let task = rooms[idx].title
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: task)
        }
    }

    /// 승인 카드에서 추가 요구사항 입력 시 방 메시지에 추가
    func appendAdditionalInput(roomID: UUID, text: String) {
        let msg = ChatMessage(role: .user, content: text)
        appendMessage(msg, to: roomID)
    }

    // MARK: - 계획 단계 편집 (승인 전)

    /// 단계 텍스트 수정
    func updateStepText(roomID: UUID, stepIndex: Int, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = rooms.firstIndex(where: { $0.id == roomID }),
              rooms[idx].awaitingType == .planApproval,
              rooms[idx].plan?.steps.indices.contains(stepIndex) == true else { return }
        cancelReviewAutoApproval(roomID: roomID)
        rooms[idx].plan?.steps[stepIndex].text = trimmed
        scheduleSave()
    }

    /// 단계 삭제 (최소 1단계 유지)
    func deleteStep(roomID: UUID, stepIndex: Int) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              rooms[idx].awaitingType == .planApproval,
              rooms[idx].plan?.steps.indices.contains(stepIndex) == true,
              (rooms[idx].plan?.steps.count ?? 0) > 1 else { return }
        cancelReviewAutoApproval(roomID: roomID)
        rooms[idx].plan?.steps.remove(at: stepIndex)
        scheduleSave()
    }

    /// 단계 추가 (afterIndex 뒤에 삽입, nil이면 맨 앞)
    func addStep(roomID: UUID, afterIndex: Int?, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = rooms.firstIndex(where: { $0.id == roomID }),
              rooms[idx].awaitingType == .planApproval else { return }
        cancelReviewAutoApproval(roomID: roomID)
        let newStep = RoomStep(text: trimmed)
        let insertAt = min((afterIndex ?? -1) + 1, rooms[idx].plan?.steps.count ?? 0)
        rooms[idx].plan?.steps.insert(newStep, at: insertAt)
        scheduleSave()
    }

    /// 단계 순서 변경
    func moveStep(roomID: UUID, fromIndex: Int, toIndex: Int) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              rooms[idx].awaitingType == .planApproval,
              let steps = rooms[idx].plan?.steps,
              steps.indices.contains(fromIndex),
              toIndex >= 0, toIndex < steps.count,
              fromIndex != toIndex else { return }
        cancelReviewAutoApproval(roomID: roomID)
        let step = rooms[idx].plan!.steps.remove(at: fromIndex)
        rooms[idx].plan!.steps.insert(step, at: toIndex)
        scheduleSave()
    }

    // MARK: - 리뷰 자동 승인 타이머

    /// 리뷰 게이트 자동 승인 타이머 시작 (초)
    func startReviewAutoApproval(roomID: UUID, seconds: Int = 15) {
        cancelReviewAutoApproval(roomID: roomID)
        reviewAutoApprovalRemaining[roomID] = seconds

        reviewAutoApprovalTasks[roomID] = Task { @MainActor [weak self] in
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.reviewAutoApprovalRemaining[roomID] = remaining
            }
            guard !Task.isCancelled else { return }
            // 타이머 만료 → 자동 승인
            self?.reviewAutoApprovalRemaining.removeValue(forKey: roomID)
            self?.reviewAutoApprovalTasks.removeValue(forKey: roomID)
            self?.approveStep(roomID: roomID)
        }
    }

    /// 사용자 상호작용 감지 시 자동 승인 타이머 취소
    func cancelReviewAutoApproval(roomID: UUID) {
        reviewAutoApprovalTasks[roomID]?.cancel()
        reviewAutoApprovalTasks.removeValue(forKey: roomID)
        reviewAutoApprovalRemaining.removeValue(forKey: roomID)
    }

    // MARK: - Intent 선택 게이트

    /// 사용자가 Intent를 선택
    func selectIntent(roomID: UUID, intent: WorkflowIntent) {
        pendingIntentSelection.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .user, content: "\(intent.displayName) 선택")
        appendMessage(msg, to: roomID)

        if approvalGates.intentContinuations[roomID] != nil {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            approvalGates.provideIntent(roomID: roomID, intent: intent)
        } else {
            // 워크플로우 없음 (앱 재시작 등) → intent 설정 후 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            rooms[idx].setWorkflowIntent(intent)
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: rooms[idx].title)
        }
    }

    // MARK: - 문서 유형 선택 게이트

    /// 사용자가 문서 유형을 선택
    func selectDocType(roomID: UUID, docType: DocumentType) {
        pendingDocTypeSelection.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .user, content: "\(docType.displayName) 선택")
        appendMessage(msg, to: roomID)

        if approvalGates.docTypeContinuations[roomID] != nil {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            approvalGates.provideDocType(roomID: roomID, docType: docType)
        } else {
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            rooms[idx].setWorkflowDocumentType(docType)
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: rooms[idx].title)
        }
    }

    // MARK: - 팀 구성 확인 게이트

    /// "이대로 진행" — 현재 선택 그대로 확정
    func confirmTeam(roomID: UUID) {
        guard let state = pendingTeamConfirmation[roomID] else { return }
        let finalIDs = state.selectedAgentIDs
        pendingTeamConfirmation.removeValue(forKey: roomID)
        approvalGates.confirmTeam(roomID: roomID, selectedIDs: finalIDs)
        scheduleSave()
    }

    /// "구성 변경" 모드 진입
    func startEditingTeam(roomID: UUID) {
        guard pendingTeamConfirmation[roomID] != nil else { return }
        pendingTeamConfirmation[roomID]?.isEditing = true
    }

    /// 편집 모드에서 에이전트 선택/해제 토글
    func toggleAgentInTeam(roomID: UUID, agentID: UUID) {
        guard pendingTeamConfirmation[roomID] != nil else { return }
        if pendingTeamConfirmation[roomID]!.selectedAgentIDs.contains(agentID) {
            pendingTeamConfirmation[roomID]!.selectedAgentIDs.remove(agentID)
        } else {
            pendingTeamConfirmation[roomID]!.selectedAgentIDs.insert(agentID)
        }
    }

    /// 편집 확정 — 변경된 선택으로 확정
    func confirmEditedTeam(roomID: UUID) {
        guard let state = pendingTeamConfirmation[roomID] else { return }
        let finalIDs = state.selectedAgentIDs
        pendingTeamConfirmation.removeValue(forKey: roomID)
        approvalGates.confirmTeam(roomID: roomID, selectedIDs: finalIDs)
        scheduleSave()
    }

    /// 취소 — 팀 구성 없이 완료
    func skipTeamConfirmation(roomID: UUID) {
        pendingTeamConfirmation.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .system, content: "전문가 배정이 취소되었습니다.")
        appendMessage(msg, to: roomID)
        approvalGates.skipTeamConfirmation(roomID: roomID)
        scheduleSave()
    }

    // MARK: - 사용자 입력 게이트

    /// ask_user 도구에 대한 사용자 답변 제출
    func answerUserQuestion(roomID: UUID, answer: String) {
        pendingQuestionOptions.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .user, content: answer)
        appendMessage(msg, to: roomID)
        // userAnswers에 저장 (질문은 메시지에서 역추적)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].addUserAnswer(UserAnswer(question: "", answer: answer))
        }

        if approvalGates.hasPendingUserInput(for: roomID) {
            approvalGates.provideUserInput(roomID: roomID, input: answer)
        } else {
            // 워크플로우 없음 (앱 재시작 등) → 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            let task = rooms[idx].title
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: task)
        }
    }

    /// 토론 체크포인트에서 "진행" 선택 — 피드백 없이 다음 단계로
    func proceedDiscussion(roomID: UUID) {
        approvalGates.provideUserInput(roomID: roomID, input: "")
    }
}
