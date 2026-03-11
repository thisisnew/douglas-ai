import Foundation

/// executeStep의 context 크기를 관리하는 유틸리티
/// 산출물 + history가 토큰 예산을 초과하면 단계적으로 축소
enum StepContextBudget {
    /// 초기 context 토큰 예산 (도구 루프를 위한 여유 ~50K 확보)
    /// CJK 텍스트 비율에 따라 실제 토큰 수가 달라지므로 TokenEstimator 기반 추정
    static let tokenBudget = 30_000

    struct Result {
        let artifactContext: String
        let shouldTrimHistory: Bool
    }

    /// 산출물 context를 예산에 맞게 조정
    /// - Parameters:
    ///   - artifacts: 토론 산출물 배열
    ///   - systemPromptSize: 시스템 프롬프트 토큰 추정치
    ///   - historySize: history 메시지 총 토큰 추정치
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

        let artifactTokens = TokenEstimator.estimate(artifactContext)
        let totalEstimate = systemPromptSize + historySize + artifactTokens + 500
        guard totalEstimate > tokenBudget else {
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

        let reducedArtifactTokens = TokenEstimator.estimate(artifactContext)
        let reducedEstimate = systemPromptSize + historySize + reducedArtifactTokens + 500
        let shouldTrimHistory = reducedEstimate > tokenBudget

        if totalEstimate > tokenBudget {
            print("[DOUGLAS] ⚠️ executeStep 토큰 예산 초과 — context 축소 (total=\(totalEstimate), budget=\(tokenBudget))")
        }

        return Result(artifactContext: artifactContext, shouldTrimHistory: shouldTrimHistory)
    }
}
