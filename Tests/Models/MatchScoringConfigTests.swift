import Testing
import Foundation
@testable import DOUGLAS

@Suite("MatchScoringConfig Tests")
struct MatchScoringConfigTests {

    @Test("default — 기본 Tier 가중치 합 = 10")
    func defaultWeights() {
        let config = MatchScoringConfig.default
        #expect(config.tier1Weight + config.tier2Weight + config.tier3Weight == 10.0)
    }

    @Test("default — 임계값 순서: suggest < autoMatch")
    func defaultThresholds() {
        let config = MatchScoringConfig.default
        #expect(config.suggestThreshold < config.autoMatchThreshold)
    }

    @Test("default — emptyTagsCap ≤ autoMatchThreshold")
    func emptyTagsCap() {
        let config = MatchScoringConfig.default
        #expect(config.emptyTagsCap >= config.suggestThreshold)
        #expect(config.emptyTagsCap <= 1.0)
    }

    @Test("default — goalKeywordLimit > 0")
    func goalKeywordLimit() {
        let config = MatchScoringConfig.default
        #expect(config.goalKeywordLimit > 0)
    }

    @Test("default — 보너스 값들이 합리적 범위 (0~1)")
    func bonusRange() {
        let config = MatchScoringConfig.default
        #expect(config.outputStyleBonus > 0 && config.outputStyleBonus <= 0.1)
        #expect(config.positionDirectBonus > 0 && config.positionDirectBonus <= 0.5)
        #expect(config.positionTemplateMaxBonus > 0 && config.positionTemplateMaxBonus <= 0.5)
    }

    @Test("커스텀 설정 생성")
    func customConfig() {
        let config = MatchScoringConfig(
            tier1Weight: 3.0, tier2Weight: 3.0, tier3Weight: 4.0,
            autoMatchThreshold: 0.8, suggestThreshold: 0.6,
            emptyTagsCap: 0.65, outputStyleBonus: 0.05,
            positionDirectBonus: 0.2, positionTemplateMaxBonus: 0.2,
            goalKeywordLimit: 3
        )
        #expect(config.tier1Weight == 3.0)
        #expect(config.autoMatchThreshold == 0.8)
        #expect(config.goalKeywordLimit == 3)
    }
}
