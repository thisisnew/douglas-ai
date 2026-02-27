import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessageType: String, Codable {
    case text
    case delegation
    case summary
    case chainProgress
    case suggestion
    case error
    case discussionRound
    case toolActivity
    case buildStatus
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let agentName: String?
    let timestamp: Date
    var messageType: MessageType
    let attachments: [ImageAttachment]?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        agentName: String? = nil,
        timestamp: Date = Date(),
        messageType: MessageType = .text,
        attachments: [ImageAttachment]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.agentName = agentName
        self.timestamp = timestamp
        self.messageType = messageType
        self.attachments = attachments
    }

    // 기존 저장 데이터 호환
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        messageType = try container.decodeIfPresent(MessageType.self, forKey: .messageType) ?? .text
        attachments = try container.decodeIfPresent([ImageAttachment].self, forKey: .attachments)
    }
}
