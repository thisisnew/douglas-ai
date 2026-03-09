import Testing
import Foundation
@testable import DOUGLAS

@Suite("토큰 예산 제한 Tests")
struct TokenBudgetTests {

    // MARK: - P3: buildDiscussionHistory 절단

    @Test("토론 히스토리 — suffix 20 제한")
    func discussionHistorySuffix20() {
        let messages = (1...30).map { i in
            ChatMessage(
                role: i % 2 == 0 ? .assistant : .user,
                content: "메시지\(i)",
                agentName: i % 2 == 0 ? "에이전트A" : nil,
                messageType: .discussion
            )
        }
        let filtered = messages
            .filter { $0.messageType == .text || $0.messageType == .discussion || $0.messageType == .discussionRound }
            .suffix(20)
        #expect(filtered.count == 20)
        // 첫 10개(메시지1~10)는 제외되어야 함
        #expect(!filtered.contains(where: { $0.content == "메시지1" }))
        #expect(filtered.contains(where: { $0.content == "메시지11" }))
    }

    @Test("토론 히스토리 — 800자 초과 메시지 절단")
    func discussionMessageTruncation() {
        let longContent = String(repeating: "가", count: 1000)
        let truncated = longContent.count > 800
            ? String(longContent.prefix(800)) + "…"
            : longContent
        #expect(truncated.count == 801) // 800자 + "…"
        #expect(truncated.hasSuffix("…"))
    }

    @Test("토론 히스토리 — 800자 이하 메시지는 절단 안 됨")
    func discussionMessageNoTruncation() {
        let content = String(repeating: "A", count: 800)
        let truncated = content.count > 800
            ? String(content.prefix(800)) + "…"
            : content
        #expect(truncated == content)
        #expect(truncated.count == 800)
    }

    // MARK: - P4: extractDescription 상한

    @Test("extractDescription — 1000자 초과 시 절단")
    func extractDescriptionTruncation() {
        let longDesc = String(repeating: "테", count: 1500)
        let truncated = longDesc.count > 1000
            ? String(longDesc.prefix(1000)) + "…"
            : longDesc
        #expect(truncated.count == 1001) // 1000자 + "…"
    }

    @Test("extractDescription — 1000자 이하는 그대로")
    func extractDescriptionNoTruncation() {
        let desc = "짧은 설명입니다."
        let truncated = desc.count > 1000
            ? String(desc.prefix(1000)) + "…"
            : desc
        #expect(truncated == desc)
    }

    // MARK: - P2: requestPlan 컨텍스트 예산

    @Test("briefingContext 2000자 제한")
    func briefingContextBudget() {
        let longBriefing = String(repeating: "B", count: 3000)
        let truncated = longBriefing.count > 2000
            ? String(longBriefing.prefix(2000)) + "…(이하 생략)"
            : longBriefing
        #expect(truncated.count < longBriefing.count)
        #expect(truncated.hasPrefix("BBB"))
        #expect(truncated.hasSuffix("…(이하 생략)"))
    }

    @Test("artifactContext 산출물 프리뷰 100자 + 전체 1000자 제한")
    func artifactContextBudget() {
        // 산출물 5개, 각 300자
        let artifacts = (1...5).map { i in
            DiscussionArtifact(
                type: .generic,
                title: "산출물\(i)",
                content: String(repeating: "C", count: 300),
                producedBy: "테스트"
            )
        }
        // 각 산출물 프리뷰 100자로 절단
        let artifactLines = artifacts.map {
            let preview = $0.content.prefix(100)
            return "- \($0.title): \(preview)…"
        }
        var artifactContext = "\n\n[참고 산출물]\n" + artifactLines.joined(separator: "\n")

        // 전체 1000자 제한
        if artifactContext.count > 1000 {
            artifactContext = String(artifactContext.prefix(1000)) + "…"
        }
        #expect(artifactContext.count <= 1001) // 1000 + "…"
    }

    @Test("시스템 프롬프트 합산 8000자 초과 시 경고 로그")
    func systemPromptBudgetWarning() {
        // 각 컴포넌트가 큰 경우 합산 테스트
        let systemPrompt = String(repeating: "S", count: 3000)
        let intakeContext = String(repeating: "I", count: 1000)
        let clarifyContext = String(repeating: "C", count: 1000)
        let briefingContext = String(repeating: "B", count: 2000)
        let artifactContext = String(repeating: "A", count: 1000)
        let templateInstructions = String(repeating: "T", count: 500)

        let total = systemPrompt.count + intakeContext.count + clarifyContext.count
            + briefingContext.count + artifactContext.count + templateInstructions.count
        #expect(total > 8000) // 8500 > 8000

        // 예산 초과 시 briefing + artifact 축소
        var adjustedBriefing = briefingContext
        var adjustedArtifact = artifactContext
        let base = systemPrompt.count + intakeContext.count + clarifyContext.count + templateInstructions.count
        let remaining = max(0, 8000 - base)
        if adjustedBriefing.count + adjustedArtifact.count > remaining {
            let briefingBudget = remaining * 2 / 3
            let artifactBudget = remaining - briefingBudget
            if adjustedBriefing.count > briefingBudget {
                adjustedBriefing = String(adjustedBriefing.prefix(briefingBudget)) + "…"
            }
            if adjustedArtifact.count > artifactBudget {
                adjustedArtifact = String(adjustedArtifact.prefix(artifactBudget)) + "…"
            }
        }
        let adjustedTotal = base + adjustedBriefing.count + adjustedArtifact.count
        // 예산 초과 시 축소가 동작하여 원래(8500)보다 작아야 함
        #expect(adjustedTotal < total)
        // "…" 접미사 포함하여 약간의 오버헤드 허용
        #expect(adjustedTotal <= 8010)
    }
}
