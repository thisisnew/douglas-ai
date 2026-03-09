import Testing
import Foundation
@testable import DOUGLAS

@Suite("StepPromptBuilder Tests")
struct StepPromptBuilderTests {

    // MARK: - Issue 1: 사용자 추가 지시 주입

    @Test("사용자 추가 지시가 있으면 stepPrompt 끝에 주입된다")
    func injectUserDirective() {
        let base = "[작업 1/3] Repository 수정"
        let fullTask = "전체 작업\n\n[사용자 추가 지시]\nfindTargetPurchaseOrderItemIds를 쓰면돼"
        let result = StepPromptBuilder.injectDirective(into: base, from: fullTask)
        #expect(result.contains("[사용자 추가 지시 — 반드시 최우선으로 반영하세요]"))
        #expect(result.contains("findTargetPurchaseOrderItemIds를 쓰면돼"))
    }

    @Test("사용자 추가 지시가 없으면 stepPrompt 그대로 반환")
    func noDirective() {
        let base = "[작업 1/3] Repository 수정"
        let fullTask = "전체 작업 내용"
        let result = StepPromptBuilder.injectDirective(into: base, from: fullTask)
        #expect(result == base)
    }

    @Test("사용자 추가 지시 마커만 있고 내용이 비면 그대로 반환")
    func emptyDirective() {
        let base = "[작업 1/3] Repository 수정"
        let fullTask = "전체 작업\n\n[사용자 추가 지시]\n   "
        let result = StepPromptBuilder.injectDirective(into: base, from: fullTask)
        #expect(result == base)
    }

    @Test("여러 줄 사용자 지시도 정상 주입")
    func multiLineDirective() {
        let base = "[작업 1/3] 수정"
        let fullTask = "작업\n\n[사용자 추가 지시]\n첫 번째 지시\n두 번째 지시"
        let result = StepPromptBuilder.injectDirective(into: base, from: fullTask)
        #expect(result.contains("첫 번째 지시"))
        #expect(result.contains("두 번째 지시"))
    }
}

@Suite("ToolActivityDetail context_info Tests")
struct ToolActivityDetailContextInfoTests {

    @Test("context_info displayName은 '작업 컨텍스트'")
    func contextInfoDisplayName() {
        let detail = ToolActivityDetail(
            toolName: "context_info",
            subject: "업무규칙 3건 · 도구 7종",
            contentPreview: nil,
            isError: false
        )
        #expect(detail.displayName == "작업 컨텍스트")
    }

    @Test("context_info 컨텍스트 요약 문자열 생성")
    func buildContextSummary() {
        let summary = StepPromptBuilder.buildContextSummary(
            ruleCount: 3,
            toolCount: 7,
            artifactCount: 2
        )
        #expect(summary == "업무규칙 3건 · 도구 7종 · 산출물 2건")
    }

    @Test("규칙 0건이면 생략")
    func noRules() {
        let summary = StepPromptBuilder.buildContextSummary(
            ruleCount: 0,
            toolCount: 5,
            artifactCount: 0
        )
        #expect(summary == "도구 5종")
        #expect(!summary.contains("업무규칙"))
        #expect(!summary.contains("산출물"))
    }

    @Test("산출물만 있을 때")
    func onlyArtifacts() {
        let summary = StepPromptBuilder.buildContextSummary(
            ruleCount: 0,
            toolCount: 3,
            artifactCount: 1
        )
        #expect(summary == "도구 3종 · 산출물 1건")
    }
}
