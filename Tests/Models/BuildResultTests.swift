import Testing
import Foundation
@testable import DOUGLAS

@Suite("BuildResult Tests")
struct BuildResultTests {

    @Test("BuildResult 기본 초기화")
    func initBasic() {
        let result = BuildResult(success: true, output: "Build succeeded", exitCode: 0)
        #expect(result.success == true)
        #expect(result.output == "Build succeeded")
        #expect(result.exitCode == 0)
    }

    @Test("BuildResult Codable 라운드트립")
    func codableRoundtrip() throws {
        let result = BuildResult(success: false, output: "error: file not found", exitCode: 1)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(BuildResult.self, from: data)
        #expect(decoded.success == false)
        #expect(decoded.output == "error: file not found")
        #expect(decoded.exitCode == 1)
    }

    @Test("BuildResult 타임스탬프 기본값")
    func defaultTimestamp() {
        let before = Date()
        let result = BuildResult(success: true, output: "", exitCode: 0)
        let after = Date()
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }

    @Test("BuildLoopStatus rawValue")
    func statusRawValues() {
        #expect(BuildLoopStatus.idle.rawValue == "idle")
        #expect(BuildLoopStatus.building.rawValue == "building")
        #expect(BuildLoopStatus.fixing.rawValue == "fixing")
        #expect(BuildLoopStatus.passed.rawValue == "passed")
        #expect(BuildLoopStatus.failed.rawValue == "failed")
    }

    @Test("BuildLoopStatus Codable 라운드트립")
    func statusCodable() throws {
        for status in [BuildLoopStatus.idle, .building, .fixing, .passed, .failed] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(BuildLoopStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}
