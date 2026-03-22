import Foundation

/// 자연어 → JSON → 플러그인 자동 생성 서비스
///
/// LLM이 출력한 JSON을 기존 ScriptGenerator + PluginManager 파이프라인에 연결
enum LLMPluginBuilder {

    /// LLM이 생성한 JSON → (PluginManifest, 스크립트 배열) 변환
    static func buildPlugin(jsonSpec: String) throws -> (
        manifest: PluginManifest,
        scripts: [(filename: String, content: String)]
    ) {
        guard let data = jsonSpec.data(using: .utf8) else {
            throw LLMPluginBuilderError.emptyName
        }
        let spec = try JSONDecoder().decode(LLMPluginSpec.self, from: data)

        // 검증
        guard !spec.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LLMPluginBuilderError.emptyName
        }

        // HandlerConfig 배열로 변환
        var handlerConfigs: [HandlerConfig] = []
        if let handlers = spec.handlers {
            if let action = handlers.onMessage {
                handlerConfigs.append(try convertAction(action, event: .onMessage))
            }
            if let action = handlers.onRoomCreated {
                handlerConfigs.append(try convertAction(action, event: .onRoomCreated))
            }
            if let action = handlers.onRoomCompleted {
                handlerConfigs.append(try convertAction(action, event: .onRoomCompleted))
            }
            if let action = handlers.onRoomFailed {
                handlerConfigs.append(try convertAction(action, event: .onRoomFailed))
            }
        }

        guard !handlerConfigs.isEmpty else {
            throw LLMPluginBuilderError.noHandlers
        }

        // Config 필드 변환
        let configFields = (spec.config ?? []).map { field in
            var cf = BuilderConfigField()
            cf.key = field.key
            cf.label = field.label
            cf.isSecret = field.secret ?? false
            cf.placeholder = field.placeholder ?? ""
            return cf
        }

        // ID 생성
        let pluginID = spec.id ?? PluginSlug.generate(from: spec.name)

        // 기존 ScriptGenerator로 manifest 생성
        let manifest = ScriptGenerator.generateManifest(
            id: pluginID,
            name: spec.name,
            description: spec.description,
            icon: spec.icon ?? "puzzlepiece.extension",
            handlers: handlerConfigs,
            configFields: configFields
        )

        // 기존 ScriptGenerator로 스크립트 생성
        let scripts = handlerConfigs.map { handler in
            (filename: handler.eventType.scriptFileName,
             content: ScriptGenerator.generate(handler: handler))
        }

        return (manifest, scripts)
    }

    // MARK: - Private

    private static func convertAction(_ action: LLMPluginSpec.ActionSpec, event: PluginEventType) throws -> HandlerConfig {
        var config = HandlerConfig(eventType: event)

        switch action.action.lowercased() {
        case "webhook":
            config.actionType = .webhook
            config.webhookURL = action.url ?? ""
        case "shell":
            config.actionType = .shell
            config.shellCommand = action.command ?? ""
        case "notification":
            config.actionType = .notification
            config.notifTitle = action.title ?? "DOUGLAS"
            config.notifBody = action.body ?? "이벤트가 발생했습니다"
        default:
            throw LLMPluginBuilderError.invalidActionType(action.action)
        }

        return config
    }
}
