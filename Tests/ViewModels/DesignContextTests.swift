import Testing
import Foundation
@testable import DOUGLAS

@Suite("Design 단계 컨텍스트 포함 Tests")
struct DesignContextTests {

    // MARK: - intakeData.asClarifyContextString에 Jira 데이터 포함

    @Test("intakeData — Jira 티켓 정보 포함")
    func intakeDataIncludesJiraInfo() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "https://example.atlassian.net/browse/PROJ-100",
            jiraKeys: ["PROJ-100"],
            jiraDataList: [
                JiraTicketSummary(
                    key: "PROJ-100",
                    summary: "로그인 화면 리뉴얼",
                    issueType: "Story",
                    status: "To Do",
                    description: "로그인 화면 UI를 Material Design 3 기반으로 변경"
                )
            ],
            urls: ["https://example.atlassian.net/browse/PROJ-100"]
        )

        let context = intake.asClarifyContextString()
        #expect(context.contains("PROJ-100"))
        #expect(context.contains("로그인 화면 리뉴얼"))
        #expect(context.contains("Story"))
        #expect(context.contains("To Do"))
    }

    @Test("intakeData — 여러 티켓 컨텍스트 포함")
    func intakeDataMultipleTickets() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "PROJ-100 PROJ-200",
            jiraKeys: ["PROJ-100", "PROJ-200"],
            jiraDataList: [
                JiraTicketSummary(key: "PROJ-100", summary: "첫 번째", issueType: "Story", status: "To Do", description: ""),
                JiraTicketSummary(key: "PROJ-200", summary: "두 번째", issueType: "Bug", status: "In Progress", description: "")
            ],
            urls: []
        )

        let context = intake.asClarifyContextString()
        #expect(context.contains("PROJ-100"))
        #expect(context.contains("PROJ-200"))
        #expect(context.contains("첫 번째"))
        #expect(context.contains("두 번째"))
    }

    @Test("intakeData — jiraKeys만 있고 데이터 없을 때 키 참조 표시")
    func intakeDataKeysWithoutData() {
        let intake = IntakeData(
            sourceType: .jira,
            rawInput: "https://example.atlassian.net/browse/PROJ-100",
            jiraKeys: ["PROJ-100"],
            jiraDataList: [],
            urls: ["https://example.atlassian.net/browse/PROJ-100"]
        )

        let context = intake.asClarifyContextString()
        #expect(context.contains("PROJ-100"))
        #expect(context.contains("조회에 실패"))
    }

    // MARK: - Room.effectiveProjectPaths

    @Test("effectiveProjectPaths — 프로젝트 경로 반환")
    func effectiveProjectPathsReturned() {
        var room = Room(
            title: "테스트",
            assignedAgentIDs: [],
            createdBy: .user,
            projectPaths: ["/Users/test/rms-front-mobile", "/Users/test/rms-front-web"]
        )
        let paths = room.effectiveProjectPaths
        #expect(paths.contains("/Users/test/rms-front-mobile"))
        #expect(paths.contains("/Users/test/rms-front-web"))
    }
}
