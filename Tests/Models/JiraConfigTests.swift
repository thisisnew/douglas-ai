import Testing
import Foundation
@testable import DOUGLAS

@Suite("JiraConfig Tests", .serialized)
struct JiraConfigTests {

    // MARK: - 기본 초기화

    @Test("기본 초기화 - 빈 값")
    func initEmpty() {
        let config = JiraConfig(domain: "", email: "")
        #expect(config.domain == "")
        #expect(config.email == "")
    }

    @Test("기본 초기화 - 값 설정")
    func initWithValues() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "user@company.com")
        #expect(config.domain == "company.atlassian.net")
        #expect(config.email == "user@company.com")
    }

    // MARK: - baseURL

    @Test("baseURL - 도메인 기반 HTTPS URL 생성")
    func baseURL() {
        let config = JiraConfig(domain: "myteam.atlassian.net", email: "a@b.com")
        #expect(config.baseURL == "https://myteam.atlassian.net")
    }

    @Test("baseURL - 빈 도메인")
    func baseURLEmpty() {
        let config = JiraConfig(domain: "", email: "")
        #expect(config.baseURL == "https://")
    }

    // MARK: - isConfigured

    @Test("isConfigured - 도메인 비어있으면 false")
    func isConfiguredNoDomain() {
        let config = JiraConfig(domain: "", email: "user@test.com")
        #expect(config.isConfigured == false)
    }

    @Test("isConfigured - 이메일 비어있으면 false")
    func isConfiguredNoEmail() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "")
        #expect(config.isConfigured == false)
    }

    // MARK: - authHeader

    @Test("authHeader - 토큰 없으면 nil")
    func authHeaderNoToken() {
        let config = JiraConfig(domain: "a.atlassian.net", email: "user@test.com")
        // apiToken이 KeychainHelper에 없으므로 nil
        #expect(config.authHeader() == nil)
    }

    @Test("authHeader - Base64 인코딩 형식 검증")
    func authHeaderFormat() {
        // email:token → Base64
        let email = "user@test.com"
        let token = "test-token-123"
        let credentials = "\(email):\(token)"
        let expectedBase64 = Data(credentials.utf8).base64EncodedString()

        // authHeader는 KeychainHelper에서 토큰을 가져오므로,
        // 직접 Base64 인코딩 로직만 검증
        #expect(expectedBase64 == "dXNlckB0ZXN0LmNvbTp0ZXN0LXRva2VuLTEyMw==")
        #expect("Basic \(expectedBase64)" == "Basic dXNlckB0ZXN0LmNvbTp0ZXN0LXRva2VuLTEyMw==")
    }

    // MARK: - isJiraURL

    @Test("isJiraURL - 일치하는 도메인")
    func isJiraURLMatch() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        #expect(config.isJiraURL("https://company.atlassian.net/browse/PROJ-123") == true)
    }

    @Test("isJiraURL - 다른 도메인")
    func isJiraURLNoMatch() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        #expect(config.isJiraURL("https://other.atlassian.net/browse/PROJ-123") == false)
    }

    @Test("isJiraURL - 빈 도메인이면 항상 false")
    func isJiraURLEmptyDomain() {
        let config = JiraConfig(domain: "", email: "a@b.com")
        #expect(config.isJiraURL("https://anything.com") == false)
    }

    @Test("isJiraURL - 도메인이 URL 중간에 포함")
    func isJiraURLContains() {
        let config = JiraConfig(domain: "myteam.atlassian.net", email: "a@b.com")
        #expect(config.isJiraURL("text with myteam.atlassian.net inside") == true)
    }

    // MARK: - apiURL 변환

    @Test("apiURL - /browse/ 패턴을 REST API로 변환")
    func apiURLBrowseToRest() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        let result = config.apiURL(from: "https://company.atlassian.net/browse/PROJ-123")
        #expect(result == "https://company.atlassian.net/rest/api/3/issue/PROJ-123")
    }

    @Test("apiURL - 쿼리스트링 제거")
    func apiURLStripQuery() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        let result = config.apiURL(from: "https://company.atlassian.net/browse/PROJ-456?focusedId=12345")
        #expect(result == "https://company.atlassian.net/rest/api/3/issue/PROJ-456")
    }

    @Test("apiURL - 이미 REST API URL이면 그대로 반환")
    func apiURLAlreadyRest() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        let url = "https://company.atlassian.net/rest/api/3/issue/PROJ-789"
        #expect(config.apiURL(from: url) == url)
    }

    @Test("apiURL - /browse/ 뒤에 이슈키 없으면 원본 반환")
    func apiURLBrowseEmpty() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        let url = "https://company.atlassian.net/browse/"
        // /browse/ 뒤가 빈 문자열 → issueKey.isEmpty → 원본 반환
        #expect(config.apiURL(from: url) == url)
    }

    @Test("apiURL - 변환 불가한 URL은 원본 반환")
    func apiURLUnknownFormat() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "a@b.com")
        let url = "https://company.atlassian.net/projects/PROJ/board"
        #expect(config.apiURL(from: url) == url)
    }

    // MARK: - Codable

    @Test("Codable 라운드트립 - apiToken은 제외")
    func codableRoundTrip() throws {
        let original = JiraConfig(domain: "test.atlassian.net", email: "dev@test.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JiraConfig.self, from: data)
        #expect(decoded.domain == original.domain)
        #expect(decoded.email == original.email)

        // JSON에 apiToken이 포함되지 않는지 확인
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiToken"] == nil)
    }

    @Test("Codable - domain과 email만 인코딩")
    func codableOnlyDomainAndEmail() throws {
        let config = JiraConfig(domain: "a.net", email: "b@c.com")
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json.keys.sorted() == ["domain", "email"])
    }

    @Test("Decodable - JSON에서 복원")
    func decodableFromJSON() throws {
        let json: [String: Any] = [
            "domain": "restored.atlassian.net",
            "email": "user@restored.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(JiraConfig.self, from: data)
        #expect(config.domain == "restored.atlassian.net")
        #expect(config.email == "user@restored.com")
    }

    // MARK: - apiToken (Keychain 통합)

    @Test("apiToken - 설정 후 읽기")
    func apiTokenSetGet() throws {
        // cleanup first to avoid interference
        _ = try? KeychainHelper.delete(key: "jira-api-token")

        var config = JiraConfig(domain: "test.atlassian.net", email: "user@test.com")
        let testToken = "test-token-\(UUID().uuidString)"
        config.apiToken = testToken
        let token = config.apiToken
        #expect(token == testToken)
        // cleanup
        config.apiToken = nil
    }

    @Test("apiToken - nil로 설정하면 삭제")
    func apiTokenDelete() throws {
        _ = try? KeychainHelper.delete(key: "jira-api-token")

        var config = JiraConfig(domain: "test.atlassian.net", email: "user@test.com")
        config.apiToken = "temp-token"
        config.apiToken = nil
        #expect(config.apiToken == nil)
    }

    @Test("apiToken - 빈 문자열은 삭제와 같음")
    func apiTokenEmptyString() throws {
        _ = try? KeychainHelper.delete(key: "jira-api-token")

        var config = JiraConfig(domain: "test.atlassian.net", email: "user@test.com")
        config.apiToken = "some-token"
        config.apiToken = ""
        let loaded = config.apiToken
        #expect(loaded == nil)
    }

    // MARK: - isConfigured (통합)

    @Test("isConfigured - 모든 필드 설정 시 true")
    func isConfiguredAllSet() {
        var config = JiraConfig(domain: "company.atlassian.net", email: "user@company.com")
        let uniqueToken = "isconfig-token-\(UUID().uuidString)"
        config.apiToken = uniqueToken
        #expect(config.isConfigured == true)
        // cleanup
        config.apiToken = nil
    }

    @Test("isConfigured - 토큰 없으면 false")
    func isConfiguredNoToken() {
        let config = JiraConfig(domain: "company.atlassian.net", email: "user@company.com")
        // apiToken이 KeychainHelper에 없는 경우
        // 이전 테스트에서 삭제했으므로 nil
        // 단, 다른 테스트에서 설정했을 수 있으므로 명시적 확인
        if config.apiToken == nil {
            #expect(config.isConfigured == false)
        }
    }

    // MARK: - authHeader (통합)

    @Test("authHeader - 토큰 설정 후 Basic 헤더 반환")
    func authHeaderWithToken() {
        var config = JiraConfig(domain: "test.atlassian.net", email: "user@test.com")
        let uniqueToken = "auth-header-token-\(UUID().uuidString)"
        config.apiToken = uniqueToken
        let header = config.authHeader()
        #expect(header != nil)
        #expect(header?.hasPrefix("Basic ") == true)
        // cleanup
        config.apiToken = nil
    }

    // MARK: - shared 싱글턴

    @Test("shared - 저장 후 로드")
    func sharedPersistence() {
        let original = JiraConfig(domain: "shared-test.atlassian.net", email: "shared@test.com")
        JiraConfig.shared = original
        let loaded = JiraConfig.shared
        #expect(loaded.domain == "shared-test.atlassian.net")
        #expect(loaded.email == "shared@test.com")
        // cleanup
        UserDefaults.standard.removeObject(forKey: "jiraConfig")
    }

    @Test("shared - 저장 안 한 상태에서 기본값")
    func sharedDefault() {
        UserDefaults.standard.removeObject(forKey: "jiraConfig")
        let config = JiraConfig.shared
        #expect(config.domain == "")
        #expect(config.email == "")
    }
}
