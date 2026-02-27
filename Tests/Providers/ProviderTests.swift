import Testing
import Foundation
@testable import DOUGLASLib

/// 모든 Provider 테스트는 MockURLProtocol.requestHandler를 공유하므로 직렬 실행 필수
@Suite("Provider Tests", .serialized)
struct ProviderTests {

    // MARK: - AIProvider Extension

    @Test("validateHTTPResponse - 200 OK")
    func validate200() throws {
        let provider = MockAIProvider()
        let response = mockHTTPResponse(statusCode: 200)
        try provider.validateHTTPResponse(response)
    }

    @Test("validateHTTPResponse - 299 OK")
    func validate299() throws {
        let provider = MockAIProvider()
        let response = mockHTTPResponse(statusCode: 299)
        try provider.validateHTTPResponse(response)
    }

    @Test("validateHTTPResponse - 400 에러")
    func validate400() {
        let provider = MockAIProvider()
        let response = mockHTTPResponse(statusCode: 400)
        #expect(throws: AIProviderError.self) {
            try provider.validateHTTPResponse(response)
        }
    }

    @Test("validateHTTPResponse - 500 에러")
    func validate500() {
        let provider = MockAIProvider()
        let response = mockHTTPResponse(statusCode: 500)
        #expect(throws: AIProviderError.self) {
            try provider.validateHTTPResponse(response)
        }
    }

    @Test("validateHTTPResponse - 일반 URLResponse")
    func validateNonHTTP() throws {
        let provider = MockAIProvider()
        let response = URLResponse(url: URL(string: "https://t.com")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        try provider.validateHTTPResponse(response)
    }

    @Test("applyAuth - none")
    func applyAuthNone() {
        let config = makeTestProviderConfig(authMethod: .none)
        let provider = MockAIProvider(config: config)
        var request = URLRequest(url: URL(string: "https://t.com")!)
        provider.applyAuth(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("applyAuth - customHeader")
    func applyAuthCustomHeader() {
        let config = ProviderConfig(
            name: "Test", type: .custom, baseURL: "https://t.com",
            authMethod: .customHeader, customHeaderName: "X-Custom", customHeaderValue: "my-value"
        )
        let provider = MockAIProvider(config: config)
        var request = URLRequest(url: URL(string: "https://t.com")!)
        provider.applyAuth(to: &request)
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "my-value")
    }

    // MARK: - OpenAI Provider

    @Test("OpenAI fetchModels - 모델 필터링")
    func openAIFetchModelsFiltering() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = [
                "data": [
                    ["id": "gpt-4o"], ["id": "gpt-3.5-turbo"],
                    ["id": "dall-e-3"], ["id": "whisper-1"], ["id": "o1-mini"]
                ]
            ]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com")
        let provider = OpenAIProvider(config: config, session: makeMockSession())
        let models = try await provider.fetchModels()
        #expect(models.contains("gpt-4o"))
        #expect(models.contains("o1-mini"))
        #expect(!models.contains("dall-e-3"))
        #expect(!models.contains("whisper-1"))
    }

    @Test("OpenAI sendMessage - 응답 파싱")
    func openAISendMessageParse() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["choices": [["message": ["content": "Hello from GPT"]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com")
        let provider = OpenAIProvider(config: config, session: makeMockSession())
        let result = try await provider.sendMessage(model: "gpt-4o", systemPrompt: "You are helpful", messages: [("user", "Hi")])
        #expect(result == "Hello from GPT")
    }

    @Test("OpenAI sendMessage - API 에러")
    func openAISendMessageAPIError() async {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["error": ["message": "quota exceeded"]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com")
        let provider = OpenAIProvider(config: config, session: makeMockSession())
        do {
            _ = try await provider.sendMessage(model: "gpt-4o", systemPrompt: "", messages: [("user", "Hi")])
            Issue.record("Expected error")
        } catch {
            #expect(error is AIProviderError)
        }
    }

    @Test("OpenAI sendMessage - HTTP 에러")
    func openAISendMessageHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            (mockHTTPResponse(url: request.url!.absoluteString, statusCode: 500), Data())
        }
        let config = makeTestProviderConfig(name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com")
        let provider = OpenAIProvider(config: config, session: makeMockSession())
        do {
            _ = try await provider.sendMessage(model: "gpt-4o", systemPrompt: "", messages: [("user", "Hi")])
            Issue.record("Expected error")
        } catch {
            #expect(error is AIProviderError)
        }
    }

    @Test("OpenAI sendMessage - 빈 systemPrompt")
    func openAIEmptySystem() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["choices": [["message": ["content": "ok"]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com")
        let provider = OpenAIProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "gpt-4o", systemPrompt: "", messages: [("user", "Hi")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let messages = captured["messages"] as? [[String: String]] {
            #expect(!messages.map { $0["role"] }.contains("system"))
        }
    }

    // MARK: - Anthropic Provider

    @Test("Anthropic fetchModels - 하드코딩")
    func anthropicFetchModels() async throws {
        let config = makeTestProviderConfig(type: .anthropic, baseURL: "https://api.anthropic.com")
        let provider = AnthropicProvider(config: config)
        let models = try await provider.fetchModels()
        #expect(models.contains("claude-opus-4-6"))
        #expect(models.contains("claude-sonnet-4-6"))
    }

    @Test("Anthropic sendMessage - 응답 파싱")
    func anthropicSendMessageParse() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["content": [["text": "Hello from Claude"]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .anthropic, baseURL: "https://api.anthropic.com")
        let provider = AnthropicProvider(config: config, session: makeMockSession())
        let result = try await provider.sendMessage(model: "claude-sonnet-4-6", systemPrompt: "Be helpful", messages: [("user", "Hi")])
        #expect(result == "Hello from Claude")
    }

    @Test("Anthropic sendMessage - system 필드 분리")
    func anthropicSystemField() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["content": [["text": "ok"]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .anthropic, baseURL: "https://api.anthropic.com")
        let provider = AnthropicProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "claude-sonnet-4-6", systemPrompt: "Be helpful", messages: [("user", "Hi")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(captured["system"] as? String == "Be helpful")
        } else {
            Issue.record("Could not capture request body")
        }
    }

    @Test("Anthropic sendMessage - 빈 systemPrompt면 system 없음")
    func anthropicEmptySystem() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["content": [["text": "ok"]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .anthropic, baseURL: "https://api.anthropic.com")
        let provider = AnthropicProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "claude-sonnet-4-6", systemPrompt: "", messages: [("user", "Hi")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(captured["system"] == nil)
        }
    }

    // MARK: - Google Provider

    @Test("Google fetchModels - 하드코딩")
    func googleFetchModels() async throws {
        let config = makeTestProviderConfig(type: .google, baseURL: "https://generativelanguage.googleapis.com")
        let provider = GoogleProvider(config: config)
        let models = try await provider.fetchModels()
        #expect(models.contains("gemini-2.0-flash"))
    }

    @Test("Google sendMessage - 응답 파싱")
    func googleSendMessageParse() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["candidates": [["content": ["parts": [["text": "Hello from Gemini"]]]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = ProviderConfig(name: "Google", type: .google, baseURL: "https://generativelanguage.googleapis.com", authMethod: .apiKey, apiKey: "test-key-google")
        let provider = GoogleProvider(config: config, session: makeMockSession())
        let result = try await provider.sendMessage(model: "gemini-2.0-flash", systemPrompt: "", messages: [("user", "Hi")])
        #expect(result == "Hello from Gemini")
        // cleanup
        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    @Test("Google sendMessage - systemInstruction 필드")
    func googleSystemInstruction() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["candidates": [["content": ["parts": [["text": "ok"]]]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = ProviderConfig(name: "Google", type: .google, baseURL: "https://generativelanguage.googleapis.com", authMethod: .apiKey, apiKey: "test-key-google2")
        let provider = GoogleProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "gemini-2.0-flash", systemPrompt: "Be helpful", messages: [("user", "Hi")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(captured["systemInstruction"] != nil)
        } else {
            Issue.record("Could not capture request body")
        }
        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    @Test("Google sendMessage - 역할 매핑 (assistant → model)")
    func googleRoleMapping() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["candidates": [["content": ["parts": [["text": "ok"]]]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = ProviderConfig(name: "Google", type: .google, baseURL: "https://generativelanguage.googleapis.com", authMethod: .apiKey, apiKey: "test-key-google3")
        let provider = GoogleProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "gemini-2.0-flash", systemPrompt: "", messages: [("user", "Hi"), ("assistant", "Hello")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let contents = captured["contents"] as? [[String: Any]] {
            let roles = contents.compactMap { $0["role"] as? String }
            #expect(roles.contains("model"))
            #expect(!roles.contains("assistant"))
        }
        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    // MARK: - Ollama Provider

    @Test("Ollama fetchModels - 모델 파싱")
    func ollamaFetchModels() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["models": [["name": "llama3"], ["name": "mistral"]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .ollama, baseURL: "http://localhost:11434")
        let provider = OllamaProvider(config: config, session: makeMockSession())
        let models = try await provider.fetchModels()
        #expect(models.contains("llama3"))
        #expect(models.contains("mistral"))
    }

    @Test("Ollama sendMessage - 응답 파싱")
    func ollamaSendMessage() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["message": ["content": "Hello from Ollama"]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .ollama, baseURL: "http://localhost:11434")
        let provider = OllamaProvider(config: config, session: makeMockSession())
        let result = try await provider.sendMessage(model: "llama3", systemPrompt: "", messages: [("user", "Hi")])
        #expect(result == "Hello from Ollama")
    }

    @Test("Ollama sendMessage - stream: false 포함")
    func ollamaStreamFalse() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["message": ["content": "ok"]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .ollama, baseURL: "http://localhost:11434")
        let provider = OllamaProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "llama3", systemPrompt: "", messages: [("user", "Hi")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(captured["stream"] as? Bool == false)
        }
    }

    @Test("Ollama sendMessage - API 에러")
    func ollamaSendMessageError() async {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["error": "model not found"]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .ollama, baseURL: "http://localhost:11434")
        let provider = OllamaProvider(config: config, session: makeMockSession())
        do {
            _ = try await provider.sendMessage(model: "bad", systemPrompt: "", messages: [("user", "Hi")])
            Issue.record("Expected error")
        } catch {
            #expect(error is AIProviderError)
        }
    }

    // MARK: - LM Studio

    @Test("LM Studio fetchModels - /v1/models")
    func lmStudioFetchModels() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["data": [["id": "model-1"]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .lmStudio, baseURL: "http://localhost:1234")
        let provider = OllamaProvider(config: config, session: makeMockSession())
        let models = try await provider.fetchModels()
        #expect(models.contains("model-1"))
    }

    @Test("LM Studio sendMessage - 응답 파싱")
    func lmStudioSendMessage() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["choices": [["message": ["content": "ok from LM Studio"]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .lmStudio, baseURL: "http://localhost:1234")
        let provider = OllamaProvider(config: config, session: makeMockSession())
        let result = try await provider.sendMessage(model: "model-1", systemPrompt: "", messages: [("user", "Hi")])
        #expect(result == "ok from LM Studio")
    }

    // MARK: - Custom Provider

    @Test("Custom fetchModels - 모델 파싱")
    func customFetchModels() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/v1/models") == true)
            let body: [String: Any] = ["data": [["id": "custom-model-1"], ["id": "custom-model-2"]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .custom, baseURL: "https://custom.example.com")
        let provider = CustomProvider(config: config, session: makeMockSession())
        let models = try await provider.fetchModels()
        #expect(models.contains("custom-model-1"))
        #expect(models.contains("custom-model-2"))
    }

    @Test("Custom sendMessage - 응답 파싱")
    func customSendMessage() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/v1/chat/completions") == true)
            let body: [String: Any] = ["choices": [["message": ["content": "Hello from Custom"]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .custom, baseURL: "https://custom.example.com")
        let provider = CustomProvider(config: config, session: makeMockSession())
        let result = try await provider.sendMessage(model: "custom-model", systemPrompt: "Be helpful", messages: [("user", "Hi")])
        #expect(result == "Hello from Custom")
    }

    @Test("Custom sendMessage - 빈 systemPrompt")
    func customEmptySystem() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["choices": [["message": ["content": "ok"]]]]
            return (mockHTTPResponse(url: request.url!.absoluteString), try! JSONSerialization.data(withJSONObject: body))
        }
        let config = makeTestProviderConfig(type: .custom, baseURL: "https://custom.example.com")
        let provider = CustomProvider(config: config, session: makeMockSession())
        _ = try await provider.sendMessage(model: "m", systemPrompt: "", messages: [("user", "Hi")])

        if let bodyData = MockURLProtocol.lastRequestBody,
           let captured = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let messages = captured["messages"] as? [[String: String]] {
            #expect(!messages.map { $0["role"] }.contains("system"))
        }
    }

    @Test("Custom sendMessage - HTTP 에러")
    func customSendMessageHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            (mockHTTPResponse(url: request.url!.absoluteString, statusCode: 503), Data())
        }
        let config = makeTestProviderConfig(type: .custom, baseURL: "https://custom.example.com")
        let provider = CustomProvider(config: config, session: makeMockSession())
        do {
            _ = try await provider.sendMessage(model: "m", systemPrompt: "", messages: [("user", "Hi")])
            Issue.record("Expected error")
        } catch {
            #expect(error is AIProviderError)
        }
    }

    // MARK: - applyAuth 추가 테스트

    @Test("applyAuth - bearerToken")
    func applyAuthBearerToken() {
        let config = ProviderConfig(
            name: "Test", type: .custom, baseURL: "https://t.com",
            authMethod: .bearerToken, apiKey: "test-bearer-token"
        )
        let provider = MockAIProvider(config: config)
        var request = URLRequest(url: URL(string: "https://t.com")!)
        provider.applyAuth(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-bearer-token")
        // cleanup
        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    @Test("applyAuth - apiKey (OpenAI 스타일)")
    func applyAuthApiKeyOpenAI() {
        let config = ProviderConfig(
            name: "Test", type: .openAI, baseURL: "https://api.openai.com",
            authMethod: .apiKey, apiKey: "sk-test-key"
        )
        let provider = MockAIProvider(config: config)
        var request = URLRequest(url: URL(string: "https://api.openai.com")!)
        provider.applyAuth(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
        // cleanup
        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    @Test("applyAuth - apiKey (Anthropic 스타일)")
    func applyAuthApiKeyAnthropic() {
        let config = ProviderConfig(
            name: "Test", type: .anthropic, baseURL: "https://api.anthropic.com",
            authMethod: .apiKey, apiKey: "sk-ant-test"
        )
        let provider = MockAIProvider(config: config)
        var request = URLRequest(url: URL(string: "https://api.anthropic.com")!)
        provider.applyAuth(to: &request)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        // cleanup
        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    @Test("applyAuth - apiKey 빈 값이면 헤더 없음")
    func applyAuthApiKeyEmpty() {
        let config = makeTestProviderConfig(authMethod: .apiKey)
        // apiKey 없이 생성 → Keychain에 값 없음
        let provider = MockAIProvider(config: config)
        var request = URLRequest(url: URL(string: "https://t.com")!)
        provider.applyAuth(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - AIProviderError

    @Test("AIProviderError 메시지")
    func providerErrorDescriptions() {
        #expect(AIProviderError.invalidURL.errorDescription?.contains("URL") == true)
        #expect(AIProviderError.invalidResponse.errorDescription?.contains("응답") == true)
        #expect(AIProviderError.apiError("test").errorDescription?.contains("test") == true)
        #expect(AIProviderError.networkError("net").errorDescription?.contains("net") == true)
        #expect(AIProviderError.noAPIKey.errorDescription?.contains("API") == true)
        #expect(AIProviderError.httpError(statusCode: 404, body: "not found").errorDescription?.contains("404") == true)
    }

    // MARK: - ClaudeCode fetchModels

    @Test("ClaudeCode fetchModels - 하드코딩")
    func claudeCodeFetchModels() async throws {
        let config = makeTestProviderConfig(type: .claudeCode, baseURL: "/usr/local/bin/claude")
        let provider = ClaudeCodeProvider(config: config)
        let models = try await provider.fetchModels()
        #expect(models.contains("claude-opus-4-6"))
        #expect(models.contains("claude-sonnet-4-6"))
        #expect(models.contains("claude-haiku-4-5"))
    }

    // MARK: - Tool Use supportsToolCalling

    @Test("OpenAI supportsToolCalling == true")
    func openAISupportsTools() {
        let config = makeTestProviderConfig(type: .openAI, baseURL: "https://api.openai.com")
        let provider = OpenAIProvider(config: config)
        #expect(provider.supportsToolCalling == true)
    }

    @Test("Anthropic supportsToolCalling == true")
    func anthropicSupportsTools() {
        let config = makeTestProviderConfig(type: .anthropic, baseURL: "https://api.anthropic.com")
        let provider = AnthropicProvider(config: config)
        #expect(provider.supportsToolCalling == true)
    }

    @Test("Google supportsToolCalling == true")
    func googleSupportsTools() {
        let config = makeTestProviderConfig(type: .google, baseURL: "https://generativelanguage.googleapis.com")
        let provider = GoogleProvider(config: config)
        #expect(provider.supportsToolCalling == true)
    }

    @Test("ClaudeCode supportsToolCalling == false")
    func claudeCodeNoTools() {
        let config = makeTestProviderConfig(type: .claudeCode, baseURL: "/usr/local/bin/claude")
        let provider = ClaudeCodeProvider(config: config)
        #expect(provider.supportsToolCalling == false)
    }

    @Test("AIProvider default supportsToolCalling == false")
    func defaultNoTools() {
        let mock = MockAIProvider()
        #expect(mock.supportsToolCalling == false)
    }

    // MARK: - Google API 키 검증

    @Test("Google sendMessage - API 키 없으면 noAPIKey 에러")
    func googleNoAPIKey() async {
        let config = ProviderConfig(name: "TestGoogle", type: .google, baseURL: "https://generativelanguage.googleapis.com")
        let provider = GoogleProvider(config: config)
        do {
            _ = try await provider.sendMessage(
                model: "gemini-2.0-flash",
                systemPrompt: "test",
                messages: [("user", "hello")]
            )
            Issue.record("Should have thrown noAPIKey")
        } catch {
            #expect(error is AIProviderError)
        }
    }

    // MARK: - OpenAI Tool Use 요청 빌드

    @Test("OpenAI sendMessageWithTools - 요청에 tools 배열 포함")
    func openAIToolsInRequest() async throws {
        let config = ProviderConfig(
            name: "TestOpenAI", type: .openAI, baseURL: "https://api.openai.com",
            authMethod: .apiKey, apiKey: "test-key"
        )
        let provider = OpenAIProvider(config: config, session: makeMockSession())

        MockURLProtocol.requestHandler = { request in
            // 요청 body 검증
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                let tools = json["tools"] as? [[String: Any]]
                #expect(tools?.count == 1)
                let funcDef = tools?.first?["function"] as? [String: Any]
                #expect(funcDef?["name"] as? String == "file_read")
            }

            let responseData = """
            {"choices":[{"message":{"role":"assistant","content":"ok"}}]}
            """.data(using: .utf8)!
            return (mockHTTPResponse(url: request.url!.absoluteString), responseData)
        }

        let tools = [AgentTool(
            id: "file_read", name: "파일 읽기", description: "Read file",
            parameters: [.init(name: "path", type: .string, description: "Path", required: true, enumValues: nil)]
        )]
        let result = try await provider.sendMessageWithTools(
            model: "gpt-4o",
            systemPrompt: "sys",
            messages: [ConversationMessage.user("hello")],
            tools: tools
        )

        if case .text(let text) = result {
            #expect(text == "ok")
        } else {
            Issue.record("Expected .text response")
        }

        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    // MARK: - OpenAI tool_calls 응답 파싱

    @Test("OpenAI sendMessageWithTools - tool_calls 파싱")
    func openAIToolCallsParsing() async throws {
        let config = ProviderConfig(
            name: "TestOpenAI", type: .openAI, baseURL: "https://api.openai.com",
            authMethod: .apiKey, apiKey: "test-key"
        )
        let provider = OpenAIProvider(config: config, session: makeMockSession())

        MockURLProtocol.requestHandler = { request in
            let responseData = """
            {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"file_read","arguments":"{\\"path\\":\\"/tmp/test\\"}"}}]}}]}
            """.data(using: .utf8)!
            return (mockHTTPResponse(url: request.url!.absoluteString), responseData)
        }

        let tools = ToolRegistry.tools(for: ["file_read"])
        let result = try await provider.sendMessageWithTools(
            model: "gpt-4o", systemPrompt: "s",
            messages: [ConversationMessage.user("read file")],
            tools: tools
        )

        if case .toolCalls(let calls) = result {
            #expect(calls.count == 1)
            #expect(calls[0].toolName == "file_read")
            #expect(calls[0].arguments["path"]?.stringValue == "/tmp/test")
        } else {
            Issue.record("Expected .toolCalls response")
        }

        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    // MARK: - Anthropic Tool Use 응답 파싱

    @Test("Anthropic sendMessageWithTools - tool_use 파싱")
    func anthropicToolUseParsing() async throws {
        let config = ProviderConfig(
            name: "TestAnthropic", type: .anthropic, baseURL: "https://api.anthropic.com",
            authMethod: .apiKey, apiKey: "test-key"
        )
        let provider = AnthropicProvider(config: config, session: makeMockSession())

        MockURLProtocol.requestHandler = { request in
            let responseData = """
            {"content":[{"type":"text","text":"Let me read that."},{"type":"tool_use","id":"toolu_01","name":"file_read","input":{"path":"/tmp/test"}}],"stop_reason":"tool_use"}
            """.data(using: .utf8)!
            return (mockHTTPResponse(url: request.url!.absoluteString), responseData)
        }

        let tools = ToolRegistry.tools(for: ["file_read"])
        let result = try await provider.sendMessageWithTools(
            model: "claude-sonnet-4-6", systemPrompt: "s",
            messages: [ConversationMessage.user("read file")],
            tools: tools
        )

        if case .mixed(let text, let calls) = result {
            #expect(text == "Let me read that.")
            #expect(calls.count == 1)
            #expect(calls[0].toolName == "file_read")
        } else {
            Issue.record("Expected .mixed response")
        }

        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    // MARK: - Google Tool Use 응답 파싱

    @Test("Google sendMessageWithTools - functionCall 파싱")
    func googleFunctionCallParsing() async throws {
        let config = ProviderConfig(
            name: "TestGoogle", type: .google, baseURL: "https://generativelanguage.googleapis.com",
            authMethod: .apiKey, apiKey: "test-key"
        )
        let provider = GoogleProvider(config: config, session: makeMockSession())

        MockURLProtocol.requestHandler = { request in
            // x-goog-api-key 헤더 확인
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            // URL에 키가 없어야 함
            #expect(request.url?.query == nil || !request.url!.query!.contains("key="))

            let responseData = """
            {"candidates":[{"content":{"parts":[{"functionCall":{"name":"file_read","args":{"path":"/tmp/test"}}}]}}]}
            """.data(using: .utf8)!
            return (mockHTTPResponse(url: request.url!.absoluteString), responseData)
        }

        let tools = ToolRegistry.tools(for: ["file_read"])
        let result = try await provider.sendMessageWithTools(
            model: "gemini-2.0-flash", systemPrompt: "s",
            messages: [ConversationMessage.user("read file")],
            tools: tools
        )

        if case .toolCalls(let calls) = result {
            #expect(calls.count == 1)
            #expect(calls[0].toolName == "file_read")
        } else {
            Issue.record("Expected .toolCalls response")
        }

        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }

    @Test("Google sendMessage - API 키가 헤더에 있고 URL에 없음")
    func googleAPIKeyInHeader() async throws {
        let config = ProviderConfig(
            name: "TestGoogle", type: .google, baseURL: "https://generativelanguage.googleapis.com",
            authMethod: .apiKey, apiKey: "secret-key-123"
        )
        let provider = GoogleProvider(config: config, session: makeMockSession())

        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "secret-key-123")
            let urlString = request.url?.absoluteString ?? ""
            #expect(!urlString.contains("key=secret-key-123"))

            let responseData = """
            {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}
            """.data(using: .utf8)!
            return (mockHTTPResponse(url: request.url!.absoluteString), responseData)
        }

        let result = try await provider.sendMessage(
            model: "gemini-2.0-flash", systemPrompt: "test",
            messages: [("user", "hello")]
        )
        #expect(result == "Hello")

        try? KeychainHelper.delete(key: "provider-apikey-\(config.id.uuidString)")
    }
}
