import Foundation
@testable import DOUGLAS

class MockAIProvider: AIProvider {
    let config: ProviderConfig

    var fetchModelsResult: Result<[String], Error> = .success(["mock-model"])
    var sendMessageResult: Result<String, Error> = .success("mock response")
    /// 순차 응답이 필요할 때 사용 (비어있으면 sendMessageResult 사용)
    var sendMessageResults: [Result<String, Error>] = []
    var sendMessageCallCount = 0
    var lastSendMessageArgs: (model: String, systemPrompt: String, messages: [(role: String, content: String)])?

    init(config: ProviderConfig? = nil) {
        self.config = config ?? ProviderConfig(
            name: "MockProvider",
            type: .openAI,
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
        if !sendMessageResults.isEmpty {
            let index = min(sendMessageCallCount - 1, sendMessageResults.count - 1)
            switch sendMessageResults[index] {
            case .success(let response): return response
            case .failure(let error): throw error
            }
        }
        switch sendMessageResult {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    // MARK: - Tool Use 지원

    var _supportsToolCalling = false
    var supportsToolCalling: Bool { _supportsToolCalling }

    var sendMessageWithToolsResults: [Result<AIResponseContent, Error>] = []
    var sendMessageWithToolsCallCount = 0
    var lastSendMessageWithToolsArgs: (model: String, systemPrompt: String, messages: [ConversationMessage], tools: [AgentTool])?

    func sendMessageWithTools(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [AgentTool]
    ) async throws -> AIResponseContent {
        lastSendMessageWithToolsArgs = (model, systemPrompt, messages, tools)
        let index = min(sendMessageWithToolsCallCount, sendMessageWithToolsResults.count - 1)
        sendMessageWithToolsCallCount += 1
        if sendMessageWithToolsResults.isEmpty {
            return .text("mock tool response")
        }
        switch sendMessageWithToolsResults[max(0, index)] {
        case .success(let content): return content
        case .failure(let error): throw error
        }
    }
}
