import Testing
import Foundation
@testable import AgentManagerLib

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
        #expect(MessageType.devAction.rawValue == "devAction")
        #expect(MessageType.buildResult.rawValue == "buildResult")
        #expect(MessageType.discussionRound.rawValue == "discussionRound")
    }

    @Test("Codable - devAction 타입 라운드트립")
    func codableDevAction() throws {
        let original = ChatMessage(role: .assistant, content: "build ok", agentName: "워즈니악", messageType: .devAction)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.messageType == .devAction)
        #expect(decoded.agentName == "워즈니악")
    }

    @Test("Codable - buildResult 타입 라운드트립")
    func codableBuildResult() throws {
        let original = ChatMessage(role: .assistant, content: "success", messageType: .buildResult)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.messageType == .buildResult)
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
}
