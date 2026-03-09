import Testing
@testable import DOUGLAS

@Suite("Intent Display Tests")
struct IntentDisplayTests {

    // MARK: - displayName (6 intents)

    @Test("displayName — 6개 intent 정확한 한국어 이름")
    func displayNameExactValues() {
        #expect(WorkflowIntent.quickAnswer.displayName == "질의응답")
        #expect(WorkflowIntent.task.displayName == "구현")
        #expect(WorkflowIntent.discussion.displayName == "토론")
        #expect(WorkflowIntent.research.displayName == "조사")
        #expect(WorkflowIntent.documentation.displayName == "문서화")
        #expect(WorkflowIntent.complex.displayName == "복합 요청")
    }

    // MARK: - iconName

    @Test("iconName — 각 intent에 고유 SF Symbol")
    func iconNameExactValues() {
        #expect(WorkflowIntent.quickAnswer.iconName == "bolt")
        #expect(WorkflowIntent.task.iconName == "hammer")
        #expect(WorkflowIntent.discussion.iconName == "bubble.left.and.bubble.right")
        #expect(WorkflowIntent.research.iconName == "magnifyingglass")
        #expect(WorkflowIntent.documentation.iconName == "doc.text")
        #expect(WorkflowIntent.complex.iconName == "square.stack.3d.up")
    }

    @Test("iconName — 전체 케이스 비어있지 않음")
    func iconNameNonEmpty() {
        for intent in WorkflowIntent.allCases {
            #expect(!intent.iconName.isEmpty, "\(intent) iconName이 비어있음")
        }
    }

    // MARK: - subtitle

    @Test("subtitle — 각 intent의 정확한 설명")
    func subtitleExactValues() {
        #expect(WorkflowIntent.quickAnswer.subtitle == "단순 질문에 바로 답변")
        #expect(WorkflowIntent.task.subtitle == "코드 작성·수정·빌드·배포")
        #expect(WorkflowIntent.discussion.subtitle == "전문가 의견 교환 및 관점 탐색")
        #expect(WorkflowIntent.research.subtitle == "자료 수집·검색·비교·정리")
        #expect(WorkflowIntent.documentation.subtitle == "기획서·보고서·제안서 등 문서 작성")
        #expect(WorkflowIntent.complex.subtitle == "여러 작업 모드 혼합 처리")
    }

    @Test("subtitle — 전체 케이스 한국어 포함")
    func subtitleContainsKorean() {
        for intent in WorkflowIntent.allCases {
            let sub = intent.subtitle
            #expect(!sub.isEmpty, "\(intent) subtitle이 비어있음")
            // 한국어 유니코드 범위 포함 여부 확인
            let hasKorean = sub.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
            #expect(hasKorean, "\(intent) subtitle에 한국어가 없음: \(sub)")
        }
    }

    // MARK: - requiresDiscussion

    @Test("requiresDiscussion — quickAnswer만 false")
    func requiresDiscussionValues() {
        #expect(WorkflowIntent.quickAnswer.requiresDiscussion == false)
        #expect(WorkflowIntent.task.requiresDiscussion == true)
        #expect(WorkflowIntent.discussion.requiresDiscussion == true)
        #expect(WorkflowIntent.research.requiresDiscussion == true)
        #expect(WorkflowIntent.documentation.requiresDiscussion == true)
        #expect(WorkflowIntent.complex.requiresDiscussion == true)
    }

    // MARK: - phaseDisplayName (context-specific overrides)

    @Test("phaseDisplayName — discussion 오버라이드")
    func phaseDisplayNameDiscussion() {
        #expect(WorkflowIntent.discussion.phaseDisplayName(.design) == "토론")
        #expect(WorkflowIntent.discussion.phaseDisplayName(.deliver) == "결론 도출")
    }

    @Test("phaseDisplayName — research 오버라이드")
    func phaseDisplayNameResearch() {
        #expect(WorkflowIntent.research.phaseDisplayName(.design) == "조사")
        #expect(WorkflowIntent.research.phaseDisplayName(.deliver) == "결과 정리")
    }

    @Test("phaseDisplayName — documentation 오버라이드")
    func phaseDisplayNameDocumentation() {
        #expect(WorkflowIntent.documentation.phaseDisplayName(.design) == "구조 설계")
        #expect(WorkflowIntent.documentation.phaseDisplayName(.build) == "문서 작성")
        #expect(WorkflowIntent.documentation.phaseDisplayName(.deliver) == "최종 정리")
    }

    @Test("phaseDisplayName — quickAnswer 오버라이드")
    func phaseDisplayNameQuickAnswer() {
        #expect(WorkflowIntent.quickAnswer.phaseDisplayName(.deliver) == "답변")
    }

    @Test("phaseDisplayName — task/complex는 기본 displayName 사용")
    func phaseDisplayNameDefaultFallback() {
        // task는 오버라이드 없음 → WorkflowPhase.displayName 그대로
        #expect(WorkflowIntent.task.phaseDisplayName(.design) == "설계")
        #expect(WorkflowIntent.task.phaseDisplayName(.build) == "구현")
        #expect(WorkflowIntent.task.phaseDisplayName(.deliver) == "전달")
        // complex도 동일
        #expect(WorkflowIntent.complex.phaseDisplayName(.design) == "설계")
        #expect(WorkflowIntent.complex.phaseDisplayName(.review) == "검토")
    }

    // MARK: - phaseSummary

    @Test("phaseSummary — quickAnswer: 요청 분석 → 전문가 배정 → 답변")
    func phaseSummaryQuickAnswer() {
        #expect(WorkflowIntent.quickAnswer.phaseSummary == "요청 분석 → 전문가 배정 → 답변")
    }

    @Test("phaseSummary — task: 풀 파이프라인")
    func phaseSummaryTask() {
        #expect(WorkflowIntent.task.phaseSummary == "요청 분석 → 전문가 배정 → 설계 → 구현 → 검토 → 전달")
    }

    @Test("phaseSummary — complex: task와 동일")
    func phaseSummaryComplex() {
        #expect(WorkflowIntent.complex.phaseSummary == "요청 분석 → 전문가 배정 → 설계 → 구현 → 검토 → 전달")
    }

    @Test("phaseSummary — discussion: 토론 + 결론 도출")
    func phaseSummaryDiscussion() {
        #expect(WorkflowIntent.discussion.phaseSummary == "요청 분석 → 전문가 배정 → 토론 → 결론 도출")
    }

    @Test("phaseSummary — research: 조사 + 결과 정리")
    func phaseSummaryResearch() {
        #expect(WorkflowIntent.research.phaseSummary == "요청 분석 → 전문가 배정 → 조사 → 결과 정리")
    }

    @Test("phaseSummary — documentation: 구조 설계 → 문서 작성 → 최종 정리")
    func phaseSummaryDocumentation() {
        #expect(WorkflowIntent.documentation.phaseSummary == "요청 분석 → 전문가 배정 → 구조 설계 → 문서 작성 → 최종 정리")
    }

    // MARK: - WorkflowPhase.displayName (11 cases)

    @Test("WorkflowPhase.displayName — 11개 전체 정확한 한국어 이름")
    func workflowPhaseDisplayNameExactValues() {
        #expect(WorkflowPhase.intake.displayName == "입력 분석")
        #expect(WorkflowPhase.intent.displayName == "목적 확인")
        #expect(WorkflowPhase.clarify.displayName == "요건 확인")
        #expect(WorkflowPhase.understand.displayName == "요청 분석")
        #expect(WorkflowPhase.assemble.displayName == "전문가 배정")
        #expect(WorkflowPhase.design.displayName == "설계")
        #expect(WorkflowPhase.build.displayName == "구현")
        #expect(WorkflowPhase.review.displayName == "검토")
        #expect(WorkflowPhase.deliver.displayName == "전달")
        #expect(WorkflowPhase.plan.displayName == "계획 수립")
        #expect(WorkflowPhase.execute.displayName == "실행")
    }
}
