import Foundation

/// 에이전트 응답 끝에 붙은 선택지 텍스트 제거 (예: "1. 다음(구현) 2. 수정할래요 x. 나가기")
func stripTrailingOptions(_ text: String) -> String {
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
func stripHallucinatedAuthLines(_ text: String) -> String {
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
func expandTildePaths(_ text: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return text.replacingOccurrences(of: "~/", with: "\(home)/")
}

/// clarify 응답에서 [delegation] 블록을 파싱하여 DelegationInfo 반환
/// 파싱 실패 시 .open 폴백 (기존 assemble 흐름)
func parseDelegationBlock(_ text: String) -> DelegationInfo {
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
func stripDelegationBlock(_ text: String) -> String {
    guard let startRange = text.range(of: "[delegation]"),
          let endRange = text.range(of: "[/delegation]") else {
        return text
    }
    var result = text
    result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 스트리밍 청크 누적용 스레드-안전 버퍼
final class StreamBuffer: @unchecked Sendable {
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
class RoomManager: ObservableObject, WorkflowHost {
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
    var approvalContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// 리뷰 게이트 자동 승인 타이머 태스크 (취소용) — internal for extension access
    var reviewAutoApprovalTasks: [UUID: Task<Void, Never>] = [:]
    /// 사용자 입력 대기 중인 continuation (방 ID → continuation)
    var userInputContinuations: [UUID: CheckedContinuation<String, Never>] = [:]
    /// 에이전트 생성 제안 승인 대기 continuation (방 ID → continuation, Bool = 사용자 응답 여부)
    private var suggestionContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// Intent 선택 대기 중인 continuation (방 ID → continuation)
    var intentContinuations: [UUID: CheckedContinuation<WorkflowIntent, Never>] = [:]
    /// 문서 유형 선택 대기 중인 continuation
    var docTypeContinuations: [UUID: CheckedContinuation<DocumentType, Never>] = [:]
    /// 팀 구성 확인 대기 중인 continuation (방 ID → continuation, Set<UUID>? = 최종 선택 또는 nil)
    var teamConfirmationContinuations: [UUID: CheckedContinuation<Set<UUID>?, Never>] = [:]
    /// 이전 사이클 완료 시점의 에이전트 수 (후속 사이클에서 에이전트 변동 감지용)
    var previousCycleAgentCount: [UUID: Int] = [:]
    /// 단계 롤백 요청 (PlanCard 클릭 시 설정, StepExecutionEngine이 소비)
    var stepRollbackTargets: [UUID: Int] = [:]
    /// ask_user 도구의 선택지 (방 ID → 옵션 목록) — UserInputCard에서 버튼으로 표시
    @Published var pendingQuestionOptions: [UUID: [String]] = [:]

    /// 플러그인 이벤트 디스패치 (PluginManager가 설정)
    var pluginEventDelegate: ((PluginEvent) -> Void)?

    /// 플러그인 도구 인터셉트 (PluginManager가 설정)
    var pluginInterceptToolDelegate: ((String, [String: String]) async -> ToolInterceptResult)?

    deinit {
        timerTask?.cancel()
        saveTask?.cancel()
        for task in roomTasks.values { task.cancel() }
        for task in reviewAutoApprovalTasks.values { task.cancel() }
    }

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
    var masterAgentName: String {
        agentStore?.masterAgent?.name ?? "DOUGLAS"
    }

    // MARK: - WorkflowHost

    func room(for id: UUID) -> Room? {
        rooms.first(where: { $0.id == id })
    }

    func updateRoom(id: UUID, _ mutate: (inout Room) -> Void) {
        guard let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rooms[idx])
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
        room.workflowState.intent = intent

        // 초기 에이전트의 참조 프로젝트를 방에 병합
        for agentID in agentIDs {
            if let agent = agentStore?.agents.first(where: { $0.id == agentID }) {
                for path in agent.referenceProjectPaths {
                    if !room.projectContext.projectPaths.contains(path) {
                        room.projectContext.projectPaths.append(path)
                    }
                }
            }
        }

        rooms.append(room)
        selectedRoomID = room.id
        syncAgentStatuses()
        scheduleSave()
        pluginEventDelegate?(.roomCreated(roomID: room.id, title: room.title))
        return room
    }

    /// 사용자 수동 방 생성 + 바로 작업 시작. 생성된 roomID 반환.
    @discardableResult
    func createManualRoom(title: String, agentIDs: [UUID], task: String, projectPaths: [String] = [], buildCommand: String? = nil, testCommand: String? = nil, intent: WorkflowIntent? = nil, attachments: [FileAttachment]? = nil) -> UUID {
        // 마스터를 첫 번째로 배치 (intake/clarify는 항상 마스터가 수행)
        var orderedIDs = agentIDs
        if let masterID = agentStore?.masterAgent?.id {
            orderedIDs.removeAll { $0 == masterID }
            orderedIDs.insert(masterID, at: 0)
        }
        let room = createRoom(title: title, agentIDs: orderedIDs, createdBy: .user, projectPaths: projectPaths, buildCommand: buildCommand, testCommand: testCommand, intent: intent)

        // 사용자 메시지 추가
        let userMsg = ChatMessage(role: .user, content: task, attachments: attachments)
        appendMessage(userMsg, to: room.id)

        // 워크플로우 시작 (추적 가능)
        launchWorkflow(roomID: room.id, task: task)
        return room.id
    }

    /// 워크플로우를 추적 가능한 Task로 시작
    func launchWorkflow(roomID: UUID, task: String) {
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task { [weak self] in
            await self?.startRoomWorkflow(roomID: roomID, task: task)
            self?.roomTasks.removeValue(forKey: roomID)
        }
    }

    // MARK: - 방에 메시지 추가

    func appendMessage(_ message: ChatMessage, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].messages.append(message)
        scheduleSave()
        pluginEventDelegate?(.messageAdded(roomID: roomID, message: message))
    }

    /// 특정 메시지 앞에 삽입 (도구 활동을 스트리밍 placeholder 앞에 배치할 때 사용)
    func insertMessage(_ message: ChatMessage, to roomID: UUID, beforeMessageID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        if let insertIdx = rooms[idx].messages.firstIndex(where: { $0.id == beforeMessageID }) {
            rooms[idx].messages.insert(message, at: insertIdx)
        } else {
            rooms[idx].messages.append(message)
        }
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
    func trackPhaseActivity(
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

    // MARK: - 문서 파일 저장

    /// documentType이 설정된 방에서 자동 파일 저장 (NSSavePanel)
    /// - 1차: 에이전트가 실제 생성한 문서 파일이 있으면 해당 경로 링크
    /// - 2차: 메시지 콘텐츠 추출 후 MD 파일 저장
    private func offerDocumentSave(roomID: UUID, task: String? = nil) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              room.workflowState.documentType != nil,
              room.status != .failed else { return }

        // 1차: 에이전트가 실제 생성한 문서 파일 확인 (바이너리 포맷: xlsx, pptx 등)
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

        // 2차: 메시지에서 콘텐츠 추출 후 파일 저장
        guard let content = DocumentExporter.extractDocumentContent(from: room) else { return }

        let suggestedName = DocumentExporter.suggestedFilename(room: room, content: content)

        // 요청 포맷 감지 (task 우선, 없으면 마지막 user 메시지)
        let userTask = (task ?? room.messages.last(where: { $0.role == .user })?.content ?? "").lowercased()
        let format = DocumentExporter.detectRequestedFormat(userTask)

        // 설정 경로 접근 불가 경고
        if let warning = DocumentExporter.checkSaveDirectoryWarning() {
            let warnMsg = ChatMessage(role: .system, content: warning, messageType: .phaseTransition)
            appendMessage(warnMsg, to: roomID)
        }

        let url: URL?
        if format == "pdf" {
            let pdfMsg = ChatMessage(role: .system, content: "Markdown → PDF 변환 중…", messageType: .phaseTransition)
            appendMessage(pdfMsg, to: roomID)
            url = await DocumentExporter.exportToPDF(markdownContent: content, suggestedName: suggestedName)
        } else {
            let savingMsg = ChatMessage(role: .system, content: "문서를 파일로 저장합니다…", messageType: .phaseTransition)
            appendMessage(savingMsg, to: roomID)
            url = DocumentExporter.saveDocument(content: content, suggestedName: suggestedName, defaultExtension: format)
        }

        if let url {
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
    func handleDocumentOutput(roomID: UUID, task: String, suggestedType: DocumentType?, isFormatConversion: Bool = false) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }

        let docType = suggestedType ?? .freeform
        rooms[idx].workflowState.documentType = docType
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
        let docMsgID = await executeDocumentWritingStep(roomID: roomID, docType: docType, task: task, isFormatConversion: isFormatConversion)

        // 자동 저장
        await offerDocumentSave(roomID: roomID, task: task)

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
    private func executeDocumentWritingStep(roomID: UUID, docType: DocumentType, task: String, isFormatConversion: Bool = false) async -> UUID? {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return nil }

        // 에이전트 선택: 전용 문서 에이전트 우선 → docType keywords 폴백 → 첫 번째 전문가
        let specialistIDs = executingAgentIDs(in: roomID)
        let agentID: UUID? = {
            // 1. 전역 풀에서 전용 문서 에이전트 탐색
            let allSubAgents = agentStore?.subAgents ?? []
            let docNameKWs: Set<String> = ["문서", "리서치", "작성"]
            let nonDocKWs: Set<String> = ["개발", "jira", "프론트", "백엔드"]
            if let docAgent = allSubAgents.first(where: { sub in
                let nameL = sub.name.lowercased()
                return docNameKWs.contains(where: { nameL.contains($0) })
                    && !nonDocKWs.contains(where: { nameL.contains($0) })
            }) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }),
                   !rooms[i].assignedAgentIDs.contains(docAgent.id) {
                    addAgent(docAgent.id, to: roomID, silent: false)
                }
                return docAgent.id
            }

            // 2. docType preferredKeywords 기반 폴백
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

        let requestedFormat = DocumentExporter.detectRequestedFormat(task.lowercased())
        let isBinaryFormat = DocumentExporter.binaryFormats.contains(requestedFormat)

        // 포맷 변환: 원본 내용을 추출하여 프롬프트에 직접 포함
        let formatConversionBlock: String
        if isFormatConversion {
            // 이전 대화에서 가장 최근의 실질적 응답을 원본으로 사용
            let originalContent = room.messages.reversed()
                .first(where: { $0.role == .assistant && $0.messageType == .text && $0.content.count >= 100 })?
                .content ?? ""
            let contentBlock = originalContent.isEmpty ? "" : """

            [원본 내용 — 아래 내용을 빠짐없이 문서화하세요]
            \(originalContent)
            """
            formatConversionBlock = """

            ⚠️ 이것은 "포맷 변환" 요청입니다.
            이전 대화에서 이미 작성된 답변 내용을 문서 형태로 정리하는 것이 목적입니다.
            기존 내용을 충실히 보존하면서 문서 구조(제목, 섹션, 표 등)를 적용하세요.
            새로운 내용을 추가하거나 기존 내용을 임의로 생략하지 마세요.
            링크나 참조만 나열하지 말고, 각 항목의 실제 내용을 본문에 포함하세요.
            \(contentBlock)
            """
        } else {
            formatConversionBlock = ""
        }

        let docPrompt: String
        if isBinaryFormat {
            // 바이너리 포맷 (xlsx, pptx, docx): LLM이 file_write로 직접 생성
            let saveDir = DocumentExporter.resolvedSaveDirectoryPath()
            let suggestedName = DocumentExporter.suggestedFilename(room: room)
            let targetPath = "\(saveDir)/\(DocumentExporter.sanitizeFilename(suggestedName, ext: requestedFormat))"
            docPrompt = """
            \(systemPrompt(for: agent, roomID: roomID))

            ⚠️ 당신은 지금 "파일 생성 모드"입니다.
            이전 대화와 분석 내용을 바탕으로 \(requestedFormat) 파일을 생성합니다.
            \(formatConversionBlock)

            [작업]
            \(task)

            [파일 저장]
            file_write 도구를 사용하여 다음 경로에 파일을 저장하세요:
            \(targetPath)

            [절대 규칙 — 위반 시 실패로 간주]
            1. 반드시 한국어로 작성하세요.
            2. file_write 도구로 파일을 반드시 생성하세요.
            3. 모르는 주제나 최신 정보가 필요하면 web_search로 검색한 후 작성하세요.
            4. 사용자에게 추가 질문을 하지 마세요.
            5. 파일 생성 완료 후 간단히 결과만 알려주세요.
            """
        } else {
            // 텍스트 포맷 (md, csv, json, txt, pdf): Markdown/텍스트 출력 → 시스템 저장
            docPrompt = """
            \(systemPrompt(for: agent, roomID: roomID))

            ⚠️ 당신은 지금 "문서 작성 모드"입니다.
            할 일은 딱 하나: 본문을 텍스트로 출력하는 것.
            파일 저장은 시스템이 자동으로 처리합니다. 당신은 텍스트만 출력하면 됩니다.

            이전 대화와 분석 내용을 바탕으로 문서를 작성합니다.
            \(templateBlock)\(formatConversionBlock)

            [작업]
            \(task)
            ※ 위 작업에서 파일 형식(PDF, MD 등)이 언급되어도 신경 쓰지 마세요.
            시스템이 알아서 처리합니다. 당신은 텍스트만 출력하면 됩니다.

            [절대 규칙 — 위반 시 실패로 간주]
            1. 반드시 한국어로 작성하세요. 영어로 응답하지 마세요.
            2. 서론, 인사말, 설명 없이 바로 문서 본문을 출력하세요.
            3. 도구 호출 없이 텍스트만 출력하세요. 시스템이 파일 저장을 대신합니다.
            4. 파일 저장, 권한, 도구, 스크립트, 설치 명령에 대해 일절 언급하지 마세요.
            5. 모르는 주제나 최신 정보가 필요하면 web_search로 검색한 후 작성하세요.
            6. 사용자에게 추가 질문을 하지 마세요.
            7. 완전한 문서를 처음부터 끝까지 빠짐없이 출력하세요.

            [문서 포맷]
            - 제목은 # (H1)으로 시작
            - 주요 섹션은 ## (H2), 하위 섹션은 ### (H3) 사용
            - 핵심 정보는 표(테이블)로 요약
            - 출처가 있으면 문서 마지막에 "## 참고 자료" 섹션으로 정리
            - Markdown 문법을 일관되게 사용하세요
            """
        }

        let context = makeToolContext(roomID: roomID, currentAgentID: id)
        let msgID = UUID()

        // 도구 활동 추적용 progress 메시지
        let progressMsg = ChatMessage(
            role: .system,
            content: "문서 작성 중…",
            messageType: .progress
        )
        appendMessage(progressMsg, to: roomID)

        do {
            let placeholder = ChatMessage(id: msgID, role: .assistant, content: "", agentName: agent.name)
            appendMessage(placeholder, to: roomID)

            let buffer = StreamBuffer()
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: docPrompt,
                conversationMessages: history,
                context: context,
                onToolActivity: { [weak self] activity, detail in
                    guard let self else { return }
                    Task { @MainActor in
                        let toolMsg = ChatMessage(
                            role: .assistant,
                            content: activity,
                            agentName: agent.name,
                            messageType: .toolActivity,
                            activityGroupID: progressMsg.id,
                            toolDetail: detail
                        )
                        self.insertMessage(toolMsg, to: roomID, beforeMessageID: msgID)
                    }
                },
                onStreamChunk: { [weak self] chunk in
                    guard let self else { return }
                    let current = buffer.append(chunk)
                    Task { @MainActor in
                        self.updateMessageContent(msgID, newContent: current, in: roomID)
                    }
                },
                allowedToolIDs: isBinaryFormat ? ["web_search", "file_write", "shell_exec"] : ["web_search"]
            )
            updateMessageContent(msgID, newContent: response, in: roomID)
        } catch {
            let errMsg = ChatMessage(role: .system, content: "문서 작성 중 오류: \(error.localizedDescription)", messageType: .error)
            appendMessage(errMsg, to: roomID)
        }

        speakingAgentIDByRoom.removeValue(forKey: roomID)
        return msgID
    }

    // MARK: - clarify 후 문서 신호 재감지

    /// 사용자 피드백 메시지에서 문서 출력 신호 감지 (clarify 이후 실행)
    func detectDocumentSignalFromMessages(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              !rooms[idx].workflowState.autoDocOutput else { return }

        let recentUserMessages = rooms[idx].messages
            .filter { $0.role == .user }
            .suffix(3)
            .map { $0.content }
            .joined(separator: " ")

        if let docResult = DocumentRequestDetector.quickDetect(recentUserMessages),
           docResult.isDocumentRequest {
            rooms[idx].workflowState.autoDocOutput = true
            rooms[idx].workflowState.documentType = docResult.suggestedDocType ?? .freeform
        }
    }

    /// 사용자가 방에 메시지 보내기
    func sendUserMessage(_ text: String, to roomID: UUID, attachments: [FileAttachment]? = nil) async {
        let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMsg, to: roomID)

        guard let room = rooms.first(where: { $0.id == roomID }) else { return }

        // 작업 진행 중: 워크플로우를 취소하지 않음 (승인 대기·입력 대기·실행 중 모두 포함)
        if room.isActive {
            if let cont = userInputContinuations.removeValue(forKey: roomID) {
                cont.resume(returning: text)
            }
            scheduleSave()
            return
        }

        // 완료/실패 → 새 후속 사이클 시작
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = Task { [weak self] in
            await self?.launchFollowUpCycle(roomID: roomID, task: text)
            self?.roomTasks.removeValue(forKey: roomID)
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
        rooms[idx].workflowState.autoDocOutput = false
        rooms[idx].workflowState.documentType = nil

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
            rooms[idx].workflowState.documentType = docType
            rooms[idx].workflowState.autoDocOutput = true
        }

        // 타이핑 인디케이터 해제 (이후 각 phase에서 개별 설정)
        speakingAgentIDByRoom.removeValue(forKey: roomID)

        // 이전 작업 컨텍스트는 LLM에 직접 전달 (executeFollowUpAgentTurn에서 workLog 주입)
        // UI에는 표시하지 않음

        // 방 재활성화
        rooms[idx].transitionTo(.planning)
        rooms[idx].completedAt = nil

        // 순수 포맷 변환 감지: 기존 대화 내용을 문서로 변환하는 요청 (새 작업 없음)
        // "md파일로 만들어줘", "문서로 정리해줘" 등 — LLM이 기존 내용을 정리하여 문서 출력
        let isFormatConversion = detectedDocType != nil && DocumentRequestDetector.isFormatConversionOnly(task)
        if isFormatConversion {
            // 문서 에이전트 배정 후 LLM 문서 작성
            let allSubAgents = agentStore?.subAgents ?? []
            let docNameKWs: Set<String> = ["문서", "리서치", "작성"]
            let nonDocKWs: Set<String> = ["개발", "jira", "프론트", "백엔드"]
            if let docAgent = allSubAgents.first(where: { sub in
                let nameL = sub.name.lowercased()
                return docNameKWs.contains(where: { nameL.contains($0) })
                    && !nonDocKWs.contains(where: { nameL.contains($0) })
            }) {
                if let i = rooms.firstIndex(where: { $0.id == roomID }),
                   !rooms[i].assignedAgentIDs.contains(docAgent.id) {
                    addAgent(docAgent.id, to: roomID, silent: false)
                }
            }

            let specialists = executingAgentIDs(in: roomID)
            if !specialists.isEmpty {
                previousCycleAgentCount[roomID] = specialists.count
                await handleDocumentOutput(roomID: roomID, task: task, suggestedType: detectedDocType, isFormatConversion: isFormatConversion)

                // handleDocumentOutput이 .completed를 설정하지 못한 경우 보완
                if let i = rooms.firstIndex(where: { $0.id == roomID }),
                   rooms[i].status != .failed && rooms[i].status != .completed {
                    rooms[i].workflowState.currentPhase = nil
                    rooms[i].status = .completed
                    rooms[i].completedAt = Date()
                    pluginEventDelegate?(.roomCompleted(roomID: roomID, title: rooms[i].title))
                }
                syncAgentStatuses()
                scheduleSave()

                // 작업일지
                let hasSpec = !executingAgentIDs(in: roomID).isEmpty
                if hasSpec, let room = rooms.first(where: { $0.id == roomID }), room.workLog == nil {
                    await generateWorkLog(roomID: roomID, task: task)
                }
                if hasSpec { detectPlaybookOverrides(roomID: roomID) }
                return
            }
        }

        // Intent 재분류 (후속 사이클 특화)
        // 짧은 후속 메시지(< 60자)는 즉답으로 처리 (기존 컨텍스트 내 빠른 액션)
        let ruleBasedIntent = IntentClassifier.quickClassify(task)
        var resolvedIntent = ruleBasedIntent
        if resolvedIntent == nil {
            if task.count < 60 && detectedDocType == nil {
                // 후속 짧은 메시지: LLM 분류 없이 quickAnswer (pr해, 커밋해, 수정해줘 등)
                // 단, 문서 요청이 감지됐으면 quickAnswer로 단락하지 않음
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
        rooms[idx].workflowState.intent = resolvedIntent ?? .quickAnswer

        // quickAnswer로 확정된 경우 문서 오탐 리셋 (단순 질문은 문서 요청이 아님)
        if rooms[idx].workflowState.intent == .quickAnswer && detectedDocType != nil {
            detectedDocType = nil
            rooms[idx].workflowState.autoDocOutput = false
            rooms[idx].workflowState.documentType = nil
        }

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
            rooms[i].workflowState.completedPhases = completedPhases
        }
        // 현재 에이전트 수 기록 (다음 후속 사이클 비교용)
        previousCycleAgentCount[roomID] = specialists.count

        while true {
            guard !Task.isCancelled,
                  let currentRoom = rooms.first(where: { $0.id == roomID }),
                  currentRoom.isActive,
                  let currentIntent = currentRoom.workflowState.intent else { break }

            let phases = currentIntent.requiredPhases
            guard let nextPhase = phases.first(where: { !completedPhases.contains($0) }) else { break }

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.currentPhase = nextPhase
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
                let intent = rooms.first(where: { $0.id == roomID })?.workflowState.intent ?? .quickAnswer
                await executePlanPhase(roomID: roomID, task: task, intent: intent)
            case .build:
                await executeBuildPhase(roomID: roomID, task: task)
            case .execute:
                let intent = rooms.first(where: { $0.id == roomID })?.workflowState.intent ?? .quickAnswer
                await executeExecutePhase(roomID: roomID, task: task, intent: intent)
            case .review:
                await executeReviewPhase(roomID: roomID, task: task)
            case .deliver:
                await executeDeliverPhase(roomID: roomID, task: task)
            }

            completedPhases.insert(nextPhase)
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.completedPhases = completedPhases
            }
        }

        // 완료
        if let i = rooms.firstIndex(where: { $0.id == roomID }),
           rooms[i].status != .failed && rooms[i].status != .completed {
            rooms[i].workflowState.currentPhase = nil
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

    func makeToolContext(
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
            projectPaths: room?.effectiveProjectPaths ?? [],
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
            currentPhase: room?.workflowState.currentPhase,
            deferHighRiskTools: deferHighRiskTools,
            collectDeferred: collectDeferred.map { callback in
                { @Sendable deferred in callback(deferred) }
            } ?? { _ in },
            fetchPendingUserMessages: {
                // 컨텍스트 생성 시점의 메시지 수를 기준점으로 캡처
                let baselineCount = room?.messages.count ?? 0
                let checkpoint = MessageCheckpoint(baselineCount)
                return { @Sendable [weak self] () async -> [ConversationMessage] in
                    await MainActor.run { [weak self] () -> [ConversationMessage] in
                        guard let self, let room = self.rooms.first(where: { $0.id == roomID }) else { return [] }
                        let currentCount = room.messages.count
                        let base = checkpoint.value
                        guard currentCount > base else { return [] }
                        let newMsgs = room.messages[base..<currentCount].compactMap { msg -> ConversationMessage? in
                            guard msg.role == .user, msg.messageType == .text,
                                  !msg.content.isEmpty else { return nil }
                            return .user(msg.content)
                        }
                        if !newMsgs.isEmpty {
                            checkpoint.value = currentCount
                        }
                        return newMsgs
                    }
                }
            }(),
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
            modelName: modelName,
            skillTags: suggestion.skillTags ?? [],
            outputStyles: suggestion.outputStyles ?? []
        )
        agentStore?.addAgent(newAgent)
        addAgent(newAgent.id, to: roomID, silent: true)

        let msg = ChatMessage(
            role: .system,
            content: "'\(suggestion.name)' 에이전트가 생성되었습니다."
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
    func waitForSuggestionResponse(roomID: UUID) async {
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
    /// WORKFLOW_SPEC §6.4: 조건 충족 시 자동 진행 (사용자 확인 스킵)
    func showTeamConfirmation(roomID: UUID, individuallyApproved: Bool = false) async {
        let subAgents = agentStore?.subAgents ?? []
        let roomAgentIDs = rooms.first(where: { $0.id == roomID })?.assignedAgentIDs ?? []
        let specialists = executingAgentIDs(in: roomID)
        let candidates = subAgents.filter { !roomAgentIDs.contains($0.id) }.map(\.id)

        // 에이전트도 없고 후보도 없으면 → 워크플로우 완료
        if specialists.isEmpty && candidates.isEmpty {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.currentPhase = nil
                rooms[i].status = .completed
                rooms[i].completedAt = Date()
            }
            syncAgentStatuses()
            scheduleSave()
            return
        }

        // 개별 suggested 에이전트 승인을 이미 거쳤으면 자동 진행 (§6.4 확장)
        if individuallyApproved {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].approvalHistory.append(
                    ApprovalRecord(type: .teamConfirmation, approved: true, feedback: "개별 승인 완료 → 자동 진행")
                )
            }
            scheduleSave()
            return
        }

        // §6.4 자동 진행 판단
        if let room = rooms.first(where: { $0.id == roomID }) {
            let intentConfidence = room.requests.last?.intentClassification?.confidence ?? .medium
            let intent = room.workflowState.intent ?? .task
            let risk = room.taskBrief?.overallRisk ?? .medium
            let suggestedCount = candidates.count - specialists.count  // 미배정 후보 수
            let autoApprove = ApprovalPolicy.shouldAutoApproveTeam(
                intentConfidence: intentConfidence,
                intent: intent,
                overallRisk: risk,
                matchedAgentCount: specialists.count,
                suggestedAgentCount: max(0, suggestedCount)
            )
            if autoApprove {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].approvalHistory.append(
                        ApprovalRecord(type: .teamConfirmation, approved: true, feedback: "자동 진행 (§6.4)")
                    )
                }
                scheduleSave()
                return
            }
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
                    rooms[i].workflowState.currentPhase = nil
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
                content: "\(finalDescs.joined(separator: ", "))님이 참여합니다.",
                agentName: masterName
            )
            appendMessage(msg, to: roomID)
        }

        // 최종적으로 에이전트 없으면 완료
        if executingAgentIDs(in: roomID).isEmpty {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].workflowState.currentPhase = nil
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
                if !rooms[idx].projectContext.projectPaths.contains(path) {
                    rooms[idx].projectContext.projectPaths.append(path)
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


    // 워크플로우 실행 메서드 → RoomManager+Workflow.swift
    // 빌드/QA + 토론 메서드 → RoomManager+Discussion.swift


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

    func generateWorkLog(roomID: UUID, task: String) async {
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
        cleanupWorktree(roomID: roomID)
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

        // 작업일지 생성 (수동 완료 시에도, 이미 있으면 중복 생성 방지)
        if rooms[idx].workLog == nil {
            let task = rooms[idx].messages.first(where: { $0.role == .user })?.content ?? rooms[idx].title
            Task { await generateWorkLog(roomID: roomID, task: task) }
        }

        syncAgentStatuses()
        scheduleSave()
    }

    /// 사용자가 승인 카드에서 취소 → 작업 종료
    func cancelRoom(roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        roomTasks[roomID]?.cancel()
        roomTasks.removeValue(forKey: roomID)
        cleanupWorktree(roomID: roomID)
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
        rooms[idx].transitionTo(.cancelled)
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
        cleanupWorktree(roomID: roomID)
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
    func buildRoomHistory(roomID: UUID, limit: Int = 20) -> [ConversationMessage] {
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

    func scheduleSave() {
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
        // 비활성 방의 잔여 worktree 정리
        cleanupStaleWorktrees()
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

    // MARK: - Git Worktree 격리

    /// 같은 projectPath에 다른 활성 방이 있는지 확인
    private func hasActiveRoomOnPath(_ projectPath: String, excluding roomID: UUID) -> Bool {
        rooms.contains { room in
            room.id != roomID && room.isActive && room.primaryProjectPath == projectPath
        }
    }

    /// projectPath가 git 저장소인지 확인
    private func isGitRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    /// 동일 projectPath 충돌 시 worktree 생성 (lazy)
    func createWorktreeIfNeeded(roomID: UUID) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let projectPath = rooms[idx].primaryProjectPath,
              rooms[idx].projectContext.worktreePath == nil,
              isGitRepository(projectPath),
              hasActiveRoomOnPath(projectPath, excluding: roomID) else { return }

        let shortID = rooms[idx].shortID
        let worktreeDir = projectPath + "/.douglas/worktrees/" + shortID
        let branchName = "douglas/room-" + shortID

        try? FileManager.default.createDirectory(
            atPath: projectPath + "/.douglas/worktrees",
            withIntermediateDirectories: true, attributes: nil
        )

        let result = await ProcessRunner.run(
            executable: "/usr/bin/git",
            args: ["worktree", "add", worktreeDir, "-b", branchName],
            workDir: projectPath
        )

        if result.exitCode == 0 {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].projectContext.worktreePath = worktreeDir
                scheduleSave()
            }
        }
        // 실패 시 원본 디렉토리 사용 (graceful degradation)
    }

    /// worktree 정리 (fire-and-forget)
    private func cleanupWorktree(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let worktreePath = room.projectContext.worktreePath,
              let projectPath = room.primaryProjectPath else { return }

        let shortID = room.shortID
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].projectContext.worktreePath = nil
        }

        Task.detached {
            let _ = await ProcessRunner.run(
                executable: "/usr/bin/git",
                args: ["worktree", "remove", worktreePath, "--force"],
                workDir: projectPath
            )
            let _ = await ProcessRunner.run(
                executable: "/usr/bin/git",
                args: ["branch", "-D", "douglas/room-" + shortID],
                workDir: projectPath
            )
        }
    }

    /// 앱 재시작 시 비활성 방의 잔여 worktree 정리
    private func cleanupStaleWorktrees() {
        for (idx, room) in rooms.enumerated() {
            guard let wt = room.projectContext.worktreePath,
                  let pp = room.primaryProjectPath,
                  !room.isActive else { continue }
            rooms[idx].projectContext.worktreePath = nil
            Task.detached {
                let _ = await ProcessRunner.run(
                    executable: "/usr/bin/git",
                    args: ["worktree", "remove", wt, "--force"],
                    workDir: pp
                )
            }
        }
    }
}
