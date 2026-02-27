import Foundation

// MARK: - 도구 정의

/// 프로바이더 무관 도구 정의
struct AgentTool: Identifiable, Codable, Hashable {
    let id: String              // "file_read", "shell_exec" 등
    let name: String            // 표시 이름: "파일 읽기"
    let description: String     // LLM에 전달되는 설명
    let parameters: [ToolParameter]

    struct ToolParameter: Codable, Hashable {
        let name: String
        let type: ParameterType
        let description: String
        let required: Bool
        let enumValues: [String]?
    }

    enum ParameterType: String, Codable, Hashable {
        case string
        case integer
        case boolean
        case array
    }
}

// MARK: - 도구 호출 / 결과

/// 모델이 요청한 도구 호출
struct ToolCall: Identifiable, Codable {
    let id: String
    let toolName: String
    let arguments: [String: ToolArgumentValue]
}

/// 타입 안전 인자값
enum ToolArgumentValue: Codable, Hashable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode(Int.self) {
            self = .integer(val)
        } else if let val = try? container.decode(Bool.self) {
            self = .boolean(val)
        } else if let val = try? container.decode([String].self) {
            self = .array(val)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val):  try container.encode(val)
        case .integer(let val): try container.encode(val)
        case .boolean(let val): try container.encode(val)
        case .array(let val):   try container.encode(val)
        }
    }

    /// 문자열 값 추출 (편의 메서드)
    var stringValue: String? {
        if case .string(let val) = self { return val }
        return nil
    }
}

/// 도구 실행 결과
struct ToolResult: Codable {
    let callID: String
    let content: String
    let isError: Bool
}

// MARK: - AI 응답 타입

/// 모델 응답 (텍스트, 도구 호출, 또는 혼합)
enum AIResponseContent {
    case text(String)
    case toolCalls([ToolCall])
    case mixed(text: String, toolCalls: [ToolCall])
}

// MARK: - 리치 대화 메시지

/// 도구 호출/결과를 포함할 수 있는 대화 메시지
struct ConversationMessage {
    let role: String            // "user", "assistant", "system", "tool"
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallID: String?     // role == "tool"일 때 참조하는 ToolCall.id
    let attachments: [ImageAttachment]?

    static func user(_ content: String, attachments: [ImageAttachment]? = nil) -> ConversationMessage {
        ConversationMessage(role: "user", content: content, toolCalls: nil, toolCallID: nil, attachments: attachments)
    }

    static func assistant(_ content: String) -> ConversationMessage {
        ConversationMessage(role: "assistant", content: content, toolCalls: nil, toolCallID: nil, attachments: nil)
    }

    static func system(_ content: String) -> ConversationMessage {
        ConversationMessage(role: "system", content: content, toolCalls: nil, toolCallID: nil, attachments: nil)
    }

    static func assistantToolCalls(_ calls: [ToolCall], text: String? = nil) -> ConversationMessage {
        ConversationMessage(role: "assistant", content: text, toolCalls: calls, toolCallID: nil, attachments: nil)
    }

    static func toolResult(callID: String, content: String, isError: Bool = false) -> ConversationMessage {
        let prefix = isError ? "[오류] " : ""
        return ConversationMessage(role: "tool", content: prefix + content, toolCalls: nil, toolCallID: callID, attachments: nil)
    }
}

// MARK: - 능력 프리셋

/// 용도별 도구 프리셋
enum CapabilityPreset: String, Codable, CaseIterable, Identifiable {
    case none       = "없음"
    case researcher = "리서처"
    case developer  = "개발자"
    case analyst    = "분석가"
    case fullAccess = "전체 권한"
    case custom     = "사용자 정의"

    var id: String { rawValue }

    var includedToolIDs: [String] {
        switch self {
        case .none:       return []
        case .researcher: return ["web_search", "web_fetch"]
        case .developer:  return ["file_read", "file_write", "shell_exec"]
        case .analyst:    return ["file_read", "shell_exec", "web_fetch", "invite_agent", "list_agents", "suggest_agent_creation", "jira_create_subtask", "jira_update_status", "jira_add_comment"]
        case .fullAccess: return ToolRegistry.allToolIDs
        case .custom:     return []
        }
    }
}

// MARK: - 도구 레지스트리

/// 내장 도구 카탈로그
enum ToolRegistry {
    static let allTools: [AgentTool] = [
        AgentTool(
            id: "file_read",
            name: "파일 읽기",
            description: "Read the contents of a file at the given path. Returns the file content as text.",
            parameters: [
                .init(name: "path", type: .string, description: "Absolute file path to read", required: true, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "file_write",
            name: "파일 쓰기",
            description: "Write content to a file at the given path. Creates the file if it doesn't exist, overwrites if it does.",
            parameters: [
                .init(name: "path", type: .string, description: "Absolute file path to write", required: true, enumValues: nil),
                .init(name: "content", type: .string, description: "Content to write to the file", required: true, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "shell_exec",
            name: "셸 명령",
            description: "Execute a shell command and return its stdout and stderr output.",
            parameters: [
                .init(name: "command", type: .string, description: "Shell command to execute", required: true, enumValues: nil),
                .init(name: "working_directory", type: .string, description: "Working directory for the command (optional)", required: false, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "web_search",
            name: "웹 검색 (준비 중)",
            description: "Search the web for information and return results. (미구현)",
            parameters: [
                .init(name: "query", type: .string, description: "Search query string", required: true, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "web_fetch",
            name: "웹 페이지 가져오기",
            description: "Fetch content from a URL. For Jira URLs, authentication is automatically applied. Returns the response body as text.",
            parameters: [
                .init(name: "url", type: .string, description: "URL to fetch", required: true, enumValues: nil),
                .init(name: "method", type: .string, description: "HTTP method (GET, POST). Default: GET", required: false, enumValues: ["GET", "POST"]),
                .init(name: "body", type: .string, description: "Request body for POST requests", required: false, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "invite_agent",
            name: "에이전트 초대",
            description: "Invite another agent into the current room to collaborate. The invited agent will join and can participate in the conversation.",
            parameters: [
                .init(name: "agent_name", type: .string, description: "Name of the agent to invite", required: true, enumValues: nil),
                .init(name: "reason", type: .string, description: "Reason for inviting this agent", required: false, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "list_agents",
            name: "에이전트 목록",
            description: "List all available agents that can be invited to the current room.",
            parameters: []
        ),
        AgentTool(
            id: "jira_create_subtask",
            name: "Jira 서브태스크 생성",
            description: "Create a Jira sub-task under the given parent issue. Returns the created issue key.",
            parameters: [
                .init(name: "parent_key", type: .string, description: "Parent issue key (e.g. PROJ-123)", required: true, enumValues: nil),
                .init(name: "summary", type: .string, description: "Sub-task summary/title", required: true, enumValues: nil),
                .init(name: "project_key", type: .string, description: "Project key (optional, inferred from parent_key if omitted)", required: false, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "jira_update_status",
            name: "Jira 상태 변경",
            description: "Transition a Jira issue to a new status. Uses case-insensitive name matching against available transitions.",
            parameters: [
                .init(name: "issue_key", type: .string, description: "Issue key (e.g. PROJ-123)", required: true, enumValues: nil),
                .init(name: "status_name", type: .string, description: "Target status name (e.g. In Progress, Done)", required: true, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "jira_add_comment",
            name: "Jira 코멘트 추가",
            description: "Add a comment to a Jira issue using Atlassian Document Format.",
            parameters: [
                .init(name: "issue_key", type: .string, description: "Issue key (e.g. PROJ-123)", required: true, enumValues: nil),
                .init(name: "comment", type: .string, description: "Comment text to add", required: true, enumValues: nil)
            ]
        ),
        AgentTool(
            id: "suggest_agent_creation",
            name: "에이전트 생성 제안",
            description: "Suggest creating a new agent for the current room. The user must approve the suggestion before the agent is created. Use this when the team is missing a role needed for the task.",
            parameters: [
                .init(name: "name", type: .string, description: "Suggested agent name", required: true, enumValues: nil),
                .init(name: "persona", type: .string, description: "Persona/system prompt for the new agent", required: true, enumValues: nil),
                .init(name: "recommended_preset", type: .string, description: "Capability preset (없음/리서처/개발자/분석가/전체 권한)", required: false, enumValues: ["없음", "리서처", "개발자", "분석가", "전체 권한"]),
                .init(name: "recommended_provider", type: .string, description: "Preferred AI provider name", required: false, enumValues: nil),
                .init(name: "recommended_model", type: .string, description: "Preferred model ID", required: false, enumValues: nil),
                .init(name: "reason", type: .string, description: "Reason why this agent is needed", required: false, enumValues: nil)
            ]
        )
    ]

    static let allToolIDs: [String] = allTools.map { $0.id }

    static func tools(for ids: [String]) -> [AgentTool] {
        allTools.filter { ids.contains($0.id) }
    }
}
