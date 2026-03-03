import Testing
import Foundation
@testable import DOUGLAS

// MARK: - Mock Plugin

@MainActor
final class MockDougPlugin: DougPlugin {
    let info: PluginInfo
    private(set) var isActive = false
    let configFields: [PluginConfigField] = []

    var configureCallCount = 0
    var activateCallCount = 0
    var deactivateCallCount = 0
    var handledEvents: [PluginEvent] = []
    var shouldActivateSucceed = true

    init(id: String = "mock") {
        self.info = PluginInfo(
            id: id,
            name: "Mock Plugin",
            description: "테스트용 플러그인",
            version: "1.0.0",
            iconSystemName: "puzzlepiece"
        )
    }

    func configure(context: PluginContext) {
        configureCallCount += 1
    }

    func activate() async -> Bool {
        activateCallCount += 1
        isActive = shouldActivateSucceed
        return shouldActivateSucceed
    }

    func deactivate() async {
        deactivateCallCount += 1
        isActive = false
    }

    func handle(event: PluginEvent) async {
        handledEvents.append(event)
    }
}

// MARK: - Tests

@Suite("PluginManager Tests")
struct PluginManagerTests {

    @Test("초기 상태 — 플러그인 목록 비어있음")
    @MainActor
    func initialState() {
        let pm = PluginManager(defaults: makeTestDefaults())
        #expect(pm.plugins.isEmpty)
        #expect(pm.activePluginIDs.isEmpty)
    }

    @Test("PluginConfigStore — 일반 값 저장/조회")
    func configStoreNonSecret() {
        let defaults = makeTestDefaults()
        PluginConfigStore.setValue("hello", key: "testKey", pluginID: "test", defaults: defaults)
        let value = PluginConfigStore.getValue("testKey", pluginID: "test", defaults: defaults)
        #expect(value == "hello")
    }

    @Test("PluginConfigStore — enabled 상태 저장/조회")
    func configStoreEnabled() {
        let defaults = makeTestDefaults()
        #expect(PluginConfigStore.isEnabled("test", defaults: defaults) == false)

        PluginConfigStore.setEnabled("test", enabled: true, defaults: defaults)
        #expect(PluginConfigStore.isEnabled("test", defaults: defaults) == true)

        PluginConfigStore.setEnabled("test", enabled: false, defaults: defaults)
        #expect(PluginConfigStore.isEnabled("test", defaults: defaults) == false)
    }

    @Test("PluginConfigStore — nil 값 제거")
    func configStoreRemoveValue() {
        let defaults = makeTestDefaults()
        PluginConfigStore.setValue("value", key: "k", pluginID: "p", defaults: defaults)
        #expect(PluginConfigStore.getValue("k", pluginID: "p", defaults: defaults) == "value")

        PluginConfigStore.setValue(nil, key: "k", pluginID: "p", defaults: defaults)
        #expect(PluginConfigStore.getValue("k", pluginID: "p", defaults: defaults) == nil)
    }
}
