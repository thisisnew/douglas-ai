import Testing
import Foundation
@testable import DOUGLAS

@Suite("ChatMessage Model Tests")
struct ChatMessageTests {

    @Test("기본 초기화")
    func initDefaults() {
        let msg = ChatMessage(role: .user, content: "hello")
        #expect(msg.role == .user)
        #expect(msg.content == "hello")
        #expect(msg.messageType == .text)
        #expect(msg.agentName == nil)
    }

    @Test("모든 파라미터 초기화")
    func initAllParameters() {
        let msg = ChatMessage(
            role: .assistant,
            content: "response",
            agentName: "Agent1",
            messageType: .delegation
        )
        #expect(msg.role == .assistant)
        #expect(msg.content == "response")
        #expect(msg.agentName == "Agent1")
        #expect(msg.messageType == .delegation)
    }

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let original = ChatMessage(
            role: .assistant,
            content: "test content",
            agentName: "TestAgent",
            messageType: .summary
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.agentName == original.agentName)
        #expect(decoded.messageType == original.messageType)
    }

    @Test("Decodable - messageType 없는 레거시 JSON")
    func decodeLegacyWithoutMessageType() throws {
        let id = UUID()
        let json: [String: Any] = [
            "id": id.uuidString,
            "role": "user",
            "content": "hello",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let msg = try decoder.decode(ChatMessage.self, from: data)
        #expect(msg.messageType == .text)
    }

    @Test("MessageRole rawValue")
    func messageRoleRawValues() {
        #expect(MessageRole.user.rawValue == "user")
        #expect(MessageRole.assistant.rawValue == "assistant")
        #expect(MessageRole.system.rawValue == "system")
    }

    @Test("MessageType 모든 케이스")
    func messageTypeAllCases() {
        #expect(MessageType.text.rawValue == "text")
        #expect(MessageType.delegation.rawValue == "delegation")
        #expect(MessageType.summary.rawValue == "summary")
        #expect(MessageType.chainProgress.rawValue == "chainProgress")
        #expect(MessageType.suggestion.rawValue == "suggestion")
        #expect(MessageType.error.rawValue == "error")
        #expect(MessageType.discussionRound.rawValue == "discussionRound")
        #expect(MessageType.toolActivity.rawValue == "toolActivity")
    }

    @Test("빈 content")
    func emptyContent() {
        let msg = ChatMessage(role: .user, content: "")
        #expect(msg.content == "")
    }

    @Test("Codable - discussionRound 타입 라운드트립")
    func codableDiscussionRound() throws {
        let original = ChatMessage(role: .system, content: "── 라운드 1/3 ──", messageType: .discussionRound)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.messageType == .discussionRound)
        #expect(decoded.content == "── 라운드 1/3 ──")
    }

    @Test("Identifiable - 고유 ID")
    func uniqueIDs() {
        let a = ChatMessage(role: .user, content: "a")
        let b = ChatMessage(role: .user, content: "b")
        #expect(a.id != b.id)
    }

    // MARK: - 이미지 첨부

    @Test("attachments - 기본값 nil")
    func attachmentsDefault() {
        let msg = ChatMessage(role: .user, content: "hello")
        #expect(msg.attachments == nil)
    }

    @Test("attachments - Codable 라운드트립")
    func attachmentsCodableRoundTrip() throws {
        let data = Data("test image".utf8)
        let att = try FileAttachment.save(data: data, mimeType: "image/png")
        defer { att.delete() }

        let msg = ChatMessage(role: .user, content: "look at this", attachments: [att])
        let encoded = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)
        #expect(decoded.attachments?.count == 1)
        #expect(decoded.attachments?.first?.mimeType == "image/png")
        #expect(decoded.attachments?.first?.id == att.id)
    }

    @Test("attachments - 레거시 JSON 역호환 (attachments 필드 없음)")
    func attachmentsLegacyCompat() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "role": "user",
            "content": "old message",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "messageType": "text"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let msg = try decoder.decode(ChatMessage.self, from: data)
        #expect(msg.attachments == nil)
    }
}
