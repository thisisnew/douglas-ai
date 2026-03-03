import Foundation

/// Slack 연동 플러그인
/// Socket Mode로 Slack 메시지를 수신하여 DOUGLAS Room으로 라우팅하고,
/// Room의 응답을 Slack 스레드로 전송한다.
@MainActor
final class SlackPlugin: DougPlugin {
    let info = PluginInfo(
        id: "slack",
        name: "Slack 연동",
        description: "Slack 채널의 메시지를 DOUGLAS 워크플로우로 연결합니다.",
        version: "1.0.0",
        iconSystemName: "bubble.left.and.bubble.right"
    )

    private(set) var isActive = false
    private var context: PluginContext?
    private var socketConnection: SlackSocketConnection?
    private var channelRoomMapper = SlackChannelRoomMapper()

    let configFields: [PluginConfigField] = [
        PluginConfigField(
            key: "botToken",
            label: "Bot Token (xoxb-)",
            type: .text,
            isSecret: true,
            placeholder: "xoxb-..."
        ),
        PluginConfigField(
            key: "appToken",
            label: "App-Level Token (xapp-)",
            type: .text,
            isSecret: true,
            placeholder: "xapp-..."
        ),
        PluginConfigField(
            key: "triggerPatterns",
            label: "트리거 패턴 (쉼표 구분)",
            type: .text,
            isSecret: false,
            placeholder: "@douglas, !ask"
        ),
        PluginConfigField(
            key: "channelFilter",
            label: "채널 필터 (빈칸=전체)",
            type: .text,
            isSecret: false,
            placeholder: "C01234567, C89ABCDEF"
        )
    ]

    // MARK: - 라이프사이클

    func configure(context: PluginContext) {
        self.context = context
    }

    func activate() async -> Bool {
        guard let botToken = PluginConfigStore.getValue("botToken", pluginID: info.id, isSecret: true),
              let appToken = PluginConfigStore.getValue("appToken", pluginID: info.id, isSecret: true),
              !botToken.isEmpty, !appToken.isEmpty else {
            return false
        }

        let patterns = PluginConfigStore.getValue("triggerPatterns", pluginID: info.id)?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []

        let channels = PluginConfigStore.getValue("channelFilter", pluginID: info.id)?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []

        channelRoomMapper.loadMappings(pluginID: info.id)

        socketConnection = SlackSocketConnection(
            appToken: appToken,
            botToken: botToken,
            triggerPatterns: patterns,
            channelFilter: Set(channels)
        )
        socketConnection?.onMessage = { [weak self] incoming in
            await self?.handleIncomingSlackMessage(incoming)
        }

        let connected = await socketConnection?.connect() ?? false
        isActive = connected
        return connected
    }

    func deactivate() async {
        socketConnection?.disconnect()
        socketConnection = nil
        isActive = false
    }

    // MARK: - Incoming: Slack → DOUGLAS

    private func handleIncomingSlackMessage(_ message: SlackIncomingMessage) async {
        guard let ctx = context else { return }

        let cleanText = SlackMessageParser.extractCleanText(message.text)
        guard !cleanText.isEmpty else { return }

        if let roomID = channelRoomMapper.roomID(for: message.channelID) {
            // 기존 매핑: Room에 메시지 주입
            await ctx.sendUserMessage(
                "[Slack: \(message.userName)] \(cleanText)",
                to: roomID
            )
        } else {
            // 새 매핑: Room 생성
            let title = "Slack: #\(message.channelName ?? message.channelID)"
            if let roomID = ctx.createRoom(title: title, task: cleanText) {
                channelRoomMapper.setMapping(
                    channelID: message.channelID,
                    roomID: roomID,
                    threadTS: message.threadTS
                )
                channelRoomMapper.saveMappings(pluginID: info.id)
            }
        }
    }

    // MARK: - Outgoing: DOUGLAS → Slack

    func handle(event: PluginEvent) async {
        switch event {
        case .messageAdded(let roomID, let message):
            // assistant 텍스트 메시지만 Slack으로 전송
            guard message.role == .assistant,
                  message.messageType == .text,
                  let mapping = channelRoomMapper.mapping(for: roomID),
                  let conn = socketConnection else { return }

            let slackText = SlackMessageParser.formatForSlack(
                content: message.content,
                agentName: message.agentName
            )
            await conn.sendMessage(
                channel: mapping.channelID,
                text: slackText,
                threadTS: mapping.threadTS
            )

        case .roomCompleted(let roomID, _):
            guard let mapping = channelRoomMapper.mapping(for: roomID),
                  let conn = socketConnection else { return }
            await conn.sendMessage(
                channel: mapping.channelID,
                text: "작업이 완료되었습니다.",
                threadTS: mapping.threadTS
            )

        case .roomFailed(let roomID, _):
            guard let mapping = channelRoomMapper.mapping(for: roomID),
                  let conn = socketConnection else { return }
            await conn.sendMessage(
                channel: mapping.channelID,
                text: "작업 처리 중 오류가 발생했습니다.",
                threadTS: mapping.threadTS
            )

        default:
            break
        }
    }
}
