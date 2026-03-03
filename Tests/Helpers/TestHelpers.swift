import Foundation
@testable import DOUGLAS

/// 격리된 UserDefaults 생성 (테스트 후 자동 정리용)
func makeTestDefaults() -> UserDefaults {
    let suiteName = "test-\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

/// 테스트용 Agent 팩토리
func makeTestAgent(
    name: String = "TestAgent",
    persona: String = "Test persona",
    providerName: String = "TestProvider",
    modelName: String = "test-model",
    isMaster: Bool = false,
    status: AgentStatus = .idle
) -> Agent {
    Agent(
        name: name,
        persona: persona,
        providerName: providerName,
        modelName: modelName,
        status: status,
        isMaster: isMaster
    )
}

/// 테스트용 ProviderConfig 팩토리 (Keychain 불필요)
func makeTestProviderConfig(
    name: String = "TestProvider",
    type: ProviderType = .openAI,
    baseURL: String = "https://test.example.com",
    authMethod: AuthMethod = .none
) -> ProviderConfig {
    ProviderConfig(
        name: name,
        type: type,
        baseURL: baseURL,
        authMethod: authMethod
    )
}

/// 테스트용 ChatMessage 팩토리
func makeTestMessage(
    role: MessageRole = .user,
    content: String = "Hello",
    agentName: String? = nil,
    messageType: MessageType = .text
) -> ChatMessage {
    ChatMessage(
        role: role,
        content: content,
        agentName: agentName,
        messageType: messageType
    )
}

/// Mock HTTP 응답 생성 헬퍼
func mockHTTPResponse(url: String = "https://test.example.com", statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

/// 테스트용 RoomManager 팩토리 — 임시 디렉토리로 격리
@MainActor
func makeTestRoomManager() -> RoomManager {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("douglas-test-rooms-\(ProcessInfo.processInfo.processIdentifier)")
    RoomManager.roomDirectoryOverride = tmpDir
    return RoomManager()
}

/// @Sendable 클로저에서 mutable 값을 캡처하기 위한 thread-safe 박스
final class CapturedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T?
    var value: T? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
