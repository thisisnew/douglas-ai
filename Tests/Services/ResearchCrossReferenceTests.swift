import Testing
import Foundation
@testable import DOUGLAS

@Suite("Research 교차 참조 Tests")
struct ResearchCrossReferenceTests {

    // MARK: - 교차 참조 블록 형식

    @Test("교차참조 블록 — findings + crossRef 합성 문자열 구조")
    func crossRefBlock_format() {
        let findings = "[FE개발자]\nVue 컴포넌트에서 GET /m/v1/receiving-return/returnable-targets 호출"
            + "\n\n---\n\n"
            + "[BE개발자]\nReceivingReturnController에서 GET /api/v1/receiving/return/history 제공"
        let crossRefs = [
            "[FE개발자 교차참조] BE가 찾은 /api/v1/receiving/return/history는 프론트엔드가 직접 호출하는 엔드포인트가 아닙니다. 프론트엔드는 inbound-service의 /m/v1/ 경로를 호출합니다."
        ]
        let crossRefBlock = "\n\n=== 교차 참조 ===\n\n" + crossRefs.joined(separator: "\n\n")
        let combined = findings + crossRefBlock

        #expect(combined.contains("=== 교차 참조 ==="))
        #expect(combined.contains("FE개발자 교차참조"))
        #expect(combined.contains("Vue 컴포넌트"))
        #expect(combined.contains("ReceivingReturnController"))
    }

    @Test("교차참조 빈 결과 시 블록 미포함")
    func crossRefBlock_empty() {
        let findings = "[FE개발자]\n결과1\n\n---\n\n[BE개발자]\n결과2"
        let crossRefs: [String] = []
        let crossRefBlock = crossRefs.isEmpty ? "" : "\n\n=== 교차 참조 ===\n\n" + crossRefs.joined(separator: "\n\n")
        let combined = findings + crossRefBlock

        #expect(!combined.contains("교차 참조"))
        #expect(combined == findings)
    }

    @Test("교차참조 '연결점 없음' 필터링")
    func crossRefBlock_filterNoConnection() {
        let rawResults: [String?] = [nil, "연결점 없음", "", "BE가 찾은 API는 inbound-service 내부용입니다."]
        let filtered = rawResults.compactMap { result -> String? in
            guard let r = result else { return nil }
            let trimmed = r.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "연결점 없음" { return nil }
            return r
        }

        #expect(filtered.count == 1)
        #expect(filtered[0].contains("inbound-service"))
    }

    @Test("교차참조 다중 에이전트 결과 합성")
    func crossRefBlock_multipleAgents() {
        let crossRefs = [
            "[FE개발자 교차참조] BE의 /api/v1/receiving/return/history는 rms-server 전용이고, 프론트엔드는 inbound-service를 경유합니다.",
            "[BE개발자 교차참조] FE가 호출하는 /m/v1/receiving-return/returnable-targets의 실제 쿼리는 inbound-service 내부에 있습니다."
        ]
        let crossRefBlock = "\n\n=== 교차 참조 ===\n\n" + crossRefs.joined(separator: "\n\n")

        #expect(crossRefBlock.contains("FE개발자 교차참조"))
        #expect(crossRefBlock.contains("BE개발자 교차참조"))
        #expect(crossRefBlock.components(separatedBy: "교차참조").count == 3) // 2 occurrences + 1
    }
}
