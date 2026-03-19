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
    // 방 라이프사이클
    case roomCreated(roomID: UUID, title: String)
    case roomCompleted(roomID: UUID, title: String)
    case roomFailed(roomID: UUID, title: String)
    case roomCancelled(roomID: UUID, title: String)

    // 메시지
    case messageAdded(roomID: UUID, message: ChatMessage)

    // 워크플로우
    case workflowPhaseChanged(roomID: UUID, phase: WorkflowPhase?)

    // 도구 실행 (신규)
    case toolExecutionStarted(roomID: UUID?, toolName: String, arguments: [String: String])
    case toolExecutionCompleted(roomID: UUID?, toolName: String, result: String, isError: Bool)

    // 에이전트 (신규)
    case agentInvited(roomID: UUID, agentName: String)
    case agentResponseReceived(roomID: UUID, agentName: String, responsePreview: String)

    // 승인 (신규)
    case approvalRequested(roomID: UUID, stepDescription: String)
    case approvalResolved(roomID: UUID, approved: Bool)

    // 파일 I/O (신규)
    case fileWritten(path: String, agentName: String?)
    case fileRead(path: String, agentName: String?)
}

// MARK: - 도구 인터셉트 결과

/// 플러그인이 도구 실행을 인터셉트한 결과
enum ToolInterceptResult: Sendable {
    /// 원래대로 실행 (인터셉트 안 함)
    case passthrough
    /// 도구 실행을 대체할 결과
    case override(content: String, isError: Bool)
    /// 도구 실행을 차단 (에러 메시지와 함께)
    case block(reason: String)
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

    // MARK: - 인터셉트 훅

    /// 도구 실행 전 인터셉트 — passthrough면 원래대로 실행
    func interceptToolExecution(
        toolName: String,
        arguments: [String: String]
    ) async -> ToolInterceptResult

    /// 에이전트에 주입할 능력 (skillTags, tools, rules, workModes)
    var agentCapabilities: PluginAgentCapabilities { get }
}

// MARK: - 플러그인이 에이전트에 주입하는 능력 (RPG식 스킬 주입)

/// 플러그인이 장착된 에이전트에 부여하는 능력
struct PluginAgentCapabilities: Sendable {
    let providedSkillTags: [String]      // 매칭용 태그 (예: ["slack", "실시간 알림"])
    let providedTools: [AgentTool]       // 사용 가능한 도구
    let providedRules: [String]          // 시스템 프롬프트에 주입되는 규칙
    let providedWorkModes: Set<WorkMode> // 작업 모드 확장

    static let empty = PluginAgentCapabilities(
        providedSkillTags: [],
        providedTools: [],
        providedRules: [],
        providedWorkModes: []
    )
}

// MARK: - 기본 구현

extension DougPlugin {
    func registeredTools() -> [AgentTool] { [] }
    func interceptToolExecution(toolName: String, arguments: [String: String]) async -> ToolInterceptResult { .passthrough }

    /// 기본 능력: 없음 (플러그인이 override하여 능력 제공)
    var agentCapabilities: PluginAgentCapabilities { .empty }
}
