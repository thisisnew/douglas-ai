import Testing
import Foundation
@testable import DOUGLAS

@Suite("ArtifactParser Tests")
struct ArtifactParserTests {

    // MARK: - extractArtifacts

    @Test("기본 산출물 추출")
    func extractBasicArtifact() {
        let content = """
        여기 API 명세입니다.

        ```artifact:api_spec title="사용자 인증 API"
        ## POST /api/auth/login
        Request: { email, password }
        Response: { token, user }
        ```

        이렇게 하면 될 것 같아요.
        """
        let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "백엔드")
        #expect(artifacts.count == 1)
        #expect(artifacts[0].type == .apiSpec)
        #expect(artifacts[0].title == "사용자 인증 API")
        #expect(artifacts[0].content.contains("POST /api/auth/login"))
        #expect(artifacts[0].producedBy == "백엔드")
        #expect(artifacts[0].version == 1)
    }

    @Test("다중 산출물 추출")
    func extractMultipleArtifacts() {
        let content = """
        ```artifact:api_spec title="인증 API"
        POST /login
        ```

        그리고 테스트 계획도 만들었습니다.

        ```artifact:test_plan title="인증 테스트"
        1. 정상 로그인 테스트
        2. 잘못된 비밀번호 테스트
        ```
        """
        let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "QA")
        #expect(artifacts.count == 2)
        #expect(artifacts[0].type == .apiSpec)
        #expect(artifacts[1].type == .testPlan)
    }

    @Test("title 없는 산출물 - type이 title로 사용됨")
    func extractArtifactWithoutTitle() {
        let content = """
        ```artifact:task_breakdown
        1단계: 설계
        2단계: 구현
        ```
        """
        let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "분석가")
        #expect(artifacts.count == 1)
        #expect(artifacts[0].type == .taskBreakdown)
        #expect(artifacts[0].title == "task_breakdown")
    }

    @Test("알 수 없는 type → generic")
    func extractUnknownType() {
        let content = """
        ```artifact:unknown_type title="기타"
        내용
        ```
        """
        let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "에이전트")
        #expect(artifacts.count == 1)
        #expect(artifacts[0].type == .generic)
    }

    @Test("산출물 없는 메시지 → 빈 배열")
    func extractNoArtifacts() {
        let content = "일반적인 토론 메시지입니다. 코드 블록도 없고 산출물도 없어요."
        let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "에이전트")
        #expect(artifacts.isEmpty)
    }

    @Test("일반 코드 블록은 무시")
    func ignoreRegularCodeBlocks() {
        let content = """
        ```swift
        let x = 1
        ```

        ```json
        {"key": "value"}
        ```
        """
        let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "에이전트")
        #expect(artifacts.isEmpty)
    }

    @Test("모든 ArtifactType 파싱")
    func extractAllTypes() {
        let types: [(String, ArtifactType)] = [
            ("api_spec", .apiSpec),
            ("test_plan", .testPlan),
            ("task_breakdown", .taskBreakdown),
            ("architecture_decision", .architectureDecision),
            ("generic", .generic)
        ]
        for (typeStr, expectedType) in types {
            let content = """
            ```artifact:\(typeStr) title="테스트"
            내용
            ```
            """
            let artifacts = ArtifactParser.extractArtifacts(from: content, producedBy: "에이전트")
            #expect(artifacts.count == 1, "Failed for type: \(typeStr)")
            #expect(artifacts[0].type == expectedType, "Type mismatch for: \(typeStr)")
        }
    }

    // MARK: - stripArtifactBlocks

    @Test("산출물 블록 제거 후 나머지 텍스트 반환")
    func stripBasic() {
        let content = """
        여기 설명입니다.

        ```artifact:api_spec title="API"
        POST /login
        ```

        계속 대화하겠습니다.
        """
        let stripped = ArtifactParser.stripArtifactBlocks(from: content)
        #expect(stripped.contains("여기 설명입니다."))
        #expect(stripped.contains("계속 대화하겠습니다."))
        #expect(!stripped.contains("artifact:api_spec"))
        #expect(!stripped.contains("POST /login"))
    }

    @Test("산출물 없는 메시지 → 그대로 반환")
    func stripNoArtifacts() {
        let content = "일반 메시지"
        let stripped = ArtifactParser.stripArtifactBlocks(from: content)
        #expect(stripped == "일반 메시지")
    }

    @Test("다중 산출물 모두 제거")
    func stripMultiple() {
        let content = """
        시작

        ```artifact:api_spec title="A"
        내용A
        ```

        중간

        ```artifact:test_plan title="B"
        내용B
        ```

        끝
        """
        let stripped = ArtifactParser.stripArtifactBlocks(from: content)
        #expect(stripped.contains("시작"))
        #expect(stripped.contains("중간"))
        #expect(stripped.contains("끝"))
        #expect(!stripped.contains("내용A"))
        #expect(!stripped.contains("내용B"))
    }

    // MARK: - DiscussionArtifact

    @Test("DiscussionArtifact Codable 라운드트립")
    func artifactCodable() throws {
        let artifact = DiscussionArtifact(
            type: .apiSpec,
            title: "인증 API",
            content: "POST /login",
            producedBy: "백엔드",
            version: 2
        )
        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(DiscussionArtifact.self, from: data)
        #expect(decoded.type == .apiSpec)
        #expect(decoded.title == "인증 API")
        #expect(decoded.content == "POST /login")
        #expect(decoded.producedBy == "백엔드")
        #expect(decoded.version == 2)
    }

    @Test("ArtifactType displayName")
    func artifactTypeDisplayNames() {
        #expect(ArtifactType.apiSpec.displayName == "API 명세")
        #expect(ArtifactType.testPlan.displayName == "테스트 계획")
        #expect(ArtifactType.taskBreakdown.displayName == "작업 분해")
        #expect(ArtifactType.architectureDecision.displayName == "아키텍처 결정")
        #expect(ArtifactType.generic.displayName == "일반 산출물")
    }

    @Test("ArtifactType icon")
    func artifactTypeIcons() {
        for type in ArtifactType.allCases {
            #expect(!type.icon.isEmpty, "\(type) has empty icon")
        }
    }

    // MARK: - Room artifacts 호환

    @Test("Room - artifacts 기본값 빈 배열")
    func roomArtifactsDefault() {
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.discussion.artifacts.isEmpty)
    }

    @Test("Room - artifacts 레거시 JSON 호환")
    func roomArtifactsLegacy() throws {
        // artifacts 필드 없는 JSON
        let json = """
        {"id":"12345678-1234-1234-1234-123456789012","title":"테스트","assignedAgentIDs":[],"messages":[],"status":"planning","createdAt":0,"createdBy":{"user":{}},"currentStepIndex":0}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.discussion.artifacts.isEmpty)
    }
}
