import Foundation

// MARK: - 매칭 스코어링 설정 (Value Object)

/// 에이전트 매칭의 가중치, 임계값, 보너스 상수를 응집한 설정 객체
/// 테스트 시 커스텀 설정 주입 가능
struct MatchScoringConfig {
    // Tier 가중치
    let tier1Weight: Double    // skillTags 직접 매칭
    let tier2Weight: Double    // workModes + position
    let tier3Weight: Double    // keyword + semantic

    // 신뢰도 임계값
    let autoMatchThreshold: Double    // ≥ 이 값이면 .matched
    let suggestThreshold: Double      // ≥ 이 값이면 .suggested

    // 보너스/상한
    let emptyTagsCap: Double              // skillTags 없는 에이전트 상한
    let outputStyleBonus: Double          // OutputStyle 매칭 보너스
    let positionDirectBonus: Double       // LLM 지정 position 직접 매칭 보너스
    let positionTemplateMaxBonus: Double  // PositionTemplate 보너스 상한
    let goalKeywordLimit: Int             // goal 키워드 상한
    let jiraDomainBonus: Double           // Jira 도메인 힌트 매칭 보너스

    /// Tier 가중치 합 (정규화 분모)
    var totalWeight: Double { tier1Weight + tier2Weight + tier3Weight }

    /// 설정 유효성 검증
    var isValid: Bool {
        tier1Weight > 0 && tier2Weight > 0 && tier3Weight > 0
            && autoMatchThreshold > suggestThreshold
            && suggestThreshold > 0
            && emptyTagsCap >= 0 && emptyTagsCap <= 1.0
            && goalKeywordLimit > 0
    }

    static let `default` = MatchScoringConfig(
        tier1Weight: 5.0,
        tier2Weight: 2.0,
        tier3Weight: 3.0,
        autoMatchThreshold: 0.7,
        suggestThreshold: 0.5,
        emptyTagsCap: 0.75,
        outputStyleBonus: 0.03,
        positionDirectBonus: 0.3,
        positionTemplateMaxBonus: 0.25,
        goalKeywordLimit: 5,
        jiraDomainBonus: 0.3
    )
}
