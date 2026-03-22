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
        // 같은 이름 + 같은 트리거의 hook이 이미 있으면 무시
        guard !hooks.contains(where: { $0.name == template.name && $0.trigger == template.trigger }) else { return }
        let hook = UserHook(name: template.name, trigger: template.trigger, action: template.action, isEnabled: true)
        hooks.append(hook)
    }

    // MARK: - Dispatch

    /// 트리거에 매칭되는 활성 Hook을 실행하고 결과를 반환
    nonisolated func dispatch(trigger: HookTrigger, context: HookContext) async -> [HookResult] {
        let activeHooks = await MainActor.run { hooks.filter { $0.isEnabled && $0.trigger == trigger } }
        var results: [HookResult] = []
        for hook in activeHooks {
            let result = await execute(hook: hook, context: context)
            results.append(result)
        }
        return results
    }

    /// 매칭되는 Hook 수 반환 (테스트용)
    func matchingHooks(for trigger: HookTrigger) -> [UserHook] {
        hooks.filter { $0.isEnabled && $0.trigger == trigger }
    }

    // MARK: - Execution

    private nonisolated func execute(hook: UserHook, context: HookContext) async -> HookResult {
        switch hook.action {
        case .logToFile(let path):
            return await executeLogToFile(path: path, hook: hook, context: context)
        case .runScript(let path):
            return await executeScript(path: path, hook: hook, context: context)
        case .systemNotification(let title):
            return await executeNotification(title: title, hook: hook, context: context)
        }
    }

    private nonisolated func executeLogToFile(path: String, hook: UserHook, context: HookContext) async -> HookResult {
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
            return HookResult(hookName: hook.name, success: true, errorMessage: nil)
        } catch {
            logger.error("Hook logToFile 실패: \(error.localizedDescription)")
            return HookResult(hookName: hook.name, success: false, errorMessage: error.localizedDescription)
        }
    }

    private static let scriptTimeoutSeconds: Double = 30

    private nonisolated func executeScript(path: String, hook: UserHook, context: HookContext) async -> HookResult {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            let msg = "스크립트를 찾을 수 없거나 실행 권한이 없습니다: \(expandedPath)"
            logger.error("Hook \(msg)")
            return HookResult(hookName: hook.name, success: false, errorMessage: msg)
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

            // 30초 타임아웃
            let deadline = Date().addingTimeInterval(Self.scriptTimeoutSeconds)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
            if process.isRunning {
                process.terminate()
                let msg = "실행 시간 초과 (\(Int(Self.scriptTimeoutSeconds))초)"
                logger.error("Hook 스크립트 \(msg): \(expandedPath)")
                return HookResult(hookName: hook.name, success: false, errorMessage: msg)
            }

            if process.terminationStatus != 0 {
                let msg = "종료 코드 \(process.terminationStatus)"
                return HookResult(hookName: hook.name, success: false, errorMessage: msg)
            }
            return HookResult(hookName: hook.name, success: true, errorMessage: nil)
        } catch {
            logger.error("Hook 스크립트 실행 실패: \(error.localizedDescription)")
            return HookResult(hookName: hook.name, success: false, errorMessage: error.localizedDescription)
        }
    }

    private nonisolated func executeNotification(title: String, hook: UserHook, context: HookContext) async -> HookResult {
        await MainActor.run {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = context.roomTitle ?? "DOUGLAS"
            NSUserNotificationCenter.default.deliver(notification)
        }
        return HookResult(hookName: hook.name, success: true, errorMessage: nil)
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(hooks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
