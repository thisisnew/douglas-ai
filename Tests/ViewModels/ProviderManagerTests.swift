import Testing
import Foundation
@testable import DOUGLAS

@Suite("ProviderManager Tests")
@MainActor
struct ProviderManagerTests {

    /// 테스트용: OnboardingViewModel.isCompleted를 임시 true로 설정/복원
    private func withOnboardingCompleted<T>(_ body: () throws -> T) rethrows -> T {
        let original = OnboardingViewModel.isCompleted
        OnboardingViewModel.isCompleted = true
        defer { OnboardingViewModel.isCompleted = original }
        return try body()
    }

    @Test("init - 기본 프로바이더 생성 (온보딩 완료 시)")
    func initCreatesDefaults() {
        withOnboardingCompleted {
            let defaults = makeTestDefaults()
            let manager = ProviderManager(defaults: defaults)
            // 온보딩 완료 시 OpenAI와 Google은 항상 생성됨
            #expect(manager.configs.contains(where: { $0.type == .openAI }))
            #expect(manager.configs.contains(where: { $0.type == .google }))
        }
    }

    @Test("init - 온보딩 미완료 시 기본 프로바이더 미생성")
    func initSkipsDefaultsBeforeOnboarding() {
        let original = OnboardingViewModel.isCompleted
        OnboardingViewModel.isCompleted = false
        defer { OnboardingViewModel.isCompleted = original }

        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        #expect(manager.configs.isEmpty)
    }

    @Test("provider(named:) - 존재하는 프로바이더")
    func providerNamedExisting() {
        withOnboardingCompleted {
            let defaults = makeTestDefaults()
            let manager = ProviderManager(defaults: defaults)
            let provider = manager.provider(named: "OpenAI")
            #expect(provider != nil)
        }
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
        withOnboardingCompleted {
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

    // MARK: - configureFromOnboarding

    @Test("configureFromOnboarding - 새 프로바이더 추가")
    func configureFromOnboardingNew() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let initialCount = manager.configs.count
        manager.configureFromOnboarding(
            selectedTypes: [.anthropic],
            apiKeys: [:]
        )
        #expect(manager.configs.count == initialCount + 1)
        #expect(manager.configs.contains(where: { $0.type == .anthropic }))
    }

    @Test("configureFromOnboarding - 이미 존재하는 프로바이더는 스킵")
    func configureFromOnboardingExisting() {
        withOnboardingCompleted {
            let defaults = makeTestDefaults()
            let manager = ProviderManager(defaults: defaults)
            let openAICount = manager.configs.filter { $0.type == .openAI }.count
            manager.configureFromOnboarding(
                selectedTypes: [.openAI],
                apiKeys: [:]
            )
            // 중복 추가 없어야 함
            #expect(manager.configs.filter { $0.type == .openAI }.count == openAICount)
        }
    }

    @Test("configureFromOnboarding - API 키 업데이트")
    func configureFromOnboardingApiKey() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        manager.configureFromOnboarding(
            selectedTypes: [.openAI],
            apiKeys: [.openAI: "sk-new-key"]
        )
        let config = manager.configs.first(where: { $0.type == .openAI })
        #expect(config?.apiKey == "sk-new-key")
        // cleanup
        if let c = config {
            try? KeychainHelper.delete(key: "provider-apikey-\(c.id.uuidString)")
        }
    }

    @Test("configureFromOnboarding - 여러 프로바이더 한번에")
    func configureFromOnboardingMultiple() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        manager.configureFromOnboarding(
            selectedTypes: [.openAI, .google, .anthropic],
            apiKeys: [.anthropic: "sk-ant-test"]
        )
        #expect(manager.configs.contains(where: { $0.type == .openAI }))
        #expect(manager.configs.contains(where: { $0.type == .google }))
        #expect(manager.configs.contains(where: { $0.type == .anthropic }))
        // cleanup
        if let c = manager.configs.first(where: { $0.type == .anthropic }) {
            try? KeychainHelper.delete(key: "provider-apikey-\(c.id.uuidString)")
        }
    }

    // MARK: - fetchModels

    @Test("fetchModels - 존재하지 않는 프로바이더")
    func fetchModelsNonExisting() async throws {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let models = try await manager.fetchModels(for: "DoesNotExist")
        #expect(models.isEmpty)
    }

    // MARK: - createProvider 추가

    // MARK: - 영속화

    @Test("configs 영속화 - 저장 후 재로드")
    func configsPersistence() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        manager.configureFromOnboarding(
            selectedTypes: [.anthropic],
            apiKeys: [:]
        )

        let manager2 = ProviderManager(defaults: defaults)
        #expect(manager2.configs.contains(where: { $0.type == .anthropic }))
    }

    // MARK: - updateConfig 존재하지 않는 config

    @Test("updateConfig - 존재하지 않는 config")
    func updateConfigNonExisting() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let fakeConfig = makeTestProviderConfig(name: "Fake", type: .anthropic)
        let countBefore = manager.configs.count
        manager.updateConfig(fakeConfig)
        #expect(manager.configs.count == countBefore) // 변경 없음
    }

    // MARK: - configureFromOnboarding - 기존 프로바이더 키 업데이트

    @Test("configureFromOnboarding - 기존 프로바이더 API 키 업데이트")
    func configureFromOnboardingUpdateKey() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        // 먼저 openAI를 추가
        manager.configureFromOnboarding(selectedTypes: [.openAI], apiKeys: [:])
        #expect(manager.configs.contains(where: { $0.type == .openAI }))

        // 같은 타입으로 다시 호출하면서 키 업데이트
        manager.configureFromOnboarding(
            selectedTypes: [.openAI],
            apiKeys: [.openAI: "sk-updated"]
        )
        // 중복 추가 없어야 함
        #expect(manager.configs.filter { $0.type == .openAI }.count == 1)
        // 키가 업데이트되었는지 확인
        let config = manager.configs.first(where: { $0.type == .openAI })
        #expect(config?.apiKey == "sk-updated")
        // cleanup
        if let c = config {
            try? KeychainHelper.delete(key: "provider-apikey-\(c.id.uuidString)")
        }
    }

    // MARK: - connectedConfigs

    @Test("connectedConfigs - 연결된 프로바이더만 반환")
    func connectedConfigs() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        // config 추가 (apiKey 없음 → 연결 안됨)
        manager.configureFromOnboarding(selectedTypes: [.openAI], apiKeys: [:])
        let connected = manager.connectedConfigs
        // openAI는 apiKey 필요 (authMethod == .apiKey)이므로 연결 안됨
        let openAIConnected = connected.contains(where: { $0.type == .openAI })
        #expect(openAIConnected == false)
    }

    // MARK: - fetchModels with mock provider

    @Test("fetchModels - testProviderOverrides로 mock 사용")
    func fetchModelsWithMock() async throws {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        manager.configureFromOnboarding(selectedTypes: [.openAI], apiKeys: [:])

        let mock = MockAIProvider()
        mock.fetchModelsResult = .success(["gpt-4o", "gpt-3.5-turbo"])
        manager.testProviderOverrides["OpenAI"] = mock

        let models = try await manager.fetchModels(for: "OpenAI")
        #expect(models.contains("gpt-4o"))
        #expect(models.count == 2)
    }

    // MARK: - testProviderOverrides 동작

    @Test("provider(named:) - testProviderOverrides 우선")
    func providerOverridePriority() {
        let defaults = makeTestDefaults()
        let manager = ProviderManager(defaults: defaults)
        let mock = MockAIProvider()
        manager.testProviderOverrides["CustomMock"] = mock
        let provider = manager.provider(named: "CustomMock")
        #expect(provider != nil)
        #expect(provider is MockAIProvider)
    }
}
