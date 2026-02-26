import Testing
import Foundation
@testable import AgentManagerLib

@Suite("OnboardingViewModel Tests")
@MainActor
struct OnboardingViewModelTests {

    // MARK: - 초기 상태

    @Test("init - 기본 상태")
    func initDefaults() {
        let vm = OnboardingViewModel()
        #expect(vm.detectedProviders.isEmpty)
        #expect(vm.allProviderTypes.isEmpty)
        #expect(vm.selectedTypes.isEmpty)
        #expect(vm.masterProviderType == nil)
        #expect(vm.apiKeys.isEmpty)
        #expect(vm.useDetectedKey.isEmpty)
        #expect(vm.isDetecting == true)
        #expect(vm.currentStep == .detecting)
    }

    // MARK: - toggleProvider

    @Test("toggleProvider - 선택 토글 on")
    func toggleProviderOn() {
        let vm = OnboardingViewModel()
        vm.toggleProvider(.openAI)
        #expect(vm.selectedTypes.contains(.openAI))
    }

    @Test("toggleProvider - 선택 토글 off")
    func toggleProviderOff() {
        let vm = OnboardingViewModel()
        vm.selectedTypes.insert(.openAI)
        vm.toggleProvider(.openAI)
        #expect(!vm.selectedTypes.contains(.openAI))
    }

    @Test("toggleProvider - 처음 선택하면 마스터 자동 설정")
    func toggleProviderAutoMaster() {
        let vm = OnboardingViewModel()
        vm.masterProviderType = nil
        vm.toggleProvider(.google)
        #expect(vm.masterProviderType == .google)
    }

    @Test("toggleProvider - 마스터 해제 시 다음 후보로 변경")
    func toggleProviderMasterFallback() {
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.claudeCode, .openAI]
        vm.masterProviderType = .openAI
        vm.toggleProvider(.openAI) // openAI 해제
        // masterPriority에 따라 claudeCode가 마스터
        #expect(vm.masterProviderType == .claudeCode)
    }

    @Test("toggleProvider - 모든 프로바이더 해제 시 마스터 nil")
    func toggleProviderAllOff() {
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.openAI]
        vm.masterProviderType = .openAI
        vm.toggleProvider(.openAI)
        #expect(vm.masterProviderType == nil)
    }

    // MARK: - setMaster

    @Test("setMaster - 마스터 설정")
    func setMaster() {
        let vm = OnboardingViewModel()
        vm.setMaster(.google)
        #expect(vm.masterProviderType == .google)
        // 선택되지 않았어도 자동 선택됨
        #expect(vm.selectedTypes.contains(.google))
    }

    @Test("setMaster - 이미 선택된 프로바이더")
    func setMasterAlreadySelected() {
        let vm = OnboardingViewModel()
        vm.selectedTypes.insert(.anthropic)
        vm.setMaster(.anthropic)
        #expect(vm.masterProviderType == .anthropic)
        // 중복 삽입 없어야 함
        #expect(vm.selectedTypes.filter { $0 == .anthropic }.count == 1)
    }

    // MARK: - selectedProvidersNeedingKey / selectedProvidersNoKey

    @Test("selectedProvidersNeedingKey - API 키 필요한 프로바이더만 반환")
    func selectedProvidersNeedingKey() {
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.claudeCode, .openAI, .google, .ollama]
        vm.allProviderTypes = [.claudeCode, .openAI, .google, .ollama]
        let needKey = vm.selectedProvidersNeedingKey
        #expect(needKey.contains(.openAI))
        #expect(needKey.contains(.google))
        #expect(!needKey.contains(.claudeCode))
        #expect(!needKey.contains(.ollama))
    }

    @Test("selectedProvidersNoKey - 키 불필요 프로바이더만 반환")
    func selectedProvidersNoKey() {
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.claudeCode, .openAI, .ollama]
        let noKey = vm.selectedProvidersNoKey
        #expect(noKey.contains(.claudeCode))
        #expect(noKey.contains(.ollama))
        #expect(!noKey.contains(.openAI))
    }

    // MARK: - goToNext / goBack

    @Test("goToNext - detecting → selection")
    func goToNextFromDetecting() {
        let vm = OnboardingViewModel()
        vm.currentStep = .detecting
        vm.goToNext()
        #expect(vm.currentStep == .selection)
    }

    @Test("goToNext - selection → apiKeyInput (키 필요한 프로바이더 있을 때)")
    func goToNextSelectionToApiKey() {
        let vm = OnboardingViewModel()
        vm.currentStep = .selection
        vm.selectedTypes = [.openAI]
        vm.allProviderTypes = [.openAI]
        vm.goToNext()
        #expect(vm.currentStep == .apiKeyInput)
    }

    @Test("goToNext - selection → complete (키 불필요)")
    func goToNextSelectionToComplete() {
        let vm = OnboardingViewModel()
        vm.currentStep = .selection
        vm.selectedTypes = [.claudeCode, .ollama]
        vm.goToNext()
        #expect(vm.currentStep == .complete)
    }

    @Test("goToNext - apiKeyInput → complete")
    func goToNextApiKeyToComplete() {
        let vm = OnboardingViewModel()
        vm.currentStep = .apiKeyInput
        vm.goToNext()
        #expect(vm.currentStep == .complete)
    }

    @Test("goToNext - complete → complete (변경 없음)")
    func goToNextFromComplete() {
        let vm = OnboardingViewModel()
        vm.currentStep = .complete
        vm.goToNext()
        #expect(vm.currentStep == .complete)
    }

    @Test("goBack - apiKeyInput → selection")
    func goBackFromApiKey() {
        let vm = OnboardingViewModel()
        vm.currentStep = .apiKeyInput
        vm.goBack()
        #expect(vm.currentStep == .selection)
    }

    @Test("goBack - selection → selection (뒤로 못 감)")
    func goBackFromSelection() {
        let vm = OnboardingViewModel()
        vm.currentStep = .selection
        vm.goBack()
        #expect(vm.currentStep == .selection)
    }

    @Test("goBack - detecting → detecting (뒤로 못 감)")
    func goBackFromDetecting() {
        let vm = OnboardingViewModel()
        vm.currentStep = .detecting
        vm.goBack()
        #expect(vm.currentStep == .detecting)
    }

    // MARK: - apply

    @Test("apply - 프로바이더 설정 + 마스터 업데이트 + 완료 플래그")
    func applyTest() {
        let original = OnboardingViewModel.isCompleted
        defer { OnboardingViewModel.isCompleted = original }

        let defaults = makeTestDefaults()
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.ollama]
        vm.masterProviderType = .ollama

        let providerManager = ProviderManager(defaults: defaults)
        let agentStore = AgentStore(defaults: defaults)

        vm.apply(providerManager: providerManager, agentStore: agentStore)

        // configs에 ollama가 추가되었는지
        #expect(providerManager.configs.contains(where: { $0.type == .ollama }))
        // 온보딩 완료 플래그 (UserDefaults.standard에 저장됨)
        #expect(OnboardingViewModel.isCompleted == true)
    }

    // MARK: - skipOnboarding

    @Test("skipOnboarding - 완료 플래그 설정")
    func skipOnboarding() {
        let vm = OnboardingViewModel()
        // 사전 조건: 미완료 상태
        UserDefaults.standard.set(false, forKey: "onboardingCompleted")
        vm.skipOnboarding()
        #expect(OnboardingViewModel.isCompleted == true)
        // cleanup
        UserDefaults.standard.removeObject(forKey: "onboardingCompleted")
    }

    // MARK: - isCompleted 정적 프로퍼티

    @Test("isCompleted - get/set")
    func isCompletedGetSet() {
        let original = OnboardingViewModel.isCompleted
        OnboardingViewModel.isCompleted = true
        #expect(OnboardingViewModel.isCompleted == true)
        OnboardingViewModel.isCompleted = false
        #expect(OnboardingViewModel.isCompleted == false)
        // restore
        OnboardingViewModel.isCompleted = original
    }

    // MARK: - 마스터 우선순위

    @Test("toggleProvider - 마스터 우선순위 (claudeCode > anthropic > openAI)")
    func masterPriorityOrder() {
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.openAI, .anthropic, .claudeCode]
        vm.masterProviderType = .claudeCode
        vm.toggleProvider(.claudeCode) // claudeCode 해제
        // anthropic이 다음 우선순위
        #expect(vm.masterProviderType == .anthropic)
        vm.toggleProvider(.anthropic) // anthropic도 해제
        // openAI가 다음
        #expect(vm.masterProviderType == .openAI)
    }

    // MARK: - OnboardingStep 열거형

    @Test("OnboardingStep - 모든 케이스")
    func onboardingStepCases() {
        let vm = OnboardingViewModel()
        vm.currentStep = .detecting
        #expect(vm.currentStep == .detecting)
        vm.currentStep = .selection
        #expect(vm.currentStep == .selection)
        vm.currentStep = .apiKeyInput
        #expect(vm.currentStep == .apiKeyInput)
        vm.currentStep = .complete
        #expect(vm.currentStep == .complete)
    }

    // MARK: - API 키 상태

    @Test("apiKeys - 수동 설정")
    func apiKeysManual() {
        let vm = OnboardingViewModel()
        vm.apiKeys[.openAI] = "sk-test-key"
        #expect(vm.apiKeys[.openAI] == "sk-test-key")
        #expect(vm.apiKeys[.google] == nil)
    }

    @Test("useDetectedKey - 감지된 키 사용 여부")
    func useDetectedKeyFlag() {
        let vm = OnboardingViewModel()
        vm.useDetectedKey[.openAI] = true
        #expect(vm.useDetectedKey[.openAI] == true)
        #expect(vm.useDetectedKey[.google] == nil)
    }
}
