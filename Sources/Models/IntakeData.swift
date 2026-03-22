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
                parts.append("[Jira 연동 활성] 티켓 데이터 조회에 실패했습니다. 사용자에게 티켓 내용을 직접 확인하세요.")
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

    /// Clarify 단계 전용: Jira/API 언급 없이 중립적으로 데이터 표현
    /// (LLM이 Jira API 인증에 대해 환각하는 것을 방지)
    func asClarifyContextString() -> String {
        var parts: [String] = ["[사전 수집된 프로젝트 데이터]"]

        if !jiraDataList.isEmpty {
            parts.append("아래 티켓 데이터는 시스템이 자동으로 수집한 결과입니다.")
            for jira in jiraDataList {
                parts.append("- [\(jira.key)] \(jira.summary) (\(jira.issueType), \(jira.status))")
                if !jira.description.isEmpty {
                    let desc = jira.description.count > 200
                        ? String(jira.description.prefix(200)) + "…"
                        : jira.description
                    parts.append("  설명: \(desc)")
                }
            }
        } else if !jiraKeys.isEmpty {
            parts.append("티켓 참조: \(jiraKeys.joined(separator: ", "))")
            parts.append("(티켓 데이터 조회에 실패했습니다. 사용자에게 내용을 확인하세요)")
        } else if sourceType == .url, !urls.isEmpty {
            parts.append("참조 URL이 포함된 요청입니다.")
        }

        // Jira 데이터에서 도메인 힌트 감지 → LLM에게 역할 판단 참고 자료 제공
        if !jiraDataList.isEmpty {
            let allSummary = jiraDataList.map { $0.summary }.joined(separator: " ")
            let allDesc = jiraDataList.map { $0.description }.joined(separator: " ")
            let hints = DomainHintDetector.detect(summary: allSummary, description: allDesc)
            if let formatted = DomainHintDetector.formatHint(hints) {
                parts.append("감지된 관련 도메인: \(formatted)")
            }
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - URL 추출

/// 텍스트에서 URL을 추출 (한글 조사 등 trailing non-ASCII 자동 제거)
enum IntakeURLExtractor {
    /// 텍스트에서 모든 Jira 키 추출 (중복 제거, 순서 유지)
    static func extractJiraKeys(from text: String) -> [String] {
        let pattern = "[A-Z][A-Z0-9]+-\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var keys: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let key = String(text[r])
            if seen.insert(key).inserted { keys.append(key) }
        }
        return keys
    }

    /// 텍스트에 외부 참조(URL 또는 Jira 키)가 포함되어 있는지 확인
    static func containsExternalReferences(in text: String) -> Bool {
        !extractURLs(from: text).isEmpty || !extractJiraKeys(from: text).isEmpty
    }

    static func extractURLs(from text: String) -> [String] {
        let pattern = "https?://[^\\s]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            var url = String(text[r])
            // URL 끝에 붙은 비-ASCII 문자 제거 (한글 조사: 를, 을, 에서, 이, 가 등)
            while let last = url.unicodeScalars.last, !last.isASCII {
                url = String(url.dropLast())
            }
            return url.isEmpty ? nil : url
        }
    }
}

// MARK: - URL 오타 자동 교정

/// 사용자 입력의 흔한 URL 오타를 교정 (ttps:// → https:// 등)
enum IntakeURLCorrector {
    /// 텍스트 내 URL 오타를 교정하여 반환
    /// 이미 올바른 `https://`, `http://`는 건드리지 않음
    static func correct(_ text: String) -> String {
        // 프로토콜 오타 패턴: 단어 경계 또는 줄 시작/공백 뒤에서만 매칭
        // 정상 URL(https://, http://)을 먼저 보호한 뒤 오타만 교정
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|(?<=\s))(h?t?t?ps?://)(?=\S)"#
        ) else { return text }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text

        // 역순으로 매칭하여 인덱스 변동 방지
        let matches = regex.matches(in: text, range: range).reversed()
        for match in matches {
            guard let swiftRange = Range(match.range(at: 1), in: result) else { continue }
            let proto = String(result[swiftRange])
            // 이미 정상이면 건너뛰기
            if proto == "https://" || proto == "http://" { continue }
            // s 포함 여부로 https/http 판별
            let replacement = proto.contains("s") ? "https://" : "http://"
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }
}
