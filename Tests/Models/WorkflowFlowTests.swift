import Testing
import Foundation
@testable import DOUGLAS

/// 9개 워크플로우 케이스의 플로우 규칙을 강제하는 테스트.
/// CLAUDE.md의 "워크플로우 플로우 (절대 규칙)"을 코드 레벨에서 보장한다.
@Suite("Workflow Flow Tests — 9 Cases")
struct WorkflowFlowTests {

    // =========================================================================
    // MARK: - Case 1: 단순 질의응답
    // 프롬프트 → quickAnswer 판단 → 방 생성 → 에이전트 매칭 확인 → 에이전트 응답 완료
    // =========================================================================

    @Test("Case 1: quickAnswer requiredPhases = understand → assemble → deliver")
    func case1Phases() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(phases == [.understand, .assemble, .deliver])
    }

    @Test("Case 1: quickAnswer는 design/build/review 없음")
    func case1NoBuildReview() {
        let phases = WorkflowIntent.quickAnswer.requiredPhases
        #expect(!phases.contains(.design))
        #expect(!phases.contains(.build))
        #expect(!phases.contains(.review))
        #expect(!phases.contains(.plan))
    }

    @Test("Case 1: quickAnswer는 토론 불필요")
    func case1NoDiscussion() {
        #expect(WorkflowIntent.quickAnswer.requiresDiscussion == false)
    }

    @Test("Case 1: 짧은 질문 → quickAnswer 분류")
    func case1Classification() {
        #expect(IntentClassifier.quickClassify("이게 뭐야") == .quickAnswer)
        #expect(IntentClassifier.quickClassify("JWT가 뭐야?") == .quickAnswer)
        #expect(IntentClassifier.quickClassify("알려줘") == .quickAnswer)
        #expect(IntentClassifier.quickClassify("뜻이 뭐야") == .quickAnswer)
    }

    // =========================================================================
    // MARK: - Case 2: 토론 1개 에이전트
    // 프롬프트 → discussion 판단 → 방 생성 → 에이전트 매칭 확인 → 에이전트 응답 완료
    // =========================================================================

    @Test("Case 2: discussion requiredPhases = understand → assemble → design → deliver")
    func case2Phases() {
        let phases = WorkflowIntent.discussion.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .deliver])
    }

    @Test("Case 2: discussion은 build/review 없음 (토론 자체가 산출물)")
    func case2NoBuildReview() {
        let phases = WorkflowIntent.discussion.requiredPhases
        #expect(!phases.contains(.build))
        #expect(!phases.contains(.review))
    }

    @Test("Case 2: 토론 키워드 → discussion 분류")
    func case2Classification() {
        #expect(IntentClassifier.quickClassify("브레인스토밍 해보자") == .discussion)
    }

    @Test("Case 2: discussion은 토론 필요")
    func case2RequiresDiscussion() {
        #expect(WorkflowIntent.discussion.requiresDiscussion == true)
    }

    // =========================================================================
    // MARK: - Case 3: 토론 복수 에이전트
    // 토론 → 라운드마다 사용자 의견 → 결론 도출 → 완료
    // =========================================================================

    @Test("Case 3: discussion은 plan 단계 없음 (에이전트 간 토론만)")
    func case3NoPlan() {
        let phases = WorkflowIntent.discussion.requiredPhases
        #expect(!phases.contains(.plan))
        #expect(!phases.contains(.build))
    }

    @Test("Case 3: discussion phase 순서 보장 (understand → assemble → design → deliver)")
    func case3PhaseOrder() {
        let phases = WorkflowIntent.discussion.requiredPhases
        #expect(phases.count == 4)
        // 순서 검증
        let understandIdx = phases.firstIndex(of: .understand)!
        let assembleIdx = phases.firstIndex(of: .assemble)!
        let designIdx = phases.firstIndex(of: .design)!
        let deliverIdx = phases.firstIndex(of: .deliver)!
        #expect(understandIdx < assembleIdx)
        #expect(assembleIdx < designIdx)
        #expect(designIdx < deliverIdx)
    }

    // =========================================================================
    // MARK: - Case 4: 구현 1개 에이전트
    // 구현 판단 → 에이전트 매칭 → 실행 계획 → 승인 → 자동 실행 → 완료
    // =========================================================================

    @Test("Case 4: task requiredPhases = understand → assemble → design → build → review → deliver")
    func case4Phases() {
        let phases = WorkflowIntent.task.requiredPhases
        #expect(phases == [.understand, .assemble, .design, .build, .review, .deliver])
    }

    @Test("Case 4: task phase 순서 보장")
    func case4PhaseOrder() {
        let phases = WorkflowIntent.task.requiredPhases
        let designIdx = phases.firstIndex(of: .design)!
        let buildIdx = phases.firstIndex(of: .build)!
        let reviewIdx = phases.firstIndex(of: .review)!
        let deliverIdx = phases.firstIndex(of: .deliver)!
        // design → build → review → deliver 순서 보장
        #expect(designIdx < buildIdx)
        #expect(buildIdx < reviewIdx)
        #expect(reviewIdx < deliverIdx)
    }

    @Test("Case 4: task는 토론 필요 (설계 토론 포함)")
    func case4RequiresDiscussion() {
        #expect(WorkflowIntent.task.requiresDiscussion == true)
    }

    @Test("Case 4: 구현 키워드 → task 분류")
    func case4Classification() {
        #expect(IntentClassifier.quickClassify("코딩해줘") == .task)
        #expect(IntentClassifier.quickClassify("로그인 기능 구현해줘") == .task)
        #expect(IntentClassifier.quickClassify("이 버그 수정해줘") == .task)
        #expect(IntentClassifier.quickClassify("이 코드 리팩토링해줘") == .task)
    }

    @Test("Case 4: high-risk 단계는 계획 승인 시 경고 표시")
    func case4HighRiskWarning() {
        let highStep = RoomStep(text: "배포", riskLevel: .high)
        let lowStep = RoomStep(text: "코드 작성", riskLevel: .low)
        let steps = [lowStep, highStep]
        let highRiskSteps = steps.filter { $0.riskLevel != .low }
        #expect(highRiskSteps.count == 1, "high-risk 단계가 1개 감지되어야 함")
        #expect(highRiskSteps[0].text == "배포")
    }

    // =========================================================================
    // MARK: - Case 5: 구현 복수 에이전트
    // 토론(라운드마다 사용자 의견) → 실행 계획 → 승인 → 자동 실행 → 완료
    // =========================================================================

    @Test("Case 5: task는 discussion과 같은 design phase 포함 (토론 후 계획)")
    func case5DesignIncluded() {
        let taskPhases = WorkflowIntent.task.requiredPhases
        let discPhases = WorkflowIntent.discussion.requiredPhases
        // 둘 다 design phase 포함
        #expect(taskPhases.contains(.design))
        #expect(discPhases.contains(.design))
        // task만 build/review 추가
        #expect(taskPhases.contains(.build))
        #expect(!discPhases.contains(.build))
    }

    // =========================================================================
    // MARK: - Case 6: 방 생성 (에이전트 매칭 없음)
    // =========================================================================

    @Test("Case 6: Room 기본 생성 시 intent nil (나중에 설정)")
    func case6RoomCreation() {
        let room = Room(title: "테스트", assignedAgentIDs: [UUID()], createdBy: .user)
        #expect(room.workflowState.intent == nil)
        #expect(room.status == .planning)
    }

    @Test("Case 6: 에이전트 사전 배정으로 생성 가능")
    func case6ManualAgents() {
        let agentIDs = [UUID(), UUID()]
        let room = Room(title: "직접 생성", assignedAgentIDs: agentIDs, createdBy: .user)
        #expect(room.assignedAgentIDs.count == 2)
    }

    // =========================================================================
    // MARK: - Case 7: 파일 생성
    // 7-1: 대화 후 "문서 만들어줘" → 문서 생성 → "완료" + 경로만
    // 7-2: 처음부터 "문서로 만들어줘" → 조사 후 문서 생성
    // =========================================================================

    @Test("Case 7: 문서 요청 감지")
    func case7DocumentDetection() {
        let result1 = DocumentRequestDetector.quickDetect("문서로 정리해줘")
        #expect(result1 != nil)
        #expect(result1?.isDocumentRequest == true)

        let result2 = DocumentRequestDetector.quickDetect("pdf로 저장해줘")
        #expect(result2 != nil)
        #expect(result2?.isDocumentRequest == true)

        let result3 = DocumentRequestDetector.quickDetect("보고서로 뽑아줘")
        #expect(result3 != nil)
        #expect(result3?.isDocumentRequest == true)
    }

    @Test("Case 7: 문서 요청은 documentation 또는 task로 분류 (quickAnswer 아님)")
    func case7IntentClassification() {
        #expect(IntentClassifier.quickClassify("문서 만들어줘") == .task)
        #expect(IntentClassifier.quickClassify("보고서로 정리해줘") == .documentation)
        #expect(IntentClassifier.quickClassify("기획서 작성해줘") == .documentation)
    }

    @Test("Case 7: 비문서 요청은 감지 안 됨")
    func case7NonDocumentNotDetected() {
        let result = DocumentRequestDetector.quickDetect("더 분석해줘")
        #expect(result == nil || result?.isDocumentRequest == false)
    }

    // =========================================================================
    // MARK: - Case 8: 후속 처리
    // 완료 후 후속 프롬프트 → intent 재분류 → 해당 플로우 수행
    // =========================================================================

    @Test("Case 8: 완료된 방에서 후속 메시지 가능 (completed → planning 전이)")
    func case8FollowUpTransition() {
        #expect(RoomStatus.completed.canTransition(to: .planning) == true)
        #expect(RoomStatus.completed.canTransition(to: .inProgress) == true)
    }

    @Test("Case 8: 실패한 방도 재활성화 가능")
    func case8FailedReactivation() {
        #expect(RoomStatus.failed.canTransition(to: .planning) == true)
        #expect(RoomStatus.failed.canTransition(to: .inProgress) == true)
    }

    @Test("Case 8: 후속 intent 분류 — 구현 키워드")
    func case8FollowUpTaskClassification() {
        #expect(IntentClassifier.quickClassify("이거 수정해줘") == .task)
        #expect(IntentClassifier.quickClassify("리팩토링해줘") == .task)
    }

    @Test("Case 8: 후속 intent 분류 — 질의 키워드")
    func case8FollowUpQuickAnswer() {
        #expect(IntentClassifier.quickClassify("이게 뭐야") == .quickAnswer)
    }

    @Test("Case 8: 후속 intent 분류 — 토론 키워드")
    func case8FollowUpDiscussion() {
        #expect(IntentClassifier.quickClassify("브레인스토밍 해보자") == .discussion)
    }

    // =========================================================================
    // MARK: - Case 9: 요건 불명확
    // URL만, 이미지만, 파일만 → DOUGLAS가 재차 질문
    // =========================================================================

    @Test("Case 9: URL만 입력 → hasExplicitUserIntent false")
    func case9UrlOnlyNoIntent() {
        #expect(IntentClassifier.hasExplicitUserIntent("https://team.atlassian.net/browse/PROJ-123") == false)
    }

    @Test("Case 9: URL + 짧은 지시 → hasExplicitUserIntent true")
    func case9UrlWithIntent() {
        #expect(IntentClassifier.hasExplicitUserIntent("https://team.atlassian.net/browse/PROJ-123 코드리뷰 해줘") == true)
    }

    @Test("Case 9: 빈 문자열 → hasExplicitUserIntent false")
    func case9EmptyNoIntent() {
        #expect(IntentClassifier.hasExplicitUserIntent("") == false)
    }

    @Test("Case 9: URL만 → quickClassify nil (LLM 폴백 필요)")
    func case9UrlOnlyNilClassification() {
        #expect(IntentClassifier.quickClassify("https://team.atlassian.net/browse/PROJ-123") == nil)
    }

    @Test("Case 9: Jira URL + 작업 텍스트 → task로 분류")
    func case9UrlWithTaskText() {
        let input = "https://company.atlassian.net/browse/IBS-100 이거 개발해줘"
        let result = IntentClassifier.quickClassify(input)
        #expect(result == .task)
    }

    @Test("Case 9: preRoute — 빈 텍스트 + 파일 없음 → empty")
    func case9PreRouteEmpty() {
        #expect(IntentClassifier.preRoute("", hasAttachments: false) == .empty)
    }

    @Test("Case 9: preRoute — 빈 텍스트 + 파일 있음 → fileOnly")
    func case9PreRouteFileOnly() {
        #expect(IntentClassifier.preRoute("", hasAttachments: true) == .fileOnly)
        #expect(IntentClassifier.preRoute("  ", hasAttachments: true) == .fileOnly)
    }

    // =========================================================================
    // MARK: - 교차 검증: Phase 불변성
    // =========================================================================

    @Test("Phase 불변성: 각 intent의 phase 수가 변하지 않음")
    func phaseInvariants() {
        #expect(WorkflowIntent.quickAnswer.requiredPhases.count == 3)
        #expect(WorkflowIntent.task.requiredPhases.count == 6)
        #expect(WorkflowIntent.discussion.requiredPhases.count == 4)
    }

    @Test("Phase 불변성: 모든 intent는 understand로 시작")
    func allStartWithUnderstand() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.requiredPhases.first == .understand,
                    "\(intent) should start with .understand")
        }
    }

    @Test("Phase 불변성: 모든 intent는 deliver로 끝남")
    func allEndWithDeliver() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.requiredPhases.last == .deliver,
                    "\(intent) should end with .deliver")
        }
    }

    @Test("Phase 불변성: 모든 intent는 assemble 포함")
    func allIncludeAssemble() {
        for intent in WorkflowIntent.allCases {
            #expect(intent.requiredPhases.contains(.assemble),
                    "\(intent) should include .assemble")
        }
    }

    @Test("Phase 불변성: build 있으면 review도 반드시 있음 (documentation 제외)")
    func buildImpliesReview() {
        for intent in WorkflowIntent.allCases {
            // documentation은 문서 전문가가 직접 최종화 — review 불필요 (WORKFLOW_SPEC §12.6)
            if intent == .documentation { continue }
            let phases = intent.requiredPhases
            if phases.contains(.build) {
                #expect(phases.contains(.review),
                        "\(intent) has .build but missing .review")
            }
        }
    }

    @Test("Phase 불변성: review 있으면 build도 반드시 있음")
    func reviewImpliesBuild() {
        for intent in WorkflowIntent.allCases {
            let phases = intent.requiredPhases
            if phases.contains(.review) {
                #expect(phases.contains(.build),
                        "\(intent) has .review but missing .build")
            }
        }
    }

    @Test("Phase 불변성: design 있으면 assemble 전에 올 수 없음")
    func designAfterAssemble() {
        for intent in WorkflowIntent.allCases {
            let phases = intent.requiredPhases
            if let designIdx = phases.firstIndex(of: .design),
               let assembleIdx = phases.firstIndex(of: .assemble) {
                #expect(assembleIdx < designIdx,
                        "\(intent): assemble must come before design")
            }
        }
    }

    // =========================================================================
    // MARK: - Room 상태 머신 안전성
    // =========================================================================

    @Test("Room 상태: planning → failed 전이 허용 (awaitPlanApproval 실패 시)")
    func roomPlanningToFailed() {
        #expect(RoomStatus.planning.canTransition(to: .failed) == true)
    }

    @Test("Room 상태: failed는 isActive가 아님 (phase loop 탈출)")
    func roomFailedNotActive() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .failed)
        #expect(room.isActive == false)
    }

    @Test("Room 상태: planning은 isActive (승인 대기 중에도 활성)")
    func roomPlanningIsActive() {
        let room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .planning)
        #expect(room.isActive == true)
    }

    @Test("Room 상태: awaitingApproval은 isActive")
    func roomAwaitingApprovalIsActive() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user, status: .inProgress)
        room.status = .awaitingApproval
        #expect(room.isActive == true)
    }

    @Test("Room 상태: awaitingUserInput은 isActive")
    func roomAwaitingUserInputIsActive() {
        var room = Room(title: "Test", assignedAgentIDs: [], createdBy: .user)
        room.status = .awaitingUserInput
        #expect(room.isActive == true)
    }

    @Test("Room 상태: awaitingApproval → planning 전이 허용 (거부 시)")
    func roomApprovalToPlanning() {
        #expect(RoomStatus.awaitingApproval.canTransition(to: .planning) == true)
    }

    // =========================================================================
    // MARK: - RoomStep / RiskLevel 검증
    // =========================================================================

    @Test("RoomStep 기본 riskLevel은 low")
    func roomStepDefaultRiskLevel() {
        let step = RoomStep(text: "코드 분석")
        #expect(step.riskLevel == .low)
        #expect(step.requiresApproval == false)
    }

    @Test("RoomStep Codable — plain String 하위 호환")
    func roomStepPlainStringDecoding() throws {
        let json = "\"코드 분석\"".data(using: .utf8)!
        let step = try JSONDecoder().decode(RoomStep.self, from: json)
        #expect(step.text == "코드 분석")
        #expect(step.riskLevel == .low)
        #expect(step.requiresApproval == false)
    }

    @Test("RoomStep Codable — object 형태")
    func roomStepObjectDecoding() throws {
        let json = """
        {"text": "배포", "requires_approval": true, "risk_level": "high"}
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(RoomStep.self, from: json)
        #expect(step.text == "배포")
        #expect(step.riskLevel == .high)
        #expect(step.requiresApproval == true)
    }

    @Test("RiskLevel 3종 존재")
    func riskLevelAllCases() {
        #expect(RiskLevel.low.rawValue == "low")
        #expect(RiskLevel.medium.rawValue == "medium")
        #expect(RiskLevel.high.rawValue == "high")
    }
}
