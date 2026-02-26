import Foundation
@testable import AgentManagerLib

class MockAIProvider: AIProvider {
    let config: ProviderConfig

    var fetchModelsResult: Result<[String], Error> = .success(["mock-model"])
    var sendMessageResult: Result<String, Error> = .success("mock response")
    var sendMessageCallCount = 0
    var lastSendMessageArgs: (model: String, systemPrompt: String, messages: [(role: String, content: String)])?

    init(config: ProviderConfig? = nil) {
        self.config = config ?? ProviderConfig(
            name: "MockProvider",
            type: .custom,
            baseURL: "https://mock.test",
            authMethod: .none
        )
    }

    func fetchModels() async throws -> [String] {
        switch fetchModelsResult {
        case .success(let models): return models
        case .failure(let error): throw error
        }
    }

    func sendMessage(model: String, systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        sendMessageCallCount += 1
        lastSendMessageArgs = (model, systemPrompt, messages)
        switch sendMessageResult {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}
