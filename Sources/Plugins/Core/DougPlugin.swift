import Foundation

// MARK: - 플러그인 메타데이터

struct PluginInfo {
    let id: String              // "slack", "github" 등
    let name: String            // "Slack 연동"
    let description: String     // 한 줄 설명
    let version: String         // "1.0.0"
    let iconSystemName: String  // SF Symbol
}

// MARK: - 플러그인 이벤트

/// 플러그인이 구독할 수 있는 앱 이벤트
enum PluginEvent: Sendable {
    case roomCreated(roomID: UUID, title: String)
    case roomCompleted(roomID: UUID, title: String)
    case roomFailed(roomID: UUID, title: String)
    case messageAdded(roomID: UUID, message: ChatMessage)
    case workflowPhaseChanged(roomID: UUID, phase: WorkflowPhase?)
}

// MARK: - 플러그인 설정 필드

/// 설정 UI 자동 생성용 필드 정의
struct PluginConfigField {
    let key: String
    let label: String
    let type: FieldType
    let isSecret: Bool
    let placeholder: String

    enum FieldType {
        case text
        case multilineText
        case toggle
        case picker([String])
    }
}

// MARK: - 플러그인 프로토콜

@MainActor
protocol DougPlugin: AnyObject {
    /// 플러그인 메타데이터 (활성화 전에도 사용 가능)
    var info: PluginInfo { get }

    /// 현재 활성화 상태
    var isActive: Bool { get }

    /// 설정 UI에 표시할 필드 목록
    var configFields: [PluginConfigField] { get }

    /// 컨텍스트 주입 (발견 직후 1회 호출)
    func configure(context: PluginContext)

    /// 플러그인 활성화 (연결, 리스너 시작 등) — 성공 시 true
    func activate() async -> Bool

    /// 플러그인 비활성화 (연결 해제, 정리)
    func deactivate() async

    /// 앱 이벤트 수신
    func handle(event: PluginEvent) async

    /// 에이전트에 추가할 도구 (기본: 빈 배열)
    func registeredTools() -> [AgentTool]
}

extension DougPlugin {
    func registeredTools() -> [AgentTool] { [] }
}
