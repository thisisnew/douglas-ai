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
    var jiraKeys: [String]
    var jiraDataList: [JiraTicketSummary]
    var urls: [String]
    let parsedAt: Date

    init(
        sourceType: InputSourceType,
        rawInput: String,
        jiraKeys: [String] = [],
        jiraDataList: [JiraTicketSummary] = [],
        urls: [String] = [],
        parsedAt: Date = Date()
    ) {
        self.sourceType = sourceType
        self.rawInput = rawInput
        self.jiraKeys = jiraKeys
        self.jiraDataList = jiraDataList
        self.urls = urls
        self.parsedAt = parsedAt
    }

    // MARK: - Codable (하위 호환)

    private enum CodingKeys: String, CodingKey {
        case sourceType, rawInput
        case jiraKey, jiraKeys          // 구버전: jiraKey (String?), 신버전: jiraKeys ([String])
        case jiraData, jiraDataList     // 구버전: jiraData (단일), 신버전: jiraDataList (배열)
        case urls, parsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceType = try c.decode(InputSourceType.self, forKey: .sourceType)
        rawInput = try c.decode(String.self, forKey: .rawInput)

        // 신버전 배열 → 구버전 단일값 폴백
        if let keys = try? c.decode([String].self, forKey: .jiraKeys) {
            jiraKeys = keys
        } else if let key = try? c.decodeIfPresent(String.self, forKey: .jiraKey) {
            jiraKeys = [key]
        } else {
            jiraKeys = []
        }

        if let list = try? c.decode([JiraTicketSummary].self, forKey: .jiraDataList) {
            jiraDataList = list
        } else if let single = try? c.decodeIfPresent(JiraTicketSummary.self, forKey: .jiraData) {
            jiraDataList = [single]
        } else {
            jiraDataList = []
        }

        urls = try c.decode([String].self, forKey: .urls)
        parsedAt = try c.decode(Date.self, forKey: .parsedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceType, forKey: .sourceType)
        try c.encode(rawInput, forKey: .rawInput)
        try c.encode(jiraKeys, forKey: .jiraKeys)
        try c.encode(jiraDataList, forKey: .jiraDataList)
        try c.encode(urls, forKey: .urls)
        try c.encode(parsedAt, forKey: .parsedAt)
    }

    /// Intake 데이터를 에이전트 컨텍스트 문자열로 변환
    func asContextString() -> String {
        var parts: [String] = ["[입력 분석]"]
        parts.append("- 소스: \(sourceType.rawValue)")
        if !jiraKeys.isEmpty {
            if !jiraDataList.isEmpty {
                parts.append("[Jira 연동 활성] 아래 티켓 데이터는 Jira API에서 자동 조회된 결과입니다.")
            } else {
                parts.append("[Jira 연동 활성] 티켓 데이터 조회 대기 중. 실행 단계에서 web_fetch 도구로 조회 가능합니다.")
            }
            parts.append("- Jira 티켓: \(jiraKeys.joined(separator: ", "))")
        }
        for jira in jiraDataList {
            parts.append("- [\(jira.key)] \(jira.summary) (\(jira.issueType), \(jira.status))")
            if !jira.description.isEmpty {
                let desc = jira.description.count > 200
                    ? String(jira.description.prefix(200)) + "…"
                    : jira.description
                parts.append("  설명: \(desc)")
            }
        }
        if !urls.isEmpty {
            parts.append("- URL: \(urls.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }
}
