import Foundation
import UserNotifications

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

    func sendMessage(_ text: String, agentID: UUID? = nil, attachments: [ImageAttachment]? = nil) {
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
        attachments: [ImageAttachment]? = nil,
        agent: Agent,
        agentStore: AgentStore
    ) async {
        agentStore.updateStatus(agentID: agent.id, status: .working)

        let progressMsg = ChatMessage(
            role: .assistant,
            content: "방을 생성하는 중...",
            agentName: "마스터",
            messageType: .toolActivity
        )
        appendMessage(progressMsg, for: agent.id)

        // Jira URL 사전 조회
        let task = await enrichTaskWithJira(text)

        guard let roomManager = roomManager else {
            let errorReply = ChatMessage(
                role: .assistant,
                content: "방 관리자를 사용할 수 없습니다.",
                agentName: "마스터",
                messageType: .error
            )
            appendMessage(errorReply, for: agent.id)
            agentStore.updateStatus(agentID: agent.id, status: .idle)
            return
        }

        // 마스터가 직접 방 생성 (LLM 라우팅 없음)
        let delegationMsg = ChatMessage(
            role: .assistant,
            content: "작업을 시작합니다: \(task)",
            agentName: "마스터",
            messageType: .delegation
        )
        appendMessage(delegationMsg, for: agent.id)

        let room = roomManager.createRoom(
            title: task,
            agentIDs: [agent.id],
            createdBy: .master(agentID: agent.id)
        )
        roomManager.selectedRoomID = room.id
        roomManager.pendingAutoOpenRoomID = room.id

        // 사용자 메시지(이미지 포함)를 방에 추가
        let userMsg = ChatMessage(role: .user, content: task, attachments: attachments)
        roomManager.appendMessage(userMsg, to: room.id)

        roomManager.launchWorkflow(roomID: room.id, task: task)

        agentStore.updateStatus(agentID: agent.id, status: .idle)
        sendNotification(agentName: "마스터", message: "작업 시작")
    }

    // MARK: - 서브 에이전트 직접 대화

    private func handleAgentMessage(
        _ text: String,
        agent: Agent,
        providerManager: ProviderManager
    ) async {
        agentStore?.updateStatus(agentID: agent.id, status: .working)

        do {
            guard let provider = providerManager.provider(named: agent.providerName) else {
                throw AIProviderError.apiError("프로바이더 '\(agent.providerName)'을(를) 찾을 수 없습니다.")
            }

            let history = buildConversationHistory(for: agent.id)
            let agentID = agent.id
            let response = try await ToolExecutor.smartSend(
                provider: provider,
                agent: agent,
                systemPrompt: agent.resolvedSystemPrompt,
                conversationMessages: history,
                onToolActivity: { [weak self] activity in
                    Task { @MainActor in
                        let toolMsg = ChatMessage(role: .assistant, content: activity, agentName: agent.name, messageType: .toolActivity)
                        self?.appendMessage(toolMsg, for: agentID)
                    }
                }
            )

            let reply = ChatMessage(role: .assistant, content: response, agentName: agent.name)
            appendMessage(reply, for: agent.id)
            agentStore?.updateStatus(agentID: agent.id, status: .idle)
            sendNotification(agentName: agent.name, message: response)

        } catch {
            agentStore?.updateStatus(agentID: agent.id, status: .error, errorMessage: error.localizedDescription)
            showToastMessage("\(agent.name) 오류: \(error.localizedDescription)")
            sendErrorNotification(agentName: agent.name, error: error.localizedDescription)

            let errorReply = ChatMessage(
                role: .assistant,
                content: "오류가 발생했습니다: \(error.localizedDescription)",
                agentName: agent.name,
                messageType: .error
            )
            appendMessage(errorReply, for: agent.id)
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
        messagesByAgent[agentID] = []
        // 저장 파일도 삭제
        let file = Self.chatDirectory.appendingPathComponent("\(agentID.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    private func saveMessages() {
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
            guard let uuid = UUID(uuidString: uuidString),
                  let data = try? Data(contentsOf: file),
                  let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data) else { continue }
            messagesByAgent[uuid] = msgs
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
                    attachments: msg.attachments
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

    // MARK: - Jira URL 사전 조회

    /// task 텍스트에서 Jira URL을 감지하고, 인증된 API로 티켓 내용을 조회하여 task에 포함
    private func enrichTaskWithJira(_ task: String) async -> String {
        let jiraConfig = JiraConfig.shared
        guard jiraConfig.isConfigured, jiraConfig.isJiraURL(task) else {
            return task
        }

        // URL 추출 (https://domain/browse/PROJ-123 패턴)
        guard let urlRange = task.range(of: "https://[^\\s]+", options: .regularExpression),
              let url = URL(string: String(task[urlRange])) else {
            return task
        }

        let apiURLString = jiraConfig.apiURL(from: url.absoluteString)
        guard let apiURL = URL(string: apiURLString),
              let auth = jiraConfig.authHeader() else {
            return task
        }

        var request = URLRequest(url: apiURL)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return task }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return task
            }

            // 핵심 필드 추출
            let fields = json["fields"] as? [String: Any] ?? [:]
            let summary = fields["summary"] as? String ?? ""
            let description = extractDescription(from: fields["description"])
            let status_ = (fields["status"] as? [String: Any])?["name"] as? String ?? ""
            let priority = (fields["priority"] as? [String: Any])?["name"] as? String ?? ""
            let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? ""
            let labels = (fields["labels"] as? [String]) ?? []
            let key = json["key"] as? String ?? ""

            // 댓글 추출
            let commentBody = fields["comment"] as? [String: Any]
            let comments = (commentBody?["comments"] as? [[String: Any]])?.suffix(5) ?? []
            let commentTexts = comments.compactMap { comment -> String? in
                let author = (comment["author"] as? [String: Any])?["displayName"] as? String ?? "?"
                let body = extractDescription(from: comment["body"])
                guard !body.isEmpty else { return nil }
                return "  - \(author): \(body.prefix(200))"
            }

            var enriched = task
            enriched += "\n\n--- Jira 티켓 내용 [\(key)] ---"
            enriched += "\n제목: \(summary)"
            enriched += "\n유형: \(issueType) | 상태: \(status_) | 우선순위: \(priority)"
            if !labels.isEmpty {
                enriched += "\n레이블: \(labels.joined(separator: ", "))"
            }
            if !description.isEmpty {
                enriched += "\n\n설명:\n\(String(description.prefix(2000)))"
            }
            if !commentTexts.isEmpty {
                enriched += "\n\n최근 댓글:\n\(commentTexts.joined(separator: "\n"))"
            }
            enriched += "\n--- 끝 ---"

            return enriched
        } catch {
            return task
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
}
