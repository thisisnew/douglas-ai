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
        #expect(intake.jiraKey == nil)
        #expect(intake.jiraData == nil)
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
            jiraKey: "PROJ-456",
            jiraData: jira,
            urls: ["https://jira.example.com/browse/PROJ-456"]
        )
        #expect(intake.sourceType == .jira)
        #expect(intake.jiraKey == "PROJ-456")
        #expect(intake.jiraData?.summary == "API 리팩토링")
        #expect(intake.urls.count == 1)
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
            jiraKey: "TEST-1",
            jiraData: jira
        )
        let data = try JSONEncoder().encode(intake)
        let decoded = try JSONDecoder().decode(IntakeData.self, from: data)
        #expect(decoded.jiraKey == "TEST-1")
        #expect(decoded.jiraData?.summary == "테스트")
        #expect(decoded.jiraData?.status == "Done")
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
            jiraKey: "PROJ-1",
            jiraData: jira
        )
        let str = intake.asContextString()
        #expect(str.contains("소스: jira"))
        #expect(str.contains("Jira 키: PROJ-1"))
        #expect(str.contains("제목: 기능 추가"))
        #expect(str.contains("유형: Story"))
        #expect(str.contains("상태: To Do"))
        #expect(str.contains("설명:"))
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
            jiraKey: "X-1",
            jiraData: jira
        )
        let str = intake.asContextString()
        #expect(!str.contains("설명:"))
    }
}
