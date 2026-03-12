import Testing
import Foundation
@testable import DOUGLAS

@Suite("ConsensusDetector Tests")
struct ConsensusDetectorTests {

    // MARK: - Strategy 기반 감지

    @Test("dialectic 모드: [합의] → true")
    func dialecticExplicitConsensus() {
        #expect(ConsensusDetector.detect(in: "[합의] 모두 동의", debateMode: .dialectic) == true)
    }

    @Test("dialectic 모드: 약한 동의 → false")
    func dialecticWeakAgree() {
        #expect(ConsensusDetector.detect(in: "좋은 방향입니다", debateMode: .dialectic) == false)
    }

    @Test("collaborative 모드: 약한 동의 + 근거 → true")
    func collaborativeWithReason() {
        #expect(ConsensusDetector.detect(
            in: "좋은 방향입니다. 왜냐하면 확장성이 보장되기 때문입니다.",
            debateMode: .collaborative
        ) == true)
    }

    @Test("collaborative 모드: 약한 동의만 → false")
    func collaborativeNoReason() {
        #expect(ConsensusDetector.detect(in: "좋은 방향입니다", debateMode: .collaborative) == false)
    }

    @Test("coordination 모드: 약한 동의 → true")
    func coordinationWeakAgree() {
        #expect(ConsensusDetector.detect(in: "좋은 방향입니다", debateMode: .coordination) == true)
    }

    @Test("coordination 모드: 동의합니다 → true")
    func coordinationAgree() {
        #expect(ConsensusDetector.detect(in: "동의합니다", debateMode: .coordination) == true)
    }

    // MARK: - 레거시 호환

    @Test("debateMode nil → 레거시 퍼지 매칭")
    func legacyFallback() {
        #expect(ConsensusDetector.detect(in: "[합의] 결정", debateMode: nil) == true)
        #expect(ConsensusDetector.detect(in: "동의합니다", debateMode: nil) == true)
        #expect(ConsensusDetector.detect(in: "일반 응답입니다", debateMode: nil) == false)
    }

    @Test("레거시: [계속] 태그 → false")
    func legacyContinueTag() {
        #expect(ConsensusDetector.detectLegacy(in: "[계속] 아직 논의 필요") == false)
    }

    @Test("레거시: 합의 + 반대 동시 → false")
    func legacyConflict() {
        #expect(ConsensusDetector.detectLegacy(in: "좋은 방향이지만 우려가 있습니다") == false)
    }

    @Test("레거시: LGTM → true")
    func legacyLgtm() {
        #expect(ConsensusDetector.detectLegacy(in: "lgtm") == true)
    }

    // MARK: - 모드 간 엄격도 비교

    @Test("같은 응답, 다른 모드 → 다른 결과")
    func strictnessComparison() {
        let response = "좋은 계획입니다"
        #expect(ConsensusDetector.detect(in: response, debateMode: .dialectic) == false)
        #expect(ConsensusDetector.detect(in: response, debateMode: .collaborative) == false)
        #expect(ConsensusDetector.detect(in: response, debateMode: .coordination) == true)
    }
}
