import Foundation

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var detectedProviders: [DetectedProvider] = []
    @Published var allProviderTypes: [ProviderType] = []  // 감지 + 미감지 전체
    @Published var selectedTypes: Set<ProviderType> = []
    @Published var masterProviderType: ProviderType?
    @Published var apiKeys: [ProviderType: String] = [:]   // 사용자 입력 or 환경변수
    @Published var useDetectedKey: [ProviderType: Bool] = [:] // 환경변수 키 사용 여부
    @Published var isDetecting = true
    @Published var currentStep: OnboardingStep = .claudeSetup

    /// Claude Code 설치/검증
    let claudeInstaller = ClaudeCodeInstaller()

    /// 의존성 체커
    let dependencyChecker = DependencyChecker()

    /// Claude Code 설정이 완료되었는지 (설치됨 or 사용자가 건너뜀)
    @Published var claudeSetupDone = false
    /// Claude Code 설정을 건너뛰었는지
    @Published var claudeSkipped = false

    enum OnboardingStep {
        case claudeSetup       // Claude Code 자동 감지/설치
        case providerSelection // 서브 에이전트용 프로바이더 선택
        case apiKeyInput       // API 키 입력
        case complete          // 완료
    }

    // MARK: - 온보딩 완료 플래그

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingCompleted") }
    }

    // MARK: - 마스터 우선순위

    private static let masterPriority: [ProviderType] = [
        .claudeCode, .anthropic, .openAI, .google, .ollama, .lmStudio
    ]

    // MARK: - Claude Setup 단계

    func startClaudeSetup() async {
        currentStep = .claudeSetup
        async let detectClaude: () = claudeInstaller.detect()
        async let checkDeps: () = dependencyChecker.checkAll()
        _ = await (detectClaude, checkDeps)
    }

    /// Claude Code 설치 요청
    func installClaudeCode() async {
        await claudeInstaller.install()
    }

    /// Claude Setup 완료 → 다음 단계로
    func finishClaudeSetup() async {
        claudeSetupDone = true

        if claudeInstaller.isReady {
            // Claude Code가 준비됨 → 마스터로 고정
            masterProviderType = .claudeCode
            selectedTypes.insert(.claudeCode)
        } else {
            claudeSkipped = true
        }

        // 나머지 프로바이더 감지
        await startProviderDetection()
    }

    /// Claude Setup 건너뛰기
    func skipClaudeSetup() async {
        claudeSkipped = true
        claudeSetupDone = true
        await startProviderDetection()
    }

    // MARK: - 프로바이더 감지 (서브 에이전트용)

    private func startProviderDetection() async {
        isDetecting = true
        let detected = await ProviderDetector.detectAll()
        detectedProviders = detected

        // 감지된 것 자동 선택 (Claude Code는 이미 처리됨)
        for dp in detected {
            if dp.type != .claudeCode {
                selectedTypes.insert(dp.type)
            }
        }

        // 환경변수로 감지된 API 키 자동 채움
        for provider in detected {
            if let key = provider.prefilledAPIKey {
                apiKeys[provider.type] = key
                useDetectedKey[provider.type] = true
            }
        }

        // 전체 프로바이더 목록 (Claude Code 제외 — 이미 처리됨)
        let detectedTypes = Set(detected.map(\.type))
        let subProviderOrder: [ProviderType] = [.openAI, .anthropic, .google, .ollama, .lmStudio]
        let detectedSubTypes = detected.map(\.type).filter { $0 != .claudeCode }
        let undetectedSubTypes = subProviderOrder.filter { !detectedTypes.contains($0) }
        allProviderTypes = detectedSubTypes + undetectedSubTypes

        // Claude Code를 건너뛴 경우: 마스터를 수동 선택 가능하게
        if claudeSkipped {
            // Claude Code가 감지되었으면 목록에 포함
            if detected.contains(where: { $0.type == .claudeCode }) {
                allProviderTypes.insert(.claudeCode, at: 0)
                selectedTypes.insert(.claudeCode)
            }
            // 마스터 자동 선택
            masterProviderType = Self.masterPriority.first { selectedTypes.contains($0) }
        }

        isDetecting = false
        currentStep = .providerSelection
    }

    // MARK: - 선택 토글

    func toggleProvider(_ type: ProviderType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
            if masterProviderType == type {
                masterProviderType = Self.masterPriority.first { selectedTypes.contains($0) }
            }
        } else {
            selectedTypes.insert(type)
            if masterProviderType == nil {
                masterProviderType = type
            }
        }
    }

    func setMaster(_ type: ProviderType) {
        if !selectedTypes.contains(type) {
            selectedTypes.insert(type)
        }
        masterProviderType = type
    }

    // MARK: - API 키가 필요한 선택된 프로바이더

    var selectedProvidersNeedingKey: [ProviderType] {
        selectedTypes.filter { type in
            type.defaultAuthMethod == .apiKey
        }.sorted { a, b in
            allProviderTypes.firstIndex(of: a) ?? 0 < allProviderTypes.firstIndex(of: b) ?? 0
        }
    }

    /// 키 불필요한 선택된 프로바이더
    var selectedProvidersNoKey: [ProviderType] {
        selectedTypes.filter { $0.defaultAuthMethod == .none }
    }

    // MARK: - 다음 단계

    func goToNext() {
        switch currentStep {
        case .claudeSetup:
            currentStep = .providerSelection
        case .providerSelection:
            if selectedProvidersNeedingKey.isEmpty {
                currentStep = .complete
            } else {
                currentStep = .apiKeyInput
            }
        case .apiKeyInput:
            currentStep = .complete
        case .complete:
            break
        }
    }

    func goBack() {
        switch currentStep {
        case .apiKeyInput:
            currentStep = .providerSelection
        default:
            break
        }
    }

    // MARK: - 최종 적용

    func apply(providerManager: ProviderManager, agentStore: AgentStore) {
        // 1. 선택된 프로바이더 설정
        providerManager.configureFromOnboarding(
            selectedTypes: Array(selectedTypes),
            apiKeys: apiKeys
        )

        // 2. 마스터 프로바이더 업데이트
        if let masterType = masterProviderType,
           let config = providerManager.configs.first(where: { $0.type == masterType }) {
            let defaultModel = defaultModelName(for: masterType)
            agentStore.updateMasterProvider(providerName: config.name, modelName: defaultModel)
        }

        // 3. 온보딩 완료 플래그
        Self.isCompleted = true
    }

    /// 프로바이더 타입별 기본 모델명
    private func defaultModelName(for type: ProviderType) -> String {
        switch type {
        case .claudeCode: return "claude-sonnet-4-6"
        case .anthropic:  return "claude-sonnet-4-6"
        case .openAI:     return "gpt-4o"
        case .google:     return "gemini-2.0-flash"
        case .ollama:     return "llama3"
        case .lmStudio:   return "default"
        case .custom:     return "default"
        }
    }

    // MARK: - "나중에 설정" (스킵)

    /// 온보딩을 건너뛰되, 감지된 프로바이더가 있으면 최소 설정을 적용한다.
    func skipOnboarding(providerManager: ProviderManager, agentStore: AgentStore) {
        // 감지된 프로바이더가 있으면 자동으로 설정
        if !selectedTypes.isEmpty {
            apply(providerManager: providerManager, agentStore: agentStore)
            return
        }

        // 아무것도 감지/선택되지 않은 경우에도 완료 처리
        Self.isCompleted = true
    }
}
