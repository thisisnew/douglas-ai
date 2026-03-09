import Testing
import Foundation
@testable import DOUGLAS

@Suite("Domain Enum Tests")
struct DomainEnumTests {

    // MARK: - ActionScope

    @Test("ActionScope - allCases count == 7")
    func actionScopeAllCasesCount() {
        #expect(ActionScope.allCases.count == 7)
    }

    @Test("ActionScope - 각 케이스 displayName 비어있지 않음")
    func actionScopeDisplayNameNonEmpty() {
        for scope in ActionScope.allCases {
            #expect(!scope.displayName.isEmpty, "displayName empty for \(scope)")
        }
    }

    @Test("ActionScope - 각 케이스 description 비어있지 않음")
    func actionScopeDescriptionNonEmpty() {
        for scope in ActionScope.allCases {
            #expect(!scope.description.isEmpty, "description empty for \(scope)")
        }
    }

    @Test("ActionScope - 특정 rawValue 검증")
    func actionScopeRawValues() {
        #expect(ActionScope.readFiles.rawValue == "readFiles")
        #expect(ActionScope.readWeb.rawValue == "readWeb")
        #expect(ActionScope.writeFiles.rawValue == "writeFiles")
        #expect(ActionScope.runCommands.rawValue == "runCommands")
        #expect(ActionScope.modifyExternal.rawValue == "modifyExternal")
        #expect(ActionScope.sendMessages.rawValue == "sendMessages")
        #expect(ActionScope.publish.rawValue == "publish")
    }

    @Test("ActionScope - rawValue Codable 왕복")
    func actionScopeCodableRoundtrip() throws {
        for scope in ActionScope.allCases {
            let data = try JSONEncoder().encode(scope)
            let decoded = try JSONDecoder().decode(ActionScope.self, from: data)
            #expect(decoded == scope)
        }
    }

    // MARK: - OutputType

    @Test("OutputType - 전체 7케이스 존재")
    func outputTypeAllCases() {
        let allCases: [OutputType] = [.code, .document, .message, .analysis, .data, .design, .answer]
        #expect(allCases.count == 7)
    }

    @Test("OutputType - 특정 rawValue 검증")
    func outputTypeRawValues() {
        #expect(OutputType.code.rawValue == "code")
        #expect(OutputType.document.rawValue == "document")
        #expect(OutputType.message.rawValue == "message")
        #expect(OutputType.analysis.rawValue == "analysis")
        #expect(OutputType.data.rawValue == "data")
        #expect(OutputType.design.rawValue == "design")
        #expect(OutputType.answer.rawValue == "answer")
    }

    @Test("OutputType - rawValue 왕복")
    func outputTypeRawValueRoundtrip() {
        for ot in [OutputType.code, .document, .message, .analysis, .data, .design, .answer] {
            let raw = ot.rawValue
            #expect(OutputType(rawValue: raw) == ot)
        }
    }

    @Test("OutputType - Codable 왕복")
    func outputTypeCodableRoundtrip() throws {
        for ot in [OutputType.code, .document, .message, .analysis, .data, .design, .answer] {
            let data = try JSONEncoder().encode(ot)
            let decoded = try JSONDecoder().decode(OutputType.self, from: data)
            #expect(decoded == ot)
        }
    }

    // MARK: - RuntimeRole

    @Test("RuntimeRole - displayName 매핑")
    func runtimeRoleDisplayNames() {
        #expect(RuntimeRole.creator.displayName == "작성자")
        #expect(RuntimeRole.reviewer.displayName == "검토자")
        #expect(RuntimeRole.planner.displayName == "설계자")
    }

    @Test("RuntimeRole - rawValue 왕복")
    func runtimeRoleRawValueRoundtrip() {
        for role in [RuntimeRole.creator, .reviewer, .planner] {
            let raw = role.rawValue
            #expect(RuntimeRole(rawValue: raw) == role)
        }
    }

    @Test("RuntimeRole - Codable 왕복")
    func runtimeRoleCodableRoundtrip() throws {
        for role in [RuntimeRole.creator, .reviewer, .planner] {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(RuntimeRole.self, from: data)
            #expect(decoded == role)
        }
    }

    // MARK: - RiskLevel

    @Test("RiskLevel - displayName 매핑")
    func riskLevelDisplayNames() {
        #expect(RiskLevel.low.displayName == "안전")
        #expect(RiskLevel.medium.displayName == "주의")
        #expect(RiskLevel.high.displayName == "위험")
    }

    // MARK: - RiskLevel (rawValue)

    @Test("RiskLevel - rawValue 왕복")
    func riskLevelRawValueRoundtrip() {
        for level in [RiskLevel.low, .medium, .high] {
            let raw = level.rawValue
            #expect(RiskLevel(rawValue: raw) == level)
        }
    }

    // MARK: - ArtifactType

    @Test("ArtifactType - allCases count == 10")
    func artifactTypeAllCasesCount() {
        #expect(ArtifactType.allCases.count == 10)
    }

    @Test("ArtifactType - 각 케이스 displayName 비어있지 않음")
    func artifactTypeDisplayNameNonEmpty() {
        for at in ArtifactType.allCases {
            #expect(!at.displayName.isEmpty, "displayName empty for \(at)")
        }
    }

    @Test("ArtifactType - 각 케이스 icon 비어있지 않음")
    func artifactTypeIconNonEmpty() {
        for at in ArtifactType.allCases {
            #expect(!at.icon.isEmpty, "icon empty for \(at)")
        }
    }

    @Test("ArtifactType - rawValue 문자열 형식 확인 (snake_case)")
    func artifactTypeRawValueFormat() {
        #expect(ArtifactType.apiSpec.rawValue == "api_spec")
        #expect(ArtifactType.testPlan.rawValue == "test_plan")
        #expect(ArtifactType.taskBreakdown.rawValue == "task_breakdown")
        #expect(ArtifactType.architectureDecision.rawValue == "architecture_decision")
        #expect(ArtifactType.assumptions.rawValue == "assumptions")
        #expect(ArtifactType.roleRequirements.rawValue == "role_requirements")
        #expect(ArtifactType.researchReport.rawValue == "research_report")
        #expect(ArtifactType.brainstormResult.rawValue == "brainstorm_result")
        #expect(ArtifactType.document.rawValue == "document")
        #expect(ArtifactType.generic.rawValue == "generic")
    }

    @Test("ArtifactType - Codable rawValue 왕복")
    func artifactTypeCodableRoundtrip() throws {
        for at in ArtifactType.allCases {
            let data = try JSONEncoder().encode(at)
            let decoded = try JSONDecoder().decode(ArtifactType.self, from: data)
            #expect(decoded == at)
        }
    }

    // MARK: - DiscussionArtifact

    @Test("DiscussionArtifact - init 기본 version == 1")
    func discussionArtifactDefaultVersion() {
        let artifact = DiscussionArtifact(
            type: .generic,
            title: "테스트",
            content: "내용",
            producedBy: "Agent"
        )
        #expect(artifact.version == 1)
    }

    @Test("DiscussionArtifact - Codable 왕복")
    func discussionArtifactCodableRoundtrip() throws {
        let artifact = DiscussionArtifact(
            type: .apiSpec,
            title: "API 설계",
            content: "# REST API\n- GET /users",
            producedBy: "백엔드 전문가",
            version: 3
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(artifact)
        let decoded = try decoder.decode(DiscussionArtifact.self, from: data)

        #expect(decoded.id == artifact.id)
        #expect(decoded.type == artifact.type)
        #expect(decoded.title == artifact.title)
        #expect(decoded.content == artifact.content)
        #expect(decoded.producedBy == artifact.producedBy)
        #expect(decoded.version == 3)
    }

    @Test("DiscussionArtifact - init 커스텀 version 유지")
    func discussionArtifactCustomVersion() {
        let artifact = DiscussionArtifact(
            type: .testPlan,
            title: "테스트",
            content: "내용",
            producedBy: "QA",
            version: 5
        )
        #expect(artifact.version == 5)
        #expect(artifact.type == .testPlan)
    }

    // MARK: - DeferredStatus

    @Test("DeferredStatus - 4케이스 rawValue 왕복")
    func deferredStatusRawValueRoundtrip() {
        let allCases: [DeferredAction.DeferredStatus] = [.pending, .approved, .executed, .cancelled]
        #expect(allCases.count == 4)
        for status in allCases {
            let raw = status.rawValue
            #expect(DeferredAction.DeferredStatus(rawValue: raw) == status)
        }
    }

    @Test("DeferredStatus - Codable 왕복")
    func deferredStatusCodableRoundtrip() throws {
        for status in [DeferredAction.DeferredStatus.pending, .approved, .executed, .cancelled] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(DeferredAction.DeferredStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    // MARK: - DeferredAction

    @Test("DeferredAction - init + 기본값")
    func deferredActionInit() {
        let action = DeferredAction(
            toolName: "shell_exec",
            arguments: ["command": .string("echo hello")],
            description: "테스트 명령 실행"
        )
        #expect(action.toolName == "shell_exec")
        #expect(action.riskLevel == .high)
        #expect(action.status == .pending)
        #expect(action.previewContent == nil)
    }

    @Test("DeferredAction - Codable 왕복")
    func deferredActionCodableRoundtrip() throws {
        let action = DeferredAction(
            toolName: "email_send",
            arguments: [
                "to": .string("user@example.com"),
                "subject": .string("제목"),
                "draft": .boolean(true)
            ],
            description: "이메일 전송",
            riskLevel: .high,
            previewContent: "미리보기 내용",
            status: .approved
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(DeferredAction.self, from: data)

        #expect(decoded.id == action.id)
        #expect(decoded.toolName == "email_send")
        #expect(decoded.arguments["to"] == .string("user@example.com"))
        #expect(decoded.arguments["draft"] == .boolean(true))
        #expect(decoded.description == "이메일 전송")
        #expect(decoded.riskLevel == .high)
        #expect(decoded.previewContent == "미리보기 내용")
        #expect(decoded.status == .approved)
    }

    // MARK: - TaskBrief

    @Test("TaskBrief - 기본값 확인")
    func taskBriefDefaults() {
        let brief = TaskBrief(goal: "테스트 목표")
        #expect(brief.overallRisk == .low)
        #expect(brief.outputType == .answer)
        #expect(brief.needsClarification == false)
        #expect(brief.questions.isEmpty)
        #expect(brief.constraints.isEmpty)
        #expect(brief.successCriteria.isEmpty)
        #expect(brief.nonGoals.isEmpty)
    }

    @Test("TaskBrief - 전체 데이터 Codable 왕복")
    func taskBriefFullCodableRoundtrip() throws {
        let brief = TaskBrief(
            goal: "납기 지연 사과 메일",
            constraints: ["격식체", "새 납기일: 3/20"],
            successCriteria: ["사과 표현 포함", "새 납기일 명시"],
            nonGoals: ["전체 공지 아님"],
            overallRisk: .high,
            outputType: .message,
            needsClarification: true,
            questions: ["수신자가 누구입니까?", "참조 대상이 있습니까?"]
        )
        let data = try JSONEncoder().encode(brief)
        let decoded = try JSONDecoder().decode(TaskBrief.self, from: data)

        #expect(decoded.goal == "납기 지연 사과 메일")
        #expect(decoded.constraints == ["격식체", "새 납기일: 3/20"])
        #expect(decoded.successCriteria == ["사과 표현 포함", "새 납기일 명시"])
        #expect(decoded.nonGoals == ["전체 공지 아님"])
        #expect(decoded.overallRisk == .high)
        #expect(decoded.outputType == .message)
        #expect(decoded.needsClarification == true)
        #expect(decoded.questions.count == 2)
    }

    @Test("TaskBrief - Equatable 비교")
    func taskBriefEquatable() {
        let a = TaskBrief(goal: "A", overallRisk: .low)
        let b = TaskBrief(goal: "A", overallRisk: .low)
        let c = TaskBrief(goal: "B", overallRisk: .high)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("TaskBrief - 레거시 디코딩: optional 필드 누락 시 기본값")
    func taskBriefLegacyDecode() throws {
        // goal만 있는 최소 JSON
        let json = """
        {"goal": "간단한 질문"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TaskBrief.self, from: json)
        #expect(decoded.goal == "간단한 질문")
        #expect(decoded.overallRisk == .low)
        #expect(decoded.outputType == .answer)
        #expect(decoded.needsClarification == false)
        #expect(decoded.questions.isEmpty)
        #expect(decoded.constraints.isEmpty)
        #expect(decoded.successCriteria.isEmpty)
        #expect(decoded.nonGoals.isEmpty)
    }
}
