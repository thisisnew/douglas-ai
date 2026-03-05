import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessageType: String, Codable {
    case text
    case delegation
    case summary
    case chainProgress
    case suggestion
    case error
    case discussionRound
    case toolActivity
    case buildStatus
    case qaStatus
    case approvalRequest
    case userQuestion       // ask_user 도구로 사용자에게 보내는 질문
    case phaseTransition    // 워크플로우 단계 전환 알림
    case assumption         // 가정 선언
    case progress           // 실행 단계 진행 상태 ("~하는 중")
    case discussion         // 토론 턴 발언 (메인 채팅에서 숨김)
}

/// 도구 실행 상세 정보 (ProgressActivityBubble 확장 표시용)
struct ToolActivityDetail: Codable {
    let toolName: String        // file_read, file_write, shell_exec, web_fetch 등
    let subject: String?        // 파일 경로 / 명령어 / URL
    let contentPreview: String? // 잘린 내용 미리보기 (최대 500자)
    let isError: Bool

    /// 도구 이름 → 한국어 표시명
    var displayName: String {
        switch toolName {
        case "Read", "file_read":           return "파일 읽기"
        case "Write", "file_write":         return "파일 쓰기"
        case "Edit":                        return "파일 수정"
        case "Bash", "shell_exec":          return "명령 실행"
        case "Glob":                        return "파일 검색"
        case "Grep":                        return "내용 검색"
        case "WebFetch", "web_fetch":       return "웹 페이지"
        case "WebSearch", "web_search":     return "웹 검색"
        case "LSP":                         return "코드 분석"
        case "Agent":                       return "서브 에이전트"
        case "llm_call":                    return "실행 중"
        case "llm_result":                  return "완료"
        case "llm_error":                   return "API 오류"
        default:                            return toolName
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let agentName: String?
    let timestamp: Date
    var messageType: MessageType
    let attachments: [FileAttachment]?
    /// 부모 .progress 메시지 ID — non-nil이면 해당 progress 버블에 소속된 활동 메시지
    let activityGroupID: UUID?
    /// 도구 실행 상세 (toolActivity 메시지에만 존재)
    let toolDetail: ToolActivityDetail?
    /// 문서 저장 완료 시 파일 URL (file:// 스킴)
    let documentURL: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        agentName: String? = nil,
        timestamp: Date = Date(),
        messageType: MessageType = .text,
        attachments: [FileAttachment]? = nil,
        activityGroupID: UUID? = nil,
        toolDetail: ToolActivityDetail? = nil,
        documentURL: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.agentName = agentName
        self.timestamp = timestamp
        self.messageType = messageType
        self.attachments = attachments
        self.activityGroupID = activityGroupID
        self.toolDetail = toolDetail
        self.documentURL = documentURL
    }

    // 기존 저장 데이터 호환
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        messageType = try container.decodeIfPresent(MessageType.self, forKey: .messageType) ?? .text
        attachments = try container.decodeIfPresent([FileAttachment].self, forKey: .attachments)
        activityGroupID = try container.decodeIfPresent(UUID.self, forKey: .activityGroupID)
        toolDetail = try container.decodeIfPresent(ToolActivityDetail.self, forKey: .toolDetail)
        documentURL = try container.decodeIfPresent(String.self, forKey: .documentURL)
    }
}
