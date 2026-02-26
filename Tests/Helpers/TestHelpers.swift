import Foundation
@testable import AgentManagerLib

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
    isDevAgent: Bool = false,
    status: AgentStatus = .idle
) -> Agent {
    Agent(
        name: name,
        persona: persona,
        providerName: providerName,
        modelName: modelName,
        status: status,
        isMaster: isMaster,
        isDevAgent: isDevAgent
    )
}

/// 테스트용 ProviderConfig 팩토리 (Keychain 불필요)
func makeTestProviderConfig(
    name: String = "TestProvider",
    type: ProviderType = .custom,
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
