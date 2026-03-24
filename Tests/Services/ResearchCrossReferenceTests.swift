import Testing
import Foundation
@testable import DOUGLAS

@Suite("Research 보완 조사 Tests")
struct ResearchFollowUpTests {

    // MARK: - 보완 조사 블록 형식

    @Test("보완 조사 블록 — findings + followUp 합성 문자열 구조")
    func followUpBlock_format() {
        let findings = "[FE개발자]\nVue 컴포넌트에서 GET /m/v1/receiving-return/returnable-targets 호출"
            + "\n\n---\n\n"
            + "[BE개발자]\nReceivingReturnController에서 GET /api/v1/receiving/return/history 제공"
        let followUps = [
            "[BE개발자 보완] FE가 찾은 /m/v1/receiving-return/returnable-targets는 rms-server에는 없습니다. inbound-service 전용 엔드포인트입니다."
        ]
        let followUpBlock = "\n\n=== 보완 조사 ===\n\n" + followUps.joined(separator: "\n\n")
        let combined = findings + followUpBlock

        #expect(combined.contains("=== 보완 조사 ==="))
        #expect(combined.contains("BE개발자 보완"))
        #expect(combined.contains("Vue 컴포넌트"))
        #expect(combined.contains("ReceivingReturnController"))
    }

    @Test("보완 조사 빈 결과 시 블록 미포함")
    func followUpBlock_empty() {
        let findings = "[FE개발자]\n결과1\n\n---\n\n[BE개발자]\n결과2"
        let followUps: [String] = []
        let followUpBlock = followUps.isEmpty ? "" : "\n\n=== 보완 조사 ===\n\n" + followUps.joined(separator: "\n\n")
        let combined = findings + followUpBlock

        #expect(!combined.contains("보완 조사"))
        #expect(combined == findings)
    }

    @Test("보완 조사 '추가 발견 없음' 필터링")
    func followUpBlock_filterNoAdditional() {
        let rawResults: [String?] = [nil, "추가 발견 없음", "", "rms-server에서 해당 엔드포인트를 찾을 수 없습니다."]
        let filtered = rawResults.compactMap { result -> String? in
            guard let r = result else { return nil }
            let trimmed = r.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "추가 발견 없음" { return nil }
            return r
        }

        #expect(filtered.count == 1)
        #expect(filtered[0].contains("rms-server"))
    }

    @Test("보완 조사 다중 에이전트 결과 합성")
    func followUpBlock_multipleAgents() {
        let followUps = [
            "[FE개발자 보완] BE의 /api/v1/receiving/return/history는 rms-server 전용이고, 화면에서 직접 호출하지 않습니다.",
            "[BE개발자 보완] FE가 호출하는 /m/v1/receiving-return/returnable-targets는 rms-server에 없음. inbound-service 내부 처리."
        ]
        let followUpBlock = "\n\n=== 보완 조사 ===\n\n" + followUps.joined(separator: "\n\n")

        #expect(followUpBlock.contains("FE개발자 보완"))
        #expect(followUpBlock.contains("BE개발자 보완"))
        #expect(followUpBlock.components(separatedBy: "보완").count >= 3)
    }
}
