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

    // MARK: - QAResult (Phase C-3)

    @Test("QAResult 기본 초기화")
    func qaResultInit() {
        let result = QAResult(success: true, output: "All tests passed", exitCode: 0)
        #expect(result.success == true)
        #expect(result.output == "All tests passed")
        #expect(result.exitCode == 0)
    }

    @Test("QAResult Codable 라운드트립")
    func qaResultCodable() throws {
        let result = QAResult(success: false, output: "2 tests failed", exitCode: 1)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(QAResult.self, from: data)
        #expect(decoded.success == false)
        #expect(decoded.output == "2 tests failed")
        #expect(decoded.exitCode == 1)
    }

    @Test("QAResult 타임스탬프 기본값")
    func qaResultTimestamp() {
        let before = Date()
        let result = QAResult(success: true, output: "", exitCode: 0)
        let after = Date()
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }

    @Test("QALoopStatus rawValue")
    func qaStatusRawValues() {
        #expect(QALoopStatus.idle.rawValue == "idle")
        #expect(QALoopStatus.testing.rawValue == "testing")
        #expect(QALoopStatus.analyzing.rawValue == "analyzing")
        #expect(QALoopStatus.passed.rawValue == "passed")
        #expect(QALoopStatus.failed.rawValue == "failed")
    }

    @Test("QALoopStatus Codable 라운드트립")
    func qaStatusCodable() throws {
        for status in [QALoopStatus.idle, .testing, .analyzing, .passed, .failed] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(QALoopStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}
