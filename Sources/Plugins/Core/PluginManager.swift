import Foundation

@MainActor
final class PluginManager: ObservableObject {
    @Published var plugins: [any DougPlugin] = []
    @Published var activePluginIDs: Set<String> = []

    private var pluginContext: PluginContext?
    private let defaults: UserDefaults

    /// 외부 플러그인 설치 디렉토리
    static var pluginsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DOUGLAS/Plugins")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 초기화 (기존 configure 패턴)

    func configure(roomManager: RoomManager, agentStore: AgentStore) {
        self.pluginContext = PluginContext(roomManager: roomManager, agentStore: agentStore)
        discoverPlugins()
        restoreActivePlugins()
    }

    // MARK: - 플러그인 발견

    private func discoverPlugins() {
        // 1. 빌트인 플러그인
        let builtins: [any DougPlugin] = [
            SlackPlugin(),
        ]
        for plugin in builtins {
            registerPlugin(plugin)
        }

        // 2. 외부 스크립트 플러그인 (~/Library/Application Support/DOUGLAS/Plugins/)
        let dir = Self.pluginsDirectory
        ensureDirectory(dir)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for itemURL in contents {
            guard (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if let plugin = loadScriptPlugin(from: itemURL) {
                registerPlugin(plugin)
            }
        }
    }

    private func registerPlugin(_ plugin: any DougPlugin) {
        if let ctx = pluginContext {
            plugin.configure(context: ctx)
        }
        plugins.append(plugin)
    }

    /// plugin.json에서 ScriptPlugin 로드
    private func loadScriptPlugin(from directory: URL) -> ScriptPlugin? {
        let manifestURL = directory.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return nil
        }
        // 중복 체크
        guard !plugins.contains(where: { $0.info.id == manifest.id }) else { return nil }
        return ScriptPlugin(manifest: manifest, directory: directory)
    }

    // MARK: - 플러그인 설치 / 제거

    /// 외부 플러그인 폴더를 선택하여 설치 (복사)
    func installPlugin(from sourceURL: URL) -> (success: Bool, message: String) {
        let manifestURL = sourceURL.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return (false, "plugin.json을 찾을 수 없거나 형식이 올바르지 않습니다.")
        }

        // 중복 체크
        if plugins.contains(where: { $0.info.id == manifest.id }) {
            return (false, "이미 설치된 플러그인입니다: \(manifest.name)")
        }

        // 설치 디렉토리로 복사
        let destURL = Self.pluginsDirectory.appendingPathComponent(manifest.id)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            // 스크립트 파일에 실행 권한 부여
            makeScriptsExecutable(in: destURL)

            // 로드 & 등록
            if let plugin = loadScriptPlugin(from: destURL) {
                registerPlugin(plugin)
                return (true, "\(manifest.name) 설치 완료")
            }
            return (false, "플러그인 로드 실패")
        } catch {
            return (false, "설치 실패: \(error.localizedDescription)")
        }
    }

    /// 외부 플러그인 제거
    func uninstallPlugin(_ pluginID: String) async -> Bool {
        guard let plugin = plugins.first(where: { $0.info.id == pluginID }),
              plugin is ScriptPlugin else { return false } // 빌트인은 제거 불가

        // 비활성화 먼저
        if plugin.isActive {
            await deactivatePlugin(pluginID)
        }

        // 파일 삭제
        let dir = Self.pluginsDirectory.appendingPathComponent(pluginID)
        try? FileManager.default.removeItem(at: dir)

        // 목록에서 제거
        plugins.removeAll { $0.info.id == pluginID }
        return true
    }

    // MARK: - 플러그인 생성 (빌더)

    /// 플러그인 ID 중복 여부 확인
    func isIDTaken(_ id: String) -> Bool {
        plugins.contains { $0.info.id == id }
    }

    /// 빌더에서 생성된 플러그인을 직접 설치
    func createPlugin(
        manifest: PluginManifest,
        scripts: [(filename: String, content: String)]
    ) -> (success: Bool, message: String) {
        // 중복 체크
        if isIDTaken(manifest.id) {
            return (false, "이미 같은 ID의 플러그인이 있습니다: \(manifest.id)")
        }

        let destURL = Self.pluginsDirectory.appendingPathComponent(manifest.id)
        do {
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)

            // plugin.json 쓰기
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(manifest)
            try jsonData.write(to: destURL.appendingPathComponent("plugin.json"))

            // 스크립트 파일 쓰기
            for script in scripts {
                let scriptURL = destURL.appendingPathComponent(script.filename)
                try script.content.write(to: scriptURL, atomically: true, encoding: .utf8)
            }

            // 실행 권한 부여
            makeScriptsExecutable(in: destURL)

            // 로드 & 등록
            if let plugin = loadScriptPlugin(from: destURL) {
                registerPlugin(plugin)
                return (true, "\(manifest.name) 생성 완료")
            }

            // 로드 실패 시 정리
            try? FileManager.default.removeItem(at: destURL)
            return (false, "플러그인 로드 실패")
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            return (false, "생성 실패: \(error.localizedDescription)")
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

    // MARK: - 인터셉트 훅

    /// 도구 실행 전 인터셉트 — 첫 번째로 override/block을 반환하는 플러그인이 우선
    func interceptTool(name: String, arguments: [String: String]) async -> ToolInterceptResult {
        for plugin in plugins where plugin.isActive {
            let result = await plugin.interceptToolExecution(toolName: name, arguments: arguments)
            switch result {
            case .passthrough:
                continue
            case .override, .block:
                return result
            }
        }
        return .passthrough
    }

    // MARK: - 에이전트 능력 주입

    /// 특정 플러그인의 agentCapabilities 조회
    func capabilities(for pluginID: String) -> PluginAgentCapabilities? {
        guard let plugin = plugins.first(where: { $0.info.id == pluginID && $0.isActive }) else { return nil }
        return plugin.agentCapabilities
    }

    /// 에이전트에 장착된 모든 플러그인의 providedSkillTags를 합산
    func effectiveSkillTags(for agent: Agent) -> [String] {
        agent.equippedPluginIDs.flatMap { id in
            capabilities(for: id)?.providedSkillTags ?? []
        }
    }

    /// 에이전트에 장착된 모든 플러그인의 providedRules를 합산
    func effectiveRules(for agent: Agent) -> [String] {
        agent.equippedPluginIDs.flatMap { id in
            capabilities(for: id)?.providedRules ?? []
        }
    }

    /// 에이전트에 장착된 모든 플러그인의 providedTools를 합산
    func effectiveTools(for agent: Agent) -> [AgentTool] {
        agent.equippedPluginIDs.flatMap { id in
            capabilities(for: id)?.providedTools ?? []
        }
    }

    // MARK: - Helpers

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeScriptsExecutable(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let scriptExts = Set(["sh", "bash", "zsh", "py", "python", "js", "rb"])
        for file in files where scriptExts.contains(file.pathExtension) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
    }
}
