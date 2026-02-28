import Foundation

// MARK: - 입력 소스 타입

enum InputSourceType: String, Codable {
    case jira    // Jira 티켓 URL
    case text    // 일반 텍스트
    case url     // 기타 URL
}

// MARK: - Jira 티켓 요약

struct JiraTicketSummary: Codable {
    let key: String          // "PROJ-123"
    let summary: String      // 티켓 제목
    let issueType: String    // "Story", "Bug" 등
    let status: String       // "To Do", "In Progress" 등
    let description: String  // 설명 텍스트
}

// MARK: - Intake 데이터

/// Intake 단계에서 파싱된 입력 데이터
struct IntakeData: Codable {
    let sourceType: InputSourceType
    let rawInput: String
    var jiraKey: String?
    var jiraData: JiraTicketSummary?
    var urls: [String]
    let parsedAt: Date

    init(
        sourceType: InputSourceType,
        rawInput: String,
        jiraKey: String? = nil,
        jiraData: JiraTicketSummary? = nil,
        urls: [String] = [],
        parsedAt: Date = Date()
    ) {
        self.sourceType = sourceType
        self.rawInput = rawInput
        self.jiraKey = jiraKey
        self.jiraData = jiraData
        self.urls = urls
        self.parsedAt = parsedAt
    }

    /// Intake 데이터를 에이전트 컨텍스트 문자열로 변환
    func asContextString() -> String {
        var parts: [String] = ["[입력 분석]"]
        parts.append("- 소스: \(sourceType.rawValue)")
        if let key = jiraKey { parts.append("- Jira 키: \(key)") }
        if let jira = jiraData {
            parts.append("- 제목: \(jira.summary)")
            parts.append("- 유형: \(jira.issueType)")
            parts.append("- 상태: \(jira.status)")
            if !jira.description.isEmpty {
                parts.append("- 설명:\n\(jira.description)")
            }
        }
        if !urls.isEmpty {
            parts.append("- URL: \(urls.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }
}
