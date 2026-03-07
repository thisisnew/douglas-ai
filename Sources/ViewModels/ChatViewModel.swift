import Foundation
import UserNotifications

/// 스트리밍 청크 누적용 스레드-안전 버퍼
private final class StreamBuffer: @unchecked Sendable {
    private var _value = ""
    func append(_ chunk: String) -> String {
        _value += chunk
        return _value
    }
}

// MARK: - ChatViewModel

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messagesByAgent: [UUID: [ChatMessage]] = [:]
    @Published var loadingAgentIDs: Set<UUID> = []
    @Published var toastMessage: String?
    @Published var showToast = false

    /// 하위 호환: 특정 에이전트가 로딩 중인지 확인
    func isLoading(for agentID: UUID?) -> Bool {
        guard let id = agentID else { return false }
        return loadingAgentIDs.contains(id)
    }

    private(set) var agentStore: AgentStore?
    private(set) var providerManager: ProviderManager?
    private(set) var roomManager: RoomManager?

    init() {}

    /// AppDelegate에서 한 번만 호출 — 의존성 설정 + 알림 권한 요청
    func configure(agentStore: AgentStore, providerManager: ProviderManager, roomManager: RoomManager? = nil) {
        self.agentStore = agentStore
        self.providerManager = providerManager
        self.roomManager = roomManager
        requestNotificationPermissionIfNeeded()
    }

    func messages(for agentID: UUID?) -> [ChatMessage] {
        guard let id = agentID else { return [] }
        return messagesByAgent[id] ?? []
    }

    /// 외부에서 메시지 추가
    func appendMessagePublic(_ message: ChatMessage, for agentID: UUID) {
        appendMessage(message, for: agentID)
    }

    // MARK: - 진행 중인 작업 취소

    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    /// 에이전트별 동시 실행 중인 작업 수 (로딩 상태 관리용)
    private var activeTaskCounts: [UUID: Int] = [:]

    /// 특정 에이전트의 진행 중인 작업을 취소
    func cancelTask(for agentID: UUID) {
        activeTasks[agentID]?.cancel()
        activeTasks.removeValue(forKey: agentID)
        activeTaskCounts[agentID] = 0
        loadingAgentIDs.remove(agentID)
        agentStore?.updateStatus(agentID: agentID, status: .idle)
    }

    /// .app 번들에서만 알림 권한 요청 (테스트 환경 크래시 방지)
    private func requestNotificationPermissionIfNeeded() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - 메시지 전송 (진입점)

    func sendMessage(_ text: String, agentID: UUID? = nil, attachments: [FileAttachment]? = nil) {
        guard let agentStore = agentStore,
              let providerManager = providerManager else { return }

        // agentID가 명시되면 해당 에이전트, 아니면 selectedAgent 사용
        let targetID = agentID ?? agentStore.selectedAgentID
        guard let agent = agentStore.agents.first(where: { $0.id == targetID }) else { return }

        // 마스터는 각 질문이 독립적 → 이전 작업 취소하지 않음
        // 서브에이전트는 기존 작업 취소
        if !agent.isMaster {
            activeTasks[agent.id]?.cancel()
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        appendMessage(userMessage, for: agent.id)

        loadingAgentIDs.insert(agent.id)
        activeTaskCounts[agent.id, default: 0] += 1

        let task = Task {
            if agent.isMaster {
                await handleMasterMessage(text, attachments: attachments, agent: agent, agentStore: agentStore)
            } else {
                await handleAgentMessage(text, agent: agent, providerManager: providerManager)
            }

            activeTaskCounts[agent.id, default: 1] -= 1
            // 모든 작업이 끝났을 때만 로딩 해제
            if activeTaskCounts[agent.id, default: 0] <= 0 {
                loadingAgentIDs.remove(agent.id)
                activeTaskCounts.removeValue(forKey: agent.id)
            }
            activeTasks.removeValue(forKey: agent.id)
        }
        activeTasks[agent.id] = task
    }

    // MARK: - 마스터 메시지 처리 → 즉시 방 생성

    private func handleMasterMessage(
        _ text: String,
        attachments: [FileAttachment]? = nil,
        agent: Agent,
        agentStore: AgentStore
    ) async {
        agentStore.updateStatus(agentID: agent.id, status: .working)

        guard let roomManager = roomManager else {
            let errorReply = ChatMessage(
                role: .assistant,
                content: "방 관리자를 사용할 수 없습니다.",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorReply, for: agent.id)
            agentStore.updateStatus(agentID: agent.id, status: .idle)
            return
        }

        // Pre-Intent 라우팅: 분류 전 특수 케이스 처리
        let hasAttachments = attachments?.isEmpty == false
        let route = IntentClassifier.preRoute(text, hasAttachments: hasAttachments)

        switch route {
        case .empty:
            // 텍스트 없음 + 파일 없음 → 무시
            agentStore.updateStatus(agentID: agent.id, status: .idle)
            return

        case .fileOnly:
            // 파일만 업로드 → 방 생성 후 사용자 의도 대기
            let roomTitle = Self.extractRoomTitle(from: text, hasAttachments: hasAttachments)
            let startMsg = ChatMessage(
                role: .assistant,
                content: "파일을 받았습니다. 작업방에서 원하시는 작업을 알려주세요.",
                agentName: agent.name,
                messageType: .delegation
            )
            appendMessage(startMsg, for: agent.id)

            let room = roomManager.createRoom(
                title: roomTitle,
                agentIDs: [agent.id],
                createdBy: .master(agentID: agent.id),
                intent: nil
            )
            roomManager.selectedRoomID = room.id
            roomManager.pendingAutoOpenRoomID = room.id
            let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
            roomManager.appendMessage(userMsg, to: room.id)
            // 빈 task로 워크플로우 시작 → executeUnderstandPhase에서 사용자 입력 대기
            roomManager.launchWorkflow(roomID: room.id, task: "")
            agentStore.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: agent.name, message: "파일 수신")

        case .command(let commandType):
            // 시스템 커맨드 → 즉시 처리 (방 생성 안 함)
            switch commandType {
            case .summonAgent(let name):
                let nameDesc = name.map { "\($0) " } ?? ""
                let reply = ChatMessage(
                    role: .assistant,
                    content: "\(nameDesc)에이전트를 사용하려면 사이드바에서 선택하거나, 작업 내용과 함께 요청해주세요.",
                    agentName: agent.name,
                    messageType: .text
                )
                appendMessage(reply, for: agent.id)
            }
            agentStore.updateStatus(agentID: agent.id, status: .idle)

        case .classified(let intent):
            // 정상 분류 → 방 생성 + 워크플로우
            let roomTitle = Self.extractRoomTitle(from: text, hasAttachments: hasAttachments)
            let startMsg = ChatMessage(
                role: .assistant,
                content: "작업을 시작합니다: \(roomTitle)",
                agentName: agent.name,
                messageType: .delegation
            )
            appendMessage(startMsg, for: agent.id)

            let room = roomManager.createRoom(
                title: roomTitle,
                agentIDs: [agent.id],
                createdBy: .master(agentID: agent.id),
                intent: intent
            )
            roomManager.selectedRoomID = room.id
            roomManager.pendingAutoOpenRoomID = room.id
            let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
            roomManager.appendMessage(userMsg, to: room.id)
            roomManager.launchWorkflow(roomID: room.id, task: text)
            agentStore.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: agent.name, message: "작업 시작")

        case .ambiguous:
            // preRoute가 더 이상 .ambiguous를 반환하지 않지만, 안전장치로 task 처리
            let roomTitle = Self.extractRoomTitle(from: text, hasAttachments: hasAttachments)
            let startMsg = ChatMessage(
                role: .assistant,
                content: "작업을 시작합니다: \(roomTitle)",
                agentName: agent.name,
                messageType: .delegation
            )
            appendMessage(startMsg, for: agent.id)

            let room = roomManager.createRoom(
                title: roomTitle,
                agentIDs: [agent.id],
                createdBy: .master(agentID: agent.id),
                intent: .task
            )
            roomManager.selectedRoomID = room.id
            roomManager.pendingAutoOpenRoomID = room.id
            let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
            roomManager.appendMessage(userMsg, to: room.id)
            roomManager.launchWorkflow(roomID: room.id, task: text)
            agentStore.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: agent.name, message: "작업 시작")
        }
    }

    // MARK: - 서브 에이전트 직접 대화

    private func handleAgentMessage(
        _ text: String,
        agent: Agent,
        providerManager: ProviderManager
    ) async {
        agentStore?.updateStatus(agentID: agent.id, status: .working)

        guard let provider = providerManager.provider(named: agent.providerName) else {
            agentStore?.updateStatus(agentID: agent.id, status: .error, errorMessage: "프로바이더를 찾을 수 없습니다.")
            return
        }

        let history = buildConversationHistory(for: agent.id)
        let agentID = agent.id

        // 스트리밍용 placeholder 메시지
        let placeholderID = UUID()
        let placeholder = ChatMessage(id: placeholderID, role: .assistant, content: "", agentName: agent.name)
        appendMessage(placeholder, for: agentID)

        do {
            let buffer = StreamBuffer()
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.resolvedSystemPrompt,
                conversationMessages: history,
                onToolActivity: { [weak self] activity, detail in
                    guard let self else { return }
                    Task { @MainActor in
                        let toolMsg = ChatMessage(role: .assistant, content: activity, agentName: agent.name, messageType: .toolActivity, toolDetail: detail)
                        self.appendMessage(toolMsg, for: agentID)
                    }
                },
                onStreamChunk: { [weak self] chunk in
                    guard let self else { return }
                    let current = buffer.append(chunk)
                    Task { @MainActor in
                        self.updateMessageContent(placeholderID, newContent: current, for: agentID)
                    }
                },
                useTools: false  // 1:1 채팅: 도구 없이 스트리밍 우선
            )

            updateMessageContent(placeholderID, newContent: response, for: agentID)
            agentStore?.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: agent.name, message: response)

        } catch {
            agentStore?.updateStatus(agentID: agent.id, status: .error, errorMessage: error.userFacingMessage)
            showToastMessage("\(agent.name) 오류: \(error.userFacingMessage)")
            sendErrorNotification(agentName: agent.name, error: error.userFacingMessage)

            updateMessageContent(placeholderID, newContent: "오류가 발생했습니다: \(error.userFacingMessage)", for: agentID)
            if var messages = messagesByAgent[agentID],
               let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].messageType = .error
                messagesByAgent[agentID] = messages
            }
        }
    }

    // MARK: - Helpers

    private func appendMessage(_ message: ChatMessage, for agentID: UUID) {
        if messagesByAgent[agentID] == nil {
            messagesByAgent[agentID] = []
        }
        messagesByAgent[agentID]?.append(message)
        scheduleSave()
    }

    private func updateMessageContent(_ messageID: UUID, newContent: String, for agentID: UUID) {
        guard var messages = messagesByAgent[agentID],
              let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].content = newContent
        messagesByAgent[agentID] = messages
    }

    // MARK: - 대화 기록 영속화

    private static var chatDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var saveTask: Task<Void, Never>?

    /// 짧은 디바운스로 저장 (빈번한 쓰기 방지)
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveMessages()
        }
    }

    func clearMessages(for agentID: UUID) {
        // 첨부 이미지 파일 삭제
        if let messages = messagesByAgent[agentID] {
            for msg in messages {
                msg.attachments?.forEach { $0.delete() }
            }
        }
        messagesByAgent[agentID] = []
        // 저장 파일도 삭제
        let file = Self.chatDirectory.appendingPathComponent("\(agentID.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    func saveMessages() {
        let dir = Self.chatDirectory
        for (agentID, messages) in messagesByAgent {
            let file = dir.appendingPathComponent("\(agentID.uuidString).json")
            if let data = try? JSONEncoder().encode(messages) {
                try? data.write(to: file)
            }
        }
    }

    func loadMessages() {
        let dir = Self.chatDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let uuidString = file.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: uuidString),
               let data = try? Data(contentsOf: file),
               let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                messagesByAgent[uuid] = msgs
            } else {
                // 디코드 실패한 고아 파일 삭제
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 마스터 에이전트 채팅이 비어있으면 환영 메시지 추가
    func addWelcomeMessageIfNeeded() {
        guard let masterID = agentStore?.masterAgent?.id else { return }
        let msgs = messagesByAgent[masterID] ?? []
        guard msgs.isEmpty else { return }

        let masterName = agentStore?.masterAgent?.name ?? "DOUGLAS"
        let welcome = ChatMessage(
            role: .assistant,
            content: "무엇을 도와드릴까요?",
            agentName: masterName
        )
        appendMessage(welcome, for: masterID)
    }

    /// 존재하지 않는 에이전트의 채팅 기록 정리
    func pruneOrphanedChats(validAgentIDs: Set<UUID>) {
        let orphanIDs = Set(messagesByAgent.keys).subtracting(validAgentIDs)
        for agentID in orphanIDs {
            clearMessages(for: agentID)
        }
    }

    func buildHistory(for agentID: UUID) -> [(role: String, content: String)] {
        let msgs = messagesByAgent[agentID] ?? []
        return msgs
            .filter { [.text, .summary].contains($0.messageType) }
            .suffix(20)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "system"
                }
                return (role: role, content: msg.content)
            }
    }

    /// 이미지 첨부를 포함한 ConversationMessage 히스토리 빌드
    func buildConversationHistory(for agentID: UUID) -> [ConversationMessage] {
        let msgs = messagesByAgent[agentID] ?? []
        return msgs
            .filter { [.text, .summary].contains($0.messageType) }
            .suffix(20)
            .map { msg in
                let role: String
                switch msg.role {
                case .user:      role = "user"
                case .assistant: role = "assistant"
                case .system:    role = "system"
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

    private var toastDismissTask: Task<Void, Never>?

    func showToastMessage(_ message: String) {
        // 이전 dismiss 타이머 취소 → 경합 방지
        toastDismissTask?.cancel()
        toastMessage = message
        showToast = true
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            showToast = false
        }
    }

    // MARK: - 알림

    private nonisolated func sendNotification(agentName: String, message: String) {
        // 번들 ID가 없는 CLI 빌드에서는 UNUserNotificationCenter 접근 시 crash
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(agentName): 작업 완료"
        content.body = String(message.prefix(100))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private nonisolated func sendErrorNotification(agentName: String, error: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(agentName): 오류 발생"
        content.body = String(error.prefix(100))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 방 제목 추출

    /// Jira URL이면 키(PROJ-123)만 추출하여 간결한 제목 생성, 아닌 경우 원본 텍스트 사용
    /// Jira 상세 데이터는 executeIntakePhase에서 단 1회만 조회
    static func extractRoomTitle(from text: String, hasAttachments: Bool = false) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 빈 텍스트 (이미지만 전송)
        if trimmed.isEmpty {
            return hasAttachments ? "이미지 분석" : "새 작업"
        }

        // 모든 Jira 키 추출 (PROJ-123 패턴, 중복 제거)
        let jiraKeys = extractAllJiraKeys(from: trimmed)

        if !jiraKeys.isEmpty {
            let withoutURL = trimmed.replacingOccurrences(of: "https?://[^\\s]+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // URL만 있고 텍스트 없음
            if withoutURL.isEmpty {
                if jiraKeys.count == 1 { return jiraKeys[0] }
                // 같은 프로젝트면 프로젝트명 + N건
                let project = jiraKeys[0].components(separatedBy: "-").first ?? ""
                return "\(project) 티켓 \(jiraKeys.count)건"
            }

            // 텍스트가 있으면: 키 요약 + 사용자 텍스트
            let keyPrefix: String
            if jiraKeys.count == 1 {
                keyPrefix = "[\(jiraKeys[0])]"
            } else {
                let project = jiraKeys[0].components(separatedBy: "-").first ?? ""
                keyPrefix = "[\(project) \(jiraKeys.count)건]"
            }
            let desc = withoutURL.count <= 25 ? withoutURL : String(withoutURL.prefix(23)) + "…"
            return "\(keyPrefix) \(desc)"
        }

        // 일반 텍스트: 첫 줄, 30자 이내로 축약
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count <= 30 {
            return firstLine
        }
        return String(firstLine.prefix(28)) + "…"
    }

    /// 텍스트에서 모든 Jira 키 추출 (중복 제거, 순서 유지)
    private static func extractAllJiraKeys(from text: String) -> [String] {
        let pattern = "[A-Z][A-Z0-9]+-\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var keys: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let key = String(text[r])
            if seen.insert(key).inserted { keys.append(key) }
        }
        return keys
    }
}
