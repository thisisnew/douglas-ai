import Foundation

/// 에이전트 응답 끝에 붙은 선택지 텍스트 제거 (예: "1. 다음(구현) 2. 수정할래요 x. 나가기")
private func stripTrailingOptions(_ text: String) -> String {
    // 마지막 수 줄 이내에서 번호+선택지 패턴을 감지하여 제거
    let lines = text.components(separatedBy: "\n")
    guard lines.count >= 2 else { return text }

    // 뒤에서부터 빈 줄 + 코드블록 닫는 마커(```) 스킵
    var endIndex = lines.count
    while endIndex > 0 {
        let trimmed = lines[endIndex - 1].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.allSatisfy({ $0 == "`" }) {
            endIndex -= 1
        } else {
            break
        }
    }

    // 선택지 라인 패턴: "1." "2." "x." 또는 "1)" 등으로 시작 + 짧은 텍스트
    let optionPattern = #"^\s*(\d+|[xX])\s*[.)]\s*.+"#
    guard let regex = try? NSRegularExpression(pattern: optionPattern) else { return text }

    var optionStart = endIndex
    var optionCount = 0
    for i in stride(from: endIndex - 1, through: max(0, endIndex - 6), by: -1) {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let range = NSRange(line.startIndex..., in: line)
        if regex.firstMatch(in: line, range: range) != nil {
            optionStart = i
            optionCount += 1
        } else {
            break
        }
    }

    // 선택지 2개 이상일 때만 제거 (단일 번호 항목은 일반 내용일 수 있음)
    guard optionCount >= 2 else { return text }

    // 선택지 바로 위의 구분선(---)도 함께 제거
    var cleanStart = optionStart
    if cleanStart > 0 {
        let above = lines[cleanStart - 1].trimmingCharacters(in: .whitespaces)
        if !above.isEmpty && above.allSatisfy({ $0 == "-" }) {
            cleanStart -= 1
        }
    }

    let kept = Array(lines[0..<cleanStart])
    return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Clarify 응답에서 Jira/인증 관련 환각 문장 제거 (안전망)
private func stripHallucinatedAuthLines(_ text: String) -> String {
    let patterns: [String] = [
        "인증 정보", "API 토큰", "자격증명", "설정되어 있지",
        "MCP 도구", "MCP 서버", "직접 호출할 수 있는",
        "직접 제공", "직접 확인해", "연결되어 있지 않",
        "접근할 수 없", "접근 권한", "Jira API를 직접",
    ]

    let lines = text.components(separatedBy: "\n")
    let filtered = lines.filter { line in
        !patterns.contains(where: { line.contains($0) })
    }

    return filtered.joined(separator: "\n")
        .replacingOccurrences(of: "\n\n\n", with: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// LLM 응답의 `~/` 경로를 절대경로로 확장
private func expandTildePaths(_ text: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return text.replacingOccurrences(of: "~/", with: "\(home)/")
}

/// clarify 응답에서 [delegation] 블록을 파싱하여 DelegationInfo 반환
/// 파싱 실패 시 .open 폴백 (기존 assemble 흐름)
private func parseDelegationBlock(_ text: String) -> DelegationInfo {
    guard let startRange = text.range(of: "[delegation]"),
          let endRange = text.range(of: "[/delegation]"),
          startRange.upperBound < endRange.lowerBound else {
        return DelegationInfo(type: .open, agentNames: [])
    }

    let blockContent = String(text[startRange.upperBound..<endRange.lowerBound])
    let lines = blockContent.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

    var type: DelegationInfo.DelegationType = .open
    var agentNames: [String] = []

    for line in lines {
        if line.lowercased().hasPrefix("type:") {
            let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()
            if value == "explicit" { type = .explicit }
        } else if line.lowercased().hasPrefix("agents:") {
            let value = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            agentNames = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    return DelegationInfo(type: type, agentNames: agentNames)
}

/// [delegation]...[/delegation] 블록을 텍스트에서 제거
private func stripDelegationBlock(_ text: String) -> String {
    guard let startRange = text.range(of: "[delegation]"),
          let endRange = text.range(of: "[/delegation]") else {
        return text
    }
    var result = text
    result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 스트리밍 청크 누적용 스레드-안전 버퍼
private final class StreamBuffer: @unchecked Sendable {
    private var _value = ""
    func append(_ chunk: String) -> String {
        _value += chunk
        return _value
    }
}

/// 팀 구성 확인 게이트 상태
struct TeamConfirmationState: Equatable {
    /// 현재 선택된 에이전트 (자동 매칭된 + 사용자 추가)
    var selectedAgentIDs: Set<UUID>
    /// 추가 가능한 에이전트 (방에 없는 서브에이전트)
    var candidateAgentIDs: [UUID]
    /// "구성 변경" 편집 모드 여부
    var isEditing: Bool = false
}

@MainActor
class RoomManager: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selectedRoomID: UUID?
    /// 마스터 위임으로 자동 생성된 방 → UI에서 자동으로 창을 열기 위한 트리거
    @Published var pendingAutoOpenRoomID: UUID?
    /// 방별 현재 발언 중인 에이전트 (UI 표시용, 영속화 안 함)
    @Published var speakingAgentIDByRoom: [UUID: UUID] = [:]
    /// Intent 선택 대기 중인 방 (방 ID → LLM 추천 intent)
    @Published var pendingIntentSelection: [UUID: WorkflowIntent] = [:]
    /// 문서 유형 선택 대기 중인 방 (향후 재활용 가능)
    @Published var pendingDocTypeSelection: [UUID: Bool] = [:]
    /// 팀 구성 확인 대기 중인 방 (방 ID → 확인 상태)
    @Published var pendingTeamConfirmation: [UUID: TeamConfirmationState] = [:]
    /// 리뷰 게이트 자동 승인 카운트다운 (방 ID → 남은 초)
    @Published var reviewAutoApprovalRemaining: [UUID: Int] = [:]

    private(set) var agentStore: AgentStore?
    private(set) var providerManager: ProviderManager?
    private var timerTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// 방별 워크플로우 태스크 (취소 가능)
    private var roomTasks: [UUID: Task<Void, Never>] = [:]
    /// 승인 게이트 대기 중인 continuation (방 ID → continuation)
    private var approvalContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// 리뷰 게이트 자동 승인 타이머 태스크 (취소용)
    private var reviewAutoApprovalTasks: [UUID: Task<Void, Never>] = [:]
    /// 사용자 입력 대기 중인 continuation (방 ID → continuation)
    private var userInputContinuations: [UUID: CheckedContinuation<String, Never>] = [:]
    /// 에이전트 생성 제안 승인 대기 continuation (방 ID → continuation, Bool = 사용자 응답 여부)
    private var suggestionContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// Intent 선택 대기 중인 continuation (방 ID → continuation)
    private var intentContinuations: [UUID: CheckedContinuation<WorkflowIntent, Never>] = [:]
    /// 문서 유형 선택 대기 중인 continuation
    private var docTypeContinuations: [UUID: CheckedContinuation<DocumentType, Never>] = [:]
    /// 팀 구성 확인 대기 중인 continuation (방 ID → continuation, Set<UUID>? = 최종 선택 또는 nil)
    private var teamConfirmationContinuations: [UUID: CheckedContinuation<Set<UUID>?, Never>] = [:]
    /// 이전 사이클 완료 시점의 에이전트 수 (후속 사이클에서 에이전트 변동 감지용)
    private var previousCycleAgentCount: [UUID: Int] = [:]
    /// 멘션으로 지명된 에이전트 (라우팅 우선권 — executeQuickAnswer/executeSoloAnalysis에서 소비)
    private var mentionedAgentIDsByRoom: [UUID: [UUID]] = [:]
    /// ask_user 도구의 선택지 (방 ID → 옵션 목록) — UserInputCard에서 버튼으로 표시
    @Published var pendingQuestionOptions: [UUID: [String]] = [:]

    /// 플러그인 이벤트 디스패치 (PluginManager가 설정)
    var pluginEventDelegate: ((PluginEvent) -> Void)?

    /// 플러그인 도구 인터셉트 (PluginManager가 설정)
    var pluginInterceptToolDelegate: ((String, [String: String]) async -> ToolInterceptResult)?

    // MARK: - 계산 프로퍼티

    var activeRooms: [Room] {
        rooms.filter { $0.isActive }.sorted { $0.createdAt > $1.createdAt }
    }

    var completedRooms: [Room] {
        rooms.filter { !$0.isActive }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var selectedRoom: Room? {
        guard let id = selectedRoomID else { return nil }
        return rooms.first { $0.id == id }
    }

    /// 마스터 에이전트(진행자) 이름 — 시스템 메시지에 사용
    private var masterAgentName: String {
        agentStore?.masterAgent?.name ?? "DOUGLAS"
    }

    // MARK: - 초기화

    func configure(agentStore: AgentStore, providerManager: ProviderManager) {
        self.agentStore = agentStore
        self.providerManager = providerManager
        startTimerRefresh()
    }

    // MARK: - 방 생성

    /// 마스터 위임 또는 사용자가 방 생성
    @discardableResult
    func createRoom(title: String, agentIDs: [UUID], createdBy: RoomCreator, mode: RoomMode = .task, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil) -> Room {
        var room = Room(
            title: title,
            assignedAgentIDs: agentIDs,
            createdBy: createdBy,
            mode: mode,
            projectPaths: projectPaths,
            buildCommand: buildCommand,
            testCommand: testCommand
        )
        room.intent = intent
        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        pluginEventDelegate?(.roomCreated(roomID: room.id, title: room.title))
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작. 생성된 roomID 반환.
    @discardableResult
    func createManualRoom(title: String, agentIDs: [UUID], task: String, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil) -> UUID {
        // 마스터를 첫 번째로 배치 (intake/clarify는 항상 마스터가 수행)
        var orderedIDs = agentIDs
        if let masterID = agentStore?.masterAgent?.id {
            orderedIDs.removeAll { $0 == masterID }
            orderedIDs.insert(masterID, at: 0)
        }
        let room = createRoom(title: title, agentIDs: orderedIDs, createdBy: .user, projectPaths: projectPaths, buildCommand: buildCommand, testCommand: testCommand, intent: intent)

        // 사용자 메시지 추가
        let userMsg = ChatMessage(role: .user, content: task)
        appendMessage(userMsg, to: room.id)

        // 워크플로우 시작 (추적 가능)
        launchWorkflow(roomID: room.id, task: task)
        return room.id
    }

    /// 워크플로우를 추적 가능한 Task로 시작
    func launchWorkflow(roomID: UUID, task: String) {
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task {
            await startRoomWorkflow(roomID: roomID, task: task)
            roomTasks.removeValue(forKey: roomID)
        }
    }

    // MARK: - 방에 메시지 추가

    func appendMessage(_ message: ChatMessage, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].messages.append(message)
        scheduleSave()
        pluginEventDelegate?(.messageAdded(roomID: roomID, message: message))
    }

    /// 스트리밍: 기존 메시지 content를 in-place로 업데이트
    func updateMessageContent(_ messageID: UUID, newContent: String, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let msgIdx = rooms[roomIdx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        rooms[roomIdx].messages[msgIdx].content = newContent
    }

    // MARK: - Phase Activity Tracking

    /// LLM 호출을 ProgressActivityBubble로 추적하는 헬퍼.
    /// .progress 부모 + llm_call 시작 + body 실행 + llm_result/llm_error 완료.
    @discardableResult
    private func trackPhaseActivity(
        roomID: UUID,
        label: String,
        agentName: String?,
        modelName: String,
        providerName: String,
        body: @escaping (_ onToolActivity: @escaping (String, ToolActivityDetail?) -> Void) async throws -> String
    ) async throws -> (response: String, progressGroupID: UUID) {
        let progressMsg = ChatMessage(
            role: .system,
            content: label,
            messageType: .progress
        )
        appendMessage(progressMsg, to: roomID)
        let groupID = progressMsg.id

        // 시작 활동: 모델 + 단계 정보
        let startDetail = ToolActivityDetail(
            toolName: "llm_call",
            subject: "\(providerName) · \(modelName)",
            contentPreview: nil,
            isError: false
        )
        let startMsg = ChatMessage(
            role: .assistant,
            content: label,
            agentName: agentName,
            messageType: .toolActivity,
            activityGroupID: groupID,
            toolDetail: startDetail
        )
        appendMessage(startMsg, to: roomID)

        let onToolActivity: (String, ToolActivityDetail?) -> Void = { [weak self] activity, detail in
            guard let self else { return }
            Task { @MainActor in
                let toolMsg = ChatMessage(
                    role: .assistant,
                    content: activity,
                    agentName: agentName,
                    messageType: .toolActivity,
                    activityGroupID: groupID,
                    toolDetail: detail
                )
                self.appendMessage(toolMsg, to: roomID)
            }
        }

        let startTime = Date()
        do {
            let response = try await body(onToolActivity)
            let duration = Date().timeIntervalSince(startTime)
            let durationStr = duration < 60
                ? String(format: "%.1f초", duration)
                : String(format: "%d분 %.0f초", Int(duration) / 60, duration.truncatingRemainder(dividingBy: 60))
            let resultDetail = ToolActivityDetail(
                toolName: "llm_result",
                subject: "\(durationStr) | \(response.count)자",
                contentPreview: nil,
                isError: false
            )
            let resultActivity = ChatMessage(
                role: .assistant,
                content: "응답 완료 (\(durationStr))",
                agentName: agentName,
                messageType: .toolActivity,
                activityGroupID: groupID,
                toolDetail: resultDetail
            )
            appendMessage(resultActivity, to: roomID)
            return (response, groupID)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let durationStr = String(format: "%.1f초", duration)
            let errorDetail = ToolActivityDetail(
                toolName: "llm_error",
                subject: error.userFacingMessage,
                contentPreview: nil,
                isError: true
            )
            let errorActivity = ChatMessage(
                role: .assistant,
                content: "오류 (\(durationStr)): \(error.userFacingMessage)",
                agentName: agentName,
                messageType: .toolActivity,
                activityGroupID: groupID,
                toolDetail: errorDetail
            )
            appendMessage(errorActivity, to: roomID)
            throw error
        }
    }

    // MARK: - 승인 게이트

    /// 승인 대기 중인 단계를 승인
    func approveStep(roomID: UUID) {
        cancelReviewAutoApproval(roomID: roomID)
        let msg = ChatMessage(role: .user, content: "승인")
        appendMessage(msg, to: roomID)
        pluginEventDelegate?(.approvalResolved(roomID: roomID, approved: true))

        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: true)
        } else {
            // 워크플로우 없음 (예전 방/앱 재시작) → 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            let task = rooms[idx].title
            rooms[idx].transitionTo(.planning)
            launchWorkflow(roomID: roomID, task: task)
        }
    }

    /// 승인 대기 중인 단계를 거부 (수정 요청)
    func rejectStep(roomID: UUID) {
        cancelReviewAutoApproval(roomID: roomID)
        let msg = ChatMessage(role: .system, content: "수정 요청")
        appendMessage(msg, to: roomID)
        pluginEventDelegate?(.approvalResolved(roomID: roomID, approved: false))

        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            cont.resume(returning: false)
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

        if let cont = intentContinuations.removeValue(forKey: roomID) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            cont.resume(returning: intent)
        } else {
            // 워크플로우 없음 (앱 재시작 등) → intent 설정 후 워크플로우 재시작
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            rooms[idx].intent = intent
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

        if let cont = docTypeContinuations.removeValue(forKey: roomID) {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            cont.resume(returning: docType)
        } else {
            guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            rooms[idx].documentType = docType
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
        if let cont = teamConfirmationContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: finalIDs)
        }
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
        if let cont = teamConfirmationContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: finalIDs)
        }
        scheduleSave()
    }

    /// 취소 — 팀 구성 없이 완료
    func skipTeamConfirmation(roomID: UUID) {
        pendingTeamConfirmation.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .system, content: "팀 구성이 취소되었습니다.")
        appendMessage(msg, to: roomID)
        if let cont = teamConfirmationContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: nil)
        }
        scheduleSave()
    }

    // MARK: - 문서 파일 저장

    /// documentType이 설정된 방에서 자동 파일 저장 (NSSavePanel)
    /// - 1차: 에이전트가 실제 생성한 문서 파일이 있으면 해당 경로 링크
    /// - 2차: 메시지 콘텐츠 추출 후 MD 파일 저장
    private func offerDocumentSave(roomID: UUID) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              room.documentType != nil,
              room.status != .failed else { return }

        // 1차: 에이전트가 실제 생성한 문서 파일 확인
        if let docURL = DocumentExporter.findActualDocumentFile(from: room) {
            let doneMsg = ChatMessage(
                role: .system,
                content: "문서가 저장되었습니다\n\(docURL.lastPathComponent)\n\(docURL.path)",
                messageType: .phaseTransition,
                documentURL: docURL.absoluteString
            )
            appendMessage(doneMsg, to: roomID)
            return
        }

        // 2차: 메시지에서 콘텐츠 추출 후 MD 파일 저장
        guard let content = DocumentExporter.extractDocumentContent(from: room) else { return }

        let suggestedName = DocumentExporter.suggestedFilename(room: room)

        let savingMsg = ChatMessage(role: .system, content: "문서를 파일로 저장합니다…", messageType: .phaseTransition)
        appendMessage(savingMsg, to: roomID)

        if let url = DocumentExporter.saveDocument(content: content, suggestedName: suggestedName, defaultExtension: "md") {
            let doneMsg = ChatMessage(
                role: .system,
                content: "문서가 저장되었습니다\n\(url.lastPathComponent)\n\(url.path)",
                messageType: .phaseTransition,
                documentURL: url.absoluteString
            )
            appendMessage(doneMsg, to: roomID)
        }
    }

    // MARK: - 문서화 요청 처리

    /// 사용자의 명시적 문서화 요청 처리 (토론 히스토리 기반 문서 작성 + 자동 저장)
    private func handleDocumentOutput(roomID: UUID, task: String, suggestedType: DocumentType?) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let docType = suggestedType ?? .freeform
        rooms[idx].documentType = docType
        rooms[idx].transitionTo(.inProgress)
        rooms[idx].completedAt = nil

        let phaseMsg = ChatMessage(
            role: .system,
            content: "문서 작성을 시작합니다…",
            messageType: .phaseTransition
        )
        appendMessage(phaseMsg, to: roomID)
        scheduleSave()

        // 기존 에이전트로 토론 히스토리 기반 문서 작성
        let docMsgID = await executeDocumentWritingStep(roomID: roomID, docType: docType, task: task)

        // 자동 저장
        await offerDocumentSave(roomID: roomID)

        // 저장 성공 후 본문 메시지 숨김 (채팅에 문서 전문이 표시되는 것 방지)
        if let docMsgID,
           let i = rooms.firstIndex(where: { $0.id == roomID }),
           let mi = rooms[i].messages.firstIndex(where: { $0.id == docMsgID }) {
            rooms[i].messages[mi].messageType = .discussion
        }

        // 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed {
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
        }
        scheduleSave()
    }

    /// 토론 히스토리 기반 문서 작성 실행. 반환값: 스트리밍 메시지 ID (저장 후 숨김 용도)
    @discardableResult
    private func executeDocumentWritingStep(roomID: UUID, docType: DocumentType, task: String) async -> UUID? {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return nil }

        // 에이전트 선택: docType preferredKeywords 기반 최적 선택 → 폴백: 첫 번째 전문가 → 마스터
        let specialistIDs = executingAgentIDs(in: roomID)
        let agentID: UUID? = {
            let preferredKWs = docType.preferredKeywords
            if !preferredKWs.isEmpty {
                let candidates = specialistIDs.isEmpty ? Array(room.assignedAgentIDs) : specialistIDs
                let scored = candidates.compactMap { id -> (UUID, Int)? in
                    guard let a = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
                    let text = "\(a.name) \(a.persona)".lowercased()
                    let score = preferredKWs.filter { text.contains($0.lowercased()) }.count
                    return (id, score)
                }
                if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 {
                    return best.0
                }
            }
            return specialistIDs.first ?? room.assignedAgentIDs.first
        }()
        guard let id = agentID,
              let agent = agentStore?.agents.first(where: { $0.id == id }),
              let provider = providerManager?.provider(named: agent.providerName) else { return nil }

        speakingAgentIDByRoom[roomID] = id

        let templateBlock = docType != .freeform ? "\n" + docType.templatePromptBlock() : ""
        let history = buildRoomHistory(roomID: roomID)

        let docPrompt = """
        \(agent.resolvedSystemPrompt)

        이전 대화와 분석 내용을 바탕으로 문서를 작성합니다.
        \(templateBlock)

        [작업]
        \(task)

        [중요 — 문서 작성 지침]
        이전 대화의 분석·요약은 참고 자료일 뿐입니다.
        완전한 문서를 처음부터 끝까지 빠짐없이 작성하세요.
        "이미 완성되었습니다", "추가 작업이 필요하신가요?" 등의 응답은 금지합니다.
        반드시 전체 문서 본문을 출력하세요.
        """

        let msgID = UUID()
        do {
            let placeholder = ChatMessage(id: msgID, role: .assistant, content: "", agentName: agent.name)
            appendMessage(placeholder, to: roomID)

            _ = try await provider.sendMessageStreaming(
                model: agent.modelName,
                systemPrompt: docPrompt,
                messages: history.map { (role: $0.role, content: $0.content ?? "") }
            ) { [weak self] chunk in
                Task { @MainActor in
                    guard let self else { return }
                    if let i = self.rooms.firstIndex(where: { $0.id == roomID }),
                       let mi = self.rooms[i].messages.lastIndex(where: { $0.id == msgID }) {
                        self.rooms[i].messages[mi].content += chunk
                    }
                }
            }
        } catch {
            let errMsg = ChatMessage(role: .system, content: "문서 작성 중 오류: \(error.localizedDescription)", messageType: .error)
            appendMessage(errMsg, to: roomID)
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
        return msgID
    }

    // MARK: - clarify 후 문서 신호 재감지

    /// 사용자 피드백 메시지에서 문서 출력 신호 감지 (clarify 이후 실행)
    private func detectDocumentSignalFromMessages(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              !rooms[idx].autoDocOutput else { return }

        let recentUserMessages = rooms[idx].messages
            .filter { $0.role == .user }
            .suffix(3)
            .map { $0.content }
            .joined(separator: " ")

        if let docResult = DocumentRequestDetector.quickDetect(recentUserMessages),
           docResult.isDocumentRequest {
            rooms[idx].autoDocOutput = true
            rooms[idx].documentType = docResult.suggestedDocType ?? .freeform
        }
    }

    // MARK: - 사용자 입력 게이트

    /// ask_user 도구에 대한 사용자 답변 제출
    func answerUserQuestion(roomID: UUID, answer: String) {
        pendingQuestionOptions.removeValue(forKey: roomID)
        let msg = ChatMessage(role: .user, content: answer)
        appendMessage(msg, to: roomID)
        // userAnswers에 저장 (질문은 메시지에서 역추적)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            let userAnswer = UserAnswer(question: "", answer: answer)
            if rooms[idx].userAnswers == nil { rooms[idx].userAnswers = [] }
            rooms[idx].userAnswers?.append(userAnswer)
        }

        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: answer)
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
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
    }

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID, attachments: [FileAttachment]? = nil) async {
        // @멘션 파싱: 에이전트 초대 + 순수 텍스트 분리
        let allSubAgents = agentStore?.subAgents ?? []
        let parsed = MentionParser.parse(text, agents: allSubAgents)
        for agent in parsed.mentions {
            addAgent(agent.id, to: roomID)
        }
        // 멘션 에이전트 → 라우팅 우선권 저장 (executeQuickAnswer/executeSoloAnalysis에서 소비)
        if !parsed.mentions.isEmpty {
            mentionedAgentIDsByRoom[roomID] = parsed.mentions.map(\.id)
        }
        let cleanText = parsed.cleanText

        let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMsg, to: roomID)

        guard let room = rooms.first(where: { $0.id == roomID }) else { return }

        // 작업 진행 중: 워크플로우를 취소하지 않음 (승인 대기·입력 대기·실행 중 모두 포함)
        if room.isActive {
            let userText = cleanText.isEmpty ? text : cleanText
            if let cont = userInputContinuations.removeValue(forKey: roomID) {
                // 입력 대기 중이면 사용자 텍스트를 답변으로 전달
                cont.resume(returning: userText)
            }
            scheduleSave()
            return
        }

        // 완료/실패 → 새 후속 사이클 시작
        let task = cleanText.isEmpty ? text : cleanText
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task {
            await launchFollowUpCycle(roomID: roomID, task: task)
            roomTasks.removeValue(forKey: roomID)
        }
    }

    /// 후속 사이클: 완료/실패 방에서 후속 질문 시 assemble부터 경량 워크플로우 재실행
    private func launchFollowUpCycle(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 즉시 타이핑 인디케이터 표시 (사용자에게 "반응 중" 피드백)
        if let firstAgentID = rooms[idx].assignedAgentIDs.first {
            speakingAgentIDByRoom[roomID] = firstAgentID
        }

        // 이전 사이클 문서 플래그 리셋
        rooms[idx].autoDocOutput = false
        rooms[idx].documentType = nil

        // 문서 요청 감지 → 플래그만 설정 (숏컷 제거 — assemble 경유로 적합 에이전트 판단)
        var detectedDocType: DocumentType? = nil
        if let docResult = DocumentRequestDetector.quickDetect(task), docResult.isDocumentRequest {
            detectedDocType = docResult.suggestedDocType ?? .freeform
        } else if task.count >= 8,
           let firstAgentID = rooms[idx].assignedAgentIDs.first,
           let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
           let provider = providerManager?.provider(named: agent.providerName) {
            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let llmResult = await DocumentRequestDetector.detectWithLLM(
                text: task, provider: provider, model: lightModel
            )
            if llmResult.isDocumentRequest {
                detectedDocType = llmResult.suggestedDocType ?? .freeform
            }
        }

        if let docType = detectedDocType {
            rooms[idx].documentType = docType
            rooms[idx].autoDocOutput = true
        }

        // 타이핑 인디케이터 해제 (이후 각 phase에서 개별 설정)
        speakingAgentIDByRoom.removeValue(forKey: roomID)

        // 이전 작업 컨텍스트는 LLM에 직접 전달 (executeFollowUpAgentTurn에서 workLog 주입)
        // UI에는 표시하지 않음

        // 방 재활성화
        rooms[idx].transitionTo(.planning)
        rooms[idx].completedAt = nil

        // Intent 재분류 (후속 사이클 특화)
        // 짧은 후속 메시지(< 60자)는 즉답으로 처리 (기존 컨텍스트 내 빠른 액션)
        let ruleBasedIntent = IntentClassifier.quickClassify(task)
        var resolvedIntent = ruleBasedIntent
        if resolvedIntent == nil {
            if task.count < 60 {
                // 후속 짧은 메시지: LLM 분류 없이 quickAnswer (pr해, 커밋해, 수정해줘 등)
                resolvedIntent = .quickAnswer
            } else if let firstAgentID = rooms[idx].assignedAgentIDs.first,
               let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
               let provider = providerManager?.provider(named: agent.providerName) {
                let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
                resolvedIntent = await IntentClassifier.classifyWithLLM(
                    task: task, provider: provider, model: lightModel
                )
            }
        }
        rooms[idx].intent = resolvedIntent ?? .quickAnswer

        syncAgentStatuses()

        // 후속 사이클 스킵 범위 결정:
        // - quickAnswer + 에이전트 변동 없음 + 문서 요청 아님 → assemble 스킵
        // - 문서 요청 → clarify 스킵 (의도 명확) + assemble 실행 (적합 에이전트 확인)
        var completedPhases: Set<WorkflowPhase> = [.intake, .intent]
        let specialists = executingAgentIDs(in: roomID)
        let previousAgentCount = previousCycleAgentCount[roomID] ?? specialists.count
        let agentsChanged = specialists.count != previousAgentCount
        let hasDocRequest = detectedDocType != nil
        if !specialists.isEmpty && !agentsChanged &&
           (resolvedIntent == .quickAnswer || hasDocRequest) {
            completedPhases.insert(.assemble)
        }
        // 문서 후속 요청: clarify 불필요 (사용자 의도가 명확함)
        if hasDocRequest {
            completedPhases.insert(.clarify)
        }
        // Room에 동기화
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].completedPhases = completedPhases
        }
        // 현재 에이전트 수 기록 (다음 후속 사이클 비교용)
        previousCycleAgentCount[roomID] = specialists.count

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive,
                  let currentIntent = currentRoom.intent else { break }

            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = nextPhase
            }
            scheduleSave()

            switch nextPhase {
            case .intake, .intent:
                break
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: task)
            case .understand:
                await executeUnderstandPhase(roomID: roomID, task: task)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: task)
            case .design:
                await executeDesignPhase(roomID: roomID, task: task)
            case .plan:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: task, intent: intent)
            case .build:
                await executeBuildPhase(roomID: roomID, task: task)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            case .review:
                await executeReviewPhase(roomID: roomID, task: task)
            case .deliver:
                await executeDeliverPhase(roomID: roomID, task: task)
            }

            completedPhases.insert(nextPhase)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].completedPhases = completedPhases
            }
        }

        // 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed && rooms[i].status != .completed {
            rooms[i].currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
        scheduleSave()

        // 작업일지 + 플레이북 감지 (완료 후 비동기)
        // 전문가 없이 취소된 경우 스킵 (실질적 작업 없음)
        let hasSpecialists1 = !executingAgentIDs(in: roomID).isEmpty
        if hasSpecialists1, let room = rooms.first(where: { $0.id == roomID }), room.workLog == nil {
            await generateWorkLog(roomID: roomID, task: task)
        }
        if hasSpecialists1 { detectPlaybookOverrides(roomID: roomID) }
    }

    // MARK: - 카테고리 기반 모델 오버라이드


    // MARK: - 도구 실행 컨텍스트

    private func makeToolContext(
        roomID: UUID,
        currentAgentID: UUID? = nil,
        fileWriteTracker: FileWriteTracker? = nil,
        deferHighRiskTools: Bool = false,
        collectDeferred: ((DeferredAction) -> Void)? = nil
    ) -> ToolExecutionContext {
        guard let store = agentStore else { return .empty }
        let subAgents = store.subAgents
        let room = rooms.first { $0.id == roomID }
        let currentAgent = currentAgentID.flatMap { id in
            store.agents.first { $0.id == id }
        }
        let currentAgentName = currentAgent?.name
        return ToolExecutionContext(
            roomID: roomID,
            agentsByName: Dictionary(uniqueKeysWithValues: subAgents.map { ($0.name, $0.id) }),
            agentListString: subAgents
                .map { "- \($0.name) [\($0.providerName)/\($0.modelName)]" }
                .joined(separator: "\n"),
            inviteAgent: { @Sendable [weak self] (agentID: UUID) -> Bool in
                await MainActor.run { [weak self] in
                    self?.addAgent(agentID, to: roomID)
                    return true
                }
            },
            suggestAgentCreation: { @Sendable [weak self] (suggestion: RoomAgentSuggestion) -> Bool in
                await MainActor.run { [weak self] in
                    self?.addAgentSuggestion(suggestion, to: roomID)
                    return true
                }
            },
            projectPaths: room?.projectPaths ?? [],
            currentAgentID: currentAgentID,
            currentAgentName: currentAgentName,
            agentPermissions: currentAgent?.actionPermissions ?? [],
            fileWriteTracker: fileWriteTracker,
            askUser: { @Sendable [weak self] (question: String, context: String?, options: [String]?) -> String in
                // 1) 질문 메시지 추가 + 상태 전이 (MainActor)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var content = question
                    if let ctx = context { content += "\n\n배경: \(ctx)" }
                    // 선택지는 메시지에 텍스트로 넣지 않고 UI 버튼으로 표시
                    if let opts = options, !opts.isEmpty {
                        self.pendingQuestionOptions[roomID] = opts
                    } else {
                        self.pendingQuestionOptions.removeValue(forKey: roomID)
                    }
                    let msg = ChatMessage(role: .assistant, content: content, agentName: currentAgentName, messageType: .userQuestion)
                    self.appendMessage(msg, to: roomID)
                    if let idx = self.rooms.firstIndex(where: { $0.id == roomID }) {
                        self.rooms[idx].transitionTo(.awaitingUserInput)
                    }
                    self.scheduleSave()
                }
                // 2) 사용자 답변 대기 (continuation)
                let answer: String = await withCheckedContinuation { continuation in
                    Task { @MainActor [weak self] in
                        self?.userInputContinuations[roomID] = continuation
                    }
                }
                // 3) 상태 복귀 (MainActor)
                await MainActor.run { [weak self] in
                    if let self, let idx = self.rooms.firstIndex(where: { $0.id == roomID }) {
                        self.rooms[idx].transitionTo(.planning)
                    }
                }
                return answer
            },
            currentPhase: room?.currentPhase,
            deferHighRiskTools: deferHighRiskTools,
            collectDeferred: collectDeferred.map { callback in
                { @Sendable deferred in callback(deferred) }
            } ?? { _ in },
            dispatchPluginEvent: { @Sendable [weak self] event in
                Task { @MainActor [weak self] in
                    self?.pluginEventDelegate?(event)
                }
            },
            interceptTool: { @Sendable [weak self] toolName, arguments in
                guard let delegate = await MainActor.run(body: { self?.pluginInterceptToolDelegate }) else {
                    return .passthrough
                }
                return await delegate(toolName, arguments)
            }
        )
    }

    // MARK: - 에이전트 생성 제안 관리

    /// 방에 에이전트 생성 제안 추가
    func addAgentSuggestion(_ suggestion: RoomAgentSuggestion, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].pendingAgentSuggestions.append(suggestion)

        let msg = ChatMessage(
            role: .system,
            content: "\(suggestion.suggestedBy)\(subjectParticle(for: suggestion.suggestedBy)) '\(suggestion.name)' 에이전트 생성을 제안했습니다.\(suggestion.reason.isEmpty ? "" : " 사유: \(suggestion.reason)")",
            messageType: .suggestion
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
    }

    /// 에이전트 생성 제안 승인 → 에이전트 생성 + 방에 초대
    func approveAgentSuggestion(suggestionID: UUID, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let sugIdx = rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }

        var suggestion = rooms[roomIdx].pendingAgentSuggestions[sugIdx]
        suggestion.status = .approved
        rooms[roomIdx].pendingAgentSuggestions[sugIdx] = suggestion

        // 에이전트 생성
        let providerName = suggestion.recommendedProvider ?? "Anthropic"
        let modelName = suggestion.recommendedModel ?? "claude-sonnet-4-20250514"

        let newAgent = Agent(
            name: suggestion.name,
            persona: suggestion.persona,
            providerName: providerName,
            modelName: modelName
        )
        agentStore?.addAgent(newAgent)
        addAgent(newAgent.id, to: roomID, silent: true)

        let msg = ChatMessage(
            role: .system,
            content: "'\(suggestion.name)' 에이전트가 생성되어 방에 참여했습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
        resumeSuggestionContinuationIfResolved(roomID: roomID)
    }

    /// 에이전트 생성 제안 거부
    func rejectAgentSuggestion(suggestionID: UUID, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let sugIdx = rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }

        rooms[roomIdx].pendingAgentSuggestions[sugIdx].status = .rejected

        let name = rooms[roomIdx].pendingAgentSuggestions[sugIdx].name
        let msg = ChatMessage(
            role: .system,
            content: "'\(name)' 에이전트 생성이 취소되었습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
        resumeSuggestionContinuationIfResolved(roomID: roomID)
    }

    /// 모든 제안이 해결되면 대기 중인 continuation 재개
    func resumeSuggestionContinuationIfResolved(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let hasPending = room.pendingAgentSuggestions.contains { $0.status == .pending }
        if !hasPending, let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: true)
        }
    }

    /// 제안 응답 대기 — 사용자가 추가/건너뛰기를 누를 때까지 무한 대기
    private func waitForSuggestionResponse(roomID: UUID) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              room.pendingAgentSuggestions.contains(where: { $0.status == .pending }) else {
            return
        }

        let _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.suggestionContinuations[roomID] = cont
        }
    }

    /// 에이전트 제안 취소 후: 기존 에이전트 피커를 표시하거나, 후보가 없으면 워크플로우 완료
    /// 팀 구성 확인 게이트: 자동 매칭된 에이전트를 사용자에게 확인받거나 변경 허용
    private func showTeamConfirmation(roomID: UUID) async {
        let subAgents = agentStore?.subAgents ?? []
        let roomAgentIDs = rooms.first(where: { $0.id == roomID })?.assignedAgentIDs ?? []
        let specialists = executingAgentIDs(in: roomID)
        let candidates = subAgents.filter { !roomAgentIDs.contains($0.id) }.map(\.id)

        // 에이전트도 없고 후보도 없으면 → 워크플로우 완료
        if specialists.isEmpty && candidates.isEmpty {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = nil
                rooms[i].status = .completed
                rooms[i].completedAt = Date()
            }
            syncAgentStatuses()
            scheduleSave()
            return
        }

        // 팀 확인 카드 표시 → 사용자 응답 대기
        pendingTeamConfirmation[roomID] = TeamConfirmationState(
            selectedAgentIDs: Set(specialists),
            candidateAgentIDs: candidates
        )

        let result = await withCheckedContinuation { (cont: CheckedContinuation<Set<UUID>?, Never>) in
            self.teamConfirmationContinuations[roomID] = cont
        }

        // nil → 건너뛰기
        guard let finalIDs = result else {
            if executingAgentIDs(in: roomID).isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].currentPhase = nil
                    rooms[i].status = .completed
                    rooms[i].completedAt = Date()
                }
                syncAgentStatuses()
                scheduleSave()
            }
            return
        }

        // 차이 적용: 제거할 에이전트 / 추가할 에이전트
        let currentSpecialists = Set(executingAgentIDs(in: roomID))
        let toRemove = currentSpecialists.subtracting(finalIDs)
        let toAdd = finalIDs.subtracting(currentSpecialists)

        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            for agentID in toRemove {
                rooms[idx].assignedAgentIDs.removeAll(where: { $0 == agentID })
            }
        }
        for agentID in toAdd {
            addAgent(agentID, to: roomID, silent: true)
        }

        // 최종 팀 확정 메시지 (RuntimeRole 포함)
        let masterName = agentStore?.masterAgent?.name ?? "DOUGLAS"
        let room = rooms.first(where: { $0.id == roomID })
        let finalDescs = executingAgentIDs(in: roomID).compactMap { id -> String? in
            guard let name = agentStore?.agents.first(where: { $0.id == id })?.name else { return nil }
            if let role = room?.agentRoles[name] {
                return "\(name)(\(role.displayName))"
            }
            return name
        }
        if !finalDescs.isEmpty {
            let msg = ChatMessage(
                role: .system,
                content: "팀 구성 확정: \(finalDescs.joined(separator: ", "))",
                agentName: masterName
            )
            appendMessage(msg, to: roomID)
        }

        // 최종적으로 에이전트 없으면 완료
        if executingAgentIDs(in: roomID).isEmpty {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = nil
                rooms[i].status = .completed
                rooms[i].completedAt = Date()
            }
            syncAgentStatuses()
            scheduleSave()
        }
    }

    // MARK: - 방에 에이전트 추가

    func addAgent(_ agentID: UUID, to roomID: UUID, silent: Bool = false) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        guard !rooms[idx].assignedAgentIDs.contains(agentID) else { return }
        rooms[idx].assignedAgentIDs.append(agentID)

        // 에이전트의 참조 프로젝트를 방에 병합
        if let agent = agentStore?.agents.first(where: { $0.id == agentID }) {
            for path in agent.referenceProjectPaths {
                if !rooms[idx].projectPaths.contains(path) {
                    rooms[idx].projectPaths.append(path)
                }
            }
        }

        syncAgentStatuses()
        scheduleSave()

        let agentName = agentStore?.agents.first(where: { $0.id == agentID })?.name
        if !silent, let agentName {
            let systemMsg = ChatMessage(role: .system, content: "\(agentName)\(subjectParticle(for: agentName)) 방에 참여했습니다.")
            appendMessage(systemMsg, to: roomID)
        }

        // 플러그인 이벤트
        if let agentName {
            pluginEventDelegate?(.agentInvited(roomID: roomID, agentName: agentName))
        }
    }

    // MARK: - 방 워크플로우

    /// 워크플로우 진입점: 항상 Intent 기반 Phase 워크플로우
    func startRoomWorkflow(roomID: UUID, task: String) async {
        // intent 미설정 → quickClassify 시도 (nil이면 executeIntentPhase에서 사용자 선택)
        if let idx = rooms.firstIndex(where: { $0.id == roomID }), rooms[idx].intent == nil {
            rooms[idx].intent = IntentClassifier.quickClassify(task)
            // quickClassify 실패 시 nil 유지 → executeIntentPhase에서 처리
        }
        await executePhaseWorkflow(roomID: roomID, task: task)
    }

    // legacyStartRoomWorkflow 삭제됨 — 모든 워크플로우는 executePhaseWorkflow를 통해 Intent 기반으로 실행

    /// 실행 대상 에이전트 (마스터 제외)
    private func executingAgentIDs(in roomID: UUID) -> [UUID] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.assignedAgentIDs.filter { id in
            let agent = agentStore?.agents.first(where: { $0.id == id })
            return !(agent?.isMaster ?? false)
        }
    }

    // MARK: - Phase 워크플로우 (새 7단계)

    /// 새 워크플로우: intent.requiredPhases 동적 순회
    /// intent 단계에서 LLM 재분류 후 남은 단계가 자동으로 재계산됨
    /// 워크플로우 전체 타임아웃 (초)
    private static let workflowTimeoutSeconds: TimeInterval = 600 // 10분

    private func executePhaseWorkflow(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        rooms[idx].status = .planning
        syncAgentStatuses()

        var workflowStart = Date()
        var completedPhases: Set<WorkflowPhase> = []
        // 파일만 업로드된 경우 understand 단계에서 사용자 입력으로 task가 갱신됨
        var resolvedTask = task

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive else { break }

            // 타임아웃 체크
            if Date().timeIntervalSince(workflowStart) > Self.workflowTimeoutSeconds {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let timeoutMsg = ChatMessage(
                    role: .system,
                    content: "워크플로우가 제한 시간(10분)을 초과하여 자동 종료되었습니다.",
                    messageType: .error
                )
                appendMessage(timeoutMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            let currentIntent = currentRoom.intent ?? .quickAnswer
            // 현재 intent 기준으로 다음 미완료 phase 찾기
            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            // 현재 단계 기록 (내부 상태만, UI 메시지 없음)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentPhase = nextPhase
            }
            scheduleSave()

            switch nextPhase {
            case .intake:
                await executeIntakePhase(roomID: roomID, task: resolvedTask)
            case .intent:
                await executeIntentPhase(roomID: roomID, task: resolvedTask)
            case .clarify:
                await executeClarifyPhase(roomID: roomID, task: resolvedTask)
                // clarify 후 문서 요청 재감지 (사용자 피드백에 문서 신호 있을 수 있음)
                detectDocumentSignalFromMessages(roomID: roomID)
            case .assemble:
                await executeAssemblePhase(roomID: roomID, task: resolvedTask)

                // assemble 완료 후: task intent이면 needsPlan 동적 판단
                if let currentRoom2 = rooms.first(where: { $0.id == roomID }),
                   currentRoom2.intent == .task {
                    let planNeeded = await classifyNeedsPlan(roomID: roomID, task: resolvedTask)
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].needsPlan = planNeeded
                    }
                    scheduleSave()

                    if planNeeded {
                        // 동적으로 plan 단계 실행
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].currentPhase = .plan
                        }
                        scheduleSave()
                        let planIntent = rooms.first(where: { $0.id == roomID })?.intent ?? .task
                        await executePlanPhase(roomID: roomID, task: resolvedTask, intent: planIntent)
                        completedPhases.insert(.plan)
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].completedPhases = completedPhases
                        }
                        workflowStart = Date()
                    }
                }
            case .plan:
                // requiredPhases에 .plan이 없으므로 여기에 오지 않음 (안전장치)
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: resolvedTask, intent: intent)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: resolvedTask, intent: intent)
            case .understand:
                // Plan C: Understand 통합 단계 — intake+intent+clarify+TaskBrief
                await executeUnderstandPhase(roomID: roomID, task: resolvedTask)
                // understand 후 사용자가 입력한 실제 task로 갱신 (파일만 업로드 등)
                if resolvedTask.isEmpty, let room = rooms.first(where: { $0.id == roomID }) {
                    resolvedTask = room.taskBrief?.goal ?? room.title
                }
                detectDocumentSignalFromMessages(roomID: roomID)
            case .design:
                // Plan C: 3턴 고정 프로토콜 (Propose → Critique → Revise)
                await executeDesignPhase(roomID: roomID, task: resolvedTask)
            case .build:
                // Plan C: Creator 단계별 실행 (riskLevel별 정책)
                await executeBuildPhase(roomID: roomID, task: resolvedTask)
            case .review:
                // Plan C: Reviewer 검토
                await executeReviewPhase(roomID: roomID, task: resolvedTask)
            case .deliver:
                // Plan C: 최종 전달 (high = Draft 프리뷰 + 명시 승인)
                await executeDeliverPhase(roomID: roomID, task: resolvedTask)
            }

            completedPhases.insert(nextPhase)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].completedPhases = completedPhases
            }
            workflowStart = Date() // 단계 완료 후 타이머 리셋 (사용자 대기 시간으로 인한 타임아웃 방지)
        }

        // 워크플로우 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed {
            rooms[i].currentPhase = nil
            rooms[i].status = .completed
            rooms[i].completedAt = Date()
            pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
        }
        syncAgentStatuses()
        scheduleSave()

        // 작업일지 + 플레이북 감지 (완료 후 비동기)
        // 전문가 없이 취소된 경우 스킵 (실질적 작업 없음)
        let hasSpecialists2 = !executingAgentIDs(in: roomID).isEmpty
        if hasSpecialists2, let room = rooms.first(where: { $0.id == roomID }), room.workLog == nil {
            // 완료 상태 확정 후 fire-and-forget (UI 지연 방지)
            Task { [weak self] in
                await self?.generateWorkLog(roomID: roomID, task: task)
            }
        }
        if hasSpecialists2 { detectPlaybookOverrides(roomID: roomID) }
    }

    /// Intent 단계: quickClassify 결과에 따라 LLM 재분류 또는 사용자 선택
    private func executeIntentPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let currentIntent = rooms[idx].intent

        // 1) quickClassify가 nil → LLM 추천 후 사용자에게 선택 카드 표시
        if currentIntent == nil {
            guard let firstAgentID = rooms[idx].assignedAgentIDs.first,
                  let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
                  let provider = providerManager?.provider(named: agent.providerName) else {
                rooms[idx].intent = .task
                return
            }

            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let suggested = await IntentClassifier.classifyWithLLM(
                task: task,
                provider: provider,
                model: lightModel
            )

            // 사용자 선택 UI 표시
            pendingIntentSelection[roomID] = suggested

            let selectedIntent = await withCheckedContinuation { (cont: CheckedContinuation<WorkflowIntent, Never>) in
                intentContinuations[roomID] = cont
            }

            rooms[idx].intent = selectedIntent
            scheduleSave()
        } else {
            // quickClassify가 결과를 반환한 경우 (quickAnswer 또는 task) — 그대로 사용
        }

        // 초기 메시지에서 문서 요청 감지 → autoDocOutput 플래그 설정
        if let resolvedIdx = rooms.firstIndex(where: { $0.id == roomID }) {
            let currentTask = task
            if let docResult = DocumentRequestDetector.quickDetect(currentTask), docResult.isDocumentRequest {
                rooms[resolvedIdx].autoDocOutput = true
                rooms[resolvedIdx].documentType = docResult.suggestedDocType ?? .freeform
            }
        }
    }

    /// Intent 확정 후 사용자에게 워크플로우 설명 메시지 표시
    private func postIntentExplanation(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let intent = room.intent else { return }

        let msg = ChatMessage(
            role: .system,
            content: "[\(intent.displayName)] \(intent.subtitle)\n진행: \(intent.phaseSummary)",
            messageType: .phaseTransition
        )
        appendMessage(msg, to: roomID)
    }

    /// clarify 완료 후 동적으로 실행 계획 필요 여부 판별
    /// 1단계: 키워드 기반 즉시 판별 (확실한 경우)
    /// 2단계: LLM 폴백 (애매한 경우만)
    private func classifyNeedsPlan(roomID: UUID, task: String) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            return false
        }

        let clarifySummary = room.clarifySummary ?? task

        // 1단계: 키워드 기반 즉시 판별
        if let keywordResult = classifyNeedsPlanByKeywords(clarifySummary: clarifySummary, task: task) {
            return keywordResult
        }

        // 2단계: 애매한 경우 LLM 폴백
        let assignedAgents = room.assignedAgentIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }.joined(separator: ", ")

        let systemPrompt = """
        사용자의 작업 요청을 보고, **실행 계획(plan)**이 필요한지 판별하세요.

        계획이 **필요한** 경우:
        - 코드 생성 또는 수정 (쿼리 변경, 함수 구현, 버그 수정 포함)
        - 여러 단계를 순차적으로 실행해야 하는 작업
        - 파일시스템 변경 (파일 생성/수정/삭제)
        - 빌드, 배포, 테스트 실행

        계획이 **불필요한** 경우:
        - 분석/리서치 (결과를 정리하여 보여주면 끝)
        - 브레인스토밍/토론
        - 문서 작성 (단일 출력물)
        - 상담/자문
        - 요약/변환

        YES 또는 NO만 출력하세요.
        """

        let userMessage = """
        [작업 요약]
        \(clarifySummary)

        [참여 에이전트]
        \(assignedAgents)

        [원본 작업]
        \(task)
        """

        let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName

        do {
            let response = try await provider.sendMessage(
                model: lightModel,
                systemPrompt: systemPrompt,
                messages: [("user", userMessage)]
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return trimmed.hasPrefix("YES")
        } catch {
            return false
        }
    }

    /// 키워드 기반 needsPlan 즉시 판별. 확실하면 Bool 반환, 애매하면 nil
    private func classifyNeedsPlanByKeywords(clarifySummary: String, task: String) -> Bool? {
        let text = "\(clarifySummary) \(task)".lowercased()

        // 구현/수정 계열 키워드 (가중치)
        let planKeywords: [(String, Int)] = [
            // 코드 수정/생성
            ("수정", 3), ("구현", 4), ("코딩", 5), ("coding", 5),
            ("fix", 5), ("implement", 4), ("리팩토", 4), ("refactor", 4),
            ("버그", 5), ("bug", 5),
            // 빌드/배포
            ("빌드", 4), ("build", 4), ("배포", 4), ("deploy", 4),
            // 파일 변경
            ("마이그레이션", 4), ("migration", 4),
            // 코드 관련 신호
            ("코드", 3), ("쿼리", 3), ("query", 3),
            ("서브쿼리", 4), ("subquery", 4),
            ("인덱스", 3), ("index", 3),
            ("from절", 4), ("where절", 4), ("join", 3),
            ("커밋", 3), ("commit", 3), ("pr", 2), ("push", 2),
            ("개선", 2), ("변경", 2),
        ]

        // 분석/리서치 계열 키워드
        let noPlanKeywords: [(String, Int)] = [
            ("리서치", 3), ("research", 3),
            ("요약", 3), ("summarize", 3), ("summary", 3),
            ("설명", 3), ("번역", 4), ("translate", 4),
            ("자문", 3), ("상담", 3), ("의견", 3),
            ("브레인스토밍", 4), ("brainstorm", 4),
        ]

        var planScore = 0
        var noPlanScore = 0

        for (keyword, weight) in planKeywords {
            if text.contains(keyword) { planScore += weight }
        }
        for (keyword, weight) in noPlanKeywords {
            if text.contains(keyword) { noPlanScore += weight }
        }

        // 확실한 구현 작업
        if planScore >= 5 { return true }
        // 확실한 분석 작업 (구현 신호 미약)
        if noPlanScore >= 5 && planScore < 3 { return false }
        // 애매 → LLM 폴백
        return nil
    }

    /// Intake 단계: 입력 파싱, Jira fetch, IntakeData 저장, 플레이북 로드
    private func executeIntakePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        // 1) URL 감지
        let urls = extractURLs(from: task)

        // 2) Jira URL 감지 + fetch
        let jiraConfig = JiraConfig.shared
        var sourceType: InputSourceType = .text
        var jiraKeys: [String] = []
        var jiraDataList: [JiraTicketSummary] = []

        // 개별 URL 단위로 Jira 판별 (전체 텍스트가 아닌 추출된 URL 사용)
        let jiraURLs = urls.filter { jiraConfig.isJiraURL($0) }

        if jiraConfig.isConfigured, !jiraURLs.isEmpty {
            sourceType = .jira
            // 모든 Jira 키 추출 (PROJ-123 패턴, 중복 제거)
            jiraKeys = extractJiraKeys(from: task)
            // 각 Jira URL에서 티켓 요약 fetch (최대 10건)
            jiraDataList = await fetchJiraTicketSummaries(urls: Array(jiraURLs.prefix(10)))
        } else if !urls.isEmpty {
            sourceType = .url
        }

        // 3) IntakeData 저장
        let intakeData = IntakeData(
            sourceType: sourceType,
            rawInput: task,
            jiraKeys: jiraKeys,
            jiraDataList: jiraDataList,
            urls: urls
        )
        rooms[idx].intakeData = intakeData

        // 4) 플레이북 로드 (내부 데이터만, UI 메시지 없음)
        if let projectPath = rooms[idx].primaryProjectPath {
            if let playbook = PlaybookManager.load(from: projectPath) {
                rooms[idx].playbook = playbook
            }
        }
        scheduleSave()
    }

    /// Clarify 단계: 복명복창 — DOUGLAS가 이해한 내용을 요약하고 사용자 컨펌까지 무한 루프
    private func executeClarifyPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        speakingAgentIDByRoom[roomID] = firstAgentID

        // 컨텍스트 구성: IntakeData + 플레이북
        var contextParts: [String] = []
        if let intakeData = rooms[idx].intakeData {
            // Clarify 단계에서는 Jira/API 언급을 제거한 중립 컨텍스트 사용 (LLM 환각 방지)
            contextParts.append(intakeData.asClarifyContextString())
        }
        if let playbook = rooms[idx].playbook {
            contextParts.append(playbook.asContextString())
        }
        let contextString = contextParts.joined(separator: "\n\n")

        // 첨부 파일 정보 수집 (Clarify에서는 파일명만 참조, 실제 파일은 실행 단계에서 전달)
        let fileAttachments = rooms[idx].messages
            .compactMap { $0.attachments }
            .flatMap { $0 }

        // Clarify용 첨부 요약 (파일 데이터 없이 이름만)
        let attachmentSummary: String
        if !fileAttachments.isEmpty {
            let names = fileAttachments.map { att in
                let typeLabel = att.isImage ? "이미지" : "문서"
                return "- \(typeLabel): \(att.displayName) (\(FileAttachment.formatFileSize(att.fileSizeBytes)))"
            }.joined(separator: "\n")
            attachmentSummary = "\n\n[첨부 파일 \(fileAttachments.count)개]\n\(names)\n(파일 내용은 실행 단계에서 전문가에게 전달됩니다. 여기서는 파일 존재만 인지하세요.)"
        } else {
            attachmentSummary = ""
        }

        // 문서 유형 템플릿 주입
        let docTypeContext = rooms[idx].documentType?.templatePromptBlock() ?? ""

        // 등록된 서브 에이전트 목록 (delegation 판단용)
        let agentListStr: String
        if let subAgents = agentStore?.subAgents, !subAgents.isEmpty {
            agentListStr = subAgents.map { "- \($0.name)" }.joined(separator: "\n")
        } else {
            agentListStr = "(없음)"
        }

        // 사용자 직접 선택 방: 배정 에이전트 명시 + delegation 블록 제거
        let isUserSelectedTeam: Bool
        let teamContext: String
        if rooms[idx].createdBy == .user {
            let subAgentNames = rooms[idx].assignedAgentIDs.compactMap { id -> String? in
                guard let a = agentStore?.agents.first(where: { $0.id == id }), !a.isMaster else { return nil }
                return a.name
            }
            isUserSelectedTeam = !subAgentNames.isEmpty
            if isUserSelectedTeam {
                let names = subAgentNames.joined(separator: ", ")
                teamContext = "\n이 작업방에는 사용자가 직접 선택한 에이전트가 배정되어 있습니다: \(names)\n이 팀으로 작업을 진행합니다.\n"
            } else {
                teamContext = ""
            }
        } else {
            isUserSelectedTeam = false
            teamContext = ""
        }

        let delegationBlock: String
        if isUserSelectedTeam {
            // 에이전트가 이미 확정 → delegation 분석 불필요
            delegationBlock = ""
        } else {
            delegationBlock = """

            요약 후 반드시 아래 블록을 마지막에 추가하세요:
            [delegation]
            type: (explicit 또는 open)
            agents: (에이전트 이름을 쉼표 구분, explicit일 때만. open이면 이 줄 생략)
            [/delegation]

            - 사용자가 특정 에이전트를 지정했으면 → type: explicit, agents에 해당 이름
            - 특정 에이전트를 지정하지 않았으면 → type: open

            [등록된 에이전트]
            \(agentListStr)
            """
        }

        let clarifySystemPrompt = """
        \(agent.resolvedSystemPrompt)

        당신은 요건 확인(Clarify) 단계를 수행하고 있습니다.
        사용자의 요청을 정확히 이해했는지 복명복창(확인)만 합니다.
        \(docTypeContext.isEmpty ? "" : "\n\(docTypeContext)\n")\(teamContext)
        아래 형식으로 이해한 내용을 요약하세요:
        - 요청 내용: (1-2문장 요약)
        - 핵심 요구사항: (불릿 포인트, 각 항목 1줄 이내)
        - 예상 산출물: (무엇이 나와야 하는지)\(docTypeContext.isEmpty ? "" : "\n- 문서 구조: (선택된 템플릿 섹션 기반으로 구성할 섹션 나열)")
        \(delegationBlock)
        [절대 금지]
        - 요약\(isUserSelectedTeam ? "" : " + delegation 블록") 외의 내용을 출력하지 마세요.
        - 질문에 대한 답변, 개념 설명, 해결책을 작성하지 마세요.
        - 작업을 수행하지 마세요. 이 단계는 확인만 합니다.
        - 첨부파일(이미지, 문서)의 내용을 상세히 나열하거나 분석하지 마세요. "첨부 문서: design.md" 처럼 무엇인지만 간단히 언급하세요.
        - 번역, 계산, 코드 작성 등 실제 작업 결과물을 포함하지 마세요.
        - "1. 다음" "2. 수정" "x. 나가기" 같은 선택지/메뉴를 절대 출력하지 마세요. 사용자 선택은 UI 버튼으로 제공됩니다.
        - 시스템 도구·인증·설정 관련 언급을 하지 마세요. 필요한 데이터는 이미 수집되었습니다.
        """

        var currentSummary = ""

        // 무한 루프: 사용자가 승인할 때까지 반복
        while true {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            // 1) DOUGLAS가 이해한 내용 요약 생성 (첨부파일은 이름만 텍스트로 전달, 데이터 미전송)
            let clarifyMessages: [ConversationMessage]
            if currentSummary.isEmpty {
                let userContent = "\(contextString)\(attachmentSummary)\n\n위 요청을 분석하고, 이해한 내용을 정리해주세요. 작업: \(task)"
                clarifyMessages = [ConversationMessage.user(userContent)]
            } else {
                // 사용자 피드백 반영 재요약
                let history = buildRoomHistory(roomID: roomID)
                    .map { "\($0.role): \($0.content ?? "")" }
                    .suffix(5)
                    .joined(separator: "\n")
                let feedbackContent = "이전 요약:\n\(currentSummary)\n\n사용자 피드백:\n\(history)\n\n피드백을 반영하여 다시 요약하세요."
                clarifyMessages = [ConversationMessage.user(feedbackContent)]
            }

            do {
                // 스트리밍용 placeholder 메시지
                let placeholderID = UUID()
                let placeholder = ChatMessage(
                    id: placeholderID, role: .assistant, content: "",
                    agentName: agent.name
                )
                appendMessage(placeholder, to: roomID)

                let response: String
                if provider.supportsStreaming {
                    // 첨부 없음 → 스트리밍 경로
                    let simpleMessages = clarifyMessages.compactMap { msg -> (role: String, content: String)? in
                        guard let content = msg.content else { return nil }
                        return (role: msg.role, content: content)
                    }
                    let buffer = StreamBuffer()
                    response = try await provider.sendMessageStreaming(
                        model: agent.modelName,
                        systemPrompt: clarifySystemPrompt,
                        messages: simpleMessages,
                        onChunk: { [weak self] chunk in
                            guard let self else { return }
                            let current = buffer.append(chunk)
                            Task { @MainActor in
                                self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                            }
                        }
                    )
                } else {
                    // 이미지 있음 또는 스트리밍 미지원 → sendMessageWithTools로 이미지 보존
                    let responseContent = try await provider.sendMessageWithTools(
                        model: agent.modelName,
                        systemPrompt: clarifySystemPrompt,
                        messages: clarifyMessages,
                        tools: []
                    )
                    switch responseContent {
                    case .text(let t): response = t
                    case .mixed(let t, _): response = t
                    case .toolCalls: response = "(요약 생성 실패)"
                    }
                }
                currentSummary = stripDelegationBlock(stripHallucinatedAuthLines(stripTrailingOptions(response)))

                // 복명복창 요약에서 방 제목 자동 추출 (첫 라운드만)
                if currentSummary.isEmpty == false,
                   let i = rooms.firstIndex(where: { $0.id == roomID }),
                   rooms[i].title == "이미지 분석" || rooms[i].title == "새 작업" || rooms[i].title.count > 28 {
                    let refined = Self.extractTitleFromClarifySummary(response)
                    if !refined.isEmpty {
                        rooms[i].title = refined
                    }
                }

                // placeholder를 최종 텍스트로 업데이트 (선택지 텍스트 제거 후)
                updateMessageContent(placeholderID, newContent: currentSummary, in: roomID)
            } catch {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
                let errorMsg = ChatMessage(
                    role: .assistant,
                    content: "요건 확인 오류: \(error.userFacingMessage)",
                    agentName: agent.name,
                    messageType: .error
                )
                appendMessage(errorMsg, to: roomID)
                return
            }

            // 2) 사용자에게 컨펌 요청 (복명복창 요약 자체가 확인 요청)
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingApproval)
            }
            syncAgentStatuses()
            scheduleSave()

            let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                approvalContinuations[roomID] = continuation
            }
            approvalContinuations.removeValue(forKey: roomID)
            guard !Task.isCancelled else { return }

            if approved {
                // 승인됨 → clarify 요약 저장 + delegation 분리 + planning 복귀
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].delegationInfo = parseDelegationBlock(currentSummary)
                    rooms[i].clarifySummary = stripDelegationBlock(currentSummary)
                    rooms[i].transitionTo(.planning)
                }
                break
            }

            // 3) 거부됨 → ApprovalCard에서 이미 피드백 입력된 경우 스킵
            let hasInlineFeedback: Bool = {
                guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
                // "수정 요청" 직전 메시지가 사용자 메시지이면 인라인 피드백 있음
                guard let rejectIdx = room.messages.lastIndex(where: { $0.content == "수정 요청" && $0.role == .system }) else { return false }
                let prevIdx = rejectIdx - 1
                guard prevIdx >= 0 else { return false }
                return room.messages[prevIdx].role == .user
            }()

            if !hasInlineFeedback {
                let askMsg = ChatMessage(
                    role: .system,
                    content: "어떤 부분을 수정해야 하나요?",
                    messageType: .userQuestion
                )
                appendMessage(askMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingUserInput)
                }
                scheduleSave()

                let _ = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                    userInputContinuations[roomID] = continuation
                }
            }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }
            // 피드백 반영하여 재요약 (루프 계속)
        }
        scheduleSave()
    }

    /// 가정 산출물 텍스트에서 WorkflowAssumption 파싱
    private func parseAssumptions(from content: String) -> [WorkflowAssumption] {
        // 형식: "- [위험:낮음] 가정 내용" 또는 "- [위험:중간] 가정 내용" 등
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [위험:") else { return nil }

            var riskLevel: WorkflowAssumption.RiskLevel = .low
            if trimmed.contains("[위험:높음]") {
                riskLevel = .high
            } else if trimmed.contains("[위험:중간]") {
                riskLevel = .medium
            }

            // 텍스트 추출: "] " 이후
            guard let bracketEnd = trimmed.range(of: "] ") else { return nil }
            let text = String(trimmed[bracketEnd.upperBound...])
            guard !text.isEmpty else { return nil }

            return WorkflowAssumption(text: text, riskLevel: riskLevel)
        }
    }

    /// Assemble 단계: 마스터 역할 산출 → 시스템 매칭/초대 → 커버리지 게이트
    private func executeAssemblePhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        // 사용자가 직접 에이전트를 선택한 방 → assemble 스킵
        if rooms[idx].createdBy == .user {
            let subAgentNames = rooms[idx].assignedAgentIDs.compactMap { id -> String? in
                guard let a = agentStore?.agents.first(where: { $0.id == id }), !a.isMaster else { return nil }
                return a.name
            }
            if !subAgentNames.isEmpty {
                let names = subAgentNames.joined(separator: ", ")
                let msg = ChatMessage(
                    role: .system,
                    content: "사용자가 선택한 팀으로 진행합니다: \(names)",
                    messageType: .phaseTransition
                )
                appendMessage(msg, to: roomID)
                return
            }
        }

        // 1) 마스터에게 역할 요구사항 산출 요청
        var contextParts: [String] = []
        if let intakeData = rooms[idx].intakeData {
            contextParts.append(intakeData.asClarifyContextString())
        }
        if let assumptions = rooms[idx].assumptions, !assumptions.isEmpty {
            contextParts.append("[가정]\n" + assumptions.map { "- \($0.text)" }.joined(separator: "\n"))
        }
        if let workLog = rooms[idx].workLog {
            contextParts.append(workLog.asContextString())
        }

        let intentName = rooms[idx].intent?.displayName ?? "구현"
        let docTypeName = rooms[idx].documentType?.displayName
        // 기존 에이전트 목록 구성
        let subAgents = agentStore?.subAgents ?? []
        let agentRoster = subAgents.isEmpty ? "(없음)" : subAgents.map { "- \($0.name)" }.joined(separator: "\n")

        let intent = rooms[idx].intent
        let maxAgentHint: String
        switch intent {
        case .quickAnswer:
            maxAgentHint = "이 작업은 즉답(quickAnswer)이므로 **반드시 1명만** 요청하세요. 가장 적합한 전문가 1명만 선택하세요."
        case .task:
            maxAgentHint = rooms[idx].autoDocOutput
                ? "이 작업은 조사/분석 + 문서 작성이므로 **2명**을 요청하세요."
                : "불확실하면 적게 요청하세요 (1~2명이면 충분한 경우가 많습니다)."
        default:
            maxAgentHint = "불확실하면 적게 요청하세요 (1~2명이면 충분한 경우가 많습니다)."
        }

        // 문서 유형 컨텍스트
        let docTypeHint: String
        if rooms[idx].autoDocOutput, let docType = rooms[idx].documentType {
            docTypeHint = """

            이 작업은 조사/분석 후 **\(docType.displayName)** 문서를 출력합니다.
            조사/분석을 수행할 전문가와 문서 작성에 적합한 전문가가 모두 필요합니다.
            예: 테스트 계획서 → 리서치 전문가 + QA/테스트 전문가, PRD → 리서치 전문가 + 기획/PM 전문가.
            """
        } else if let docType = rooms[idx].documentType, docType != .freeform {
            docTypeHint = """

            이 작업은 **\(docType.displayName)** 문서를 작성하는 작업입니다.
            문서를 잘 작성할 수 있는 전문가를 선택하세요.
            작업 대상 도메인(예: 백엔드, 프론트엔드)의 개발자가 아니라, 해당 문서 유형을 작성할 역량이 있는 전문가를 우선하세요.
            예: 테스트 계획서 → QA/테스트 전문가, PRD → 기획/PM 전문가, 기술 설계서 → 시니어 개발자/아키텍트.
            """
        } else {
            docTypeHint = ""
        }

        let assembleSystemPrompt = """
        \(agent.resolvedSystemPrompt)

        당신은 Assemble(팀 구성) 단계를 수행하고 있습니다.
        작업 유형은 **\(intentName)**\(docTypeName != nil ? " (\(docTypeName!))" : "")입니다.

        작업에 **직접적으로** 필요한 역할만 최소한으로 요청하세요.
        작업과 무관한 역할은 절대 포함하지 마세요.
        \(maxAgentHint)\(docTypeHint)

        사용자의 요청을 정확히 읽고, 요청된 관점의 전문가만 초대하세요.
        예: "프론트엔드 관점에서" → 프론트엔드 전문가만. 백엔드 전문가는 불필요.

        **[선택] 역할 제한:**
        - [선택]은 사용자가 명시적으로 요청한 경우에만 추가하세요.
        - 코드 수정/구현 작업에는 해당 도메인 개발자 1명이면 충분합니다.
        - "혹시 필요할 수도 있다"는 이유로 QA, 리서치, 디자인 등 보조 역할을 추가하지 마세요.

        현재 사용 가능한 에이전트:
        \(agentRoster)

        반드시 아래 형식으로 산출물을 생성하세요:

        ```artifact:role_requirements title="역할 요구사항"
        - [필수] 역할이름: 이 역할이 필요한 이유
        - [선택] 역할이름: 이 역할이 필요한 이유
        ```

        주의:
        - **반드시 위 에이전트 목록에서 선택하세요.** 목록의 정확한 이름을 그대로 사용하세요.
        - 목록에 적합한 에이전트가 정말 없을 때만 새 이름을 만드세요. 이 경우에도 역할 역량 중심으로 짓세요.
        - 작업 내용과 직접 관련된 에이전트만 선택하세요. "백엔드 쿼리 수정" → 백엔드 개발자, "UI 개선" → 프론트엔드 개발자.
        """

        // --- 명시적 위임 감지 (clarify LLM 판단) ---
        if let delegation = rooms[idx].delegationInfo,
           delegation.type == .explicit,
           !delegation.agentNames.isEmpty {
            let matchedAgents = delegation.agentNames.compactMap { name -> Agent? in
                let lowered = name.lowercased()
                return subAgents.first { agent in
                    let agentLowered = agent.name.lowercased()
                    return agentLowered == lowered
                        || agentLowered.contains(lowered)
                        || lowered.contains(agentLowered)
                }
            }
            if !matchedAgents.isEmpty {
                for matched in matchedAgents {
                    if let room = rooms.first(where: { $0.id == roomID }),
                       !room.assignedAgentIDs.contains(matched.id) {
                        addAgent(matched.id, to: roomID, silent: true)
                    }
                }
                scheduleSave()
                await showTeamConfirmation(roomID: roomID)
                return  // LLM 역할 분석 스킵
            }
            // 매칭 실패 → 기존 directMatch + LLM 흐름으로 폴스루
        }

        // 사전 매칭 (폴백): 사용자 요청에서 기존 에이전트 이름 키워드 직접 탐색
        // delegationInfo가 없는 과거 방이나 파싱 실패 시 사용
        var directMatchText: String
        if let clarifySummary = rooms[idx].clarifySummary {
            directMatchText = clarifySummary
        } else {
            directMatchText = task
        }
        // Jira 키워드 자동 주입 제거: clarifySummary에 사용자 의도가 이미 반영됨
        // (sourceType만으로 Jira 전문가를 강제 매칭하면 false positive 발생)
        let taskLowered = directMatchText.lowercased()
        let taskWords = taskLowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        let directMatches: [Agent] = subAgents.filter { sub in
            let nameKeywords = sub.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { word in
                    guard word.count >= 2 else { return false }
                    // 숫자 접미사 제거 후 범용 접미사 확인 (전문가1 → 전문가 → 제외)
                    let stripped = word.replacingOccurrences(of: "\\d+$", with: "", options: .regularExpression)
                    return !AgentMatcher.isGenericSuffix(word) && !AgentMatcher.isGenericSuffix(stripped)
                }
            return nameKeywords.contains(where: { keyword in
                // 정확 매칭: task에 키워드 포함 (ex: "백엔드" in task)
                taskLowered.contains(keyword) ||
                // 접두어 매칭: task 단어가 키워드의 접두어 (ex: "프론트" → "프론트엔드")
                taskWords.contains(where: { word in
                    guard !AgentMatcher.isGenericSuffix(word) else { return false }
                    return keyword.hasPrefix(word) && word.count >= 2
                })
            })
        }

        if !directMatches.isEmpty {
            // directMatches: 사용자가 이름을 직접 언급한 에이전트 → 제한 없이 전부 초대
            for sub in directMatches {
                if let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(sub.id) {
                    addAgent(sub.id, to: roomID, silent: true)
                }
            }
            scheduleSave()
            await showTeamConfirmation(roomID: roomID)
            return
        }

        let messages: [(role: String, content: String)] = [
            ("user", "\(contextParts.joined(separator: "\n\n"))\n\n위 작업에 필요한 역할을 분석하세요. 작업: \(task)")
        ]

        do {
            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let response = try await provider.sendMessage(
                model: lightModel,
                systemPrompt: assembleSystemPrompt,
                messages: messages
            )

            // 산출물 추출
            let artifacts = ArtifactParser.extractArtifacts(from: response, producedBy: agent.name)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].artifacts.append(contentsOf: artifacts)
            }

            // role_requirements 산출물에서 역할 파싱
            var requirements: [RoleRequirement] = []
            for artifact in artifacts where artifact.type == .roleRequirements {
                requirements.append(contentsOf: AgentMatcher.parseRoleRequirements(from: artifact.content))
            }

            // documentType이 설정되고 autoDocOutput이 아닌 경우: 최대 1명만 허용
            // autoDocOutput이면 리서치+문서 복합 → 다수 에이전트 허용
            if rooms[idx].documentType != nil && !rooms[idx].autoDocOutput, requirements.count > 1 {
                if let firstRequired = requirements.first(where: { $0.priority == .required }) {
                    requirements = [firstRequired]
                } else {
                    requirements = [requirements[0]]
                }
            }

            if requirements.isEmpty {
                // 기존 전문가가 있으면 팀 확인 후 진행
                let existingSpecialists = executingAgentIDs(in: roomID)
                if !existingSpecialists.isEmpty {
                    await showTeamConfirmation(roomID: roomID)
                    return
                }

                // 전문가 없음 → 작업 내용 기반 구체적 에이전트 제안
                let taskSnippet = String(task.prefix(60))
                let suggestedName: String
                let suggestedPersona: String
                if let brief = rooms[idx].taskBrief {
                    // taskBrief 기반: 목표에서 전문 분야 추출
                    let domain = brief.goal.prefix(30)
                    suggestedName = brief.outputType == .answer || brief.outputType == .analysis
                        ? "리서치 전문가" : "\(intentName) 전문가"
                    suggestedPersona = "\(domain) 관련 질문에 답변하고 분석하는 전문가입니다."
                } else {
                    // taskBrief 없음: 키워드 기반 추론
                    let lower = task.lowercased()
                    if lower.contains("트렌드") || lower.contains("동향") {
                        suggestedName = "트렌드 분석가"
                        suggestedPersona = "기술 트렌드와 산업 동향을 분석하는 전문가입니다."
                    } else if lower.contains("코드") || lower.contains("개발") || lower.contains("구현") {
                        suggestedName = "소프트웨어 엔지니어"
                        suggestedPersona = "소프트웨어 설계 및 구현 전문가입니다."
                    } else if lower.contains("문서") || lower.contains("보고서") || lower.contains("작성") {
                        suggestedName = "문서 작성 전문가"
                        suggestedPersona = "보고서, 기획서 등 문서 작성 전문가입니다."
                    } else {
                        suggestedName = "범용 전문가"
                        suggestedPersona = "'\(taskSnippet)' 작업을 수행하는 전문가입니다."
                    }
                }
                let suggestion = RoomAgentSuggestion(
                    name: suggestedName,
                    persona: suggestedPersona,
                    reason: "'\(taskSnippet)' 작업에 적합한 전문가가 필요합니다.",
                    suggestedBy: agent.name
                )
                addAgentSuggestion(suggestion, to: roomID)
                await waitForSuggestionResponse(roomID: roomID)

                // 제안 해결 후 → 팀 확인 게이트
                await showTeamConfirmation(roomID: roomID)
                return
            }

            // 2) 시스템 매칭 (Plan C: 3단 가중치 + 신뢰도 임계값)
            let subAgents = agentStore?.subAgents ?? []
            let taskBrief = rooms.first(where: { $0.id == roomID })?.taskBrief
            let matched = AgentMatcher.matchRoles(
                requirements: requirements,
                agents: subAgents,
                intent: intent,
                documentType: rooms.first(where: { $0.id == roomID })?.documentType,
                taskBrief: taskBrief
            )

            // 3) [필수] matched(0.7+) 에이전트 자동 초대
            for req in matched where req.status == .matched && req.priority == .required {
                if let agentID = req.matchedAgentID,
                   let room = rooms.first(where: { $0.id == roomID }),
                   !room.assignedAgentIDs.contains(agentID) {
                    addAgent(agentID, to: roomID, silent: true)
                }
            }

            // 3.5) suggested(0.5~0.7) 에이전트: 사용자에게 추가 여부 질문
            let suggestedReqs = matched.filter { $0.status == .suggested && $0.matchedAgentID != nil }
            for req in suggestedReqs {
                guard let agentID = req.matchedAgentID,
                      let sugAgent = agentStore?.agents.first(where: { $0.id == agentID }) else { continue }
                let confidenceStr = String(format: "%.0f%%", req.confidence * 100)
                let suggestMsg = ChatMessage(
                    role: .system,
                    content: "\(sugAgent.name)도 추가할까요? (매칭도: \(confidenceStr)) [추가] [이대로]",
                    messageType: .approvalRequest
                )
                appendMessage(suggestMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingApproval)
                }
                syncAgentStatuses()
                scheduleSave()

                let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = cont
                }
                approvalContinuations.removeValue(forKey: roomID)

                if approved {
                    if let room = rooms.first(where: { $0.id == roomID }),
                       !room.assignedAgentIDs.contains(agentID) {
                        addAgent(agentID, to: roomID, silent: true)
                    }
                }
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }
            }

            // 4) [필수] 미매칭 역할은 에이전트 생성 제안 ([선택] 미매칭은 무시)
            for req in matched where req.status == .unmatched && req.priority == .required {
                let suggestion = RoomAgentSuggestion(
                    name: req.roleName,
                    persona: "이 에이전트는 '\(req.roleName)' 역할을 수행합니다. \(req.reason)",
                    reason: req.reason,
                    suggestedBy: agent.name
                )
                addAgentSuggestion(suggestion, to: roomID)
            }

            // 4.5) 미매칭 제안이 있으면 사용자가 추가/건너뛰기할 때까지 대기
            let hadUnmatched = matched.contains(where: { $0.status == .unmatched && $0.priority == .required })
            if hadUnmatched {
                await waitForSuggestionResponse(roomID: roomID)
            }

            // 5) RuntimeRole 사전 배정 (Plan C: Assemble에서 배정)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let specialists = executingAgentIDs(in: roomID)
                if specialists.count >= 2 {
                    let (creatorID, reviewerID, plannerID) = assignDesignRoles(specialists: specialists)
                    if let creatorName = agentStore?.agents.first(where: { $0.id == creatorID })?.name {
                        rooms[i].agentRoles[creatorName] = .creator
                    }
                    if let reviewerName = agentStore?.agents.first(where: { $0.id == reviewerID })?.name {
                        rooms[i].agentRoles[reviewerName] = .reviewer
                    }
                    if let plannerID, let plannerName = agentStore?.agents.first(where: { $0.id == plannerID })?.name {
                        rooms[i].agentRoles[plannerName] = .planner
                    }
                } else if let solo = specialists.first, let name = agentStore?.agents.first(where: { $0.id == solo })?.name {
                    rooms[i].agentRoles[name] = .creator
                }
            }

            // 6) 팀 구성 확인 게이트
            await showTeamConfirmation(roomID: roomID)

        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Assemble 단계 오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
        scheduleSave()
    }


    // MARK: - Plan C: 새 6단계 워크플로우

    /// Understand 단계 (Plan C): intake + intent + TaskBrief 생성 (clarify 루프 제거)
    private func executeUnderstandPhase(roomID: UUID, task: String) async {
        var actualTask = task

        // 0) 파일만 업로드된 경우: 사용자에게 작업 의도 확인
        if task.isEmpty {
            let questionMsg = ChatMessage(
                role: .assistant,
                content: "어떤 작업을 진행할까요?\n(예: 이미지 분석, 텍스트 추출, 디자인 피드백, 코드 리뷰 등)",
                agentName: masterAgentName,
                messageType: .userQuestion
            )
            appendMessage(questionMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            // 2분 타임아웃으로 사용자 응답 대기
            let answer: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask { @MainActor [weak self] in
                    guard let self else { return nil }
                    return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                        self.userInputContinuations[roomID] = continuation
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            guard let userAnswer = answer, !userAnswer.isEmpty else {
                // 타임아웃 → 종료
                let timeoutMsg = ChatMessage(
                    role: .system,
                    content: "입력 대기 시간이 초과되었습니다. 새로 요청해주세요.",
                    messageType: .error
                )
                appendMessage(timeoutMsg, to: roomID)
                userInputContinuations.removeValue(forKey: roomID)
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                syncAgentStatuses()
                scheduleSave()
                return
            }

            actualTask = userAnswer
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
                let titleText = userAnswer.prefix(30).components(separatedBy: "\n").first ?? String(userAnswer.prefix(30))
                rooms[i].title = String(titleText)
            }
            scheduleSave()
        }

        // 1) Intake: URL/Jira fetch
        await executeIntakePhase(roomID: roomID, task: actualTask)
        guard !Task.isCancelled,
              rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // 2) Intent: quickAnswer vs task 분류
        await executeIntentPhase(roomID: roomID, task: actualTask)
        guard !Task.isCancelled,
              rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // 3) TaskBrief 생성 (clarify 루프 대신 1회 질문으로 대체)
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let firstAgentID = rooms[idx].assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName

        let intakeContext = rooms[idx].intakeData?.asClarifyContextString()
        let hasExplicitIntent = IntentClassifier.hasExplicitUserIntent(actualTask)
        let brief = await IntentClassifier.generateTaskBrief(
            task: actualTask,
            intakeContext: intakeContext,
            clarifySummary: rooms[idx].clarifySummary,
            userHasExplicitIntent: hasExplicitIntent,
            provider: provider,
            model: lightModel
        )

        if let brief {
            rooms[idx].taskBrief = brief
        } else {
            print("[DOUGLAS] ⚠️ TaskBrief 생성 실패 — 키워드 기반 fallback으로 진행")
        }
        scheduleSave()

        // 4) needsClarification이면 질문 최대 2회 → 자동 진행 (Plan C)
        var currentBrief: TaskBrief? = brief
        var enrichedTask = actualTask
        let maxQuestions = 2

        for questionRound in 1...maxQuestions {
            guard let cb = currentBrief, cb.needsClarification, !cb.questions.isEmpty else { break }
            guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            let questionText = (currentBrief?.questions ?? []).joined(separator: "\n")
            let questionMsg = ChatMessage(
                role: .assistant,
                content: "추가 확인이 필요합니다 (\(questionRound)/\(maxQuestions)):\n\n\(questionText)",
                agentName: masterAgentName,
                messageType: .userQuestion
            )
            appendMessage(questionMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            // 30초 타임아웃 or 사용자 응답
            let answer: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask { @MainActor [weak self] in
                    guard let self else { return nil }
                    return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                        self.userInputContinuations[roomID] = continuation
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            if let answer, !answer.isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }
                enrichedTask = "\(enrichedTask)\n\n추가 정보: \(answer)"
                if let updatedBrief = await IntentClassifier.generateTaskBrief(
                    task: enrichedTask,
                    intakeContext: intakeContext,
                    clarifySummary: rooms[idx].clarifySummary,
                    userHasExplicitIntent: true,
                    provider: provider,
                    model: lightModel
                ) {
                    currentBrief = updatedBrief
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].taskBrief = updatedBrief
                    }
                } else {
                    break  // 재생성 실패 시 기존 brief로 진행
                }
            } else {
                // 타임아웃 — 최선의 해석으로 진행
                let autoMsg = ChatMessage(
                    role: .system,
                    content: "응답 대기 시간 초과 — 현재 정보로 진행합니다.",
                    messageType: .phaseTransition
                )
                appendMessage(autoMsg, to: roomID)
                userInputContinuations.removeValue(forKey: roomID)
                break
            }
        }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.planning)
        }
        scheduleSave()
    }

    /// Design 단계 (Plan C): outputType에 따라 토론 모드 / 계획 모드 분기
    private func executeDesignPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let specialists = executingAgentIDs(in: roomID)
        let room = rooms[idx]

        // 전문가 1명: 구조화된 플랜 생성 (Plan C: 1인 프로토콜)
        if specialists.count < 2 {
            await executeSoloDesign(roomID: roomID, task: task, room: room)
            return
        }

        // TaskBrief 기반 컨텍스트
        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = """
            [작업 브리프]
            목표: \(brief.goal)
            제약: \(brief.constraints.joined(separator: ", "))
            성공기준: \(brief.successCriteria.joined(separator: ", "))
            비목표: \(brief.nonGoals.joined(separator: ", "))
            위험도: \(brief.overallRisk.rawValue)
            산출물 유형: \(brief.outputType.rawValue)
            """
        } else {
            briefContext = room.clarifySummary ?? task
        }

        // outputType에 따라 토론 모드 / 계획 모드 분기
        let isDiscussionMode: Bool = {
            // 1순위: taskBrief의 outputType
            if let outputType = room.taskBrief?.outputType {
                switch outputType {
                case .analysis, .answer: return true
                case .code, .document, .message, .data, .design: return false
                }
            }
            // 2순위: taskBrief 없을 때 키워드 기반 fallback
            let lower = task.lowercased()
            let discussionSignals = ["어떻게 생각", "의견", "토론", "브레인스토밍", "brainstorm",
                                     "트렌드", "전망", "관점", "견해", "좋을까", "어떨까",
                                     "장단점", "비교", "분석해", "어떤 것이"]
            let hasDiscussionSignal = discussionSignals.contains { lower.contains($0) }
            let hasExecutionSignal = ["만들어", "구현", "작성해", "코딩", "빌드", "배포",
                                      "수정해", "커밋", "fix", "implement", "deploy"]
                .contains { lower.contains($0) }
            return hasDiscussionSignal && !hasExecutionSignal
        }()

        if isDiscussionMode {
            await executeDiscussionDesign(roomID: roomID, task: task, briefContext: briefContext, specialists: specialists)
            return
        }

        let startMsg = ChatMessage(
            role: .system,
            content: "설계 토론을 시작합니다. (Propose → Critique → Revise)",
            messageType: .phaseTransition
        )
        appendMessage(startMsg, to: roomID)

        // RuntimeRole 할당: workModes 기반 (Plan C: 4d)
        let (creatorID, reviewerID, plannerID) = assignDesignRoles(specialists: specialists)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            let creatorName = agentStore?.agents.first(where: { $0.id == creatorID })?.name ?? ""
            let reviewerName = agentStore?.agents.first(where: { $0.id == reviewerID })?.name ?? ""
            rooms[i].agentRoles[creatorName] = .creator
            rooms[i].agentRoles[reviewerName] = .reviewer
            if let plannerID, let plannerName = agentStore?.agents.first(where: { $0.id == plannerID })?.name {
                rooms[i].agentRoles[plannerName] = .planner
            }
        }

        guard let creatorAgent = agentStore?.agents.first(where: { $0.id == creatorID }),
              let creatorProvider = providerManager?.provider(named: creatorAgent.providerName),
              let reviewerAgent = agentStore?.agents.first(where: { $0.id == reviewerID }),
              let reviewerProvider = providerManager?.provider(named: reviewerAgent.providerName) else {
            // 에이전트/프로바이더 없으면 plan 폴백
            let intent = room.intent ?? .task
            await executePlanPhase(roomID: roomID, task: task, intent: intent)
            return
        }

        // 3인+ Planner 프로토콜 vs 2인 Creator/Reviewer 프로토콜
        let usePlannerProtocol = plannerID != nil && specialists.count >= 3
        let plannerAgent = plannerID.flatMap { id in agentStore?.agents.first(where: { $0.id == id }) }
        let plannerProvider = plannerAgent.flatMap { providerManager?.provider(named: $0.providerName) }

        // Turn 1 리더: 3인+=Planner, 2인=Creator
        let turn1Agent = (usePlannerProtocol ? plannerAgent : nil) ?? creatorAgent
        let turn1Provider = (usePlannerProtocol ? plannerProvider : nil) ?? creatorProvider
        let turn1ID = usePlannerProtocol ? (plannerID ?? creatorID) : creatorID
        let turn1Role = usePlannerProtocol ? "Planner" : "Creator"

        // Turn 1: Propose
        speakingAgentIDByRoom[roomID] = turn1ID
        let proposePrompt = """
        \(turn1Agent.resolvedSystemPrompt)

        당신은 설계(Design) 단계의 \(turn1Role)입니다.
        아래 작업 브리프를 바탕으로 **구체적인 실행 계획**을 제안하세요.
        \(usePlannerProtocol ? "\n각 단계에 담당 에이전트를 지정하세요." : "")

        \(briefContext)

        형식:
        1. 각 단계를 번호로 나열
        2. 각 단계에 [위험도: low/medium/high] 표시
        3. 예상 산출물 명시
        4. 주의사항/가정 나열
        """

        var proposal = ""
        do {
            // Progress 추적: Turn 1
            let progressMsg = ChatMessage(role: .system, content: "\(turn1Agent.name) 설계 제안 중", messageType: .progress)
            appendMessage(progressMsg, to: roomID)
            let startActivity = ChatMessage(
                role: .assistant, content: "\(turn1Agent.name) 설계 제안 중",
                agentName: turn1Agent.name, messageType: .toolActivity,
                activityGroupID: progressMsg.id,
                toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(turn1Agent.providerName) · \(turn1Agent.modelName)", contentPreview: nil, isError: false)
            )
            appendMessage(startActivity, to: roomID)

            let placeholderID = UUID()
            appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: turn1Agent.name), to: roomID)

            let startTime = Date()
            let buffer = StreamBuffer()
            proposal = try await turn1Provider.sendMessageStreaming(
                model: turn1Agent.modelName,
                systemPrompt: proposePrompt,
                messages: [("user", "작업 계획을 제안해주세요.\n\n\(briefContext)")],
                onChunk: { [weak self] chunk in
                    guard let self else { return }
                    let current = buffer.append(chunk)
                    Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                }
            )
            updateMessageContent(placeholderID, newContent: proposal, in: roomID)

            let duration = Date().timeIntervalSince(startTime)
            let durationStr = duration < 60 ? String(format: "%.1f초", duration) : String(format: "%d분 %.0f초", Int(duration) / 60, duration.truncatingRemainder(dividingBy: 60))
            let resultActivity = ChatMessage(
                role: .assistant, content: "제안 완료 (\(durationStr))",
                agentName: turn1Agent.name, messageType: .toolActivity,
                activityGroupID: progressMsg.id,
                toolDetail: ToolActivityDetail(toolName: "llm_result", subject: "\(durationStr) | \(proposal.count)자", contentPreview: nil, isError: false)
            )
            appendMessage(resultActivity, to: roomID)
        } catch {
            appendMessage(ChatMessage(role: .assistant, content: "설계 제안 오류: \(error.userFacingMessage)", agentName: turn1Agent.name, messageType: .error), to: roomID)
            return
        }
        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // Turn 2: Critique
        // 3인+: 나머지 전원(Creator+Reviewer) 병렬 피드백
        // 2인: Reviewer만
        var critique = ""
        if usePlannerProtocol {
            // Progress 추적: Turn 2 병렬 피드백
            let parallelProgressMsg = ChatMessage(role: .system, content: "병렬 검토 진행 중", messageType: .progress)
            appendMessage(parallelProgressMsg, to: roomID)

            // 병렬 피드백 수집
            let feedbackAgents = specialists.filter { $0 != turn1ID }
            var feedbacks: [(String, String)] = []
            await withTaskGroup(of: (String, String).self) { group in
                for agentID in feedbackAgents {
                    guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
                          let provider = providerManager?.provider(named: agent.providerName) else { continue }
                    group.addTask { [self] in
                        let prompt = """
                        \(agent.resolvedSystemPrompt)

                        Planner의 실행 계획을 검토하세요.
                        자신의 담당 영역에서 빠진 것, 문제점, 수정 제안을 하세요.
                        문제 없으면 '승인'이라고만 쓰세요.
                        """
                        do {
                            let placeholderID = UUID()
                            await MainActor.run { [self] in
                                self.speakingAgentIDByRoom[roomID] = agentID
                                self.appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name), to: roomID)
                                self.appendMessage(ChatMessage(
                                    role: .assistant, content: "\(agent.name) 검토 중",
                                    agentName: agent.name, messageType: .toolActivity,
                                    activityGroupID: parallelProgressMsg.id,
                                    toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(agent.providerName) · \(agent.modelName)", contentPreview: nil, isError: false)
                                ), to: roomID)
                            }
                            let buffer = StreamBuffer()
                            let result = try await provider.sendMessageStreaming(
                                model: agent.modelName,
                                systemPrompt: prompt,
                                messages: [("user", "다음 실행 계획을 검토해주세요:\n\n\(proposal)")],
                                onChunk: { [weak self] chunk in
                                    guard let self else { return }
                                    let current = buffer.append(chunk)
                                    Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                                }
                            )
                            await MainActor.run { [self] in
                                self.updateMessageContent(placeholderID, newContent: result, in: roomID)
                            }
                            return (agent.name, result)
                        } catch {
                            return (agent.name, "검토 오류: \(error.localizedDescription)")
                        }
                    }
                }
                for await feedback in group {
                    feedbacks.append(feedback)
                }
            }
            critique = feedbacks.map { "[\($0.0)] \($0.1)" }.joined(separator: "\n\n")
        } else {
            // 2인 프로토콜: Reviewer만
            speakingAgentIDByRoom[roomID] = reviewerID

            // Progress 추적: Turn 2
            let critiqueProgressMsg = ChatMessage(role: .system, content: "\(reviewerAgent.name) 검토 중", messageType: .progress)
            appendMessage(critiqueProgressMsg, to: roomID)
            appendMessage(ChatMessage(
                role: .assistant, content: "\(reviewerAgent.name) 검토 중",
                agentName: reviewerAgent.name, messageType: .toolActivity,
                activityGroupID: critiqueProgressMsg.id,
                toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(reviewerAgent.providerName) · \(reviewerAgent.modelName)", contentPreview: nil, isError: false)
            ), to: roomID)

            let critiquePrompt = """
            \(reviewerAgent.resolvedSystemPrompt)

            당신은 설계(Design) 단계의 Reviewer입니다.
            Creator의 실행 계획을 검토하고 **구체적인 개선점**을 제시하세요.

            검토 기준:
            1. 위험도 평가가 적절한가?
            2. 누락된 단계나 엣지케이스가 있는가?
            3. 순서가 최적인가?
            4. 산출물이 요구사항을 충족하는가?

            동의하면 '승인'이라고만 쓰세요.
            간결하게 핵심만 지적하세요.
            """

            do {
                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: reviewerAgent.name), to: roomID)

                let critiqueStart = Date()
                let buffer = StreamBuffer()
                critique = try await reviewerProvider.sendMessageStreaming(
                    model: reviewerAgent.modelName,
                    systemPrompt: critiquePrompt,
                    messages: [("user", "다음 실행 계획을 검토해주세요:\n\n\(proposal)")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: critique, in: roomID)

                let critiqueDuration = Date().timeIntervalSince(critiqueStart)
                let critiqueDurationStr = critiqueDuration < 60 ? String(format: "%.1f초", critiqueDuration) : String(format: "%d분 %.0f초", Int(critiqueDuration) / 60, critiqueDuration.truncatingRemainder(dividingBy: 60))
                appendMessage(ChatMessage(
                    role: .assistant, content: "검토 완료 (\(critiqueDurationStr))",
                    agentName: reviewerAgent.name, messageType: .toolActivity,
                    activityGroupID: critiqueProgressMsg.id,
                    toolDetail: ToolActivityDetail(toolName: "llm_result", subject: "\(critiqueDurationStr) | \(critique.count)자", contentPreview: nil, isError: false)
                ), to: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "검토 오류: \(error.userFacingMessage)", agentName: reviewerAgent.name, messageType: .error), to: roomID)
            }
        }
        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // Turn 3 스킵 판단: Critique에서 "승인"/"동의" 시 스킵
        let critiqueApproved = isCritiqueApproval(critique)
        var finalDesignText = proposal

        if !critiqueApproved {
            // Turn 3: Revise (리더가 피드백 반영 → 최종 계획)
            speakingAgentIDByRoom[roomID] = turn1ID

            // Progress 추적: Turn 3
            let reviseProgressMsg = ChatMessage(role: .system, content: "\(turn1Agent.name) 계획 수정 중", messageType: .progress)
            appendMessage(reviseProgressMsg, to: roomID)
            appendMessage(ChatMessage(
                role: .assistant, content: "\(turn1Agent.name) 계획 수정 중",
                agentName: turn1Agent.name, messageType: .toolActivity,
                activityGroupID: reviseProgressMsg.id,
                toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(turn1Agent.providerName) · \(turn1Agent.modelName)", contentPreview: nil, isError: false)
            ), to: roomID)

            let revisePrompt = """
            \(turn1Agent.resolvedSystemPrompt)

            피드백을 반영하여 최종 실행 계획을 작성하세요.
            변경 사항이 없으면 원래 계획을 유지하세요.
            최종 계획만 출력하세요 (변경 이유 설명 불필요).

            형식:
            1. [위험도] 단계 설명
            2. [위험도] 단계 설명
            ...
            """

            do {
                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: turn1Agent.name), to: roomID)

                let reviseStart = Date()
                let buffer = StreamBuffer()
                let revisedPlan = try await turn1Provider.sendMessageStreaming(
                    model: turn1Agent.modelName,
                    systemPrompt: revisePrompt,
                    messages: [
                        ("user", "원래 제안:\n\(proposal)\n\n피드백:\n\(critique)\n\n피드백을 반영한 최종 계획을 작성하세요.")
                    ],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: revisedPlan, in: roomID)
                finalDesignText = revisedPlan

                let reviseDuration = Date().timeIntervalSince(reviseStart)
                let reviseDurationStr = reviseDuration < 60 ? String(format: "%.1f초", reviseDuration) : String(format: "%d분 %.0f초", Int(reviseDuration) / 60, reviseDuration.truncatingRemainder(dividingBy: 60))
                appendMessage(ChatMessage(
                    role: .assistant, content: "수정 완료 (\(reviseDurationStr))",
                    agentName: turn1Agent.name, messageType: .toolActivity,
                    activityGroupID: reviseProgressMsg.id,
                    toolDetail: ToolActivityDetail(toolName: "llm_result", subject: "\(reviseDurationStr) | \(revisedPlan.count)자", contentPreview: nil, isError: false)
                ), to: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "수정 오류: \(error.userFacingMessage)", agentName: turn1Agent.name, messageType: .error), to: roomID)
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)
        }
        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // 최종 계획을 Plan으로 파싱
        let plan = await requestPlan(roomID: roomID, task: task, designOutput: finalDesignText)
        if let plan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].plan = plan
        }

        // 승인 루프 (기존 plan 승인과 동일)
        if let plan = rooms.first(where: { $0.id == roomID })?.plan {
            var currentPlan = plan
            let maxRevisions = 2
            var revisionCount = 0
            while true {
                guard !Task.isCancelled,
                      let planIdx = rooms.firstIndex(where: { $0.id == roomID }),
                      rooms[planIdx].isActive else { return }

                rooms[planIdx].transitionTo(.awaitingApproval)
                syncAgentStatuses()

                let stepsDesc = currentPlan.steps.enumerated().map { i, s in
                    let risk = s.riskLevel == .low ? "" : " [\(s.riskLevel.displayName)]"
                    return "\(i + 1). \(s.text)\(risk)"
                }.joined(separator: "\n")
                let approvalMsg = ChatMessage(
                    role: .system,
                    content: "설계 완료:\n\n\(stepsDesc)\n\n이 계획으로 진행하시겠습니까?",
                    messageType: .approvalRequest
                )
                appendMessage(approvalMsg, to: roomID)
                pluginEventDelegate?(.approvalRequested(roomID: roomID, stepDescription: stepsDesc))
                scheduleSave()

                let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = continuation
                }
                approvalContinuations.removeValue(forKey: roomID)
                guard !Task.isCancelled else { return }

                if approved {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.planning)
                    }
                    break
                }

                revisionCount += 1
                if revisionCount > maxRevisions {
                    // Plan C: 수정 요청 최대 2회 초과 → 사용자에게 최종 선택
                    let limitMsg = ChatMessage(
                        role: .system,
                        content: "수정 요청이 \(maxRevisions)회를 초과했습니다. 현재 계획으로 진행하시겠습니까?",
                        messageType: .approvalRequest
                    )
                    appendMessage(limitMsg, to: roomID)
                    let finalApproved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                        approvalContinuations[roomID] = cont
                    }
                    approvalContinuations.removeValue(forKey: roomID)
                    if finalApproved {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.planning)
                        }
                    } else {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.completed)
                            rooms[i].completedAt = Date()
                        }
                        syncAgentStatuses()
                        scheduleSave()
                        return
                    }
                    break
                }

                // 거부 → 피드백 반영 재계획
                let feedback = rooms.first(where: { $0.id == roomID })?
                    .messages.last(where: { $0.role == .user })?.content
                let replanMsg = ChatMessage(role: .system, content: "피드백을 반영하여 계획을 수정합니다... (\(revisionCount)/\(maxRevisions))")
                appendMessage(replanMsg, to: roomID)
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }

                let newPlan = await requestPlan(roomID: roomID, task: task, previousPlan: currentPlan, feedback: feedback)
                guard !Task.isCancelled else { return }
                if let p = newPlan {
                    currentPlan = p
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) { rooms[i].plan = p }
                } else {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    syncAgentStatuses()
                    scheduleSave()
                    return
                }
            }
        }
        scheduleSave()
    }

    /// Critique 응답이 "승인/동의"인지 판별 (4a)
    private func isCritiqueApproval(_ critique: String) -> Bool {
        let approvalKeywords = ["승인", "동의합니다", "이상 없", "문제 없", "좋은 계획", "적절합니다", "동의합니다"]
        let lower = critique.trimmingCharacters(in: .whitespacesAndNewlines)
        // 짧은 긍정 응답이거나 명확한 승인 키워드가 있으면 승인
        return lower.count < 100 && approvalKeywords.contains(where: { lower.contains($0) })
    }

    /// workModes 기반 RuntimeRole 배정 (4d)
    private func assignDesignRoles(specialists: [UUID]) -> (creator: UUID, reviewer: UUID, planner: UUID?) {
        guard specialists.count >= 2 else {
            return (specialists[0], specialists[0], nil)
        }

        var creatorID: UUID?
        var reviewerID: UUID?
        var plannerID: UUID?

        for id in specialists {
            guard let agent = agentStore?.agents.first(where: { $0.id == id }) else { continue }
            if creatorID == nil && agent.workModes.contains(.create) { creatorID = id }
            // reviewer는 creator와 반드시 다른 에이전트여야 함
            if reviewerID == nil && agent.workModes.contains(.review) && id != creatorID { reviewerID = id }
            if plannerID == nil && agent.workModes.contains(.plan) { plannerID = id }
        }

        // 폴백: 지정 안 된 역할은 순서대로 할당
        let creator = creatorID ?? specialists[0]
        let reviewer = reviewerID ?? specialists.first(where: { $0 != creator }) ?? specialists[0]
        let planner = specialists.count >= 3 ? (plannerID ?? specialists.first(where: { $0 != creator && $0 != reviewer })) : nil

        return (creator, reviewer, planner)
    }

    // MARK: - 토론 모드 Design (analysis/answer)

    /// 토론 모드: 전문가 각자 의견 제시 → 상호 피드백 → 종합
    /// plan을 생성하지 않고, 토론 결과를 Build에서 종합 문서로 정리
    private func executeDiscussionDesign(roomID: UUID, task: String, briefContext: String, specialists: [UUID]) async {
        let startMsg = ChatMessage(
            role: .system,
            content: "전문가 토론을 시작합니다.",
            messageType: .phaseTransition
        )
        appendMessage(startMsg, to: roomID)

        // 전문가 에이전트 정보 수집
        let agentInfos: [(id: UUID, agent: Agent, provider: any AIProvider)] = specialists.compactMap { id in
            guard let agent = agentStore?.agents.first(where: { $0.id == id }),
                  let provider = providerManager?.provider(named: agent.providerName) else { return nil }
            return (id, agent, provider)
        }
        guard agentInfos.count >= 2 else { return }

        // --- Turn 1: 각 전문가가 자기 관점에서 의견 제시 (병렬) ---
        var opinions: [(name: String, content: String)] = []

        let turn1ProgressMsg = ChatMessage(role: .system, content: "각 전문가 의견 수렴 중", messageType: .progress)
        appendMessage(turn1ProgressMsg, to: roomID)

        await withTaskGroup(of: (String, String, UUID).self) { group in
            for info in agentInfos {
                group.addTask { [self] in
                    let prompt = """
                    \(info.agent.resolvedSystemPrompt)

                    당신은 **\(info.agent.name)** 관점의 전문가입니다.
                    아래 주제에 대해 당신의 전문 영역에서 의견을 제시하세요.

                    규칙:
                    - 당신의 전문 분야 관점에서만 답변하세요.
                    - 구체적인 근거와 사례를 포함하세요.
                    - 핵심을 간결하게 정리하세요.

                    \(briefContext)
                    """

                    let placeholderID = UUID()
                    await MainActor.run { [self] in
                        self.speakingAgentIDByRoom[roomID] = info.id
                        self.appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: info.agent.name), to: roomID)
                        self.appendMessage(ChatMessage(
                            role: .assistant, content: "\(info.agent.name) 의견 작성 중",
                            agentName: info.agent.name, messageType: .toolActivity,
                            activityGroupID: turn1ProgressMsg.id,
                            toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(info.agent.providerName) · \(info.agent.modelName)", contentPreview: nil, isError: false)
                        ), to: roomID)
                    }

                    do {
                        let buffer = StreamBuffer()
                        let result = try await info.provider.sendMessageStreaming(
                            model: info.agent.modelName,
                            systemPrompt: prompt,
                            messages: [("user", "다음 주제에 대해 당신의 전문적 의견을 제시해주세요:\n\n\(task)")],
                            onChunk: { [weak self] chunk in
                                guard let self else { return }
                                let current = buffer.append(chunk)
                                Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                            }
                        )
                        await MainActor.run { [self] in
                            self.updateMessageContent(placeholderID, newContent: result, in: roomID)
                        }
                        return (info.agent.name, result, info.id)
                    } catch {
                        await MainActor.run { [self] in
                            self.updateMessageContent(placeholderID, newContent: "의견 작성 오류: \(error.localizedDescription)", in: roomID)
                        }
                        return (info.agent.name, "", info.id)
                    }
                }
            }
            for await (name, content, _) in group {
                if !content.isEmpty {
                    opinions.append((name, content))
                }
            }
        }

        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }
        guard !opinions.isEmpty else { return }

        // --- Turn 2: 상대방 의견에 대한 피드백 (병렬) ---
        let turn2ProgressMsg = ChatMessage(role: .system, content: "상호 피드백 진행 중", messageType: .progress)
        appendMessage(turn2ProgressMsg, to: roomID)

        var feedbacks: [(name: String, content: String)] = []

        await withTaskGroup(of: (String, String).self) { group in
            for info in agentInfos {
                let othersOpinions = opinions.filter { $0.name != info.agent.name }
                guard !othersOpinions.isEmpty else { continue }

                let othersText = othersOpinions.map { "[\($0.name)]\n\($0.content)" }.joined(separator: "\n\n---\n\n")

                group.addTask { [self] in
                    let prompt = """
                    \(info.agent.resolvedSystemPrompt)

                    다른 전문가의 의견을 읽고, 당신의 관점에서 피드백을 제시하세요.

                    규칙:
                    - 동의하는 부분과 다른 시각이 있는 부분을 구분하세요.
                    - 보완할 점이나 놓친 관점을 지적하세요.
                    - 간결하게 핵심만 말하세요.
                    """

                    let placeholderID = UUID()
                    await MainActor.run { [self] in
                        self.speakingAgentIDByRoom[roomID] = info.id
                        self.appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: info.agent.name), to: roomID)
                        self.appendMessage(ChatMessage(
                            role: .assistant, content: "\(info.agent.name) 피드백 작성 중",
                            agentName: info.agent.name, messageType: .toolActivity,
                            activityGroupID: turn2ProgressMsg.id,
                            toolDetail: ToolActivityDetail(toolName: "llm_call", subject: "\(info.agent.providerName) · \(info.agent.modelName)", contentPreview: nil, isError: false)
                        ), to: roomID)
                    }

                    do {
                        let buffer = StreamBuffer()
                        let result = try await info.provider.sendMessageStreaming(
                            model: info.agent.modelName,
                            systemPrompt: prompt,
                            messages: [("user", "다른 전문가들의 의견입니다:\n\n\(othersText)\n\n이에 대한 피드백을 제시해주세요.")],
                            onChunk: { [weak self] chunk in
                                guard let self else { return }
                                let current = buffer.append(chunk)
                                Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                            }
                        )
                        await MainActor.run { [self] in
                            self.updateMessageContent(placeholderID, newContent: result, in: roomID)
                        }
                        return (info.agent.name, result)
                    } catch {
                        return (info.agent.name, "")
                    }
                }
            }
            for await (name, content) in group {
                if !content.isEmpty {
                    feedbacks.append((name, content))
                }
            }
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // --- 토론 결과를 1-step plan으로 변환 (Build에서 종합 문서 생성용) ---
        let discussionSummary = opinions.map { "[\($0.name) 의견]\n\($0.content)" }.joined(separator: "\n\n")
            + "\n\n---\n\n"
            + feedbacks.map { "[\($0.name) 피드백]\n\($0.content)" }.joined(separator: "\n\n")

        // 토론 결과를 room에 저장 (Build에서 참조)
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].clarifySummary = (rooms[i].clarifySummary ?? "") + "\n\n[토론 결과]\n" + discussionSummary
        }

        // 종합 정리 1-step plan 생성
        let synthesisStep = RoomStep(
            text: "전문가 토론 결과를 종합하여 최종 분석 보고서를 작성합니다.",
            assignedAgentID: agentInfos.first?.id
        )
        let plan = RoomPlan(
            summary: "전문가 토론 종합",
            estimatedSeconds: 120,
            steps: [synthesisStep]
        )
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].plan = plan
        }

        // 토론 모드에서는 승인 없이 바로 Build로 진행
        let completeMsg = ChatMessage(
            role: .system,
            content: "토론 완료 — 종합 정리를 진행합니다.",
            messageType: .phaseTransition
        )
        appendMessage(completeMsg, to: roomID)
        scheduleSave()
    }

    /// 1인 에이전트 구조화된 플랜 생성 (4b: executePlanPhase 대신)
    private func executeSoloDesign(roomID: UUID, task: String, room: Room) async {
        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = """
            [작업 브리프]
            목표: \(brief.goal)
            제약: \(brief.constraints.joined(separator: ", "))
            성공기준: \(brief.successCriteria.joined(separator: ", "))
            위험도: \(brief.overallRisk.rawValue)
            """
        } else {
            briefContext = room.clarifySummary ?? task
        }

        let specialists = executingAgentIDs(in: roomID)
        guard let agentID = specialists.first,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            let intent = room.intent ?? .task
            await executePlanPhase(roomID: roomID, task: task, intent: intent)
            return
        }

        let startMsg = ChatMessage(role: .system, content: "실행 계획을 수립합니다...", messageType: .phaseTransition)
        appendMessage(startMsg, to: roomID)

        speakingAgentIDByRoom[roomID] = agentID
        let soloPrompt = """
        \(agent.resolvedSystemPrompt)

        아래 작업을 수행하기 위한 실행 계획을 JSON으로 작성하세요.

        \(briefContext)

        반드시 아래 JSON 형식으로만 출력하세요:
        ```json
        {
          "plan": {
            "summary": "계획 요약",
            "estimated_minutes": 10,
            "steps": [
              {"text": "단계 설명", "risk_level": "low"}
            ]
          }
        }
        ```
        risk_level: low(읽기/분석), medium(파일수정/코드생성), high(외부시스템)
        """

        do {
            let placeholderID = UUID()
            appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name), to: roomID)

            let buffer = StreamBuffer()
            let response = try await provider.sendMessageStreaming(
                model: agent.modelName,
                systemPrompt: soloPrompt,
                messages: [("user", task)],
                onChunk: { [weak self] chunk in
                    guard let self else { return }
                    let current = buffer.append(chunk)
                    Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                }
            )
            updateMessageContent(placeholderID, newContent: response, in: roomID)

            if let plan = parsePlan(from: response),
               let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
            }
        } catch {
            appendMessage(ChatMessage(role: .assistant, content: "계획 수립 오류: \(error.userFacingMessage)", agentName: agent.name, messageType: .error), to: roomID)
        }
        speakingAgentIDByRoom.removeValue(forKey: roomID)

        // 승인 루프 (최대 2회 수정 요청)
        if let plan = rooms.first(where: { $0.id == roomID })?.plan {
            var currentPlan = plan
            let maxRevisions = 2
            var revisionCount = 0
            while true {
                guard !Task.isCancelled,
                      let planIdx = rooms.firstIndex(where: { $0.id == roomID }),
                      rooms[planIdx].isActive else { return }

                rooms[planIdx].transitionTo(.awaitingApproval)
                syncAgentStatuses()

                let stepsDesc = currentPlan.steps.enumerated().map { i, s in
                    let risk = s.riskLevel == .low ? "" : " [\(s.riskLevel.displayName)]"
                    return "\(i + 1). \(s.text)\(risk)"
                }.joined(separator: "\n")
                let approvalMsg = ChatMessage(
                    role: .system,
                    content: "실행 계획:\n\n\(stepsDesc)\n\n이 계획으로 진행하시겠습니까?",
                    messageType: .approvalRequest
                )
                appendMessage(approvalMsg, to: roomID)
                scheduleSave()

                let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = continuation
                }
                approvalContinuations.removeValue(forKey: roomID)
                guard !Task.isCancelled else { return }

                if approved {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.planning)
                    }
                    break
                }

                revisionCount += 1
                if revisionCount > maxRevisions {
                    let limitMsg = ChatMessage(
                        role: .system,
                        content: "수정 요청이 \(maxRevisions)회를 초과했습니다. 현재 계획으로 진행하시겠습니까?",
                        messageType: .approvalRequest
                    )
                    appendMessage(limitMsg, to: roomID)
                    let finalApproved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                        approvalContinuations[roomID] = cont
                    }
                    approvalContinuations.removeValue(forKey: roomID)
                    if finalApproved {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.planning)
                        }
                    } else {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.completed)
                            rooms[i].completedAt = Date()
                        }
                        syncAgentStatuses()
                        scheduleSave()
                        return
                    }
                    break
                }

                // 거부 → 피드백 반영 재계획
                let feedback = rooms.first(where: { $0.id == roomID })?
                    .messages.last(where: { $0.role == .user })?.content
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }
                let newPlan = await requestPlan(roomID: roomID, task: task, previousPlan: currentPlan, feedback: feedback)
                guard !Task.isCancelled else { return }
                if let p = newPlan {
                    currentPlan = p
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) { rooms[i].plan = p }
                } else {
                    break
                }
            }
        }
        scheduleSave()
    }

    /// Build 단계 (Plan C): Creator가 단계별 실행 — riskLevel별 정책 적용
    private func executeBuildPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let intent = rooms[idx].intent ?? .task

        // 계획이 없으면 기존 execute 폴백
        guard let plan = rooms[idx].plan else {
            if intent == .quickAnswer {
                await executeQuickAnswer(roomID: roomID, task: task)
            } else {
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            }
            return
        }

        // Plan C: step 단위 루프 — riskLevel별 정책
        let tracker = FileWriteTracker()

        rooms[idx].timerDurationSeconds = plan.estimatedSeconds
        rooms[idx].timerStartedAt = Date()
        rooms[idx].transitionTo(.inProgress)
        scheduleSave()

        for (stepIndex, step) in plan.steps.enumerated() {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { break }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].setCurrentStep(stepIndex)
            }

            // high-risk step → DeferredAction 생성, 실행하지 않음
            if step.riskLevel == .high {
                let deferred = DeferredAction(
                    id: UUID(),
                    toolName: "step_\(stepIndex + 1)",
                    arguments: ["text": .string(step.text)],
                    description: step.text,
                    riskLevel: .high,
                    previewContent: "[\(stepIndex + 1)/\(plan.steps.count)] \(step.text)",
                    status: .pending
                )
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].deferredActions.append(deferred)
                }
                let deferMsg = ChatMessage(
                    role: .system,
                    content: "⏸ 단계 \(stepIndex + 1) (high-risk): Deliver에서 승인 후 실행됩니다.\n→ \(step.text)",
                    messageType: .progress
                )
                appendMessage(deferMsg, to: roomID)
                scheduleSave()
                continue
            }

            // low/medium → 자동 실행
            await tracker.reset()
            let shortLabel = Self.shortenStepLabel(step.text)
            let progressMsg = ChatMessage(
                role: .system,
                content: shortLabel,
                messageType: .progress
            )
            appendMessage(progressMsg, to: roomID)

            let targetAgentIDs: [UUID]
            if let assignedID = step.assignedAgentID {
                targetAgentIDs = [assignedID]
            } else {
                let specialists = executingAgentIDs(in: roomID)
                let room = rooms.first(where: { $0.id == roomID })
                targetAgentIDs = specialists.isEmpty ? (room?.assignedAgentIDs ?? []) : specialists
            }

            // Build 단계: 도구 레벨 external deferring 활성화
            let deferCollector: (DeferredAction) -> Void = { [weak self] deferred in
                Task { @MainActor in
                    guard let self, let i = self.rooms.firstIndex(where: { $0.id == roomID }) else { return }
                    self.rooms[i].deferredActions.append(deferred)
                }
            }

            var failedAgentIDs: [UUID] = []
            await withTaskGroup(of: (UUID, Bool).self) { group in
                for agentID in targetAgentIDs {
                    group.addTask { [self] in
                        let success = await self.executeStep(
                            step: step.text,
                            fullTask: task,
                            agentID: agentID,
                            roomID: roomID,
                            stepIndex: stepIndex,
                            totalSteps: plan.steps.count,
                            fileWriteTracker: tracker,
                            progressGroupID: progressMsg.id,
                            deferHighRiskTools: true,
                            collectDeferred: deferCollector
                        )
                        return (agentID, success)
                    }
                }
                for await (agentID, success) in group {
                    if !success { failedAgentIDs.append(agentID) }
                }
            }

            // 실패한 에이전트 1회 재시도
            if !failedAgentIDs.isEmpty {
                var stillFailed: [UUID] = []
                for agentID in failedAgentIDs {
                    let success = await executeStep(
                        step: step.text,
                        fullTask: task,
                        agentID: agentID,
                        roomID: roomID,
                        stepIndex: stepIndex,
                        totalSteps: plan.steps.count,
                        fileWriteTracker: tracker,
                        progressGroupID: progressMsg.id,
                        deferHighRiskTools: true,
                        collectDeferred: deferCollector
                    )
                    if !success { stillFailed.append(agentID) }
                }
                failedAgentIDs = stillFailed
            }

            // 전원 실패 → 워크플로우 중단
            if failedAgentIDs.count == targetAgentIDs.count && !targetAgentIDs.isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let failMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1): 모든 에이전트 실패로 워크플로우를 중단합니다.",
                    messageType: .error
                )
                appendMessage(failMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }
        }
        scheduleSave()
    }

    /// Review 단계 (Plan C): Reviewer가 Build 결과물 검토
    private func executeReviewPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let room = rooms[idx]

        // reviewer 역할의 에이전트 찾기
        let reviewerName = room.agentRoles.first(where: { $0.value == .reviewer })?.key
        let reviewerAgent: Agent?
        if let name = reviewerName {
            reviewerAgent = agentStore?.agents.first(where: { $0.name == name })
        } else {
            let specialists = executingAgentIDs(in: roomID)
            if specialists.count >= 2 {
                reviewerAgent = agentStore?.agents.first(where: { $0.id == specialists[1] })
            } else {
                return  // 전문가 1명: review 스킵
            }
        }

        guard let reviewer = reviewerAgent,
              let reviewerProvider = providerManager?.provider(named: reviewer.providerName) else { return }

        // Creator 찾기 (fail 시 수정 요청용)
        let creatorName = room.agentRoles.first(where: { $0.value == .creator })?.key
        let creatorAgent = creatorName.flatMap { name in agentStore?.agents.first(where: { $0.name == name }) }
            ?? executingAgentIDs(in: roomID).first.flatMap { id in agentStore?.agents.first(where: { $0.id == id }) }

        let briefContext: String
        if let brief = room.taskBrief {
            briefContext = "목표: \(brief.goal)\n성공기준: \(brief.successCriteria.joined(separator: ", "))"
        } else {
            briefContext = room.clarifySummary ?? task
        }

        let maxRetries = 2
        var retryCount = 0

        while retryCount <= maxRetries {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            // Build 결과 수집
            let currentRoom = rooms.first(where: { $0.id == roomID })
            let recentMessages = (currentRoom?.messages ?? []).suffix(15)
            let buildOutput = recentMessages
                .filter { $0.role == .assistant }
                .compactMap { $0.content }
                .joined(separator: "\n---\n")

            guard !buildOutput.isEmpty else { return }

            let reviewPrompt = """
            \(reviewer.resolvedSystemPrompt)

            당신은 Review 단계의 Reviewer입니다.
            Build 결과물이 작업 목표와 성공기준을 충족하는지 검토하세요.

            \(briefContext)

            검토 후 반드시 첫 줄에 판정을 작성하세요:
            - PASS: 결과물이 기준을 충족함
            - FAIL: 핵심 기준 미충족, 수정 필요 (사유를 구체적으로 작성)

            간결하게 핵심만 작성하세요.
            """

            speakingAgentIDByRoom[roomID] = reviewer.id
            var reviewResult = ""
            do {
                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: reviewer.name), to: roomID)

                let buffer = StreamBuffer()
                reviewResult = try await reviewerProvider.sendMessageStreaming(
                    model: reviewer.modelName,
                    systemPrompt: reviewPrompt,
                    messages: [("user", "다음 결과물을 검토해주세요:\n\n\(buildOutput)")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: reviewResult, in: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "검토 오류: \(error.userFacingMessage)", agentName: reviewer.name, messageType: .error), to: roomID)
                break
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // Verdict 파싱
            let verdict = parseReviewVerdict(reviewResult)
            if verdict == .pass {
                break  // Review 통과
            }

            retryCount += 1
            if retryCount > maxRetries {
                // 최대 재시도 초과 → 사용자 에스컬레이션
                let escalateMsg = ChatMessage(
                    role: .system,
                    content: "Review \(maxRetries)회 실패. 사용자 확인이 필요합니다.\n\n사유: \(reviewResult.prefix(200))",
                    messageType: .approvalRequest
                )
                appendMessage(escalateMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingApproval)
                }
                syncAgentStatuses()
                scheduleSave()

                let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = cont
                }
                approvalContinuations.removeValue(forKey: roomID)
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.inProgress)
                }
                break
            }

            // FAIL → Creator에게 수정 요청
            guard let creator = creatorAgent,
                  let creatorProvider = providerManager?.provider(named: creator.providerName) else { break }

            let fixMsg = ChatMessage(
                role: .system,
                content: "Review 실패 (\(retryCount)/\(maxRetries)). Creator에게 수정을 요청합니다.",
                messageType: .progress
            )
            appendMessage(fixMsg, to: roomID)

            speakingAgentIDByRoom[roomID] = creator.id
            let fixPrompt = """
            \(creator.resolvedSystemPrompt)

            Reviewer가 결과물을 반려했습니다. 피드백을 반영하여 수정하세요.

            [Reviewer 피드백]
            \(reviewResult)

            수정된 결과물만 출력하세요.
            """

            do {
                let placeholderID = UUID()
                appendMessage(ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: creator.name), to: roomID)

                let buffer = StreamBuffer()
                let fixedOutput = try await creatorProvider.sendMessageStreaming(
                    model: creator.modelName,
                    systemPrompt: fixPrompt,
                    messages: [("user", "Reviewer 피드백을 반영하여 수정해주세요.")],
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in self.updateMessageContent(placeholderID, newContent: current, in: roomID) }
                    }
                )
                updateMessageContent(placeholderID, newContent: fixedOutput, in: roomID)
            } catch {
                appendMessage(ChatMessage(role: .assistant, content: "수정 오류: \(error.userFacingMessage)", agentName: creator.name, messageType: .error), to: roomID)
                break
            }
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            // 루프 → 다시 Review
        }
        scheduleSave()
    }

    /// Review verdict 파싱: PASS / FAIL
    private func parseReviewVerdict(_ text: String) -> ReviewVerdict {
        let upper = text.uppercased()
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let firstLineUpper = firstLine.uppercased()
        // PASS 계열
        if firstLineUpper.contains("PASS") || firstLine.contains("✅") || firstLine.contains("통과") || upper.hasPrefix("PASS") {
            return .pass
        }
        // FAIL 계열
        if firstLineUpper.contains("FAIL") || firstLine.contains("❌") || firstLine.contains("불합격") || firstLine.contains("실패") || upper.hasPrefix("FAIL") {
            return .fail
        }
        // 조건부 승인
        if firstLine.contains("⚠️") || text.contains("조건부 승인") || text.contains("조건부 통과") {
            return .pass
        }
        return .pass  // 불확실하면 pass
    }

    private enum ReviewVerdict {
        case pass, fail
    }

    /// Deliver 단계 (Plan C): 최종 전달 — high risk인 경우 Draft 프리뷰 + 명시 승인
    private func executeDeliverPhase(roomID: UUID, task: String) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let room = rooms[idx]

        // DeferredAction 처리 (high risk 도구 호출이 보류된 경우)
        if !room.deferredActions.isEmpty {
            let pending = room.deferredActions.filter { $0.status == .pending }
            if !pending.isEmpty {
                let deferredDesc = pending.enumerated().map { i, action in
                    var line = "\(i + 1). [\(action.riskLevel.displayName)] \(action.description)"
                    if let preview = action.previewContent, !preview.isEmpty {
                        line += "\n   \(preview)"
                    }
                    return line
                }.joined(separator: "\n")

                let approvalMsg = ChatMessage(
                    role: .system,
                    content: "보류된 작업 \(pending.count)건:\n\n\(deferredDesc)\n\n[승인] 실행 / [거부] 취소",
                    messageType: .approvalRequest
                )
                appendMessage(approvalMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.awaitingApproval)
                }
                syncAgentStatuses()
                scheduleSave()

                let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = cont
                }
                approvalContinuations.removeValue(forKey: roomID)

                if approved {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.inProgress)
                    }

                    // 승인된 deferred 도구 실제 실행
                    for action in pending {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }),
                           let j = rooms[i].deferredActions.firstIndex(where: { $0.id == action.id }) {
                            rooms[i].deferredActions[j].status = .approved
                        }

                        let execMsg = ChatMessage(
                            role: .system,
                            content: "▶ 실행 중: \(action.description)",
                            messageType: .progress
                        )
                        appendMessage(execMsg, to: roomID)

                        // step 기반 deferred (step_N) → executeStep으로 실행
                        if action.toolName.hasPrefix("step_") {
                            let stepText = action.arguments["text"]?.stringValue ?? action.description
                            let specialists = executingAgentIDs(in: roomID)
                            let agentID = specialists.first ?? room.assignedAgentIDs.first
                            if let agentID {
                                _ = await executeStep(
                                    step: stepText,
                                    fullTask: task,
                                    agentID: agentID,
                                    roomID: roomID,
                                    stepIndex: 0,
                                    totalSteps: 1,
                                    fileWriteTracker: nil,
                                    progressGroupID: execMsg.id
                                )
                            }
                        } else {
                            // 도구 기반 deferred → ToolExecutor로 직접 실행
                            let context = makeToolContext(
                                roomID: roomID,
                                currentAgentID: room.assignedAgentIDs.first
                            )
                            let toolCall = ToolCall(
                                id: UUID().uuidString,
                                toolName: action.toolName,
                                arguments: action.arguments
                            )
                            _ = await ToolExecutor.executeSingleTool(toolCall, context: context)
                        }

                        if let i = rooms.firstIndex(where: { $0.id == roomID }),
                           let j = rooms[i].deferredActions.firstIndex(where: { $0.id == action.id }) {
                            rooms[i].deferredActions[j].status = .executed
                        }
                        scheduleSave()
                    }
                } else {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        for j in rooms[i].deferredActions.indices where rooms[i].deferredActions[j].status == .pending {
                            rooms[i].deferredActions[j].status = .cancelled
                        }
                    }
                }
            }
        }

        // quickAnswer: deliver에서 실제 답변 실행 (requiredPhases에 execute 없음)
        if room.intent == .quickAnswer {
            await executeQuickAnswer(roomID: roomID, task: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }
        }

        // 최종 전달 메시지
        let deliverMsg = ChatMessage(
            role: .system,
            content: "작업이 완료되었습니다.",
            messageType: .phaseTransition
        )
        appendMessage(deliverMsg, to: roomID)
        scheduleSave()
    }

    /// Plan 단계: needsPlan=true일 때만 호출됨. 토론 → 계획 수립 → 승인 루프
    private func executePlanPhase(roomID: UUID, task: String, intent: WorkflowIntent) async {
        let specialistCount = executingAgentIDs(in: roomID).count

        if specialistCount >= 2 && intent.requiresDiscussion {
            // 전문가 2명 이상: 토론 → 브리핑
            let startMsg = ChatMessage(
                role: .system,
                content: "토론을 시작합니다. 참여자: \(specialistCount)명 | 합의 시 자동 종료"
            )
            appendMessage(startMsg, to: roomID)

            await executeDiscussion(roomID: roomID, topic: task)
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

            await generateBriefing(roomID: roomID, topic: task)
            guard !Task.isCancelled else { return }
        }
        // 전문가 1명: soloAnalysis 스킵 (requestPlan이 직접 분석)

        // 계획 수립 (PlanCard UI로 표시되므로 별도 메시지 불필요)
        var currentPlan = await requestPlan(roomID: roomID, task: task)
        guard !Task.isCancelled else { return }

        if let plan = currentPlan {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = plan
            }
        }

        // 승인 — 거부 시 피드백 → 재계획 무제한 루프
        if currentPlan != nil {
            while true {
                guard !Task.isCancelled,
                      let idx = rooms.firstIndex(where: { $0.id == roomID }),
                      rooms[idx].isActive else { return }

                rooms[idx].transitionTo(.awaitingApproval)
                syncAgentStatuses()

                let plan = currentPlan!
                let stepsDesc = plan.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
                let approvalMsg = ChatMessage(
                    role: .system,
                    content: "실행 계획:\n\n\(stepsDesc)\n\n이 순서대로 진행하시겠습니까?",
                    messageType: .approvalRequest
                )
                appendMessage(approvalMsg, to: roomID)
                pluginEventDelegate?(.approvalRequested(roomID: roomID, stepDescription: stepsDesc))
                scheduleSave()

                let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    approvalContinuations[roomID] = continuation
                }
                approvalContinuations.removeValue(forKey: roomID)
                guard !Task.isCancelled else { return }

                if approved {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.planning)
                    }
                    break
                }

                // 거부됨 — 피드백 추출 + 재계획
                let feedback = rooms.first(where: { $0.id == roomID })?
                    .messages.last(where: { $0.role == .user })?.content

                let replanMsg = ChatMessage(
                    role: .system,
                    content: "피드백을 반영하여 계획을 수정합니다..."
                )
                appendMessage(replanMsg, to: roomID)

                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.planning)
                }

                let newPlan = await requestPlan(roomID: roomID, task: task, previousPlan: currentPlan, feedback: feedback)
                guard !Task.isCancelled else { return }

                if let plan = newPlan {
                    currentPlan = plan
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].plan = plan
                    }
                } else {
                    // 재계획 실패
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.failed)
                        rooms[i].completedAt = Date()
                    }
                    syncAgentStatuses()
                    scheduleSave()
                    return
                }
            }
        }
        scheduleSave()
    }

    /// Execute 단계: quickAnswer 즉답 / task 토론+분석 또는 계획 기반 실행
    private func executeExecutePhase(roomID: UUID, task: String, intent: WorkflowIntent) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        if intent == .quickAnswer {
            // quickAnswer: 전문가 1명이 바로 답변
            await executeQuickAnswer(roomID: roomID, task: task)
        } else if rooms[idx].needsPlan {
            // task + needsPlan: 계획 기반 단계별 실행
            if rooms[idx].plan == nil {
                rooms[idx].plan = RoomPlan(summary: task, estimatedSeconds: 300, steps: [RoomStep(text: task)])
            }

            rooms[idx].timerDurationSeconds = rooms[idx].plan?.estimatedSeconds ?? 300
            rooms[idx].timerStartedAt = Date()
            rooms[idx].transitionTo(.inProgress)
            scheduleSave()

            await executeRoomWork(roomID: roomID, task: task)
        } else {
            // task + !needsPlan: 토론/분석 후 결과 정리
            let specialistCount = executingAgentIDs(in: roomID).count

            if specialistCount >= 2 && intent.requiresDiscussion {
                let startMsg = ChatMessage(
                    role: .system,
                    content: "토론을 시작합니다. 참여자: \(specialistCount)명 | 합의 시 자동 종료"
                )
                appendMessage(startMsg, to: roomID)

                await executeDiscussion(roomID: roomID, topic: task)
                guard !Task.isCancelled,
                      rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

                await generateBriefing(roomID: roomID, topic: task)
                guard !Task.isCancelled else { return }
            } else if specialistCount == 1 {
                await executeSoloAnalysis(roomID: roomID, task: task)
                guard !Task.isCancelled else { return }
            }

            // autoDocOutput 플래그가 설정된 경우 자동 문서화
            if let room = rooms.first(where: { $0.id == roomID }), room.autoDocOutput {
                await handleDocumentOutput(roomID: roomID, task: task, suggestedType: room.documentType)
            }
            scheduleSave()
        }
    }

    /// quickAnswer 실행: 최적 전문가 1명이 도구 포함 즉답 (전문가 없으면 마스터 폴백)
    private func executeQuickAnswer(roomID: UUID, task: String) async {
        let specialistIDs = executingAgentIDs(in: roomID)
        let room = rooms.first(where: { $0.id == roomID })

        // 라우팅: 멘션 우선 → 전문가 2명+ LLM 지명 → 첫 번째 전문가 → 마스터 폴백
        let candidateID: UUID?
        if let mentionedIDs = mentionedAgentIDsByRoom.removeValue(forKey: roomID),
           let firstMentioned = mentionedIDs.first {
            candidateID = firstMentioned
        } else if specialistIDs.count >= 2 {
            candidateID = await routeQuickAnswer(roomID: roomID, task: task, specialistIDs: specialistIDs)
                ?? specialistIDs.first
        } else {
            candidateID = specialistIDs.first ?? room?.assignedAgentIDs.first
        }

        guard let agentID = candidateID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.inProgress)
        }
        speakingAgentIDByRoom[roomID] = agentID

        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)
        var history: [ConversationMessage] = []
        if let intakeData = room?.intakeData, intakeData.sourceType != .text {
            history.append(ConversationMessage.user(intakeData.asClarifyContextString()))
        }
        if let workLog = rooms.first(where: { $0.id == roomID })?.workLog {
            history.append(ConversationMessage.user("[이전 작업 컨텍스트]\n\(workLog.asContextString())"))
        }
        history.append(contentsOf: buildRoomHistory(roomID: roomID))

        // 스트리밍용 placeholder 메시지
        let placeholderID = UUID()
        let placeholder = ChatMessage(
            id: placeholderID, role: .assistant, content: "",
            agentName: agent.name
        )
        appendMessage(placeholder, to: roomID)

        do {
            // 웹 검색 지침 추가: 모르는 내용은 반드시 검색 후 답변
            let searchPrompt = agent.resolvedSystemPrompt
                + "\n\n[웹 검색 지침] 답을 확실히 알지 못하거나 최신 정보가 필요한 질문은 반드시 WebSearch 도구로 검색한 후 답변하세요. 인터넷 밈, 슬랭, 브랜드, 제품명, 또는 익숙하지 않은 용어는 검색을 먼저 수행하세요."
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "답변을 작성하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { onToolActivity in
                let hasAttachments = history.contains { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }
                if let claudeProvider = provider as? ClaudeCodeProvider, !hasAttachments {
                    // ClaudeCodeProvider: CLI 자체 WebSearch 사용 (검색+읽기만 허용, 첨부 없을 때만)
                    let simple = history.compactMap { msg -> (role: String, content: String)? in
                        guard let content = msg.content else { return nil }
                        return (role: msg.role, content: content)
                    }
                    return try await claudeProvider.sendMessageWithSearch(
                        model: agent.modelName,
                        systemPrompt: searchPrompt,
                        messages: simple,
                        onToolActivity: onToolActivity
                    )
                } else {
                    // 다른 프로바이더: DOUGLAS 내장 도구 사용
                    let buffer = StreamBuffer()
                    return try await ToolExecutor.smartSend(
                        provider: provider,
                        agent: agent,
                        systemPrompt: searchPrompt,
                        conversationMessages: history,
                        context: context,
                        onToolActivity: onToolActivity,
                        onStreamChunk: { [weak self] chunk in
                            guard let self else { return }
                            let current = buffer.append(chunk)
                            Task { @MainActor in
                                self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                            }
                        },
                        allowedToolIDs: ["web_search", "web_fetch"]
                    )
                }
            }
            updateMessageContent(placeholderID, newContent: stripTrailingOptions(response), in: roomID)
        } catch {
            updateMessageContent(
                placeholderID,
                newContent: "오류: \(error.userFacingMessage)",
                in: roomID
            )
            if let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
               let msgIdx = rooms[roomIdx].messages.firstIndex(where: { $0.id == placeholderID }) {
                rooms[roomIdx].messages[msgIdx].messageType = .error
            }
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
    }

    /// 경량 라우팅: 마스터가 즉답에 최적인 전문가 1명을 지명
    /// LLM 1회 호출로 에이전트 이름만 반환받음. 실패 시 nil (호출측에서 첫 번째 폴백)
    private func routeQuickAnswer(roomID: UUID, task: String, specialistIDs: [UUID]) async -> UUID? {
        // 마스터 에이전트 + 프로바이더 확보
        guard let masterID = rooms.first(where: { $0.id == roomID })?.assignedAgentIDs.first,
              let master = agentStore?.agents.first(where: { $0.id == masterID }),
              let provider = providerManager?.provider(named: master.providerName) else { return nil }

        let roster = specialistIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })
        }.map { "- \($0.name): \($0.persona.prefix(60))" }.joined(separator: "\n")

        let prompt = """
        아래 전문가 중 이 질문에 가장 적합한 1명의 **이름만** 출력하세요. 다른 내용은 절대 출력하지 마세요.

        전문가:
        \(roster)

        질문: \(task)
        """

        do {
            let lightModel = providerManager?.lightModelName(for: master.providerName) ?? master.modelName
            let response = try await provider.sendMessage(
                model: lightModel,
                systemPrompt: "당신은 질문 라우터입니다. 전문가 이름만 한 줄로 출력하세요.",
                messages: [("user", prompt)]
            )
            let name = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "- ", with: "")
            return specialistIDs.first { id in
                agentStore?.agents.first(where: { $0.id == id })?.name == name
            }
        } catch {
            return nil
        }
    }

    /// 전문가 1명 Solo 분석: 토론 없이 혼자 분석하여 결과 공유 (전문가 없으면 마스터 폴백)
    private func executeSoloAnalysis(roomID: UUID, task: String) async {
        let specialistIDs = executingAgentIDs(in: roomID)
        let room = rooms.first(where: { $0.id == roomID })
        // 멘션 우선 → 첫 번째 전문가 → 마스터 폴백
        let candidateID: UUID?
        if let mentionedIDs = mentionedAgentIDsByRoom.removeValue(forKey: roomID),
           let firstMentioned = mentionedIDs.first {
            candidateID = firstMentioned
        } else {
            candidateID = specialistIDs.first ?? room?.assignedAgentIDs.first
        }
        guard let agentID = candidateID,
              let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        speakingAgentIDByRoom[roomID] = agentID

        // intake 데이터 (Jira 트리거 제거된 중립 버전)
        let intakeBlock: String
        if let intakeData = room?.intakeData, intakeData.sourceType != .text {
            intakeBlock = "\n" + intakeData.asClarifyContextString()
        } else {
            intakeBlock = ""
        }

        let soloPrompt = """
        \(agent.resolvedSystemPrompt)

        현재 작업방에서 아래 작업에 대해 혼자 분석합니다.
        \(intakeBlock)

        [작업]
        \(task)

        대화 히스토리를 참고하여 핵심 사항, 접근 방향, 주의점을 정리해주세요.
        작업과 무관한 내용을 절대 생성하지 마세요.
        """

        let history = buildRoomHistory(roomID: roomID)
        let context = makeToolContext(roomID: roomID, currentAgentID: agentID)

        // 스트리밍용 placeholder 메시지
        let placeholderID = UUID()
        let placeholder = ChatMessage(
            id: placeholderID, role: .assistant, content: "",
            agentName: agent.name
        )
        appendMessage(placeholder, to: roomID)

        do {
            let buffer = StreamBuffer()
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "사전 분석 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                try await ToolExecutor.smartSend(
                    provider: provider,
                    agent: agent,
                    systemPrompt: soloPrompt,
                    conversationMessages: history,
                    context: context,
                    onStreamChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in
                            self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                        }
                    },
                    useTools: false  // 소로 분석: 도구 없이 스트리밍 우선
                )
            }
            updateMessageContent(placeholderID, newContent: stripTrailingOptions(response), in: roomID)
        } catch {
            // 사전 분석 실패는 워크플로우에 영향 없음 — placeholder를 조용히 제거
            if let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
               let msgIdx = rooms[roomIdx].messages.firstIndex(where: { $0.id == placeholderID }) {
                rooms[roomIdx].messages.remove(at: msgIdx)
            }
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
    }

    /// 플레이북 override 감지 (완료 후 호출)
    private func detectPlaybookOverrides(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let playbook = room.playbook,
              room.primaryProjectPath != nil else { return }

        let workSummary = room.workLog?.outcome ?? ""
        var overrides: [String] = []

        if let branchPattern = playbook.branchPattern, !branchPattern.isEmpty,
           (workSummary.contains("branch") || workSummary.contains("브랜치")) {
            overrides.append("브랜치 패턴 변경 감지 (설정: \(branchPattern))")
        }

        if !overrides.isEmpty {
            let overrideMsg = ChatMessage(
                role: .system,
                content: "플레이북과 다른 패턴이 감지되었습니다:\n" + overrides.map { "- \($0)" }.joined(separator: "\n") + "\n\n플레이북을 업데이트하시겠습니까?"
            )
            appendMessage(overrideMsg, to: roomID)
        }
        scheduleSave()
    }

    // MARK: - Intake 헬퍼

    /// 텍스트에서 URL 추출
    private func extractURLs(from text: String) -> [String] {
        let pattern = "https?://[^\\s]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    /// 텍스트에서 모든 Jira 키 추출 (중복 제거, 순서 유지)
    private func extractJiraKeys(from text: String) -> [String] {
        let pattern = "[A-Z][A-Z0-9]+-\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var keys: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let key = String(text[r])
            if seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    /// 여러 Jira URL에서 티켓 요약을 동시 fetch
    private func fetchJiraTicketSummaries(urls: [String]) async -> [JiraTicketSummary] {
        await withTaskGroup(of: JiraTicketSummary?.self, returning: [JiraTicketSummary].self) { group in
            for urlString in urls {
                group.addTask { [self] in
                    await self.fetchSingleJiraTicket(urlString: urlString)
                }
            }
            var results: [JiraTicketSummary] = []
            for await result in group {
                if let ticket = result { results.append(ticket) }
            }
            return results
        }
    }

    /// 단일 Jira URL에서 티켓 요약 fetch
    private func fetchSingleJiraTicket(urlString: String) async -> JiraTicketSummary? {
        let jiraConfig = JiraConfig.shared
        let apiURLString = jiraConfig.apiURL(from: urlString)
        guard let apiURL = URL(string: apiURLString),
              let auth = jiraConfig.authHeader() else { return nil }

        var request = URLRequest(url: apiURL)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let fields = json["fields"] as? [String: Any] ?? [:]
            let key = json["key"] as? String ?? ""
            let summary = fields["summary"] as? String ?? ""
            let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? ""
            let statusName = (fields["status"] as? [String: Any])?["name"] as? String ?? ""
            let description = extractDescription(from: fields["description"])

            return JiraTicketSummary(
                key: key,
                summary: summary,
                issueType: issueType,
                status: statusName,
                description: description
            )
        } catch {
            return nil
        }
    }

    /// Jira ADF(Atlassian Document Format) 또는 일반 텍스트에서 설명 추출
    private func extractDescription(from value: Any?) -> String {
        if let text = value as? String { return text }
        guard let adf = value as? [String: Any],
              let content = adf["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { node -> String? in
            guard let innerContent = node["content"] as? [[String: Any]] else { return nil }
            return innerContent.compactMap { inner -> String? in
                inner["text"] as? String
            }.joined()
        }.joined(separator: "\n")
    }

    /// 에이전트에게 계획 수립 요청
    private func requestPlan(roomID: UUID, task: String, previousPlan: RoomPlan? = nil, feedback: String? = nil, designOutput: String? = nil) async -> RoomPlan? {
        guard let room = rooms.first(where: { $0.id == roomID }) else {
            return nil
        }
        // 전문가(마스터 제외)를 계획 생성자로 선택
        let specialistID = room.assignedAgentIDs.first { id in
            guard let a = agentStore?.agents.first(where: { $0.id == id }) else { return false }
            return !(a.isMaster)
        } ?? room.assignedAgentIDs.first
        guard let firstAgentID = specialistID,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            let errorMsg = ChatMessage(
                role: .system,
                content: "에이전트 또는 API 연결을 찾을 수 없습니다."
            )
            appendMessage(errorMsg, to: roomID)
            return nil
        }

        // intake 데이터 (Jira 트리거 제거된 중립 버전)
        let intakeContext: String
        if let intakeData = room.intakeData {
            intakeContext = "\n" + intakeData.asClarifyContextString()
        } else {
            intakeContext = ""
        }

        // 브리핑 + 산출물 기반 컨텍스트 구성 (압축)
        let briefingContext: String
        if let briefing = room.briefing {
            briefingContext = briefing.asContextString()
        } else {
            // 폴백: 기존 토론 히스토리에서 요약 생성
            let history = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
            briefingContext = history.map { "[\($0.role)] \($0.content)" }.suffix(10).joined(separator: "\n")
        }

        let artifactContext: String
        if !room.artifacts.isEmpty {
            // 계획 수립용: 산출물 프리뷰만 전달 (토큰 절감, 전체 내용은 실행 단계에서 사용)
            artifactContext = "\n\n[참고 산출물]\n" + room.artifacts.map {
                let preview = $0.content.prefix(200)
                let suffix = $0.content.count > 200 ? "... (\($0.content.count)자)" : ""
                return "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\(preview)\(suffix)"
            }.joined(separator: "\n---\n")
        } else {
            artifactContext = ""
        }

        // 플레이북 컨텍스트 주입
        let playbookContext: String
        if let playbook = room.playbook {
            playbookContext = "\n\n[프로젝트 플레이북]\n" + playbook.asContextString()
        } else {
            playbookContext = ""
        }

        // 방 내 전문가 목록 (마스터 제외)
        let specialistNames: String
        let specialists = room.assignedAgentIDs.compactMap { id -> String? in
            guard let agent = agentStore?.agents.first(where: { $0.id == id }) else { return nil }
            if agent.isMaster { return nil }
            return agent.name
        }
        specialistNames = specialists.isEmpty ? "(없음)" : specialists.joined(separator: ", ")

        // 원래 사용자 요청 앵커링
        let clarifyContext: String
        if let summary = room.clarifySummary {
            clarifyContext = "\n[원래 사용자 요청]\n\(summary)\n"
        } else {
            clarifyContext = ""
        }

        // 문서 유형 템플릿 주입
        let docTemplateContext = room.documentType?.templatePromptBlock() ?? ""

        let planSystemPrompt = """
        \(agent.resolvedSystemPrompt)
        \(intakeContext)\(clarifyContext)\(docTemplateContext.isEmpty ? "" : "\n\(docTemplateContext)\n")
        현재 작업방에 배정되었습니다. 팀원들과의 토론이 완료되었습니다.
        토론 내용을 바탕으로, 원래 사용자 요청 범위 안에서 실행 계획을 제출하세요:

        {"plan": {"summary": "전체 계획 요약", "estimated_minutes": 5, "steps": [{"text": "단계 설명", "agent": "담당 에이전트 이름"}, ...]}}

        방 내 전문가: \(specialistNames)

        규칙:
        - 각 단계는 **한 가지 명확한 산출물**을 가져야 합니다 (코드 작성, 테스트, PR 오픈 등).
        - 사용자 검수/승인이 필요한 지점마다 반드시 새 단계를 시작하세요.
        - 구현, PR 오픈, 코드 리뷰, 배포 등은 **반드시 별개 단계**로 분할하세요.
        - 번역, 요약, 분석 등 단일 작업은 1단계로 작성하세요.
        - 같은 에이전트가 연속 수행해도, 산출물이 다르면 단계를 나누세요.
        - estimated_minutes는 현실적으로 추정하세요 (1~30분)
        - 각 step에 "agent" 필드로 담당 전문가를 지정하세요 (위 목록에서 정확한 이름 사용)
        - 마스터(진행자/오케스트레이터)는 실행 대상이 아닙니다. 마스터에게 step을 배정하지 마세요.
        - "requires_approval": true는 **외부에 영향을 미치거나 되돌리기 어려운 모든 작업**에 반드시 사용하세요. 예: 커밋, PR, push, 배포, DB 변경, API 호출, 메시지 전송, 파일 삭제 등. 코드 분석, 파일 읽기 등 읽기 전용 작업에는 불필요합니다.
        - 반드시 유효한 JSON으로만 응답하세요
        """

        // 첨부 파일 정보 포함 (첨부된 내용을 "확인하라"는 불필요한 단계 방지)
        let attachmentContext: String
        let fileAttachments = room.messages
            .compactMap { $0.attachments }
            .flatMap { $0 }
        if !fileAttachments.isEmpty {
            let imageCount = fileAttachments.filter { $0.isImage }.count
            let docCount = fileAttachments.count - imageCount
            var desc = "사용자 첨부 파일 \(fileAttachments.count)개"
            if imageCount > 0 && docCount > 0 {
                desc += " (이미지 \(imageCount)장, 문서 \(docCount)개)"
            } else if imageCount > 0 {
                desc += " (이미지 \(imageCount)장)"
            } else {
                desc += " (문서 \(docCount)개)"
            }
            attachmentContext = "\n\n[\(desc) — 이미 제공됨]\n" +
                "(파일이 이미 제공되었으므로, 사용자에게 다시 요청하지 마세요. 바로 작업하세요. 계획의 step에 파일 경로를 포함하지 마세요.)"
        } else {
            attachmentContext = ""
        }

        // 재계획 컨텍스트 (이전 계획이 거부된 경우)
        var replanContext = ""
        if let prev = previousPlan {
            let prevSteps = prev.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            replanContext = "\n\n[이전 계획 — 사용자가 거부함]\n\(prev.summary)\n단계:\n\(prevSteps)"
            if let fb = feedback, !fb.isEmpty {
                replanContext += "\n\n[사용자 피드백]\n\(fb)\n\n위 피드백을 반영하여 계획을 다시 수립하세요."
            } else {
                replanContext += "\n\n사용자가 이전 계획을 거부했습니다. 다른 접근 방식으로 계획을 다시 수립하세요."
            }
        }

        // Design 단계 결과가 있으면 해당 텍스트를 직접 구조화
        let designContext = designOutput.map { "\n\n[Design 단계 결과]\n\($0)\n\n위 설계 결과를 JSON 형식의 실행 계획으로 변환하세요." } ?? ""

        let planMessages: [(role: String, content: String)] = [
            ("user", "브리핑:\n\(briefingContext)\(artifactContext)\(playbookContext)\(attachmentContext)\(replanContext)\(designContext)\n\n실행 계획을 JSON으로 작성해주세요. 작업: \(task)")
        ]

        speakingAgentIDByRoom[roomID] = firstAgentID

        do {
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "계획을 수립하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                // sendRouterMessage: 도구 비활성화 (계획 수립 중 파일 수정/셸 실행 방지)
                try await provider.sendRouterMessage(
                    model: agent.modelName,
                    systemPrompt: planSystemPrompt,
                    messages: planMessages
                )
            }

            speakingAgentIDByRoom.removeValue(forKey: roomID)
            return parsePlan(from: response)
        } catch {
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "계획 수립 실패: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return nil
        }
    }

    /// 계획 JSON 파싱
    private func parsePlan(from response: String) -> RoomPlan? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let planDict = json["plan"] as? [String: Any],
              let summary = planDict["summary"] as? String,
              let estimatedMinutes = planDict["estimated_minutes"] as? Int,
              let rawSteps = planDict["steps"] as? [Any] else {
            return nil
        }

        // 에이전트 이름 → ID 매핑 (퍼지 매칭)
        let agentNameToID: [String: UUID] = {
            guard let agents = agentStore?.subAgents else { return [:] }
            var map: [String: UUID] = [:]
            for agent in agents {
                map[agent.name.lowercased()] = agent.id
            }
            return map
        }()

        func resolveAgentID(name: String?) -> UUID? {
            guard let name = name?.lowercased() else { return nil }
            if let id = agentNameToID[name] { return id }
            // 부분 매칭
            return agentNameToID.first(where: { $0.key.contains(name) || name.contains($0.key) })?.value
        }

        // steps: plain String과 {"text":"...", "agent":"...", "requires_approval": true} 혼합 지원
        var steps: [RoomStep] = []
        for raw in rawSteps {
            if let str = raw as? String {
                steps.append(RoomStep(text: str))
            } else if let dict = raw as? [String: Any], let text = dict["text"] as? String {
                let requiresApproval = dict["requires_approval"] as? Bool ?? false
                let agentName = dict["agent"] as? String
                let agentID = resolveAgentID(name: agentName)
                let riskLevel: RiskLevel
                if let rl = dict["risk_level"] as? String {
                    riskLevel = RiskLevel(rawValue: rl) ?? .low
                } else {
                    riskLevel = .low
                }
                steps.append(RoomStep(text: text, requiresApproval: requiresApproval, assignedAgentID: agentID, riskLevel: riskLevel))
            }
        }
        guard !steps.isEmpty else { return nil }

        return RoomPlan(
            summary: summary,
            estimatedSeconds: estimatedMinutes * 60,
            steps: steps
        )
    }

    /// JSON 추출 (ChatViewModel.extractJSON과 동일 로직)
    private func extractJSON(from text: String) -> String {
        // 뒤에서부터 검색하여 중첩 코드블록(```json 안의 ```) 잘림 방지
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", options: .backwards, range: startRange.upperBound..<text.endIndex),
           endRange.lowerBound > startRange.upperBound {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = text.range(of: "```\n"),
           let endRange = text.range(of: "\n```", options: .backwards, range: startRange.upperBound..<text.endIndex),
           endRange.lowerBound > startRange.upperBound {
            return String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    /// 방의 단계별 작업 실행
    private func executeRoomWork(roomID: UUID, task: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let plan = room.plan else { return }

        // 병렬 실행 시 파일 충돌 추적용
        let tracker = FileWriteTracker()
        // 이전 단계 응답 추적 (반복 감지용)
        var previousStepResponse: String?

        for (stepIndex, step) in plan.steps.enumerated() {
            // 취소 또는 방 삭제 감지
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { break }

            // 현재 단계 업데이트 (승인 게이트 전에 호출 → 이전 단계들이 체크 표시됨)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].setCurrentStep(stepIndex)
            }

            // 승인 게이트: requiresApproval인 단계에서 일시 정지 (거절 시 피드백 → 재수행 루프)
            if step.requiresApproval {
                var stepFeedback: String?
                var approvalLoop = true
                while approvalLoop {
                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].transitionTo(.awaitingApproval)
                        rooms[i].pendingApprovalStepIndex = stepIndex
                    }
                    syncAgentStatuses()

                    let prompt = stepFeedback != nil
                        ? "[\(stepIndex + 1)/\(plan.steps.count)] 피드백을 반영하여 재수행합니다. 승인하시겠습니까?"
                        : "[\(stepIndex + 1)/\(plan.steps.count)] \"\(step.text)\" — 이 단계는 승인이 필요합니다."
                    let approvalMsg = ChatMessage(
                        role: .system,
                        content: prompt,
                        messageType: .approvalRequest
                    )
                    appendMessage(approvalMsg, to: roomID)
                    pluginEventDelegate?(.approvalRequested(roomID: roomID, stepDescription: step.text))
                    scheduleSave()

                    // 자동 승인 타이머: 15초 후 자동 승인 (사용자 개입 시 취소)
                    startReviewAutoApproval(roomID: roomID, seconds: 15)

                    let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        approvalContinuations[roomID] = continuation
                    }
                    approvalContinuations.removeValue(forKey: roomID)

                    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[i].pendingApprovalStepIndex = nil
                    }

                    if approved {
                        // 승인됨 → inProgress 복귀
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.inProgress)
                        }
                        let resumeMsg = ChatMessage(
                            role: .system,
                            content: "단계 \(stepIndex + 1) 승인됨. 실행을 계속합니다."
                        )
                        appendMessage(resumeMsg, to: roomID)
                        approvalLoop = false
                    } else {
                        // 거절 → 마지막 사용자 메시지를 피드백으로 사용
                        let feedback = rooms.first(where: { $0.id == roomID })?
                            .messages.last(where: { $0.role == .user })?.content ?? ""

                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.inProgress)
                        }

                        stepFeedback = feedback

                        let retryMsg = ChatMessage(
                            role: .system,
                            content: "피드백을 반영하여 단계 \(stepIndex + 1)을 재수행합니다.",
                            messageType: .progress
                        )
                        appendMessage(retryMsg, to: roomID)

                        // 단계 재수행 (피드백 포함된 히스토리로)
                        let targetAgentIDs: [UUID]
                        if let assignedID = step.assignedAgentID {
                            targetAgentIDs = [assignedID]
                        } else {
                            let specialists = executingAgentIDs(in: roomID)
                            targetAgentIDs = specialists.isEmpty ? (rooms.first(where: { $0.id == roomID })?.assignedAgentIDs ?? []) : specialists
                        }
                        for agentID in targetAgentIDs {
                            _ = await executeStep(
                                step: step.text + "\n\n[사용자 피드백] \(feedback)",
                                fullTask: task,
                                agentID: agentID,
                                roomID: roomID,
                                stepIndex: stepIndex,
                                totalSteps: plan.steps.count,
                                fileWriteTracker: tracker,
                                progressGroupID: retryMsg.id
                            )
                        }
                        // 루프 → 다시 승인 요청
                    }
                }
            }

            // 단계별 충돌 추적 초기화
            await tracker.reset()

            // 진행률 메시지: 짧은 "~하는 중" 스타일
            let shortLabel = Self.shortenStepLabel(step.text)
            let progressMsg = ChatMessage(
                role: .system,
                content: shortLabel,
                messageType: .progress
            )
            appendMessage(progressMsg, to: roomID)

            // 실행 대상: 마스터 제외, 전문가만
            let targetAgentIDs: [UUID]
            if let assignedID = step.assignedAgentID {
                targetAgentIDs = [assignedID]
            } else {
                let specialists = executingAgentIDs(in: roomID)
                targetAgentIDs = specialists.isEmpty ? room.assignedAgentIDs : specialists
            }

            // 에이전트 실행 — 실패 시 1회 재시도, 전원 실패만 워크플로우 중단
            var failedAgentIDs: [UUID] = []
            await withTaskGroup(of: (UUID, Bool).self) { group in
                for agentID in targetAgentIDs {
                    group.addTask { [self] in
                        let success = await self.executeStep(
                            step: step.text,
                            fullTask: task,
                            agentID: agentID,
                            roomID: roomID,
                            stepIndex: stepIndex,
                            totalSteps: plan.steps.count,
                            fileWriteTracker: tracker,
                            progressGroupID: progressMsg.id
                        )
                        return (agentID, success)
                    }
                }
                for await (agentID, success) in group {
                    if !success { failedAgentIDs.append(agentID) }
                }
            }

            // 실패한 에이전트 1회 재시도
            if !failedAgentIDs.isEmpty {
                var stillFailed: [UUID] = []
                for agentID in failedAgentIDs {
                    let retryMsg = ChatMessage(
                        role: .system,
                        content: "에이전트 재시도 중...",
                        agentName: agentStore?.agents.first(where: { $0.id == agentID })?.name,
                        messageType: .progress
                    )
                    appendMessage(retryMsg, to: roomID)
                    let success = await executeStep(
                        step: step.text,
                        fullTask: task,
                        agentID: agentID,
                        roomID: roomID,
                        stepIndex: stepIndex,
                        totalSteps: plan.steps.count,
                        fileWriteTracker: tracker,
                        progressGroupID: progressMsg.id
                    )
                    if !success { stillFailed.append(agentID) }
                }
                failedAgentIDs = stillFailed
            }

            let succeededCount = targetAgentIDs.count - failedAgentIDs.count

            // 전원 실패 → 워크플로우 중단 (에이전트가 있었는데 전부 실패한 경우만)
            if succeededCount == 0 && !targetAgentIDs.isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].transitionTo(.failed)
                    rooms[i].completedAt = Date()
                }
                let failMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1): 모든 에이전트 실패로 워크플로우를 중단합니다.",
                    messageType: .error
                )
                appendMessage(failMsg, to: roomID)
                syncAgentStatuses()
                scheduleSave()
                return
            }

            // 일부 실패 → 경고 후 계속 진행
            if !failedAgentIDs.isEmpty {
                let failedNames = failedAgentIDs.compactMap { id in
                    agentStore?.agents.first(where: { $0.id == id })?.name
                }.joined(separator: ", ")
                let warnMsg = ChatMessage(
                    role: .system,
                    content: "단계 \(stepIndex + 1): \(failedNames) 실패 (재시도 포함). 나머지 에이전트로 계속 진행합니다.",
                    messageType: .error
                )
                appendMessage(warnMsg, to: roomID)
            }

            // 충돌 감지 경고
            let conflicts = await tracker.getConflicts()
            if !conflicts.isEmpty {
                let conflictPaths = conflicts.map { $0.path }.joined(separator: ", ")
                let warnMsg = ChatMessage(
                    role: .system,
                    content: "⚠️ 파일 충돌 감지: \(conflictPaths). 에이전트 간 동일 파일 수정 발생.",
                    messageType: .error
                )
                appendMessage(warnMsg, to: roomID)
            }

            // 연속 응답 유사도 감지: 에이전트가 같은 응답을 반복하면 중단
            if let currentRoom = rooms.first(where: { $0.id == roomID }) {
                let latestResponse = currentRoom.messages
                    .last(where: { $0.role == .assistant && ($0.messageType == .text || $0.messageType == .toolActivity) })?
                    .content ?? ""
                if let prev = previousStepResponse, !prev.isEmpty, !latestResponse.isEmpty {
                    let similarity = Self.wordOverlapSimilarity(prev, latestResponse)
                    if similarity > 0.6 {
                        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[i].transitionTo(.failed)
                            rooms[i].completedAt = Date()
                        }
                        let stuckMsg = ChatMessage(
                            role: .system,
                            content: "에이전트가 동일한 응답을 반복하여 워크플로우를 중단합니다.",
                            messageType: .error
                        )
                        appendMessage(stuckMsg, to: roomID)
                        syncAgentStatuses()
                        scheduleSave()
                        return
                    }
                }
                previousStepResponse = latestResponse
            }

            // 단계 완료 후 리뷰 게이트: 모든 단계에서 자동 승인 (사용자 개입 가능)
            do {
                var stepApproved = false
                while !stepApproved {
                    guard !Task.isCancelled,
                          let idx = rooms.firstIndex(where: { $0.id == roomID }),
                          rooms[idx].isActive else { return }

                    rooms[idx].transitionTo(.awaitingApproval)
                    rooms[idx].pendingApprovalStepIndex = stepIndex
                    syncAgentStatuses()

                    let reviewMsg = ChatMessage(
                        role: .system,
                        content: "[\(stepIndex + 1)/\(plan.steps.count)] \"\(step.text)\" 완료 — 결과를 확인해주세요.",
                        messageType: .approvalRequest
                    )
                    appendMessage(reviewMsg, to: roomID)
                    scheduleSave()
                    pluginEventDelegate?(.approvalRequested(roomID: roomID, stepDescription: step.text))

                    // 자동 승인 타이머: 15초 후 자동 승인 (사용자 개입 시 취소)
                    startReviewAutoApproval(roomID: roomID, seconds: 15)

                    let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        approvalContinuations[roomID] = continuation
                    }
                    approvalContinuations.removeValue(forKey: roomID)

                    if let idx2 = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[idx2].pendingApprovalStepIndex = nil
                    }

                    guard !Task.isCancelled else { return }

                    if approved {
                        stepApproved = true
                        if let idx2 = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[idx2].transitionTo(.inProgress)
                        }
                        let isLastStep = stepIndex == plan.steps.count - 1
                        let okMsg = ChatMessage(
                            role: .system,
                            content: isLastStep
                                ? "단계 \(stepIndex + 1) 확인. 작업을 완료합니다."
                                : "단계 \(stepIndex + 1) 확인. 다음 단계로 진행합니다."
                        )
                        appendMessage(okMsg, to: roomID)
                    } else {
                        // 거부 — 사용자 피드백을 반영하여 같은 단계 재실행
                        let feedback = rooms.first(where: { $0.id == roomID })?
                            .messages.last(where: { $0.role == .user })?.content ?? ""

                        let retryNotice = ChatMessage(
                            role: .system,
                            content: "피드백을 반영하여 단계 \(stepIndex + 1)을 다시 실행합니다."
                        )
                        appendMessage(retryNotice, to: roomID)

                        if let idx2 = rooms.firstIndex(where: { $0.id == roomID }) {
                            rooms[idx2].transitionTo(.inProgress)
                        }

                        // 피드백이 반영된 단계 텍스트로 재실행
                        let revisedStep = feedback.isEmpty
                            ? step.text
                            : "\(step.text)\n\n[사용자 피드백] \(feedback)\n위 피드백을 반영하여 다시 작업하세요. 이전 결과의 문제점을 수정해주세요."

                        let retryProgressMsg = ChatMessage(
                            role: .system,
                            content: Self.shortenStepLabel(step.text) + " (재작업)",
                            messageType: .progress
                        )
                        appendMessage(retryProgressMsg, to: roomID)

                        await tracker.reset()
                        for agentID in targetAgentIDs {
                            _ = await executeStep(
                                step: revisedStep,
                                fullTask: task,
                                agentID: agentID,
                                roomID: roomID,
                                stepIndex: stepIndex,
                                totalSteps: plan.steps.count,
                                fileWriteTracker: tracker,
                                progressGroupID: retryProgressMsg.id
                            )
                        }
                    }
                }
            }
        }

        // 완료: 먼저 상태 변경 후 작업일지 생성 (상태가 inProgress인 동안 추가 메시지가 묻히는 문제 방지)
        if rooms.first(where: { $0.id == roomID })?.status == .inProgress {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.completed)
                rooms[i].completedAt = Date()
            }
            // 에이전트 수 스냅샷 (다음 후속 사이클에서 변동 감지용)
            previousCycleAgentCount[roomID] = executingAgentIDs(in: roomID).count
            syncAgentStatuses()

            let doneMsg = ChatMessage(role: .system, content: "모든 작업이 완료되었습니다.")
            appendMessage(doneMsg, to: roomID)
            scheduleSave()

            // 작업일지는 방 상태 확정 후 비동기 생성
            await generateWorkLog(roomID: roomID, task: task)
        } else {
            syncAgentStatuses()
            scheduleSave()
        }
    }

    /// 외부 영향(되돌리기 어려운) 키워드 감지 — 리뷰 게이트 강제 트리거
    static func hasExternalEffectKeywords(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = ["pr ", "pull request", "push", "배포", "deploy", "merge", "릴리스", "release", "git push"]
        return keywords.contains { lower.contains($0) }
    }

    /// step 텍스트를 짧은 "~하는 중" 스타일로 변환
    static func shortenStepLabel(_ text: String) -> String {
        // 핵심 키워드 추출: 첫 번째 의미 있는 동사/명사 구문
        let cleaned = text
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // 긴 텍스트면 첫 문장/절만 사용 (마침표, 쉼표, 줄바꿈 기준)
        let firstClause: String
        if let range = cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: ".,\n")) {
            firstClause = String(cleaned[cleaned.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        } else {
            firstClause = cleaned
        }

        // 최대 40자로 자르고 "하는 중" 접미사
        let maxLen = 40
        let truncated: String
        if firstClause.count > maxLen {
            truncated = String(firstClause.prefix(maxLen)) + "…"
        } else {
            truncated = firstClause
        }

        // 이미 "~중" 으로 끝나면 그대로 반환
        if truncated.hasSuffix("중") {
            return truncated
        }

        return "\(truncated) 하는 중…"
    }

    /// 개별 에이전트의 단계 실행. 성공 시 true, 실패 시 false.
    @discardableResult
    private func executeStep(
        step: String,
        fullTask: String,
        agentID: UUID,
        roomID: UUID,
        stepIndex: Int,
        totalSteps: Int,
        fileWriteTracker: FileWriteTracker? = nil,
        progressGroupID: UUID? = nil,
        deferHighRiskTools: Bool = false,
        collectDeferred: ((DeferredAction) -> Void)? = nil
    ) async -> Bool {
        guard let baseAgent = agentStore?.agents.first(where: { $0.id == agentID }) else { return false }
        let agent = baseAgent
        guard let provider = providerManager?.provider(named: agent.providerName) else { return false }

        let room = rooms.first(where: { $0.id == roomID })

        // 브리핑 기반 컨텍스트 (압축) + 최근 메시지 + 첫 사용자 메시지(이미지 포함) 보장
        var history: [ConversationMessage] = []
        if let intakeData = room?.intakeData, intakeData.sourceType != .text {
            history.append(ConversationMessage.user(intakeData.asClarifyContextString()))
        }
        if let briefing = room?.briefing {
            history.append(ConversationMessage.user("작업 브리핑:\n\(briefing.asContextString())"))
        }

        // 첫 사용자 메시지(이미지 첨부 포함)를 항상 포함
        let recentHistory = buildRoomHistory(roomID: roomID, limit: 5)
        if let room = room,
           let firstUserMsg = room.messages.first(where: { $0.role == .user && $0.messageType == .text }),
           firstUserMsg.attachments != nil && !(firstUserMsg.attachments?.isEmpty ?? true),
           !recentHistory.contains(where: { $0.attachments != nil && !($0.attachments?.isEmpty ?? true) }) {
            history.append(ConversationMessage(
                role: "user", content: firstUserMsg.content,
                toolCalls: nil, toolCallID: nil, attachments: firstUserMsg.attachments,
                isError: false
            ))
        }
        history.append(contentsOf: recentHistory)

        // 산출물 컨텍스트 구성
        let artifactContext: String
        if let room = room, !room.artifacts.isEmpty {
            artifactContext = "\n\n[참고 산출물]\n" + room.artifacts.map {
                "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\($0.content)"
            }.joined(separator: "\n---\n")
        } else {
            artifactContext = ""
        }

        // 문서 유형 템플릿 (documentType 설정 시 섹션 가이드 주입)
        let docTemplateBlock: String
        if let docType = room?.documentType, docType != .freeform {
            docTemplateBlock = "\n" + docType.templatePromptBlock()
        } else {
            docTemplateBlock = ""
        }
        let isDocumentation = room?.documentType != nil

        let isLastStep = stepIndex == totalSteps - 1
        let stepPrompt: String
        if isLastStep || totalSteps == 1 {
            let docWriteInstruction = isDocumentation ? """

            [중요 — 문서 작성 지침]
            이전 대화의 분석·요약은 참고 자료일 뿐입니다.
            완전한 문서를 처음부터 끝까지 빠짐없이 작성하세요.
            "이미 완성되었습니다", "추가 작업이 필요하신가요?" 등의 응답은 금지합니다.
            반드시 전체 문서 본문을 출력하세요.
            """ : ""

            stepPrompt = """
            [작업 \(stepIndex + 1)/\(totalSteps)] \(step)
            \(artifactContext)\(docTemplateBlock)\(docWriteInstruction)

            이것이 최종 단계입니다. 사용자에게 전달할 완성된 결과물을 직접 작성하세요.
            과정 설명이나 단계 번호 없이, 결과물만 깔끔하게 출력하세요.
            """
        } else {
            stepPrompt = """
            [작업 \(stepIndex + 1)/\(totalSteps)] \(step)
            \(artifactContext)\(docTemplateBlock)

            중간 단계입니다. 다음 단계에 필요한 핵심 데이터만 간결하게 출력하세요 (3줄 이내).
            전체 결과물은 마지막 단계에서 작성합니다.
            """
        }

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            // 실행 시작 시각 (완료 활동에서 소요 시간 계산용)
            let stepStartTime = Date()

            // 단계 시작 활동: 어떤 작업을 수행하는지 표시
            if let progressGroupID {
                let stepLabel = step.count > 60 ? String(step.prefix(57)) + "..." : step
                let startDetail = ToolActivityDetail(
                    toolName: "llm_call",
                    subject: "[\(stepIndex + 1)/\(totalSteps)] \(stepLabel)",
                    contentPreview: nil,
                    isError: false
                )
                let startMsg = ChatMessage(
                    role: .assistant,
                    content: stepLabel,
                    agentName: agent.name,
                    messageType: .toolActivity,
                    activityGroupID: progressGroupID,
                    toolDetail: startDetail
                )
                appendMessage(startMsg, to: roomID)
            }

            let context = makeToolContext(roomID: roomID, currentAgentID: agentID, fileWriteTracker: fileWriteTracker, deferHighRiskTools: deferHighRiskTools, collectDeferred: collectDeferred)
            let messagesWithStep = history + [ConversationMessage.user(stepPrompt)]
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.resolvedSystemPrompt,
                conversationMessages: messagesWithStep,
                context: context,
                onToolActivity: { [weak self] activity, detail in
                    guard let self else { return }
                    Task { @MainActor in
                        let toolMsg = ChatMessage(
                            role: .assistant,
                            content: activity,
                            agentName: agent.name,
                            messageType: .toolActivity,
                            activityGroupID: progressGroupID,
                            toolDetail: detail
                        )
                        self.appendMessage(toolMsg, to: roomID)
                    }
                }
            )

            // 에이전트 응답 이벤트
            pluginEventDelegate?(.agentResponseReceived(
                roomID: roomID,
                agentName: agent.name,
                responsePreview: String(response.prefix(300))
            ))

            // llm_result 완료 활동
            if let progressGroupID {
                let stepDuration = Date().timeIntervalSince(stepStartTime)
                let durationStr = stepDuration < 60
                    ? String(format: "%.1f초", stepDuration)
                    : String(format: "%d분 %.0f초", Int(stepDuration) / 60, stepDuration.truncatingRemainder(dividingBy: 60))
                let resultDetail = ToolActivityDetail(
                    toolName: "llm_result",
                    subject: "\(durationStr) | \(response.count)자",
                    contentPreview: nil,
                    isError: false
                )
                let resultMsg = ChatMessage(
                    role: .assistant,
                    content: "실행 완료 (\(durationStr))",
                    agentName: agent.name,
                    messageType: .toolActivity,
                    activityGroupID: progressGroupID,
                    toolDetail: resultDetail
                )
                appendMessage(resultMsg, to: roomID)
            }

            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }

            // 중간 단계는 toolActivity(접힘), 마지막 단계만 일반 메시지로 표시
            let cleanedResponse = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(response)))
            if isLastStep || totalSteps == 1 {
                let reply = ChatMessage(role: .assistant, content: cleanedResponse, agentName: agent.name)
                appendMessage(reply, to: roomID)
            } else {
                let reply = ChatMessage(role: .assistant, content: cleanedResponse, agentName: agent.name, messageType: .toolActivity)
                appendMessage(reply, to: roomID)
            }
            return true
        } catch {
            if speakingAgentIDByRoom[roomID] == agentID {
                speakingAgentIDByRoom.removeValue(forKey: roomID)
            }
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "단계 실행 오류: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return false
        }
    }

    // MARK: - 빌드 루프

    /// 빌드→실패→에이전트 수정→재빌드 루프. 성공 시 true, 최대 재시도 초과 시 false.
    private func runBuildLoop(
        roomID: UUID,
        buildCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
        let maxRetries = room.maxBuildRetries

        // 빌드 루프 상태 초기화
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildLoopStatus = .building
            rooms[i].buildRetryCount = 0
        }

        let buildMsg = ChatMessage(
            role: .system,
            content: "빌드 실행 중: `\(buildCommand)`",
            messageType: .buildStatus
        )
        appendMessage(buildMsg, to: roomID)

        let result = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].lastBuildResult = result
        }

        if result.success {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildLoopStatus = .passed
            }
            let successMsg = ChatMessage(
                role: .system,
                content: "빌드 성공",
                messageType: .buildStatus
            )
            appendMessage(successMsg, to: roomID)
            return true
        }

        // 빌드 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { return false }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildLoopStatus = .fixing
                rooms[i].buildRetryCount = retry
            }

            let failMsg = ChatMessage(
                role: .system,
                content: "빌드 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .buildStatus
            )
            appendMessage(failMsg, to: roomID)

            // 첫 번째 에이전트에게 수정 요청
            let lastOutput = rooms.first(where: { $0.id == roomID })?.lastBuildResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.buildFixPrompt(
                buildCommand: buildCommand,
                buildOutput: lastOutput,
                retryNumber: retry,
                maxRetries: maxRetries
            )

            if let firstAgentID = room.assignedAgentIDs.first {
                await executeStep(
                    step: fixPrompt,
                    fullTask: "빌드 오류 수정",
                    agentID: firstAgentID,
                    roomID: roomID,
                    stepIndex: 0,
                    totalSteps: 1,
                    fileWriteTracker: fileWriteTracker
                )
            }

            // 재빌드
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].buildLoopStatus = .building
            }

            let rebuildMsg = ChatMessage(
                role: .system,
                content: "재빌드 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .buildStatus
            )
            appendMessage(rebuildMsg, to: roomID)

            let retryResult = await BuildLoopRunner.runBuild(command: buildCommand, workingDirectory: projectPath)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].lastBuildResult = retryResult
            }

            if retryResult.success {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].buildLoopStatus = .passed
                }
                let successMsg = ChatMessage(
                    role: .system,
                    content: "빌드 성공 (시도 \(retry) 후)",
                    messageType: .buildStatus
                )
                appendMessage(successMsg, to: roomID)
                return true
            }
        }

        // 최대 재시도 초과
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].buildLoopStatus = .failed
        }
        return false
    }

    // MARK: - QA 루프

    /// 테스트→실패→에이전트 수정→재테스트 루프. 성공 시 true, 최대 재시도 초과 시 false.
    private func runQALoop(
        roomID: UUID,
        testCommand: String,
        projectPath: String,
        fileWriteTracker: FileWriteTracker?
    ) async -> Bool {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return false }
        let maxRetries = room.maxQARetries

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].qaLoopStatus = .testing
            rooms[i].qaRetryCount = 0
        }

        let testMsg = ChatMessage(
            role: .system,
            content: "테스트 실행 중: `\(testCommand)`",
            messageType: .qaStatus
        )
        appendMessage(testMsg, to: roomID)

        let result = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].lastQAResult = result
        }

        if result.success {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].qaLoopStatus = .passed
            }
            let successMsg = ChatMessage(
                role: .system,
                content: "테스트 통과",
                messageType: .qaStatus
            )
            appendMessage(successMsg, to: roomID)
            return true
        }

        // 테스트 실패 → 수정 루프
        for retry in 1...maxRetries {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.status == .inProgress else { return false }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].qaLoopStatus = .analyzing
                rooms[i].qaRetryCount = retry
            }

            let failMsg = ChatMessage(
                role: .system,
                content: "테스트 실패 (시도 \(retry)/\(maxRetries)). 에이전트에게 수정 요청 중...",
                messageType: .qaStatus
            )
            appendMessage(failMsg, to: roomID)

            let lastOutput = rooms.first(where: { $0.id == roomID })?.lastQAResult?.output ?? ""
            let fixPrompt = BuildLoopRunner.qaFixPrompt(
                testCommand: testCommand,
                testOutput: lastOutput,
                retryNumber: retry,
                maxRetries: maxRetries
            )

            // QA 에이전트 우선, 없으면 첫 번째 에이전트
            let fixAgentID = qaAgentID(in: room) ?? room.assignedAgentIDs.first
            if let agentID = fixAgentID {
                await executeStep(
                    step: fixPrompt,
                    fullTask: "테스트 실패 수정",
                    agentID: agentID,
                    roomID: roomID,
                    stepIndex: 0,
                    totalSteps: 1,
                    fileWriteTracker: fileWriteTracker
                )
            }

            // 재테스트
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].qaLoopStatus = .testing
            }

            let retestMsg = ChatMessage(
                role: .system,
                content: "재테스트 실행 중... (시도 \(retry)/\(maxRetries))",
                messageType: .qaStatus
            )
            appendMessage(retestMsg, to: roomID)

            let retryResult = await BuildLoopRunner.runTests(command: testCommand, workingDirectory: projectPath)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].lastQAResult = retryResult
            }

            if retryResult.success {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].qaLoopStatus = .passed
                }
                let successMsg = ChatMessage(
                    role: .system,
                    content: "테스트 통과 (시도 \(retry) 후)",
                    messageType: .qaStatus
                )
                appendMessage(successMsg, to: roomID)
                return true
            }
        }

        // 최대 재시도 초과
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].qaLoopStatus = .failed
        }
        return false
    }

    /// QA 에이전트 우선 선택 (이름/페르소나에 QA 키워드 포함 에이전트 우선)
    private func qaAgentID(in room: Room) -> UUID? {
        for agentID in room.assignedAgentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }),
               agent.name.lowercased().contains("qa") || agent.persona.lowercased().contains("qa") {
                return agentID
            }
        }
        return nil
    }

    // MARK: - 토론 실행

    /// 합의 기반 토론 실행 (사용자가 빈 피드백 입력 시 종료)
    /// 토론: 라운드별 자유 토론 + 사용자 체크포인트
    private func executeDiscussion(roomID: UUID, topic: String) async {
        guard rooms.first(where: { $0.id == roomID }) != nil else { return }

        var round = 0
        while true {
            guard !Task.isCancelled,
                  rooms.first(where: { $0.id == roomID })?.isActive == true else { break }

            // ── 토론 라운드 N ──
            let roundMsg = ChatMessage(
                role: .system,
                content: "── 토론 라운드 \(round + 1) ──",
                messageType: .discussionRound
            )
            appendMessage(roundMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].currentRound = round
            }

            // 마스터 제외한 전문가만 토론 참여
            let agentIDs = executingAgentIDs(in: roomID)
            guard !agentIDs.isEmpty else { break }

            // 첫 라운드는 병렬 (히스토리 스냅샷 기준), 이후는 순차 (이전 발언 참고)
            if round == 0 && agentIDs.count > 1 {
                let frozenHistory = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)
                    .map { msg in
                        ConversationMessage(role: msg.role, content: msg.content,
                                            toolCalls: nil, toolCallID: nil,
                                            attachments: nil, isError: false)
                    }
                var historyBuilder: [ConversationMessage] = []
                if let firstUserMsg = rooms.first(where: { $0.id == roomID })?.messages
                    .first(where: { $0.role == .user && $0.messageType == .text }) {
                    historyBuilder.append(ConversationMessage.user(firstUserMsg.content))
                }
                historyBuilder.append(contentsOf: frozenHistory)
                let fullHistory = historyBuilder

                var results: [(Int, ChatMessage, Bool)] = []
                await withTaskGroup(of: (Int, ChatMessage, Bool).self) { group in
                    for (idx, agentID) in agentIDs.enumerated() {
                        group.addTask { [weak self] in
                            guard let self else {
                                return (idx, ChatMessage(role: .assistant, content: "", agentName: nil, messageType: .error), false)
                            }
                            let (msg, agreed) = await self.generateDiscussionResponse(
                                topic: topic, agentID: agentID, roomID: roomID,
                                round: round,
                                frozenHistory: fullHistory
                            )
                            return (idx, msg, agreed)
                        }
                    }
                    for await item in group { results.append(item) }
                }
                for (_, msg, agreed) in results.sorted(by: { $0.0 < $1.0 }) {
                    appendMessage(msg, to: roomID)
                    if agreed, let agentName = msg.agentName,
                       let i = rooms.firstIndex(where: { $0.id == roomID }) {
                        let decision = Self.parseDecisionContent(from: msg.content) ?? "합의 도달"
                        rooms[i].decisionLog.append(DecisionEntry(
                            round: round, decision: decision, supporters: [agentName]
                        ))
                    }
                }
            } else {
                for agentID in agentIDs {
                    guard !Task.isCancelled,
                          rooms.first(where: { $0.id == roomID })?.isActive == true else { break }

                    await executeDiscussionTurn(
                        topic: topic,
                        agentID: agentID,
                        roomID: roomID,
                        round: round
                    )
                }
            }

            // 사용자 체크포인트
            let checkpointMsg = ChatMessage(
                role: .system,
                content: "토론 라운드 \(round + 1) 완료. 피드백이 있으시면 입력해주세요.",
                messageType: .userQuestion
            )
            appendMessage(checkpointMsg, to: roomID)

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].isDiscussionCheckpoint = true
                rooms[i].transitionTo(.awaitingUserInput)
            }
            scheduleSave()

            let feedback = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                userInputContinuations[roomID] = cont
            }
            userInputContinuations.removeValue(forKey: roomID)
            guard !Task.isCancelled else { return }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].isDiscussionCheckpoint = false
                rooms[i].transitionTo(.inProgress)
            }

            if feedback.isEmpty {
                // "진행" → 토론 종료, 브리핑으로
                break
            } else {
                // 사용자 피드백 → answerUserQuestion에서 이미 appendMessage 됨
                let feedbackNote = ChatMessage(
                    role: .system,
                    content: "사용자 피드백을 반영하여 새 라운드를 시작합니다."
                )
                appendMessage(feedbackNote, to: roomID)
            }
            round += 1
        }

        let doneMsg = ChatMessage(role: .system, content: "토론이 완료되었습니다. 다음 단계로 넘어갑니다.")
        appendMessage(doneMsg, to: roomID)
        scheduleSave()
    }

    /// 개별 에이전트의 토론 턴. 합의 여부를 Bool로 리턴.
    @discardableResult
    private func executeDiscussionTurn(
        topic: String,
        agentID: UUID,
        roomID: UUID,
        round: Int
    ) async -> Bool {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return false }

        // 토론 히스토리 (이미지는 존재 여부만 알림 — 실제 작업은 실행 단계에서)
        let roomRef = rooms.first(where: { $0.id == roomID })
        var history: [ConversationMessage] = []
        if let firstUserMsg = roomRef?.messages.first(where: { $0.role == .user && $0.messageType == .text }) {
            var content = firstUserMsg.content
            if let attachments = firstUserMsg.attachments, !attachments.isEmpty {
                content += "\n\n[첨부 이미지 \(attachments.count)장 — 실행 단계에서 확인 가능]"
            }
            history.append(ConversationMessage.user(content))
        }
        let discussionMsgs = buildDiscussionHistory(roomID: roomID, currentAgentName: agent.name)
        history.append(contentsOf: discussionMsgs.map { msg in
            ConversationMessage(role: msg.role, content: msg.content, toolCalls: nil, toolCallID: nil, attachments: nil, isError: false)
        })

        // 동료 목록 (마스터 제외 — 전문가끼리만 토론)
        let otherSpecialists = executingAgentIDs(in: roomID)
            .filter { $0 != agentID }
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id }) }
        let otherNames = otherSpecialists.map { $0.name }.joined(separator: ", ")

        // intake 데이터
        let intakeText = roomRef?.intakeData?.asClarifyContextString() ?? ""
        let intakeBlock = intakeText.isEmpty ? "" : "\n\(intakeText)"

        // clarify 요약 앵커링 (토론 범위 제한)
        let clarifyText = roomRef?.clarifySummary ?? ""
        let anchorBlock = clarifyText.isEmpty ? "" : """

        [사용자 확인 요약 — 이 범위를 벗어나지 마세요]
        \(clarifyText)
        """

        // 에이전트 이름에서 도메인 키워드 추출하여 전문 영역 힌트 생성
        let domainHint = Self.domainHint(for: agent.name)

        let discussionPrompt = """
        [역할] 당신은 **\(agent.name)**입니다.
        \(domainHint)
        \(agent.resolvedSystemPrompt)
        [필수 규칙]
        - 첫 문장을 반드시 **\(agent.name)의 전문 영역 시각**으로 시작하세요.
        - 예: "\(agent.name) 관점에서 보면..."
        - 동료가 이미 말한 관점을 자신의 것처럼 반복하지 마세요.
        - 동료의 영역(예: 백엔드 개발자가 아닌데 "백엔드에서는..."이라고 말하는 것)은 금지입니다.
        - 동료 발언에 응답할 때도 자신의 전문 영역 시각으로 해석하여 답하세요.

        [시스템] 필요한 외부 데이터는 이미 수집되었습니다. 도구·인증·API 연동 관련 언급을 하지 마세요.
        \(intakeBlock)\(anchorBlock)

        [회의실] \(topic)
        라운드 \(round + 1) | 동료: \(otherNames)

        첨부된 이미지나 파일이 있으면 내용을 확인하고 참고하세요.
        2-4문장으로 핵심만 말하세요.
        이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
        발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
        """

        // 활동 추적: ProgressActivityBubble로 모델/소요시간 표시
        let progressGroupID = UUID()
        let turnStartTime = Date()

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)
            speakingAgentIDByRoom[roomID] = agentID

            let progressMsg = ChatMessage(
                role: .assistant,
                content: "\(agent.providerName) · \(agent.modelName)",
                agentName: agent.name,
                messageType: .progress,
                activityGroupID: progressGroupID
            )
            appendMessage(progressMsg, to: roomID)

            // 스트리밍용 placeholder 메시지 — 청크가 실시간으로 표시됨
            let placeholderID = UUID()
            let placeholder = ChatMessage(
                id: placeholderID, role: .assistant, content: "",
                agentName: agent.name, messageType: .discussion
            )
            appendMessage(placeholder, to: roomID)

            // 스트리밍 전송: 청크마다 placeholder 업데이트
            let simpleHistory = history.compactMap { msg -> (role: String, content: String)? in
                guard let content = msg.content else { return nil }
                return (role: msg.role, content: content)
            }
            let buffer = StreamBuffer()
            let response: String
            if provider.supportsStreaming {
                response = try await provider.sendMessageStreaming(
                    model: agent.modelName,
                    systemPrompt: discussionPrompt,
                    messages: simpleHistory,
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        let current = buffer.append(chunk)
                        Task { @MainActor in
                            self.updateMessageContent(placeholderID, newContent: current, in: roomID)
                        }
                    }
                )
            } else {
                let responseContent = try await provider.sendMessageWithTools(
                    model: agent.modelName,
                    systemPrompt: discussionPrompt,
                    messages: history,
                    tools: []
                )
                switch responseContent {
                case .text(let t): response = t
                case .toolCalls: response = "[합의]"
                case .mixed(let t, _): response = t
                }
            }

            // 활동 추적: 응답 완료
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let durationStr = turnDuration < 60
                ? String(format: "%.1f초", turnDuration)
                : String(format: "%d분 %.0f초", Int(turnDuration) / 60, turnDuration.truncatingRemainder(dividingBy: 60))
            let resultDetail = ToolActivityDetail(
                toolName: "llm_result",
                subject: durationStr,
                contentPreview: nil, isError: false
            )
            let resultActivity = ChatMessage(
                role: .assistant,
                content: "응답 완료 (\(durationStr))",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: resultDetail
            )
            appendMessage(resultActivity, to: roomID)

            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // 합의 감지 (퍼지 매칭 포함) 후 DecisionLog 기록
            let agreed = Self.detectConsensus(in: response)
            if agreed, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                let decision = Self.parseDecisionContent(from: response) ?? "합의 도달"
                let entry = DecisionEntry(
                    round: round,
                    decision: decision,
                    supporters: [agent.name]
                )
                rooms[i].decisionLog.append(entry)
            }
            let cleanResponse = response
                .replacingOccurrences(of: "\\[합의(?::[^\\]]*)?\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[계속]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 산출물 파싱 → Room에 저장
            let newArtifacts = ArtifactParser.extractArtifacts(from: cleanResponse, producedBy: agent.name)
            if !newArtifacts.isEmpty, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                for artifact in newArtifacts {
                    if let existingIdx = rooms[i].artifacts.firstIndex(where: {
                        $0.type == artifact.type && $0.title == artifact.title
                    }) {
                        var updated = artifact
                        updated.version = rooms[i].artifacts[existingIdx].version + 1
                        rooms[i].artifacts[existingIdx] = updated
                    } else {
                        rooms[i].artifacts.append(artifact)
                    }
                }
            }
            let displayResponse = ArtifactParser.stripArtifactBlocks(from: cleanResponse)

            // placeholder를 최종 정리된 텍스트로 업데이트 (환각 제거 + ~/ 확장)
            let finalText = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(displayResponse.isEmpty ? cleanResponse : displayResponse)))
            updateMessageContent(placeholderID, newContent: finalText, in: roomID)

            return agreed
        } catch {
            // 활동 추적: 오류
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let errDurationStr = String(format: "%.1f초", turnDuration)
            let errorDetail = ToolActivityDetail(
                toolName: "llm_error",
                subject: error.userFacingMessage,
                contentPreview: nil, isError: true
            )
            let errorActivity = ChatMessage(
                role: .assistant,
                content: "오류 (\(errDurationStr)): \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: errorDetail
            )
            appendMessage(errorActivity, to: roomID)

            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "발언 실패: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
            return false
        }
    }

    /// 병렬 실행용: 토론 응답만 생성하고 Room에 append하지 않음 (발산 라운드용)
    private func generateDiscussionResponse(
        topic: String,
        agentID: UUID,
        roomID: UUID,
        round: Int,
        frozenHistory: [ConversationMessage]
    ) async -> (message: ChatMessage, agreed: Bool) {
        guard let agent = agentStore?.agents.first(where: { $0.id == agentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            return (ChatMessage(role: .assistant, content: "에이전트 없음", agentName: nil, messageType: .error), false)
        }

        // 동료 정보 구성 (마스터 제외 — 전문가끼리만 토론)
        let roomRef = rooms.first(where: { $0.id == roomID })
        let otherSpecialists = executingAgentIDs(in: roomID)
            .filter { $0 != agentID }
            .compactMap { id in agentStore?.agents.first(where: { $0.id == id }) }
        let otherNames = otherSpecialists.map { $0.name }.joined(separator: ", ")

        let clarifyText = roomRef?.clarifySummary ?? ""
        let anchorBlock = clarifyText.isEmpty ? "" : """

        [사용자 확인 요약 — 이 범위를 벗어나지 마세요]
        \(clarifyText)
        """

        let discussionPrompt = """
        \(agent.resolvedSystemPrompt)
        [시스템] 필요한 외부 데이터는 이미 수집되었습니다. 도구·인증·API 연동 관련 언급을 하지 마세요.
        \(anchorBlock)

        [회의실] \(topic)
        라운드 \(round + 1) | 동료: \(otherNames)
        전문 영역에서 의견을 제시하고, 동의/보완/반론하세요.

        첨부된 이미지나 파일이 있으면 내용을 확인하고 참고하세요.
        2-4문장으로 핵심만 말하세요.
        이름 헤더(**[이름]** 등)를 붙이지 마세요. UI가 화자를 표시합니다.
        발언 마지막 줄에 [합의] 또는 [계속] 태그를 붙이세요.
        """

        // 활동 추적: ProgressActivityBubble로 모델/소요시간 표시
        let progressGroupID = UUID()
        let turnStartTime = Date()

        do {
            agentStore?.updateStatus(agentID: agentID, status: .working)

            let progressMsg = ChatMessage(
                role: .assistant,
                content: "\(agent.name) 발언 중…",
                agentName: agent.name,
                messageType: .progress,
                activityGroupID: progressGroupID
            )
            appendMessage(progressMsg, to: roomID)

            // 병렬 실행이므로 비스트리밍 (placeholder 충돌 방지)
            let responseContent = try await provider.sendMessageWithTools(
                model: agent.modelName,
                systemPrompt: discussionPrompt,
                messages: frozenHistory,
                tools: []
            )
            let response: String
            switch responseContent {
            case .text(let t): response = t
            case .toolCalls: response = "[합의]"
            case .mixed(let t, _): response = t
            }

            // 활동 추적: 응답 완료
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let durationStr = turnDuration < 60
                ? String(format: "%.1f초", turnDuration)
                : String(format: "%d분 %.0f초", Int(turnDuration) / 60, turnDuration.truncatingRemainder(dividingBy: 60))
            let resultDetail = ToolActivityDetail(
                toolName: "llm_result",
                subject: durationStr,
                contentPreview: nil, isError: false
            )
            let resultActivity = ChatMessage(
                role: .assistant,
                content: "응답 완료 (\(durationStr))",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: resultDetail
            )
            appendMessage(resultActivity, to: roomID)

            agentStore?.updateStatus(agentID: agentID, status: .idle)

            let agreed = Self.detectConsensus(in: response)
            let cleanResponse = response
                .replacingOccurrences(of: "\\[합의(?::[^\\]]*)?\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[계속]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayResponse = ArtifactParser.stripArtifactBlocks(from: cleanResponse)

            let finalText = expandTildePaths(stripHallucinatedAuthLines(stripTrailingOptions(displayResponse.isEmpty ? cleanResponse : displayResponse)))
            let msg = ChatMessage(
                role: .assistant,
                content: finalText,
                agentName: agent.name,
                messageType: .discussion
            )
            return (msg, agreed)
        } catch {
            // 활동 추적: 오류
            let turnDuration = Date().timeIntervalSince(turnStartTime)
            let errDurationStr = String(format: "%.1f초", turnDuration)
            let errorDetail = ToolActivityDetail(
                toolName: "llm_error",
                subject: error.userFacingMessage,
                contentPreview: nil, isError: true
            )
            let errorActivity = ChatMessage(
                role: .assistant,
                content: "오류 (\(errDurationStr)): \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .toolActivity,
                activityGroupID: progressGroupID,
                toolDetail: errorDetail
            )
            appendMessage(errorActivity, to: roomID)

            agentStore?.updateStatus(agentID: agentID, status: .idle)
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "발언 실패: \(error.userFacingMessage)",
                agentName: agent.name,
                messageType: .error
            )
            return (errorMsg, false)
        }
    }

    /// 토론 브리핑 생성 (컨텍스트 압축)
    private func generateBriefing(roomID: UUID, topic: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else { return }

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)

        // 산출물 목록도 포함
        let artifactList = room.artifacts.isEmpty ? "" :
            "\n\n산출물 목록:\n" + room.artifacts.map { "- [\($0.type.displayName)] \($0.title)" }.joined(separator: "\n")

        // 원래 사용자 요청 앵커링
        let originalContext: String
        if let summary = room.clarifySummary {
            originalContext = "[원래 사용자 요청]\n\(summary)\n\n"
        } else {
            originalContext = ""
        }

        let briefingPrompt = """
        \(originalContext)토론 내용을 분석하여 실행팀을 위한 브리핑 문서를 JSON으로 작성하세요.\(artifactList)

        반드시 아래 형식의 JSON으로만 응답하세요:
        {"summary": "작업 요약 2-3문장", "key_decisions": ["결정1", "결정2"], "agent_responsibilities": {"에이전트명": "담당역할"}, "open_issues": ["미결사항"]}

        규칙:
        - summary: 팀이 합의한 방향과 핵심 목표 (2-3문장). 반드시 원래 사용자 요청 범위 내에서 작성
        - key_decisions: 토론에서 확정된 결정사항 (3-5개)
        - agent_responsibilities: 각 참여자의 담당 역할 (토론에서 드러난 전문성 기반)
        - open_issues: 추가 논의가 필요한 미결 사항 (없으면 빈 배열)
        - 반드시 유효한 JSON으로만 응답하세요
        """

        speakingAgentIDByRoom[roomID] = firstAgentID

        do {
            let lightModel = providerManager?.lightModelName(for: agent.providerName) ?? agent.modelName
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "토론 브리핑을 생성하는 중…",
                agentName: agent.name,
                modelName: lightModel,
                providerName: agent.providerName
            ) { _ in
                // sendRouterMessage: 도구 비활성화 (브리핑 요약 중 파일 수정 방지)
                try await provider.sendRouterMessage(
                    model: lightModel,
                    systemPrompt: briefingPrompt,
                    messages: history
                )
            }

            speakingAgentIDByRoom.removeValue(forKey: roomID)

            // JSON 파싱 → RoomBriefing
            if let briefing = parseBriefing(from: response) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].briefing = briefing
                }
                let reply = ChatMessage(
                    role: .assistant,
                    content: briefing.asContextString(),
                    agentName: "토론 정리",
                    messageType: .summary
                )
                appendMessage(reply, to: roomID)
            } else {
                // JSON 파싱 실패 → 폴백 브리핑
                let fallback = RoomBriefing(
                    summary: response.prefix(500).description,
                    keyDecisions: [],
                    agentResponsibilities: [:],
                    openIssues: []
                )
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].briefing = fallback
                }
                let reply = ChatMessage(
                    role: .assistant,
                    content: response,
                    agentName: "토론 정리",
                    messageType: .summary
                )
                appendMessage(reply, to: roomID)
            }
        } catch {
            speakingAgentIDByRoom.removeValue(forKey: roomID)
            let errorMsg = ChatMessage(
                role: .system,
                content: "브리핑 생성 실패: \(error.userFacingMessage)",
                messageType: .error
            )
            appendMessage(errorMsg, to: roomID)
        }
    }

    /// 브리핑 JSON 파싱
    private func parseBriefing(from response: String) -> RoomBriefing? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? String else {
            return nil
        }
        let keyDecisions = json["key_decisions"] as? [String] ?? []
        let responsibilities = json["agent_responsibilities"] as? [String: String] ?? [:]
        let openIssues = json["open_issues"] as? [String] ?? []
        return RoomBriefing(
            summary: summary,
            keyDecisions: keyDecisions,
            agentResponsibilities: responsibilities,
            openIssues: openIssues
        )
    }

    /// 토론용 히스토리 빌드 (에이전트 이름을 명시하여 누가 말했는지 구분)
    private func buildDiscussionHistory(roomID: UUID, currentAgentName: String?) -> [(role: String, content: String)] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
            .filter { $0.messageType == .text || $0.messageType == .discussion || $0.messageType == .discussionRound }
            .suffix(40)
            .map { msg in
                let role: String
                let content: String
                switch msg.role {
                case .user:
                    role = "user"
                    content = msg.content
                case .assistant:
                    // 자신의 발언은 assistant, 다른 에이전트 발언은 user로 (컨텍스트 구분)
                    if let agentName = msg.agentName, agentName == currentAgentName {
                        role = "assistant"
                        content = msg.content
                    } else {
                        role = "user"
                        content = "[\(msg.agentName ?? "에이전트")의 발언]: \(msg.content)"
                    }
                case .system:
                    role = "user"
                    content = "[시스템]: \(msg.content)"
                }
                return (role: role, content: content)
            }
    }

    // MARK: - 도메인 힌트

    /// 에이전트 이름에서 전문 영역 힌트를 생성 (토론 시 역할 혼동 방지)
    static func domainHint(for agentName: String) -> String {
        let name = agentName.lowercased()
        if name.contains("프론트엔드") || name.contains("frontend") || name.contains("ui") {
            return """

            [전문 영역 — 반드시 준수] 당신은 프론트엔드 전문가입니다. 아래 영역만 다루세요:
            UI/UX, 클라이언트 상태관리, 컴포넌트 설계, 렌더링 성능, 브라우저 호환성, 반응형 디자인, 접근성, CSS/스타일링, 프론트엔드 프레임워크(React, Vue, Svelte 등)
            [금지] 백엔드, 서버, 데이터베이스, API 설계, 인프라에 대해 말하지 마세요. "백엔드에서는", "서버 측에서는"이라는 표현을 사용하면 안 됩니다. 주제가 백엔드와 관련되더라도 반드시 프론트엔드 시각으로만 해석하세요.
            """
        } else if name.contains("백엔드") || name.contains("backend") || name.contains("서버") {
            return """

            [전문 영역 — 반드시 준수] 당신은 백엔드 전문가입니다. 아래 영역만 다루세요:
            API 설계, 데이터베이스, 서버 아키텍처, 인증/보안, 성능 최적화, 인프라, 마이크로서비스
            [금지] 프론트엔드, UI/UX, 컴포넌트, 렌더링, CSS에 대해 말하지 마세요. "프론트엔드에서는", "클라이언트 측에서는"이라는 표현을 사용하면 안 됩니다. 주제가 프론트엔드와 관련되더라도 반드시 백엔드 시각으로만 해석하세요.
            """
        } else if name.contains("qa") || name.contains("테스트") || name.contains("품질") {
            return """

            [전문 영역] 테스트 전략, 품질 보증, 자동화 테스트, 버그 트래킹, 성능 테스트, 보안 테스트
            - "QA/테스트 관점에서"로 시작하세요.
            """
        } else if name.contains("디자인") || name.contains("design") || name.contains("ux") {
            return """

            [전문 영역] 사용자 경험, 인터페이스 디자인, 디자인 시스템, 프로토타이핑, 사용성 테스트, 접근성
            - "디자인 관점에서"로 시작하세요.
            """
        } else if name.contains("devops") || name.contains("인프라") || name.contains("sre") {
            return """

            [전문 영역] CI/CD, 컨테이너, 클라우드 인프라, 모니터링, 배포 전략, IaC
            - "DevOps/인프라 관점에서"로 시작하세요.
            """
        } else if name.contains("기획") || name.contains("pm") || name.contains("프로덕트") {
            return """

            [전문 영역] 제품 전략, 요구사항 분석, 로드맵, 사용자 리서치, 비즈니스 가치, 우선순위
            - "기획/PM 관점에서"로 시작하세요.
            """
        } else if name.contains("리서치") || name.contains("분석") || name.contains("research") {
            return """

            [전문 영역] 시장 조사, 데이터 분석, 트렌드 파악, 경쟁사 분석, 사용자 리서치
            - "리서치/분석 관점에서"로 시작하세요.
            """
        }
        return ""
    }

    // MARK: - 유틸리티

    /// [합의: 내용] 태그에서 내용 추출
    /// 퍼지 합의 감지: [합의] 태그 우선, 없으면 한국어 합의 표현 탐지
    static func detectConsensus(in response: String) -> Bool {
        // 1) 명시적 태그 — 가장 신뢰도 높음
        if response.contains("[합의") { return true }

        // 2) 명시적 반대/계속 태그 — 확실한 비합의
        if response.contains("[계속]") { return false }

        // 3) 퍼지: 합의 표현 vs 반대 표현 비교
        let lower = response.lowercased()
        let agreePhrases = [
            "동의합니다", "합의합니다", "찬성합니다",
            "이의 없습니다", "이의없습니다",
            "좋은 계획", "좋은 방향", "좋은 접근",
            "이 방향으로 진행", "이대로 진행",
            "agree", "consensus", "lgtm",
        ]
        let disagreePhrases = [
            "반대합니다", "다른 의견", "다른 접근",
            "재고해", "재검토", "우려가 있", "우려됩니다",
            "수정이 필요", "보완이 필요", "disagree",
        ]

        let hasAgree = agreePhrases.contains { lower.contains($0) }
        let hasDisagree = disagreePhrases.contains { lower.contains($0) }

        // 합의 표현이 있고 반대 표현이 없으면 합의
        return hasAgree && !hasDisagree
    }

    static func parseDecisionContent(from text: String) -> String? {
        // [합의: 내용] 형태
        if let range = text.range(of: "\\[합의:\\s*([^\\]]+)\\]", options: .regularExpression) {
            let matched = String(text[range])
            // ":" 이후 내용 추출
            if let colonIdx = matched.firstIndex(of: ":") {
                let content = matched[matched.index(after: colonIdx)..<matched.index(before: matched.endIndex)]
                    .trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? nil : content
            }
        }
        return nil
    }

    static func wordOverlapSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
        let wordsB = Set(b.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - 방 제목 자동 추출

    /// clarify 요약에서 "요청 내용:" 줄을 추출하여 방 제목으로 사용
    static func extractTitleFromClarifySummary(_ summary: String) -> String {
        for line in summary.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "- 요청 내용: ..." 또는 "요청 내용: ..." 패턴
            if let range = trimmed.range(of: "요청 내용:", options: .caseInsensitive) {
                var title = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                // 마크다운 볼드 제거
                title = title.replacingOccurrences(of: "**", with: "")
                if title.count > 30 {
                    title = String(title.prefix(28)) + "…"
                }
                return title.isEmpty ? "" : title
            }
        }
        return ""
    }

    // MARK: - 작업일지 생성

    private func generateWorkLog(roomID: UUID, task: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let firstAgentID = room.assignedAgentIDs.first,
              let agent = agentStore?.agents.first(where: { $0.id == firstAgentID }),
              let provider = providerManager?.provider(named: agent.providerName) else {
            // API 없어도 기본 일지는 생성
            createFallbackLog(roomID: roomID, task: task)
            return
        }

        let participants = room.assignedAgentIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }
        let duration = Int(Date().timeIntervalSince(room.createdAt))

        let history = buildDiscussionHistory(roomID: roomID, currentAgentName: nil)

        let logPrompt = """
        아래 작업방의 전체 과정을 작업일지로 정리하세요.

        형식 (반드시 이 형식만 사용):
        [결과] 한 줄 요약
        [토론] 핵심 합의 사항 (1-2줄)
        [계획] 실행한 단계 요약 (1-2줄)
        [비고] 특이사항 또는 후속 작업 (있으면)

        총 5줄 이내. 군더더기 없이 팩트만.
        """

        do {
            let (response, _) = try await trackPhaseActivity(
                roomID: roomID,
                label: "작업일지를 생성하는 중…",
                agentName: agent.name,
                modelName: agent.modelName,
                providerName: agent.providerName
            ) { _ in
                // sendRouterMessage: 도구 비활성화 (작업일지 생성 중 파일 수정 방지)
                try await provider.sendRouterMessage(
                    model: agent.modelName,
                    systemPrompt: logPrompt,
                    messages: history + [("user", "작업: \(task)")]
                )
            }

            // 토론 요약 추출 (summary 타입 메시지에서)
            let discussionSummary = room.messages
                .first(where: { $0.messageType == .summary })?.content ?? ""
            let planSummary = room.plan?.summary ?? ""

            let log = WorkLog(
                roomTitle: room.title,
                participants: participants,
                task: task,
                discussionSummary: discussionSummary,
                planSummary: planSummary,
                outcome: response,
                durationSeconds: duration
            )

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workLog = log
            }

            scheduleSave()
        } catch {
            createFallbackLog(roomID: roomID, task: task)
        }
    }

    private func createFallbackLog(roomID: UUID, task: String) {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let participants = room.assignedAgentIDs.compactMap { id in
            agentStore?.agents.first(where: { $0.id == id })?.name
        }
        let duration = Int(Date().timeIntervalSince(room.createdAt))

        let log = WorkLog(
            roomTitle: room.title,
            participants: participants,
            task: task,
            discussionSummary: room.messages.first(where: { $0.messageType == .summary })?.content ?? "",
            planSummary: room.plan?.summary ?? "",
            outcome: "작업 완료",
            durationSeconds: duration
        )

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].workLog = log
        }
        scheduleSave()
    }

    // MARK: - 방 상태 관리

    func completeRoom(_ roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        // 진행 중인 워크플로우 취소
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        // 대기 중인 continuation 해제
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
        if let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = intentContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .task)
        }
        if let cont = docTypeContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .freeform)
        }
        if let cont = teamConfirmationContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: nil)
        }
        pendingTeamConfirmation.removeValue(forKey: roomID)
        pendingIntentSelection.removeValue(forKey: roomID)
        pendingDocTypeSelection.removeValue(forKey: roomID)
        guard rooms[idx].transitionTo(.completed) else { return }
        rooms[idx].completedAt = Date()
        // 에이전트 수 스냅샷 (다음 후속 사이클에서 변동 감지용)
        previousCycleAgentCount[roomID] = executingAgentIDs(in: roomID).count

        // 작업일지 생성 (수동 완료 시에도)
        let task = rooms[idx].messages.first(where: { $0.role == .user })?.content ?? rooms[idx].title
        Task { await generateWorkLog(roomID: roomID, task: task) }

        syncAgentStatuses()
        scheduleSave()
    }

    /// 사용자가 승인 카드에서 취소 → 작업 종료
    func cancelRoom(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
        if let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = intentContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .task)
        }
        if let cont = docTypeContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .freeform)
        }
        if let cont = teamConfirmationContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: nil)
        }
        pendingTeamConfirmation.removeValue(forKey: roomID)
        pendingIntentSelection.removeValue(forKey: roomID)
        pendingDocTypeSelection.removeValue(forKey: roomID)
        rooms[idx].transitionTo(.failed)
        rooms[idx].completedAt = Date()
        let msg = ChatMessage(role: .system, content: "사용자가 작업을 취소했습니다.", messageType: .error)
        appendMessage(msg, to: roomID)
        syncAgentStatuses()
        scheduleSave()
    }

    func completeRooms(_ roomIDs: Set<UUID>) {
        for roomID in roomIDs {
            completeRoom(roomID)
        }
    }

    func deleteRooms(_ roomIDs: Set<UUID>) {
        for roomID in roomIDs {
            deleteRoom(roomID)
        }
    }

    func deleteRoom(_ roomID: UUID) {
        // 진행 중인 워크플로우 취소
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        speakingAgentIDByRoom.removeValue(forKey: roomID)
        // 대기 중인 모든 continuation 해제 (누수 방지)
        if let cont = approvalContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = userInputContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: "")
        }
        if let cont = suggestionContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: false)
        }
        if let cont = intentContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .task)
        }
        if let cont = docTypeContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: .freeform)
        }
        if let cont = teamConfirmationContinuations.removeValue(forKey: roomID) {
            cont.resume(returning: nil)
        }
        pendingTeamConfirmation.removeValue(forKey: roomID)
        pendingIntentSelection.removeValue(forKey: roomID)
        pendingDocTypeSelection.removeValue(forKey: roomID)

        // 첨부 이미지 파일 삭제
        if let room = rooms.first(where: { $0.id == roomID }) {
            for msg in room.messages {
                msg.attachments?.forEach { $0.delete() }
            }
        }

        rooms.removeAll { $0.id == roomID }
        if selectedRoomID == roomID { selectedRoomID = nil }

        // 저장 파일 삭제
        let file = Self.roomDirectory.appendingPathComponent("\(roomID.uuidString).json")
        try? FileManager.default.removeItem(at: file)

        syncAgentStatuses()
        scheduleSave()
    }

    // MARK: - 에이전트 상태 동기화

    func syncAgentStatuses() {
        guard let agentStore = agentStore else { return }

        for agent in agentStore.agents where !agent.isMaster {
            let activeCount = rooms.filter { room in
                room.isActive && room.assignedAgentIDs.contains(agent.id)
            }.count

            let newStatus: AgentStatus
            switch activeCount {
            case 0: newStatus = .idle
            case 1...2: newStatus = .working
            default: newStatus = .busy   // 3개+ 활성 방 참여 시 바쁨
            }

            if agent.status != .error {
                agentStore.updateStatus(agentID: agent.id, status: newStatus)
            }
        }
    }

    /// 에이전트가 참여 중인 활성 방 수
    func activeRoomCount(for agentID: UUID) -> Int {
        rooms.filter { $0.isActive && $0.assignedAgentIDs.contains(agentID) }.count
    }

    /// 에이전트가 속한 전체 방 수 (완료 포함)
    func totalRoomCount(for agentID: UUID) -> Int {
        rooms.filter { $0.assignedAgentIDs.contains(agentID) }.count
    }

    // MARK: - 타이머

    private func startTimerRefresh() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                // @Published 변경 트리거 (remainingSeconds는 computed이므로 UI 갱신용)
                if rooms.contains(where: { $0.status == .inProgress }) {
                    objectWillChange.send()
                }
            }
        }
    }

    // MARK: - 대화 히스토리

    /// 간단한 (role, content) 튜플 히스토리 (토론/요약 등 내부 호출용)
    private func buildSimpleHistory(roomID: UUID) -> [(role: String, content: String)] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
            .filter { $0.messageType == .text }
            .suffix(20)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "user"
                }
                return (role: role, content: msg.content)
            }
    }

    /// ConversationMessage 히스토리 (이미지 첨부 포함, smartSend용)
    private func buildRoomHistory(roomID: UUID, limit: Int = 20) -> [ConversationMessage] {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return room.messages
            .filter { $0.messageType == .text }
            .suffix(limit)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "user"
                }
                return ConversationMessage(
                    role: role,
                    content: msg.content,
                    toolCalls: nil,
                    toolCallID: nil,
                    attachments: msg.attachments,
                    isError: false
                )
            }
    }

    // MARK: - 영속화

    /// 테스트에서 임시 디렉토리로 교체 가능 (프로덕션에서는 nil)
    static var roomDirectoryOverride: URL?

    private static var roomDirectory: URL {
        if let override = roomDirectoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/rooms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveRooms()
        }
    }

    private static let roomEncoder = JSONEncoder()

    func saveRooms() {
        let dir = Self.roomDirectory
        for room in rooms {
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            if let data = try? Self.roomEncoder.encode(room) {
                try? data.write(to: file)
            }
        }
    }

    func loadRooms() {
        let dir = Self.roomDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var loaded: [Room] = []
        var failedFiles: [URL] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let room = try? JSONDecoder().decode(Room.self, from: data) {
                loaded.append(room)
            } else {
                failedFiles.append(file)
            }
        }
        // 디코드 실패한 고아 JSON 파일 삭제
        for file in failedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        rooms = loaded.sorted { $0.createdAt > $1.createdAt }
        // 완료된 방 프루닝 — 최근 30개만 유지
        pruneCompletedRooms(maxKeep: 30)
        syncAgentStatuses()
    }

    /// 완료된 방이 maxKeep 개를 초과하면 오래된 순서대로 삭제
    private func pruneCompletedRooms(maxKeep: Int) {
        let completed = rooms
            .filter { !$0.isActive }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        guard completed.count > maxKeep else { return }
        let toRemove = completed.suffix(from: maxKeep)
        let dir = Self.roomDirectory
        for room in toRemove {
            // 첨부 이미지 파일 삭제
            for msg in room.messages {
                msg.attachments?.forEach { $0.delete() }
            }
            // JSON 파일 삭제
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            try? FileManager.default.removeItem(at: file)
        }
        let removeIDs = Set(toRemove.map { $0.id })
        rooms.removeAll { removeIDs.contains($0.id) }
    }

    // MARK: - 한글 조사 헬퍼

    /// 마지막 글자의 받침 유무에 따라 "이"/"가" 반환
    private func subjectParticle(for name: String) -> String {
        guard let last = name.last else { return "이" }
        let v = last.unicodeScalars.first!.value
        guard (0xAC00...0xD7A3).contains(v) else { return "가" }   // 비한글(영문 등)
        return (v - 0xAC00) % 28 == 0 ? "가" : "이"               // 받침 없으면 "가"
    }
}
