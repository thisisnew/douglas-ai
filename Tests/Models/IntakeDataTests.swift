import Testing
import Foundation
@testable import DOUGLAS

@Suite("IntakeData Tests")
struct IntakeDataTests {

    // MARK: - InputSourceType

    @Test("InputSourceType rawValue")
    func sourceTypeRawValues() {
        #expect(InputSourceType.jira.rawValue == "jira")
        #expect(InputSourceType.text.rawValue == "text")
        #expect(InputSourceType.url.rawValue == "url")
    }

    @Test("InputSourceType Codable 라운드트립")
    func sourceTypeCodable() throws {
        for type in [InputSourceType.jira, .text, .url] {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(InputSourceType.self, from: data)
            #expect(decoded == type)
        }
    }

    // MARK: - JiraTicketSummary

    @Test("JiraTicketSummary Codable 라운드트립")
    func jiraSummaryCodable() throws {
        let jira = JiraTicketSummary(
            key: "PROJ-123",
            summary: "로그인 버그 수정",
            issueType: "Bug",
            status: "In Progress",
            description: "로그인 시 간헐적 크래시"
        )
        let data = try JSONEncoder().encode(jira)
        let decoded = try JSONDecoder().decode(JiraTicketSummary.self, from: data)
        #expect(decoded.key == "PROJ-123")
        #expect(decoded.summary == "로그인 버그 수정")
        #expect(decoded.issueType == "Bug")
        #expect(decoded.status == "In Progress")
        #expect(decoded.description == "로그인 시 간헐적 크래시")
    }

    // MARK: - IntakeData 초기화

    @Test("IntakeData 기본 초기화 — text 소스")
    func intakeTextInit() {
        let intake = IntakeData(sourceType: .text, rawInput: "블로그 글 작성")
        #expect(intake.sourceType == .text)
        #expect(intake.rawInput == "블로그 글 작성")
        #expect(intake.jiraKeys.isEmpty)
        #expect(intake.jiraDataList.isEmpty)
        #expect(intake.urls.isEmpty)
    }

    @Test("IntakeData Jira 소스 초기화")
    func intakeJiraInit() {
        let jira = JiraTicketSummary(
            key: "PROJ-456",
            summary: "API 리팩토링",
            issueType: "Story",
            status: "To Do",
            description: "v2 API 마이그레이션"
        )
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "https://jira.example.com/browse/PROJ-456",
            jiraKeys: ["PROJ-456"],
            jiraDataList: [jira],
            urls: ["https://jira.example.com/browse/PROJ-456"]
        )
        #expect(intake.sourceType == .jira)
        #expect(intake.jiraKeys == ["PROJ-456"])
        #expect(intake.jiraDataList.first?.summary == "API 리팩토링")
        #expect(intake.urls.count == 1)
    }

    @Test("IntakeData 다중 Jira 키")
    func intakeMultipleJiraKeys() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "IBS-100 IBS-200 IBS-300",
            jiraKeys: ["IBS-100", "IBS-200", "IBS-300"]
        )
        #expect(intake.jiraKeys.count == 3)
        #expect(intake.jiraKeys[1] == "IBS-200")
    }

    @Test("IntakeData Codable 라운드트립")
    func intakeCodable() throws {
        let intake = IntakeData(
            sourceType: .url,
            rawInput: "https://example.com/spec",
            urls: ["https://example.com/spec", "https://example.com/api"]
        )
        let data = try JSONEncoder().encode(intake)
        let decoded = try JSONDecoder().decode(IntakeData.self, from: data)
        #expect(decoded.sourceType == .url)
        #expect(decoded.rawInput == "https://example.com/spec")
        #expect(decoded.urls.count == 2)
    }

    @Test("IntakeData Codable 라운드트립 — Jira 포함")
    func intakeCodableWithJira() throws {
        let jira = JiraTicketSummary(
            key: "TEST-1",
            summary: "테스트",
            issueType: "Task",
            status: "Done",
            description: "완료"
        )
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "TEST-1",
            jiraKeys: ["TEST-1"],
            jiraDataList: [jira]
        )
        let data = try JSONEncoder().encode(intake)
        let decoded = try JSONDecoder().decode(IntakeData.self, from: data)
        #expect(decoded.jiraKeys == ["TEST-1"])
        #expect(decoded.jiraDataList.first?.summary == "테스트")
        #expect(decoded.jiraDataList.first?.status == "Done")
    }

    @Test("IntakeData Codable 하위 호환 — 구버전 jiraKey/jiraData")
    func intakeCodableBackwardCompat() throws {
        // 구버전 JSON (jiraKey: String, jiraData: single object)
        let oldJSON = """
        {
            "sourceType": "jira",
            "rawInput": "PROJ-1",
            "jiraKey": "PROJ-1",
            "jiraData": {
                "key": "PROJ-1",
                "summary": "구버전",
                "issueType": "Bug",
                "status": "Open",
                "description": "테스트"
            },
            "urls": [],
            "parsedAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(IntakeData.self, from: oldJSON)
        #expect(decoded.jiraKeys == ["PROJ-1"])
        #expect(decoded.jiraDataList.count == 1)
        #expect(decoded.jiraDataList[0].summary == "구버전")
    }

    // MARK: - asContextString

    @Test("asContextString — text 소스")
    func contextStringText() {
        let intake = IntakeData(sourceType: .text, rawInput: "작업 내용")
        let str = intake.asContextString()
        #expect(str.contains("[입력 분석]"))
        #expect(str.contains("소스: text"))
        #expect(!str.contains("Jira"))
    }

    @Test("asContextString — Jira 소스")
    func contextStringJira() {
        let jira = JiraTicketSummary(
            key: "PROJ-1",
            summary: "기능 추가",
            issueType: "Story",
            status: "To Do",
            description: "상세 설명"
        )
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "PROJ-1",
            jiraKeys: ["PROJ-1"],
            jiraDataList: [jira]
        )
        let str = intake.asContextString()
        #expect(str.contains("소스: jira"))
        #expect(str.contains("Jira 티켓: PROJ-1"))
        #expect(str.contains("[PROJ-1] 기능 추가"))
        #expect(str.contains("Story"))
        #expect(str.contains("To Do"))
        #expect(str.contains("설명: 상세 설명"))
    }

    @Test("asContextString — 다중 Jira 키")
    func contextStringMultipleJira() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "test",
            jiraKeys: ["IBS-100", "IBS-200", "IBS-300"]
        )
        let str = intake.asContextString()
        #expect(str.contains("Jira 티켓: IBS-100, IBS-200, IBS-300"))
    }

    @Test("asContextString — URL 포함")
    func contextStringWithURLs() {
        let intake = IntakeData(
            sourceType: .url,
            rawInput: "spec",
            urls: ["https://a.com", "https://b.com"]
        )
        let str = intake.asContextString()
        #expect(str.contains("URL: https://a.com, https://b.com"))
    }

    // MARK: - Jira fetch 실패 시 메시지 정확성

    @Test("asContextString — Jira 키만 있고 데이터 없으면 web_fetch 언급하지 않음")
    func contextStringJiraNoData_noWebFetchMention() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "IBS-3279",
            jiraKeys: ["IBS-3279"]
        )
        let str = intake.asContextString()
        #expect(!str.contains("web_fetch"), "web_fetch 도구는 차단되어 있으므로 언급하면 안 됨")
        #expect(str.contains("IBS-3279"))
    }

    @Test("asClarifyContextString — Jira 키만 있고 데이터 없으면 자동 조회 약속하지 않음")
    func clarifyContextStringJiraNoData_noAutoFetchPromise() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "IBS-3279",
            jiraKeys: ["IBS-3279"]
        )
        let str = intake.asClarifyContextString()
        #expect(!str.contains("자동 조회"), "자동 조회 메커니즘이 없으므로 약속하면 안 됨")
        #expect(str.contains("IBS-3279"))
    }

    @Test("asContextString — Jira 데이터 있으면 정상 표시")
    func contextStringJiraWithData() {
        let jira = JiraTicketSummary(
            key: "IBS-3279", summary: "서명 조회 확장",
            issueType: "Story", status: "In Progress", description: "상세"
        )
        let intake = IntakeData(
            sourceType: .jira, rawInput: "IBS-3279",
            jiraKeys: ["IBS-3279"], jiraDataList: [jira]
        )
        let str = intake.asContextString()
        #expect(str.contains("[IBS-3279] 서명 조회 확장"))
        #expect(!str.contains("web_fetch"))
    }

    // MARK: - extractJiraKeys

    @Test("extractJiraKeys — 단일 키")
    func extractJiraKeys_singleKey() {
        let keys = IntakeURLExtractor.extractJiraKeys(from: "IBS-3110 구현")
        #expect(keys == ["IBS-3110"])
    }

    @Test("extractJiraKeys — 복수 키")
    func extractJiraKeys_multipleKeys() {
        let keys = IntakeURLExtractor.extractJiraKeys(from: "IBS-3110 IBS-3111 처리")
        #expect(keys == ["IBS-3110", "IBS-3111"])
    }

    @Test("extractJiraKeys — 키 없음")
    func extractJiraKeys_noKeys() {
        let keys = IntakeURLExtractor.extractJiraKeys(from: "구현하자")
        #expect(keys.isEmpty)
    }

    @Test("extractJiraKeys — 중복 키 제거")
    func extractJiraKeys_duplicateKeys() {
        let keys = IntakeURLExtractor.extractJiraKeys(from: "IBS-3110 봐줘 IBS-3110 처리")
        #expect(keys == ["IBS-3110"])
    }

    // MARK: - containsExternalReferences

    @Test("containsExternalReferences — URL 포함")
    func containsExternalReferences_withURL() {
        #expect(IntakeURLExtractor.containsExternalReferences(in: "https://jira.com/browse/IBS-3110 구현"))
    }

    @Test("containsExternalReferences — Jira 키 포함")
    func containsExternalReferences_withJiraKey() {
        #expect(IntakeURLExtractor.containsExternalReferences(in: "IBS-3110 구현"))
    }

    @Test("containsExternalReferences — 참조 없음")
    func containsExternalReferences_noReferences() {
        #expect(!IntakeURLExtractor.containsExternalReferences(in: "구현하자"))
    }

    @Test("containsExternalReferences — 한국어만")
    func containsExternalReferences_koreanOnly() {
        #expect(!IntakeURLExtractor.containsExternalReferences(in: "다른 방법으로 토론해보자"))
    }

    @Test("asContextString — Jira 설명 빈 문자열이면 미포함")
    func contextStringJiraEmptyDescription() {
        let jira = JiraTicketSummary(
            key: "X-1",
            summary: "제목",
            issueType: "Bug",
            status: "Open",
            description: ""
        )
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "X-1",
            jiraKeys: ["X-1"],
            jiraDataList: [jira]
        )
        let str = intake.asContextString()
        #expect(!str.contains("설명:"))
    }
}
