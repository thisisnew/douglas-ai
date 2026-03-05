import Foundation

// MARK: - 플러그인 매니페스트 (plugin.json)

/// 외부 스크립트 플러그인의 매니페스트 파일 구조
struct PluginManifest: Codable {
    let id: String
    let name: String
    let description: String
    let version: String
    let icon: String?               // SF Symbol name (기본: "puzzlepiece.extension")
    let author: String?

    /// 이벤트 → 스크립트 경로 매핑
    let handlers: PluginHandlers?

    /// 사용자 설정 필드
    let config: [ManifestConfigField]?

    struct PluginHandlers: Codable {
        let onMessage: String?       // "on_message.sh"
        let onRoomCreated: String?   // "on_room_created.sh"
        let onRoomCompleted: String? // "on_room_completed.sh"
        let onRoomFailed: String?    // "on_room_failed.sh"
        let onActivate: String?      // "on_activate.sh" (활성화 시 1회)
        let onDeactivate: String?    // "on_deactivate.sh"

        enum CodingKeys: String, CodingKey {
            case onMessage = "on_message"
            case onRoomCreated = "on_room_created"
            case onRoomCompleted = "on_room_completed"
            case onRoomFailed = "on_room_failed"
            case onActivate = "on_activate"
            case onDeactivate = "on_deactivate"
        }
    }

    struct ManifestConfigField: Codable {
        let key: String
        let label: String
        let secret: Bool?
        let placeholder: String?
    }
}

// MARK: - 스크립트 플러그인

/// 외부 스크립트 기반 플러그인 — plugin.json + 스크립트 파일로 구성
@MainActor
final class ScriptPlugin: DougPlugin {
    let info: PluginInfo
    let manifest: PluginManifest
    let pluginDirectory: URL

    private(set) var isActive = false
    private var context: PluginContext?

    var configFields: [PluginConfigField] {
        (manifest.config ?? []).map { field in
            PluginConfigField(
                key: field.key,
                label: field.label,
                type: .text,
                isSecret: field.secret ?? false,
                placeholder: field.placeholder ?? ""
            )
        }
    }

    init(manifest: PluginManifest, directory: URL) {
        self.manifest = manifest
        self.pluginDirectory = directory
        self.info = PluginInfo(
            id: manifest.id,
            name: manifest.name,
            description: manifest.description,
            version: manifest.version,
            iconSystemName: manifest.icon ?? "puzzlepiece.extension"
        )
    }

    // MARK: - 라이프사이클

    func configure(context: PluginContext) {
        self.context = context
    }

    func activate() async -> Bool {
        isActive = true
        // on_activate 스크립트 실행
        if let script = manifest.handlers?.onActivate {
            _ = await runScript(script, env: [:])
        }
        return true
    }

    func deactivate() async {
        if let script = manifest.handlers?.onDeactivate {
            _ = await runScript(script, env: [:])
        }
        isActive = false
    }

    // MARK: - 이벤트 처리

    func handle(event: PluginEvent) async {
        switch event {
        case .messageAdded(let roomID, let message):
            guard let script = manifest.handlers?.onMessage else { return }
            let env: [String: String] = [
                "ROOM_ID": roomID.uuidString,
                "MESSAGE_ROLE": message.role.rawValue,
                "MESSAGE_CONTENT": message.content,
                "MESSAGE_AGENT": message.agentName ?? "",
                "MESSAGE_TYPE": message.messageType.rawValue,
            ]
            let output = await runScript(script, env: env)
            await handleScriptOutput(output, roomID: roomID)

        case .roomCreated(let roomID, let title):
            guard let script = manifest.handlers?.onRoomCreated else { return }
            let env = ["ROOM_ID": roomID.uuidString, "ROOM_TITLE": title]
            let output = await runScript(script, env: env)
            await handleScriptOutput(output, roomID: roomID)

        case .roomCompleted(let roomID, let title):
            guard let script = manifest.handlers?.onRoomCompleted else { return }
            let env = ["ROOM_ID": roomID.uuidString, "ROOM_TITLE": title]
            _ = await runScript(script, env: env)

        case .roomFailed(let roomID, let title):
            guard let script = manifest.handlers?.onRoomFailed else { return }
            let env = ["ROOM_ID": roomID.uuidString, "ROOM_TITLE": title]
            _ = await runScript(script, env: env)

        case .workflowPhaseChanged,
             .toolExecutionStarted, .toolExecutionCompleted,
             .agentInvited, .agentResponseReceived,
             .approvalRequested, .approvalResolved,
             .fileWritten, .fileRead:
            break // 스크립트 플러그인에서는 미지원 (향후 확장 가능)
        }
    }

    // MARK: - 스크립트 실행

    private func runScript(_ scriptName: String, env: [String: String]) async -> String {
        let scriptURL = pluginDirectory.appendingPathComponent(scriptName)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return "" }

        return await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            // 스크립트 실행 방법 결정
            let ext = scriptURL.pathExtension
            switch ext {
            case "py", "python":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", scriptURL.path]
            case "js":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["node", scriptURL.path]
            default:
                // sh, bash, zsh 또는 직접 실행
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [scriptURL.path]
            }

            // 환경 변수: 시스템 기본 + 플러그인 설정값 + 이벤트 데이터
            var processEnv = ProcessInfo.processInfo.environment
            // 플러그인 설정값 주입
            for field in manifest.config ?? [] {
                if let value = PluginConfigStore.getValue(field.key, pluginID: info.id, isSecret: field.secret ?? false) {
                    processEnv["PLUGIN_\(field.key.uppercased())"] = value
                }
            }
            // 이벤트 데이터 주입
            for (key, value) in env {
                processEnv["DOUGLAS_\(key)"] = value
            }
            process.environment = processEnv
            process.currentDirectoryURL = pluginDirectory
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    /// 스크립트 stdout 처리 — JSON 액션 또는 일반 텍스트
    private func handleScriptOutput(_ output: String, roomID: UUID) async {
        guard !output.isEmpty, let ctx = context else { return }

        // JSON 액션 시도
        if let data = output.data(using: .utf8),
           let action = try? JSONDecoder().decode(ScriptAction.self, from: data) {
            switch action.type {
            case "reply":
                if let text = action.text {
                    await ctx.sendUserMessage(text, to: roomID)
                }
            case "create_room":
                if let title = action.title, let task = action.text {
                    ctx.createRoom(title: title, task: task)
                }
            default:
                break
            }
            return
        }

        // 일반 텍스트 → 응답으로 주입
        if !output.isEmpty {
            await ctx.sendUserMessage(output, to: roomID)
        }
    }
}

/// 스크립트가 stdout으로 반환할 수 있는 액션
private struct ScriptAction: Codable {
    let type: String        // "reply", "create_room"
    let text: String?
    let title: String?
}
