import Foundation

/// Jira Cloud 연결 설정
struct JiraConfig: Codable {
    var domain: String   // "company.atlassian.net"
    var email: String    // "user@company.com"

    // API 토큰은 KeychainHelper에 저장 (Codable 제외)
    private enum CodingKeys: String, CodingKey {
        case domain, email
    }

    var apiToken: String? {
        get { try? KeychainHelper.load(key: "jira-api-token") }
        set {
            if let value = newValue, !value.isEmpty {
                _ = try? KeychainHelper.save(key: "jira-api-token", value: value)
            } else {
                _ = try? KeychainHelper.delete(key: "jira-api-token")
            }
        }
    }

    var isConfigured: Bool {
        !domain.isEmpty && !email.isEmpty && apiToken != nil && !(apiToken?.isEmpty ?? true)
    }

    var baseURL: String {
        "https://\(domain)"
    }

    /// Basic Auth 헤더 값: "Basic base64(email:apiToken)"
    func authHeader() -> String? {
        guard let token = apiToken, !token.isEmpty else { return nil }
        let credentials = "\(email):\(token)"
        return "Basic \(Data(credentials.utf8).base64EncodedString())"
    }

    /// URL이 설정된 Jira 도메인에 해당하는지
    func isJiraURL(_ url: String) -> Bool {
        guard !domain.isEmpty, let parsed = URL(string: url), let host = parsed.host else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    /// Jira 키(PROJ-123)로 브라우저 URL 생성
    func buildBrowseURL(forKey key: String) -> String {
        "\(baseURL)/browse/\(key)"
    }

    /// 내 Jira accountId 캐시 (self-assign 용)
    var cachedAccountId: String?

    /// /rest/api/3/myself → accountId 조회 + 캐싱
    mutating func fetchMyAccountId() async throws -> String {
        if let cached = cachedAccountId { return cached }
        guard let auth = authHeader() else { throw URLError(.userAuthenticationRequired) }
        let url = URL(string: "\(baseURL)/rest/api/3/myself")!
        var req = URLRequest(url: url)
        req.addValue(auth, forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountId = json["accountId"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        cachedAccountId = accountId
        return accountId
    }

    /// Jira 브라우저 URL을 REST API URL로 변환
    /// "/browse/PROJ-123" → "/rest/api/3/issue/PROJ-123"
    func apiURL(from browseURL: String) -> String {
        // 이미 REST API URL이면 그대로 반환
        if browseURL.contains("/rest/api/") { return browseURL }

        // /browse/PROJ-123 패턴 감지
        if let range = browseURL.range(of: "/browse/") {
            let issueKey = String(browseURL[range.upperBound...])
                .components(separatedBy: "?").first ?? ""  // 쿼리 스트링 제거
            if !issueKey.isEmpty {
                return "\(baseURL)/rest/api/3/issue/\(issueKey)"
            }
        }

        // 변환 불가하면 원본 반환
        return browseURL
    }
}

// MARK: - 싱글턴 저장/로드

extension JiraConfig {
    private static let saveKey = "jiraConfig"

    static var shared: JiraConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: saveKey),
                  let config = try? JSONDecoder().decode(JiraConfig.self, from: data) else {
                return JiraConfig(domain: "", email: "")
            }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: saveKey)
            }
        }
    }
}
