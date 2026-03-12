import Testing
import Foundation
@testable import DOUGLAS

@Suite("UserDesignationExtractor Tests")
struct UserDesignationExtractorTests {

    @Test("슬래시 구분 — '백엔드/프론트/기획 관점에서'")
    func slashSeparated() {
        let roles = UserDesignationExtractor.extract(from: "백엔드/프론트/기획 관점에서 논의해줘")
        #expect(roles.count == 3)
        #expect(roles.contains("백엔드"))
        #expect(roles.contains("프론트"))
        #expect(roles.contains("기획"))
    }

    @Test("쉼표 구분 — '백엔드, 프론트, QA 관점에서'")
    func commaSeparated() {
        let roles = UserDesignationExtractor.extract(from: "백엔드, 프론트, QA 관점에서 토론해줘")
        #expect(roles.count == 3)
    }

    @Test("명시적 에이전트 지정 — 'agents: A, B'")
    func explicitAgents() {
        let roles = UserDesignationExtractor.extract(from: "에이전트: 백엔드, 프론트")
        #expect(roles.count == 2)
    }

    @Test("지명 없는 일반 요청 → 빈 배열")
    func noDesignation() {
        let roles = UserDesignationExtractor.extract(from: "이 기능 구현해줘")
        #expect(roles.isEmpty)
    }

    @Test("입장에서 패턴")
    func positionPattern() {
        let roles = UserDesignationExtractor.extract(from: "보안/인프라 입장에서 검토해줘")
        #expect(roles.count == 2)
    }
}
