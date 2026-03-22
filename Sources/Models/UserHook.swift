import Foundation

/// 사용자가 직접 정의하는 자동화 Hook
struct UserHook: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var trigger: HookTrigger
    var action: HookAction
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, trigger: HookTrigger, action: HookAction, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
    }
}

// MARK: - Hook Trigger

enum HookTrigger: String, Codable, CaseIterable, Hashable {
    case roomCompleted       // 작업 완료 시
    case roomFailed          // 작업 실패 시
    case fileWritten         // 파일 작성 시
    case beforeShellExec     // 명령 실행 전
    case approvalRequested   // 승인 요청 시

    var displayName: String {
        switch self {
        case .roomCompleted:     return "작업 완료 시"
        case .roomFailed:        return "작업 실패 시"
        case .fileWritten:       return "파일 작성 시"
        case .beforeShellExec:   return "명령 실행 전"
        case .approvalRequested: return "승인 요청 시"
        }
    }

    var icon: String {
        switch self {
        case .roomCompleted:     return "checkmark.circle"
        case .roomFailed:        return "exclamationmark.triangle"
        case .fileWritten:       return "doc.badge.plus"
        case .beforeShellExec:   return "terminal"
        case .approvalRequested: return "hand.raised"
        }
    }
}

// MARK: - Hook Action

enum HookAction: Codable, Hashable {
    case logToFile(path: String)
    case runScript(path: String)
    case systemNotification(title: String)

    var displayName: String {
        switch self {
        case .logToFile:          return "파일에 기록"
        case .runScript:          return "스크립트 실행"
        case .systemNotification: return "시스템 알림"
        }
    }

    var icon: String {
        switch self {
        case .logToFile:          return "doc.text"
        case .runScript:          return "applescript"
        case .systemNotification: return "bell"
        }
    }
}

// MARK: - Hook Context

/// Hook 실행 시 전달되는 컨텍스트 정보
struct HookContext: Sendable {
    let roomID: UUID?
    let roomTitle: String?
    let agentName: String?
    let command: String?
    let filePath: String?
    let timestamp: Date

    init(
        roomID: UUID? = nil,
        roomTitle: String? = nil,
        agentName: String? = nil,
        command: String? = nil,
        filePath: String? = nil,
        timestamp: Date = Date()
    ) {
        self.roomID = roomID
        self.roomTitle = roomTitle
        self.agentName = agentName
        self.command = command
        self.filePath = filePath
        self.timestamp = timestamp
    }
}

// MARK: - Hook Templates

extension UserHook {
    /// 내장 Hook 템플릿
    static let templates: [UserHook] = [
        UserHook(
            name: "작업 이력 자동 기록",
            trigger: .roomCompleted,
            action: .logToFile(path: "~/Documents/douglas-log.md"),
            isEnabled: false
        ),
        UserHook(
            name: "위험 명령 알림",
            trigger: .beforeShellExec,
            action: .systemNotification(title: "위험한 명령이 실행됩니다"),
            isEnabled: false
        ),
        UserHook(
            name: "작업 완료 알림",
            trigger: .roomCompleted,
            action: .systemNotification(title: "작업이 완료되었습니다"),
            isEnabled: false
        ),
    ]
}
