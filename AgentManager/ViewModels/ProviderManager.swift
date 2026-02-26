import Foundation

@MainActor
class ProviderManager: ObservableObject {
    @Published var configs: [ProviderConfig] = []

    private let saveKey = "providerConfigs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadConfigs()
        ensureDefaultProviders()
    }

    /// 3개 기본 프로바이더 보장: Claude Code, OpenAI, Google
    private func ensureDefaultProviders() {
        // Claude Code
        if !configs.contains(where: { $0.type == .claudeCode }) {
            let claudePath = ClaudeCodeProvider.findClaudePath()
            if FileManager.default.isExecutableFile(atPath: claudePath) {
                configs.append(ProviderConfig(
                    name: "Claude Code",
                    type: .claudeCode,
                    baseURL: claudePath,
                    authMethod: .none,
                    isBuiltIn: true
                ))
            }
        }

        // OpenAI (GPT)
        if !configs.contains(where: { $0.type == .openAI }) {
            configs.append(ProviderConfig(
                name: "OpenAI",
                type: .openAI,
                baseURL: ProviderType.openAI.defaultBaseURL,
                authMethod: .apiKey,
                isBuiltIn: true
            ))
        }

        // Google (Gemini)
        if !configs.contains(where: { $0.type == .google }) {
            configs.append(ProviderConfig(
                name: "Google",
                type: .google,
                baseURL: ProviderType.google.defaultBaseURL,
                authMethod: .apiKey,
                isBuiltIn: true
            ))
        }

        saveConfigs()
    }

    func updateConfig(_ updated: ProviderConfig) {
        if let idx = configs.firstIndex(where: { $0.id == updated.id }) {
            configs[idx] = updated
            saveConfigs()
        }
    }

    func provider(named name: String) -> AIProvider? {
        guard let config = configs.first(where: { $0.name == name }) else {
            return nil
        }
        return createProvider(from: config)
    }

    func createProvider(from config: ProviderConfig) -> AIProvider {
        switch config.type {
        case .claudeCode:        return ClaudeCodeProvider(config: config)
        case .openAI:            return OpenAIProvider(config: config)
        case .google:            return GoogleProvider(config: config)
        case .ollama, .lmStudio: return OllamaProvider(config: config)
        case .anthropic:         return AnthropicProvider(config: config)
        case .custom:            return CustomProvider(config: config)
        }
    }

    func fetchModels(for providerName: String) async throws -> [String] {
        guard let p = provider(named: providerName) else {
            return []
        }
        return try await p.fetchModels()
    }

    // MARK: - 저장/불러오기

    private func saveConfigs() {
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: saveKey)
        }
    }

    private func loadConfigs() {
        guard let data = defaults.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
            return
        }
        configs = loaded
    }
}
