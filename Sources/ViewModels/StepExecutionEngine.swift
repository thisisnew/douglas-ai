import Foundation

/// Build 단계 실행 엔진: 계획 승인 후 끝까지 자동 실행
///
/// 패턴: WorkflowHost 프로토콜 의존, FileWriteTracker actor 재사용
/// - 단계 루프 관리 (step.status 전이 포함)
/// - 반복 감지 (자동 안전장치)
/// - 실행 중 사용자 개입 없음 (계획 승인 = 실행 위임)
@MainActor
final class StepExecutionEngine {

    // MARK: - 실행 정책

    struct Policy {
        let detectRepetition: Bool         // 반복 응답 감지 → 중단
        let generateWorkLog: Bool          // 완료 후 WorkLog 생성

        /// 기본 정책
        static let standard = Policy(
            detectRepetition: false,
            generateWorkLog: true
        )

        /// executeRoomWork 호환 정책
        static let legacy = Policy(
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
    private var previousStepResponse: String? // 반복 감지용

    // MARK: - 초기화

    init(host: any WorkflowHost, roomID: UUID, task: String, policy: Policy = .standard) {
        self.host = host
        self.roomID = roomID
        self.task = task
        self.policy = policy
    }

    // MARK: - 공개 인터페이스

    /// 전체 단계 루프 실행 (plan.steps 순회) — 계획 승인 후 끝까지 자동
    func run() async {
        guard let host else { return }
        guard let room = host.room(for: roomID), let plan = room.plan else { return }

        // 초기화 — Build 시작 시점 기록
        host.updateRoom(id: roomID) { room in
            room.buildPhaseMessageOffset = room.messages.count
            room.timerDurationSeconds = plan.estimatedSeconds
            room.timerStartedAt = Date()
            room.transitionTo(.inProgress)
        }
        host.scheduleSave()

        // 단계 순회 — 중단 없이 끝까지 실행
        for stepIndex in 0..<plan.steps.count {
            guard !Task.isCancelled,
                  let currentRoom = host.room(for: roomID),
                  currentRoom.status == .inProgress else { break }

            let step = currentRoom.plan!.steps[stepIndex]

            // 현재 단계 상태 업데이트
            host.updateRoom(id: roomID) { room in
                room.setCurrentStep(stepIndex)
                room.plan?.steps[stepIndex].status = .inProgress
            }

            // 단계 실행
            let success = await runStep(
                step: step, stepIndex: stepIndex, plan: plan
            )

            if success {
                // 완료: 전문 아카이브 + journal 요약 기록
                let fullResult: String
                let journalEntry: String
                if let room = host.room(for: roomID),
                   let lastMsg = room.messages.last(where: { $0.role == .assistant && $0.messageType == .text }),
                   !lastMsg.content.isEmpty {
                    fullResult = lastMsg.content
                    journalEntry = String(lastMsg.content.prefix(300))
                } else {
                    fullResult = ""
                    journalEntry = ""
                }
                host.updateRoom(id: roomID) { room in
                    room.plan?.steps[stepIndex].status = .completed
                    if !fullResult.isEmpty {
                        while room.plan?.stepResultsFull.count ?? 0 <= stepIndex {
                            room.plan?.stepResultsFull.append("")
                        }
                        room.plan?.stepResultsFull[stepIndex] = fullResult
                    }
                    if !journalEntry.isEmpty {
                        while room.plan?.stepJournal.count ?? 0 <= stepIndex {
                            room.plan?.stepJournal.append("")
                        }
                        room.plan?.stepJournal[stepIndex] = journalEntry
                    }
                }

                // 반복 감지
                if policy.detectRepetition, let result = checkRepetition() {
                    if case .aborted = result { return }
                }
            } else {
                // 실패: 워크플로우 중단
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
            }
        }

        host.scheduleSave()
    }

    // MARK: - LLM 호출 (단계 실행)

    private func runStep(
        step: RoomStep,
        stepIndex: Int,
        plan: RoomPlan
    ) async -> Bool {
        guard let host else { return false }

        let targetAgentIDs = resolveTargetAgents(for: step)

        let shortLabel = RoomManager.shortenStepLabel(step.text)
        let progressMsg = ChatMessage(
            role: .system,
            content: shortLabel,
            messageType: .progress
        )
        host.appendMessage(progressMsg, to: roomID)

        // TaskGroup 병렬 실행
        var failedAgentIDs: [UUID] = []
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for agentID in targetAgentIDs {
                group.addTask { [self] in
                    let success = await host.executeStep(
                        step: step.text,
                        fullTask: self.task,
                        agentID: agentID,
                        roomID: self.roomID,
                        stepIndex: stepIndex,
                        totalSteps: plan.steps.count,
                        fileWriteTracker: self.tracker,
                        progressGroupID: progressMsg.id,
                        deferHighRiskTools: false,
                        collectDeferred: { _ in },
                        workingDirectoryOverride: step.workingDirectory
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
                    deferHighRiskTools: false,
                    collectDeferred: { _ in },
                    workingDirectoryOverride: step.workingDirectory
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

    // MARK: - 반복 감지

    private enum StepResult {
        case aborted
    }

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
}
