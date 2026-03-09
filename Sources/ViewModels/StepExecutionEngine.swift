import Foundation

/// Build 단계 실행 엔진: executeBuildPhase + executeRoomWork 통합 대체
///
/// 패턴: WorkflowHost 프로토콜 의존, FileWriteTracker actor 재사용
/// - 단계 루프 관리 (step.status 전이 포함)
/// - 사용자 피드백 루프 (실행 중 입력 → 재실행)
/// - 롤백 (UI 클릭 또는 텍스트 명령)
/// - 정책 기반 동작 분기 (high-risk 위임, 반복 감지, WorkLog 생성)
@MainActor
final class StepExecutionEngine {

    // MARK: - 실행 정책

    /// 실행 정책 — 기존 executeBuildPhase / executeRoomWork 차이를 설정으로 흡수
    struct Policy {
        let enableUserFeedbackLoop: Bool   // 단계 실행 중 사용자 입력 → 재실행
        let deferHighRiskSteps: Bool       // high-risk → DeferredAction으로 위임
        let detectRepetition: Bool         // 반복 응답 감지 → 중단
        let generateWorkLog: Bool          // 완료 후 WorkLog 생성

        /// 기본 정책 (executeBuildPhase 대체)
        static let standard = Policy(
            enableUserFeedbackLoop: true,
            deferHighRiskSteps: true,
            detectRepetition: false,
            generateWorkLog: true
        )

        /// executeRoomWork 호환 정책
        static let legacy = Policy(
            enableUserFeedbackLoop: true,
            deferHighRiskSteps: false,
            detectRepetition: true,
            generateWorkLog: true
        )
    }

    // MARK: - 의존성

    private weak var host: (any WorkflowHost)?
    private let roomID: UUID
    private let task: String
    private let policy: Policy

    // MARK: - 내부 상태

    private let tracker = FileWriteTracker()
    private var pendingUserDirective: String?
    private var stepBaselineMessageCount: Int = 0
    private var previousStepResponse: String? // 반복 감지용

    // MARK: - 초기화

    init(host: any WorkflowHost, roomID: UUID, task: String, policy: Policy = .standard) {
        self.host = host
        self.roomID = roomID
        self.task = task
        self.policy = policy
    }

    // MARK: - 공개 인터페이스

    /// 전체 단계 루프 실행 (plan.steps 순회)
    func run() async {
        guard let host else { return }
        guard let room = host.room(for: roomID), let plan = room.plan else { return }

        // 초기화
        stepBaselineMessageCount = room.messages.count
        host.updateRoom(id: roomID) { room in
            room.timerDurationSeconds = plan.estimatedSeconds
            room.timerStartedAt = Date()
            room.transitionTo(.inProgress)
        }
        host.scheduleSave()

        var stepIndex = 0
        while stepIndex < plan.steps.count {
            // 취소 / 비활성 체크
            guard !Task.isCancelled,
                  let currentRoom = host.room(for: roomID),
                  currentRoom.status == .inProgress else { break }

            // 롤백 요청 체크 (PlanCard 클릭)
            if let rollbackTarget = host.stepRollbackTargets[roomID] {
                host.stepRollbackTargets.removeValue(forKey: roomID)
                let currentPlan = currentRoom.plan
                host.updateRoom(id: roomID) { room in
                    guard let steps = currentPlan?.steps else { return }
                    for j in rollbackTarget..<steps.count {
                        room.plan?.steps[j].status = .pending
                    }
                }
                // 즉시 확인 메시지는 PlanCard에서 이미 전송됨
                // 여기서는 실행 시작 메시지만 추가
                let rollbackMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(rollbackTarget + 1) 재실행을 시작합니다.",
                    messageType: .progress
                )
                host.appendMessage(rollbackMsg, to: roomID)
                stepIndex = rollbackTarget
                continue
            }

            let step = currentRoom.plan!.steps[stepIndex]

            // 이전 단계 이후 사용자 메시지 수집
            collectPendingDirective()

            // 현재 단계 상태 업데이트
            host.updateRoom(id: roomID) { room in
                room.setCurrentStep(stepIndex)
                room.plan?.steps[stepIndex].status = .inProgress
            }

            // High-risk 위임
            if policy.deferHighRiskSteps && step.riskLevel == .high {
                deferHighRiskStep(stepIndex: stepIndex, step: step,
                                  totalSteps: plan.steps.count)
                host.updateRoom(id: roomID) { room in
                    room.plan?.steps[stepIndex].status = .skipped
                }
                stepIndex += 1
                continue
            }

            // 단계 실행 + 피드백 루프
            let result = await executeStepWithFeedback(
                step: step, stepIndex: stepIndex, plan: plan
            )

            switch result {
            case .success:
                host.updateRoom(id: roomID) { room in
                    room.plan?.steps[stepIndex].status = .completed
                }
                stepIndex += 1

            case .rollback(let target):
                // 피드백 루프에서 롤백 감지
                host.updateRoom(id: roomID) { room in
                    for j in target..<plan.steps.count {
                        room.plan?.steps[j].status = .pending
                    }
                }
                let rollbackMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(target + 1)부터 다시 실행합니다.",
                    messageType: .progress
                )
                host.appendMessage(rollbackMsg, to: roomID)
                stepIndex = target

            case .failed:
                host.updateRoom(id: roomID) { room in
                    room.plan?.steps[stepIndex].status = .failed
                    room.transitionTo(.failed)
                    room.completedAt = Date()
                }
                let failMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1): 모든 에이전트 실패로 워크플로우를 중단합니다.",
                    messageType: .error
                )
                host.appendMessage(failMsg, to: roomID)
                host.syncAgentStatuses()
                host.scheduleSave()
                return

            case .aborted:
                // 반복 감지 또는 취소
                host.syncAgentStatuses()
                host.scheduleSave()
                return
            }
        }

        host.scheduleSave()
    }

    // MARK: - 단계 실행 결과

    private enum StepResult {
        case success
        case failed
        case aborted
        case rollback(Int) // 0-based step index
    }

    // MARK: - 단계 실행 + 피드백 루프

    private func executeStepWithFeedback(
        step: RoomStep,
        stepIndex: Int,
        plan: RoomPlan
    ) async -> StepResult {
        guard let host else { return .aborted }

        let targetAgentIDs = resolveTargetAgents(for: step)
        let deferCollector = makeDeferCollector()

        // 첫 실행
        let firstRun = await runStep(
            step: step, stepIndex: stepIndex, plan: plan,
            targetAgentIDs: targetAgentIDs, deferCollector: deferCollector
        )
        guard firstRun else { return .failed }

        // 반복 감지
        if policy.detectRepetition {
            if let result = checkRepetition() {
                return result
            }
        }

        // 피드백 루프
        guard policy.enableUserFeedbackLoop else { return .success }

        while true {
            guard !Task.isCancelled,
                  let room = host.room(for: roomID),
                  room.status == .inProgress else { return .aborted }

            // 롤백 요청 체크 (PlanCard 클릭)
            if let rollbackTarget = host.stepRollbackTargets[roomID] {
                host.stepRollbackTargets.removeValue(forKey: roomID)
                return .rollback(rollbackTarget)
            }

            let newUserTexts = collectNewUserMessages()
            guard !newUserTexts.isEmpty else { return .success }

            // 롤백 구문 확인 ("3단계부터 다시")
            let joined = newUserTexts.joined(separator: "\n")
            if let rollbackTarget = parseRollbackRequest(from: joined, totalSteps: plan.steps.count) {
                pendingUserDirective = joined
                return .rollback(rollbackTarget)
            }

            // 사용자 피드백 → 같은 단계 재실행
            pendingUserDirective = joined

            let retryMsg = ChatMessage(
                role: .system,
                content: "추가 요건을 반영하여 단계 \(stepIndex + 1)을 다시 실행합니다.",
                messageType: .progress
            )
            host.appendMessage(retryMsg, to: roomID)

            await tracker.reset()
            let retrySuccess = await runStep(
                step: step, stepIndex: stepIndex, plan: plan,
                targetAgentIDs: targetAgentIDs, deferCollector: deferCollector
            )
            guard retrySuccess else { return .failed }

            // 반복 감지
            if policy.detectRepetition {
                if let result = checkRepetition() {
                    return result
                }
            }
        }
    }

    // MARK: - LLM 호출 (단계 실행)

    private func runStep(
        step: RoomStep,
        stepIndex: Int,
        plan: RoomPlan,
        targetAgentIDs: [UUID],
        deferCollector: @escaping (DeferredAction) -> Void
    ) async -> Bool {
        guard let host else { return false }

        let shortLabel = RoomManager.shortenStepLabel(step.text)
        let progressMsg = ChatMessage(
            role: .system,
            content: shortLabel,
            messageType: .progress
        )
        host.appendMessage(progressMsg, to: roomID)

        // 사용자 지시 반영
        let effectiveTask: String
        if let directive = pendingUserDirective {
            effectiveTask = task + "\n\n[사용자 추가 지시]\n\(directive)"
            pendingUserDirective = nil
        } else {
            effectiveTask = task
        }

        // TaskGroup 병렬 실행
        var failedAgentIDs: [UUID] = []
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for agentID in targetAgentIDs {
                group.addTask { [self] in
                    let success = await host.executeStep(
                        step: step.text,
                        fullTask: effectiveTask,
                        agentID: agentID,
                        roomID: self.roomID,
                        stepIndex: stepIndex,
                        totalSteps: plan.steps.count,
                        fileWriteTracker: self.tracker,
                        progressGroupID: progressMsg.id,
                        deferHighRiskTools: self.policy.deferHighRiskSteps,
                        collectDeferred: deferCollector
                    )
                    return (agentID, success)
                }
            }
            for await (agentID, success) in group {
                if !success { failedAgentIDs.append(agentID) }
            }
        }

        // 1회 재시도
        if !failedAgentIDs.isEmpty {
            var stillFailed: [UUID] = []
            for agentID in failedAgentIDs {
                let success = await host.executeStep(
                    step: step.text,
                    fullTask: task,
                    agentID: agentID,
                    roomID: roomID,
                    stepIndex: stepIndex,
                    totalSteps: plan.steps.count,
                    fileWriteTracker: tracker,
                    progressGroupID: progressMsg.id,
                    deferHighRiskTools: policy.deferHighRiskSteps,
                    collectDeferred: deferCollector
                )
                if !success { stillFailed.append(agentID) }
            }
            failedAgentIDs = stillFailed
        }

        // 전원 실패 여부
        let allFailed = failedAgentIDs.count == targetAgentIDs.count && !targetAgentIDs.isEmpty
        if allFailed { return false }

        // 일부 실패 경고
        if !failedAgentIDs.isEmpty, let host = self.host {
            let failedNames = failedAgentIDs.compactMap { id in
                host.agentStore?.agents.first(where: { $0.id == id })?.name
            }.joined(separator: ", ")
            let warnMsg = ChatMessage(
                role: .system,
                content: "단계 \(stepIndex + 1): \(failedNames) 실패 (재시도 포함). 나머지 에이전트로 계속 진행합니다.",
                messageType: .error
            )
            host.appendMessage(warnMsg, to: roomID)
        }

        // 충돌 감지
        let conflicts = await tracker.getConflicts()
        if !conflicts.isEmpty, let host = self.host {
            let conflictPaths = conflicts.map { $0.path }.joined(separator: ", ")
            let warnMsg = ChatMessage(
                role: .system,
                content: "⚠️ 파일 충돌 감지: \(conflictPaths). 에이전트 간 동일 파일 수정 발생.",
                messageType: .error
            )
            host.appendMessage(warnMsg, to: roomID)
        }

        return true
    }

    // MARK: - 사용자 메시지 수집

    /// 단계 간 사용자 메시지 수집 (루프 시작에서 호출)
    private func collectPendingDirective() {
        guard let room = host?.room(for: roomID) else { return }
        let allMsgs = room.messages
        guard stepBaselineMessageCount < allMsgs.count else { return }

        let slice = Array(allMsgs[stepBaselineMessageCount...])
        let userTexts: [String] = slice.compactMap { msg in
            guard msg.role == .user, msg.messageType == .text,
                  !msg.content.isEmpty else { return nil }
            return msg.content
        }
        if !userTexts.isEmpty {
            pendingUserDirective = userTexts.joined(separator: "\n")
        }
        stepBaselineMessageCount = allMsgs.count
    }

    /// 단계 실행 후 새 사용자 메시지 확인 (피드백 루프에서 호출)
    private func collectNewUserMessages() -> [String] {
        guard let room = host?.room(for: roomID) else { return [] }
        let allMsgs = room.messages
        guard stepBaselineMessageCount < allMsgs.count else { return [] }

        let slice = Array(allMsgs[stepBaselineMessageCount...])
        let userTexts: [String] = slice.compactMap { msg in
            guard msg.role == .user, msg.messageType == .text,
                  !msg.content.isEmpty else { return nil }
            return msg.content
        }
        stepBaselineMessageCount = allMsgs.count
        return userTexts
    }

    // MARK: - 에이전트 결정

    private func resolveTargetAgents(for step: RoomStep) -> [UUID] {
        guard let host, let room = host.room(for: roomID) else { return [] }

        if let assignedID = step.assignedAgentID {
            return [assignedID]
        }

        // 마스터 제외 전문가
        let specialists = room.assignedAgentIDs.filter { id in
            let agent = host.agentStore?.agents.first(where: { $0.id == id })
            return !(agent?.isMaster ?? false)
        }
        return specialists.isEmpty ? room.assignedAgentIDs : specialists
    }

    // MARK: - DeferredAction 수집

    private func makeDeferCollector() -> (DeferredAction) -> Void {
        let roomID = self.roomID
        return { [weak self] deferred in
            Task { @MainActor in
                self?.host?.updateRoom(id: roomID) { room in
                    room.deferredActions.append(deferred)
                }
            }
        }
    }

    // MARK: - High-risk 위임

    private func deferHighRiskStep(stepIndex: Int, step: RoomStep, totalSteps: Int) {
        guard let host else { return }

        let deferred = DeferredAction(
            id: UUID(),
            toolName: "step_\(stepIndex + 1)",
            arguments: ["text": .string(step.text)],
            description: step.text,
            riskLevel: .high,
            previewContent: "[\(stepIndex + 1)/\(totalSteps)] \(step.text)",
            status: .pending
        )
        host.updateRoom(id: roomID) { room in
            room.deferredActions.append(deferred)
        }

        let deferMsg = ChatMessage(
            role: .system,
            content: "⏸ 단계 \(stepIndex + 1) (high-risk): Deliver에서 승인 후 실행됩니다.\n→ \(step.text)",
            messageType: .progress
        )
        host.appendMessage(deferMsg, to: roomID)
        host.scheduleSave()
    }

    // MARK: - 반복 감지

    private func checkRepetition() -> StepResult? {
        guard let host, let room = host.room(for: roomID) else { return nil }

        let latestResponse = room.messages
            .last(where: { $0.role == .assistant && ($0.messageType == .text || $0.messageType == .toolActivity) })?
            .content ?? ""

        if let prev = previousStepResponse, !prev.isEmpty, !latestResponse.isEmpty {
            let similarity = RoomManager.wordOverlapSimilarity(prev, latestResponse)
            if similarity > 0.6 {
                host.updateRoom(id: roomID) { room in
                    room.transitionTo(.failed)
                    room.completedAt = Date()
                }
                let stuckMsg = ChatMessage(
                    role: .system,
                    content: "에이전트가 동일한 응답을 반복하여 워크플로우를 중단합니다.",
                    messageType: .error
                )
                host.appendMessage(stuckMsg, to: roomID)
                return .aborted
            }
        }
        previousStepResponse = latestResponse
        return nil
    }

    // MARK: - 롤백 구문 파싱

    /// 사용자 메시지에서 롤백 요청 감지 ("3단계부터 다시", "step 2" 등)
    private func parseRollbackRequest(from text: String, totalSteps: Int) -> Int? {
        let lower = text.lowercased()
        let patterns = ["(\\d+)\\s*단계", "(\\d+)\\s*번", "step\\s*(\\d+)"]

        // "다시", "롤백", "돌아" 같은 의도 단어가 있는지 확인
        let intentWords = ["다시", "롤백", "돌아", "되돌", "rollback", "redo"]
        let hasRollbackIntent = intentWords.contains { lower.contains($0) }
        guard hasRollbackIntent else { return nil }

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: lower), let num = Int(lower[swiftRange]),
                   num >= 1 && num <= totalSteps {
                    return num - 1 // 0-based
                }
            }
        }
        return nil
    }
}
