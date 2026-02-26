import Testing
import Foundation
@testable import AgentManagerLib

@Suite("ProviderManager Tests")
@MainActor
struct ProviderManagerTests {

    @Test("init - 기본 프로바이더 생성")
    func initCreatesDefaults() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        // OpenAI와 Google은 항상 생성됨
        #expect(manager.configs.contains(where: { $0.type == .openAI }))
        #expect(manager.configs.contains(where: { $0.type == .google }))
    }

    @Test("provider(named:) - 존재하는 프로바이더")
    func providerNamedExisting() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let provider = manager.provider(named: "OpenAI")
        #expect(provider != nil)
    }

    @Test("provider(named:) - 존재하지 않는 프로바이더")
    func providerNamedNonExisting() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let provider = manager.provider(named: "DoesNotExist")
        #expect(provider == nil)
    }

    @Test("createProvider - OpenAI")
    func createProviderOpenAI() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let config = makeTestProviderConfig(type: .openAI)
        let provider = manager.createProvider(from: config)
        #expect(provider is OpenAIProvider)
    }

    @Test("createProvider - Anthropic")
    func createProviderAnthropic() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let config = makeTestProviderConfig(type: .anthropic)
        let provider = manager.createProvider(from: config)
        #expect(provider is AnthropicProvider)
    }

    @Test("createProvider - Google")
    func createProviderGoogle() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let config = makeTestProviderConfig(type: .google)
        let provider = manager.createProvider(from: config)
        #expect(provider is GoogleProvider)
    }

    @Test("createProvider - Ollama")
    func createProviderOllama() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let config = makeTestProviderConfig(type: .ollama)
        let provider = manager.createProvider(from: config)
        #expect(provider is OllamaProvider)
    }

    @Test("createProvider - Custom")
    func createProviderCustom() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let config = makeTestProviderConfig(type: .custom)
        let provider = manager.createProvider(from: config)
        #expect(provider is CustomProvider)
    }

    @Test("createProvider - Claude Code")
    func createProviderClaudeCode() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let config = makeTestProviderConfig(type: .claudeCode)
        let provider = manager.createProvider(from: config)
        #expect(provider is ClaudeCodeProvider)
    }

    @Test("updateConfig")
    func updateConfig() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        guard var config = manager.configs.first(where: { $0.type == .openAI }) else {
            Issue.record("OpenAI config not found")
            return
        }
        config.baseURL = "https://custom.openai.com"
        manager.updateConfig(config)
        let updated = manager.configs.first(where: { $0.id == config.id })
        #expect(updated?.baseURL == "https://custom.openai.com")
    }
}
