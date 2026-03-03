import Foundation

@MainActor
final class PluginManager: ObservableObject {
    @Published var plugins: [any DougPlugin] = []
    @Published var activePluginIDs: Set<String> = []

    private var pluginContext: PluginContext?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 초기화 (기존 configure 패턴)

    func configure(roomManager: RoomManager, agentStore: AgentStore) {
        self.pluginContext = PluginContext(roomManager: roomManager, agentStore: agentStore)
        discoverPlugins()
        restoreActivePlugins()
    }

    // MARK: - 플러그인 발견 (하드코딩 — 향후 동적 로딩 확장 가능)

    private func discoverPlugins() {
        let allPlugins: [any DougPlugin] = [
            SlackPlugin(),
        ]
        for plugin in allPlugins {
            if let ctx = pluginContext {
                plugin.configure(context: ctx)
            }
            plugins.append(plugin)
        }
    }

    // MARK: - 라이프사이클

    private func restoreActivePlugins() {
        Task {
            for plugin in plugins {
                if PluginConfigStore.isEnabled(plugin.info.id, defaults: defaults) {
                    let success = await plugin.activate()
                    if success {
                        activePluginIDs.insert(plugin.info.id)
                    }
                }
            }
        }
    }

    func activatePlugin(_ pluginID: String) async -> Bool {
        guard let plugin = plugins.first(where: { $0.info.id == pluginID }),
              !plugin.isActive else { return false }

        let success = await plugin.activate()
        if success {
            activePluginIDs.insert(pluginID)
            PluginConfigStore.setEnabled(pluginID, enabled: true, defaults: defaults)
        }
        return success
    }

    func deactivatePlugin(_ pluginID: String) async {
        guard let plugin = plugins.first(where: { $0.info.id == pluginID }) else { return }
        await plugin.deactivate()
        activePluginIDs.remove(pluginID)
        PluginConfigStore.setEnabled(pluginID, enabled: false, defaults: defaults)
    }

    // MARK: - 이벤트 디스패치

    func dispatch(_ event: PluginEvent) {
        Task {
            for plugin in plugins where plugin.isActive {
                await plugin.handle(event: event)
            }
        }
    }

    // MARK: - 도구 등록

    var pluginTools: [AgentTool] {
        plugins.filter { $0.isActive }.flatMap { $0.registeredTools() }
    }
}
