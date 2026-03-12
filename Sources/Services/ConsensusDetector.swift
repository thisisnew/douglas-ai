import Foundation

/// 합의 감지 서비스 — DebateStrategy에 위임하여 모드별 엄격도 적용
/// RoomManager.detectConsensus에서 추출한 독립 서비스
struct ConsensusDetector {

    /// Strategy 기반 합의 감지 (신규)
    /// - Parameters:
    ///   - response: 에이전트 응답 텍스트
    ///   - strategy: 현재 토론의 DebateStrategy
    /// - Returns: 합의 여부
    static func detect(in response: String, strategy: DebateStrategy) -> Bool {
        strategy.isConsensus(response: response)
    }

    /// 레거시 호환 — debateMode 없을 때 기존 퍼지 매칭 (RoomManager.detectConsensus와 동일)
    static func detectLegacy(in response: String) -> Bool {
        // 1) 명시적 태그 — 가장 신뢰도 높음
        if response.contains("[합의") { return true }

        // 2) 명시적 반대/계속 태그 — 확실한 비합의
        if response.contains("[계속]") { return false }

        // 3) 퍼지: 합의 표현 vs 반대 표현 비교
        let lower = response.lowercased()
        let agreePhrases = [
            "동의합니다", "합의합니다", "찬성합니다",
            "이의 없습니다", "이의없습니다",
            "좋은 계획", "좋은 방향", "좋은 접근",
            "이 방향으로 진행", "이대로 진행",
            "agree", "consensus", "lgtm",
        ]
        let disagreePhrases = [
            "반대합니다", "다른 의견", "다른 접근",
            "재고해", "재검토", "우려가 있", "우려됩니다",
            "수정이 필요", "보완이 필요", "disagree",
        ]

        let hasAgree = agreePhrases.contains { lower.contains($0) }
        let hasDisagree = disagreePhrases.contains { lower.contains($0) }

        return hasAgree && !hasDisagree
    }

    /// 통합 API — debateMode가 있으면 Strategy 사용, 없으면 레거시 폴백
    static func detect(in response: String, debateMode: DebateMode?) -> Bool {
        if let mode = debateMode {
            return detect(in: response, strategy: mode.strategy)
        }
        return detectLegacy(in: response)
    }
}
