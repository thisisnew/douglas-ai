import Testing
import Foundation
@testable import DOUGLAS

@Suite("ToolFormatConverter Bool Tests")
struct ToolFormatConverterBoolTests {

    // MARK: - convertToToolArguments Bool vs Int

    @Test("true NSNumber → .boolean(true), not .integer(1)")
    func trueNSNumberIsBool() {
        let result = ToolFormatConverter.convertToToolArguments(["flag": true as NSNumber])
        #expect(result["flag"] == .boolean(true))
        #expect(result["flag"] != .integer(1))
    }

    @Test("false NSNumber → .boolean(false), not .integer(0)")
    func falseNSNumberIsBool() {
        let result = ToolFormatConverter.convertToToolArguments(["flag": false as NSNumber])
        #expect(result["flag"] == .boolean(false))
        #expect(result["flag"] != .integer(0))
    }

    @Test("빈 딕셔너리 → 빈 결과")
    func emptyDictReturnsEmpty() {
        let result = ToolFormatConverter.convertToToolArguments([:])
        #expect(result.isEmpty)
    }

    // MARK: - parseArguments Bool

    @Test("parseArguments JSON true → .boolean(true)")
    func parseArgumentsBoolTrue() {
        let result = ToolFormatConverter.parseArguments(from: "{\"flag\":true}")
        #expect(result["flag"] == .boolean(true))
    }

    @Test("parseArguments JSON false와 Int 0 구분")
    func parseArgumentsBoolFalseVsIntZero() {
        let result = ToolFormatConverter.parseArguments(from: "{\"flag\":false,\"count\":0}")
        #expect(result["flag"] == .boolean(false))
        #expect(result["count"] == .integer(0))
    }

    // MARK: - encodeArguments Bool

    @Test("encodeArguments .boolean(true) → JSON에 true (1 아님)")
    func encodeArgumentsBoolTrue() {
        let json = ToolFormatConverter.encodeArguments(["b": .boolean(true)])
        // JSON 직렬화 결과에 true가 포함되어야 하며, 숫자 1이 아니어야 함
        let data = json.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let num = parsed["b"] as! NSNumber
        #expect(CFGetTypeID(num) == CFBooleanGetTypeID())
        #expect(num.boolValue == true)
    }

    // MARK: - Roundtrip

    @Test("encode → parse 라운드트립: 혼합 타입 보존")
    func roundtripMixedTypes() {
        let original: [String: ToolArgumentValue] = [
            "name": .string("test"),
            "count": .integer(42),
            "active": .boolean(true),
            "tags": .array(["a", "b"])
        ]
        let encoded = ToolFormatConverter.encodeArguments(original)
        let decoded = ToolFormatConverter.parseArguments(from: encoded)

        #expect(decoded["name"] == .string("test"))
        #expect(decoded["count"] == .integer(42))
        #expect(decoded["active"] == .boolean(true))
        #expect(decoded["tags"] == .array(["a", "b"]))
    }

    // MARK: - buildJSONSchema enumValues

    @Test("buildJSONSchema enumValues → enum 키 포함")
    func buildJSONSchemaWithEnumValues() {
        let params: [AgentTool.ToolParameter] = [
            .init(name: "mode", type: .string, description: "Mode", required: true, enumValues: ["fast", "slow"])
        ]
        let schema = ToolFormatConverter.buildJSONSchema(params)
        let properties = schema["properties"] as? [String: Any]
        let modeProp = properties?["mode"] as? [String: Any]
        #expect(modeProp?["type"] as? String == "string")
        #expect(modeProp?["description"] as? String == "Mode")
        let enumVals = modeProp?["enum"] as? [String]
        #expect(enumVals == ["fast", "slow"])
    }
}
