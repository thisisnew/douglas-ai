import Testing
import Foundation
@testable import DOUGLAS

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
        #expect(vm.currentStep == .claudeSetup)
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
        vm.selectedTypes = [.claudeCode, .openAI, .google]
        vm.allProviderTypes = [.claudeCode, .openAI, .google]
        let needKey = vm.selectedProvidersNeedingKey
        #expect(needKey.contains(.openAI))
        #expect(needKey.contains(.google))
        #expect(!needKey.contains(.claudeCode))
    }

    @Test("selectedProvidersNoKey - 키 불필요 프로바이더만 반환")
    func selectedProvidersNoKey() {
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.claudeCode, .openAI]
        let noKey = vm.selectedProvidersNoKey
        #expect(noKey.contains(.claudeCode))
        #expect(!noKey.contains(.openAI))
    }

    // MARK: - goToNext / goBack

    @Test("goToNext - claudeSetup → providerSelection")
    func goToNextFromClaudeSetup() {
        let vm = OnboardingViewModel()
        vm.currentStep = .claudeSetup
        vm.goToNext()
        #expect(vm.currentStep == .providerSelection)
    }

    @Test("goToNext - providerSelection → apiKeyInput (키 필요한 프로바이더 있을 때)")
    func goToNextSelectionToApiKey() {
        let vm = OnboardingViewModel()
        vm.currentStep = .providerSelection
        vm.selectedTypes = [.openAI]
        vm.allProviderTypes = [.openAI]
        vm.goToNext()
        #expect(vm.currentStep == .apiKeyInput)
    }

    @Test("goToNext - providerSelection → complete (키 불필요)")
    func goToNextSelectionToComplete() {
        let vm = OnboardingViewModel()
        vm.currentStep = .providerSelection
        vm.selectedTypes = [.claudeCode]
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

    @Test("goBack - apiKeyInput → providerSelection")
    func goBackFromApiKey() {
        let vm = OnboardingViewModel()
        vm.currentStep = .apiKeyInput
        vm.goBack()
        #expect(vm.currentStep == .providerSelection)
    }

    @Test("goBack - providerSelection → providerSelection (뒤로 못 감)")
    func goBackFromSelection() {
        let vm = OnboardingViewModel()
        vm.currentStep = .providerSelection
        vm.goBack()
        #expect(vm.currentStep == .providerSelection)
    }

    @Test("goBack - claudeSetup → claudeSetup (뒤로 못 감)")
    func goBackFromClaudeSetup() {
        let vm = OnboardingViewModel()
        vm.currentStep = .claudeSetup
        vm.goBack()
        #expect(vm.currentStep == .claudeSetup)
    }

    // MARK: - apply

    @Test("apply - 프로바이더 설정 + 마스터 업데이트 + 완료 플래그")
    func applyTest() {
        let original = OnboardingViewModel.isCompleted
        defer { OnboardingViewModel.isCompleted = original }

        let defaults = makeTestDefaults()
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.openAI]
        vm.masterProviderType = .openAI

        let providerManager = ProviderManager(defaults: defaults)
        let agentStore = AgentStore(defaults: defaults)

        vm.apply(providerManager: providerManager, agentStore: agentStore)

        #expect(providerManager.configs.contains(where: { $0.type == .openAI }))
        // 온보딩 완료 플래그 (UserDefaults.standard에 저장됨)
        #expect(OnboardingViewModel.isCompleted == true)
    }

    // MARK: - skipOnboarding

    @Test("skipOnboarding - 완료 플래그 설정")
    func skipOnboarding() {
        let vm = OnboardingViewModel()
        // 사전 조건: 미완료 상태
        UserDefaults.standard.set(false, forKey: "onboardingCompleted")
        let defaults = makeTestDefaults()
        let providerManager = ProviderManager(defaults: defaults)
        let agentStore = AgentStore(defaults: defaults)
        vm.skipOnboarding(providerManager: providerManager, agentStore: agentStore)
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
        vm.currentStep = .claudeSetup
        #expect(vm.currentStep == .claudeSetup)
        vm.currentStep = .providerSelection
        #expect(vm.currentStep == .providerSelection)
        vm.currentStep = .apiKeyInput
        #expect(vm.currentStep == .apiKeyInput)
        vm.currentStep = .complete
        #expect(vm.currentStep == .complete)
    }

    // MARK: - Claude Setup 관련

    @Test("claudeSetupDone - 초기값 false")
    func claudeSetupDoneInit() {
        let vm = OnboardingViewModel()
        #expect(vm.claudeSetupDone == false)
        #expect(vm.claudeSkipped == false)
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

    // MARK: - startClaudeSetup

    @Test("startClaudeSetup - 비동기 감지 실행")
    func startClaudeSetup() async {
        await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains(where: { $0.contains("command -v claude") }) {
                return (exitCode: 1, stdout: "", stderr: "not found")
            }
            if args.contains(where: { $0.contains("command -v") }) {
                return (exitCode: 0, stdout: "node:\nnpm:\ngit:/usr/bin/git\nbrew:\n", stderr: "")
            }
            return (exitCode: 1, stdout: "", stderr: "")
        }) {
            let vm = OnboardingViewModel()
            await vm.startClaudeSetup()
            #expect(vm.claudeInstaller.state != .checking)
            #expect(vm.dependencyChecker.isChecking == false)
        }
    }

    // MARK: - finishClaudeSetup

    @Test("finishClaudeSetup - Claude 준비됨 → 마스터 설정")
    func finishClaudeSetupReady() async {
        let vm = OnboardingViewModel()
        // Claude가 준비된 상태를 시뮬레이션
        vm.claudeInstaller.state = .ready
        await vm.finishClaudeSetup()

        #expect(vm.claudeSetupDone == true)
        #expect(vm.masterProviderType == .claudeCode)
        #expect(vm.selectedTypes.contains(.claudeCode))
        #expect(vm.isDetecting == false)
        #expect(vm.currentStep == .providerSelection)
    }

    @Test("finishClaudeSetup - Claude 미준비 → 건너뛰기")
    func finishClaudeSetupNotReady() async {
        let vm = OnboardingViewModel()
        vm.claudeInstaller.state = .notFound
        await vm.finishClaudeSetup()

        #expect(vm.claudeSetupDone == true)
        #expect(vm.claudeSkipped == true)
        #expect(vm.isDetecting == false)
        #expect(vm.currentStep == .providerSelection)
    }

    // MARK: - skipClaudeSetup

    @Test("skipClaudeSetup - 건너뛰기 후 프로바이더 감지")
    func skipClaudeSetup() async {
        let vm = OnboardingViewModel()
        await vm.skipClaudeSetup()

        #expect(vm.claudeSkipped == true)
        #expect(vm.claudeSetupDone == true)
        #expect(vm.isDetecting == false)
        #expect(vm.currentStep == .providerSelection)
    }

    // MARK: - installClaudeCode

    @Test("installClaudeCode - 크래시 없이 실행")
    func installClaudeCode() async {
        await ProcessRunner.withMock({ _, args, _, _ in
            if args.contains("install") {
                return (exitCode: 0, stdout: "installed mock\n", stderr: "")
            }
            return (exitCode: 1, stdout: "", stderr: "not found")
        }) {
            let vm = OnboardingViewModel()
            await vm.installClaudeCode()
            #expect(vm.claudeInstaller.state != .checking)
        }
    }

    // MARK: - apply 다양한 프로바이더

    @Test("apply - 여러 프로바이더 + API 키")
    func applyMultipleProviders() {
        let original = OnboardingViewModel.isCompleted
        defer { OnboardingViewModel.isCompleted = original }

        let defaults = makeTestDefaults()
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.openAI, .google]
        vm.masterProviderType = .openAI
        vm.apiKeys[.openAI] = "sk-test"
        vm.apiKeys[.google] = "gk-test"

        let providerManager = ProviderManager(defaults: defaults)
        let agentStore = AgentStore(defaults: defaults)

        vm.apply(providerManager: providerManager, agentStore: agentStore)

        #expect(providerManager.configs.contains(where: { $0.type == .openAI }))
        #expect(providerManager.configs.contains(where: { $0.type == .google }))
        #expect(OnboardingViewModel.isCompleted == true)
    }

    @Test("apply - ClaudeCode 마스터 → 모델명 확인")
    func applyClaudeCodeMaster() {
        let original = OnboardingViewModel.isCompleted
        defer { OnboardingViewModel.isCompleted = original }

        let defaults = makeTestDefaults()
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.claudeCode]
        vm.masterProviderType = .claudeCode

        let providerManager = ProviderManager(defaults: defaults)
        let agentStore = AgentStore(defaults: defaults)

        vm.apply(providerManager: providerManager, agentStore: agentStore)

        let master = agentStore.masterAgent
        #expect(master?.modelName == "claude-sonnet-4-6")
    }

    // MARK: - skipOnboarding 감지된 프로바이더 있을 때

    @Test("skipOnboarding - 선택된 프로바이더가 있으면 apply 호출")
    func skipOnboardingWithSelected() {
        let original = OnboardingViewModel.isCompleted
        defer { OnboardingViewModel.isCompleted = original }

        let defaults = makeTestDefaults()
        let vm = OnboardingViewModel()
        vm.selectedTypes = [.google]
        vm.masterProviderType = .google

        let providerManager = ProviderManager(defaults: defaults)
        let agentStore = AgentStore(defaults: defaults)

        vm.skipOnboarding(providerManager: providerManager, agentStore: agentStore)

        #expect(OnboardingViewModel.isCompleted == true)
        #expect(providerManager.configs.contains(where: { $0.type == .google }))
    }

    // MARK: - startProviderDetection (finishClaudeSetup을 통한 간접 테스트)

    @Test("startProviderDetection - allProviderTypes 채워짐")
    func providerDetection() async {
        let vm = OnboardingViewModel()
        vm.claudeInstaller.state = .notFound
        await vm.finishClaudeSetup()

        // 감지 완료 후 allProviderTypes가 채워져야 함
        #expect(!vm.allProviderTypes.isEmpty)
        #expect(vm.isDetecting == false)
    }

    // MARK: - claudeInstaller / dependencyChecker 접근

    @Test("claudeInstaller - 직접 접근 가능")
    func claudeInstallerAccess() {
        let vm = OnboardingViewModel()
        #expect(vm.claudeInstaller.state == .checking)
    }

    @Test("dependencyChecker - 직접 접근 가능")
    func dependencyCheckerAccess() {
        let vm = OnboardingViewModel()
        #expect(vm.dependencyChecker.dependencies.count == 1)
    }
}
