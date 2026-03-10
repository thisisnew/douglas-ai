import Foundation

/// executeStep의 context 크기를 관리하는 유틸리티
/// 산출물 + history가 토큰 예산을 초과하면 단계적으로 축소
enum StepContextBudget {
    /// 전체 context 예산 (보수적: ~25K 토큰, 모든 모델 호환)
    static let budget = 100_000

    struct Result {
        let artifactContext: String
        let shouldTrimHistory: Bool
    }

    /// 산출물 context를 예산에 맞게 조정
    /// - Parameters:
    ///   - artifacts: 토론 산출물 배열
    ///   - systemPromptSize: 시스템 프롬프트 문자 수
    ///   - historySize: history 메시지 총 문자 수
    /// - Returns: 조정된 산출물 context + history 축소 필요 여부
    static func apply(
        artifacts: [DiscussionArtifact],
        systemPromptSize: Int,
        historySize: Int
    ) -> Result {
        // 전체 산출물 context
        var artifactContext = ""
        if !artifacts.isEmpty {
            artifactContext = "\n\n[참고 산출물]\n" + artifacts.map {
                "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\($0.content)"
            }.joined(separator: "\n---\n")
        }

        let totalEstimate = systemPromptSize + historySize + artifactContext.count + 1000
        guard totalEstimate > budget else {
            return Result(artifactContext: artifactContext, shouldTrimHistory: false)
        }

        // Level 1: 산출물 → 요약 모드 (제목 + 첫 200자)
        if !artifacts.isEmpty {
            artifactContext = "\n\n[참고 산출물 요약]\n" + artifacts.map {
                let preview = $0.content.count > 200
                    ? String($0.content.prefix(200)) + "…"
                    : $0.content
                return "[\($0.type.displayName)] \($0.title) (v\($0.version)):\n\(preview)"
            }.joined(separator: "\n---\n")
        }

        let reducedEstimate = systemPromptSize + historySize + artifactContext.count + 1000
        let shouldTrimHistory = reducedEstimate > budget

        if totalEstimate > budget {
            print("[DOUGLAS] ⚠️ executeStep 토큰 예산 초과 — context 축소 (total=\(totalEstimate), budget=\(budget))")
        }

        return Result(artifactContext: artifactContext, shouldTrimHistory: shouldTrimHistory)
    }
}
