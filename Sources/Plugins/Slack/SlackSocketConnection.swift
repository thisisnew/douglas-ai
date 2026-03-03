import Foundation

/// Slack Socket Mode로 수신된 메시지
struct SlackIncomingMessage: Sendable {
    let channelID: String
    let channelName: String?
    let userID: String
    let userName: String
    let text: String
    let threadTS: String?
    let eventTS: String
}

/// Slack Socket Mode WebSocket 연결 관리
/// - apps.connections.open → WebSocket URL 획득
/// - URLSessionWebSocketTask로 이벤트 수신
/// - chat.postMessage Web API로 메시지 전송
final class SlackSocketConnection: @unchecked Sendable {
    private let appToken: String
    private let botToken: String
    private let triggerPatterns: [String]
    private let channelFilter: Set<String>

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private(set) var isConnected = false

    /// 메시지 수신 콜백 (@MainActor에서 호출됨)
    var onMessage: (@MainActor (SlackIncomingMessage) async -> Void)?

    init(
        appToken: String,
        botToken: String,
        triggerPatterns: [String],
        channelFilter: Set<String>
    ) {
        self.appToken = appToken
        self.botToken = botToken
        self.triggerPatterns = triggerPatterns
        self.channelFilter = channelFilter
    }

    // MARK: - 연결

    func connect() async -> Bool {
        guard let wsURL = await fetchWebSocketURL() else { return false }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        isConnected = true

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.webSocketTask?.sendPing { _ in }
            }
        }

        return true
    }

    func disconnect() {
        receiveTask?.cancel()
        pingTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // MARK: - Socket Mode: WebSocket URL 획득

    private func fetchWebSocketURL() async -> URL? {
        guard let url = URL(string: "https://slack.com/api/apps.connections.open") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true,
              let urlString = json["url"] as? String,
              let wsURL = URL(string: urlString) else {
            return nil
        }
        return wsURL
    }

    // MARK: - 수신 루프

    private func receiveLoop() async {
        while !Task.isCancelled, let ws = webSocketTask {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    await handleSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleSocketMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    _ = await connect()
                }
                return
            }
        }
    }

    private func handleSocketMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Socket Mode: 모든 envelope에 ACK 응답
        if let envelopeID = json["envelope_id"] as? String {
            await acknowledgeEnvelope(envelopeID)
        }

        let type = json["type"] as? String

        // events_api 타입만 처리
        guard type == "events_api",
              let payload = json["payload"] as? [String: Any],
              let event = payload["event"] as? [String: Any],
              let eventType = event["type"] as? String,
              eventType == "message" || eventType == "app_mention" else { return }

        // 봇 자신의 메시지 무시 (에코 방지)
        if event["bot_id"] != nil { return }

        guard let channelID = event["channel"] as? String,
              let userID = event["user"] as? String,
              let messageText = event["text"] as? String,
              let eventTS = event["ts"] as? String else { return }

        // 채널 필터 체크
        if !channelFilter.isEmpty && !channelFilter.contains(channelID) { return }

        // 트리거 패턴 체크
        let matchesTrigger = triggerPatterns.isEmpty || triggerPatterns.contains { pattern in
            messageText.lowercased().contains(pattern.lowercased())
        }
        guard matchesTrigger else { return }

        let threadTS = event["thread_ts"] as? String ?? eventTS
        let userName = await fetchUserName(userID: userID) ?? userID

        let incoming = SlackIncomingMessage(
            channelID: channelID,
            channelName: nil,
            userID: userID,
            userName: userName,
            text: messageText,
            threadTS: threadTS,
            eventTS: eventTS
        )

        await MainActor.run {
            let callback = onMessage
            Task { @MainActor in
                await callback?(incoming)
            }
        }
    }

    private func acknowledgeEnvelope(_ envelopeID: String) async {
        let ack: [String: String] = ["envelope_id": envelopeID]
        guard let data = try? JSONSerialization.data(withJSONObject: ack),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await webSocketTask?.send(.string(text))
    }

    // MARK: - 메시지 전송 (Web API)

    func sendMessage(channel: String, text: String, threadTS: String?) async {
        guard let url = URL(string: "https://slack.com/api/chat.postMessage") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["channel": channel, "text": text]
        if let ts = threadTS {
            body["thread_ts"] = ts
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - 유저 이름 캐시

    private var userNameCache: [String: String] = [:]

    private func fetchUserName(userID: String) async -> String? {
        if let cached = userNameCache[userID] { return cached }

        guard let url = URL(string: "https://slack.com/api/users.info?user=\(userID)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let name = (user["real_name"] as? String) ?? (user["name"] as? String) else {
            return nil
        }

        userNameCache[userID] = name
        return name
    }
}
