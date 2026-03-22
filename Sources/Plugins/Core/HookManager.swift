import Foundation
import os.log

private let logger = Logger(subsystem: "com.douglas.app", category: "HookManager")

/// 사용자 정의 Hook 관리 및 실행
@MainActor
final class HookManager: ObservableObject {

    @Published var hooks: [UserHook] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let storageKey = "userHooks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([UserHook].self, from: data) {
            self.hooks = decoded
        } else {
            self.hooks = []
        }
    }

    // MARK: - CRUD

    func addHook(_ hook: UserHook) {
        hooks.append(hook)
    }

    func removeHook(id: UUID) {
        hooks.removeAll { $0.id == id }
    }

    func toggleHook(id: UUID) {
        guard let idx = hooks.firstIndex(where: { $0.id == id }) else { return }
        hooks[idx].isEnabled.toggle()
    }

    func installTemplate(_ template: UserHook) {
        var hook = template
        hook = UserHook(name: template.name, trigger: template.trigger, action: template.action, isEnabled: true)
        hooks.append(hook)
    }

    // MARK: - Dispatch

    /// 트리거에 매칭되는 활성 Hook을 실행
    nonisolated func dispatch(trigger: HookTrigger, context: HookContext) async {
        let activeHooks = await MainActor.run { hooks.filter { $0.isEnabled && $0.trigger == trigger } }
        for hook in activeHooks {
            await execute(hook: hook, context: context)
        }
    }

    /// 매칭되는 Hook 수 반환 (테스트용)
    func matchingHooks(for trigger: HookTrigger) -> [UserHook] {
        hooks.filter { $0.isEnabled && $0.trigger == trigger }
    }

    // MARK: - Execution

    private nonisolated func execute(hook: UserHook, context: HookContext) async {
        switch hook.action {
        case .logToFile(let path):
            await executeLogToFile(path: path, hook: hook, context: context)
        case .runScript(let path):
            await executeScript(path: path, context: context)
        case .systemNotification(let title):
            await executeNotification(title: title, context: context)
        }
    }

    private nonisolated func executeLogToFile(path: String, hook: UserHook, context: HookContext) async {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: context.timestamp)

        var logEntry = "\n## \(timestamp)\n"
        logEntry += "- Hook: \(hook.name)\n"
        if let title = context.roomTitle { logEntry += "- Room: \(title)\n" }
        if let agent = context.agentName { logEntry += "- Agent: \(agent)\n" }
        if let cmd = context.command { logEntry += "- Command: \(cmd)\n" }
        if let file = context.filePath { logEntry += "- File: \(file)\n" }

        let fileURL = URL(fileURLWithPath: expandedPath)
        do {
            // 파일이 없으면 생성, 있으면 append
            if FileManager.default.fileExists(atPath: expandedPath) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                let header = "# DOUGLAS Hook Log\n"
                try (header + logEntry).write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Hook logToFile 실패: \(error.localizedDescription)")
        }
    }

    private nonisolated func executeScript(path: String, context: HookContext) async {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            logger.error("Hook 스크립트를 찾을 수 없거나 실행 권한이 없습니다: \(expandedPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: expandedPath)
        var env = ProcessInfo.processInfo.environment
        if let roomID = context.roomID { env["HOOK_ROOM_ID"] = roomID.uuidString }
        if let title = context.roomTitle { env["HOOK_ROOM_TITLE"] = title }
        if let agent = context.agentName { env["HOOK_AGENT_NAME"] = agent }
        if let cmd = context.command { env["HOOK_COMMAND"] = cmd }
        if let file = context.filePath { env["HOOK_FILE_PATH"] = file }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Hook 스크립트 실행 실패: \(error.localizedDescription)")
        }
    }

    private nonisolated func executeNotification(title: String, context: HookContext) async {
        await MainActor.run {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = context.roomTitle ?? "DOUGLAS"
            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(hooks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
