import Testing
import Foundation
@testable import DOUGLAS

@Suite("RoomStep Tests")
struct RoomStepTests {

    // MARK: - 기본 초기화

    @Test("기본 init - requiresApproval false")
    func defaultInit() {
        let step = RoomStep(text: "코드 작성")
        #expect(step.text == "코드 작성")
        #expect(step.requiresApproval == false)
    }

    @Test("명시적 init - requiresApproval true")
    func explicitInit() {
        let step = RoomStep(text: "배포 승인", requiresApproval: true)
        #expect(step.text == "배포 승인")
        #expect(step.requiresApproval == true)
    }

    @Test("ExpressibleByStringLiteral")
    func stringLiteral() {
        let step: RoomStep = "단계 1"
        #expect(step.text == "단계 1")
        #expect(step.requiresApproval == false)
    }

    // MARK: - Codable: plain String 디코딩

    @Test("plain String JSON → RoomStep 디코딩")
    func decodePlainString() throws {
        let json = "\"테스트 단계\""
        let data = json.data(using: .utf8)!
        let step = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(step.text == "테스트 단계")
        #expect(step.requiresApproval == false)
    }

    // MARK: - Codable: object 디코딩

    @Test("object JSON → RoomStep 디코딩 (requires_approval true)")
    func decodeObject() throws {
        let json = """
        {"text": "배포", "requires_approval": true}
        """
        let data = json.data(using: .utf8)!
        let step = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(step.text == "배포")
        #expect(step.requiresApproval == true)
    }

    @Test("object JSON → requires_approval 누락 시 false")
    func decodeObjectMissingApproval() throws {
        let json = """
        {"text": "일반 단계"}
        """
        let data = json.data(using: .utf8)!
        let step = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(step.text == "일반 단계")
        #expect(step.requiresApproval == false)
    }

    // MARK: - Codable: 인코딩

    @Test("requiresApproval false → plain String 인코딩")
    func encodeAsPlainString() throws {
        let step = RoomStep(text: "코드 작성")
        let data = try JSONEncoder().encode(step)
        let str = String(data: data, encoding: .utf8)!
        // plain String이므로 { } 없이 "코드 작성" 형태
        #expect(str == "\"코드 작성\"")
    }

    @Test("requiresApproval true → object 인코딩")
    func encodeAsObject() throws {
        let step = RoomStep(text: "배포", requiresApproval: true)
        let data = try JSONEncoder().encode(step)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["text"] as? String == "배포")
        #expect(dict?["requires_approval"] as? Bool == true)
    }

    // MARK: - Codable 라운드트립

    @Test("라운드트립 - plain step")
    func roundTripPlain() throws {
        let step = RoomStep(text: "빌드")
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(decoded == step)
    }

    @Test("라운드트립 - approval step")
    func roundTripApproval() throws {
        let step = RoomStep(text: "프로덕션 배포", requiresApproval: true)
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(decoded == step)
    }

    // MARK: - 혼합 배열 (RoomPlan 역호환)

    @Test("혼합 배열 디코딩 - String + Object")
    func decodeMixedArray() throws {
        let json = """
        ["코드 작성", {"text": "배포 승인", "requires_approval": true}, "테스트 실행"]
        """
        let data = json.data(using: .utf8)!
        let steps = try JSONDecoder().decode([RoomStep].self, from: data)
        #expect(steps.count == 3)
        #expect(steps[0].text == "코드 작성")
        #expect(steps[0].requiresApproval == false)
        #expect(steps[1].text == "배포 승인")
        #expect(steps[1].requiresApproval == true)
        #expect(steps[2].text == "테스트 실행")
        #expect(steps[2].requiresApproval == false)
    }

    @Test("RoomPlan - steps가 RoomStep 배열")
    func roomPlanWithSteps() throws {
        let plan = RoomPlan(
            summary: "계획",
            estimatedSeconds: 60,
            steps: [
                RoomStep(text: "구현", requiresApproval: false),
                RoomStep(text: "배포", requiresApproval: true)
            ]
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(decoded.steps.count == 2)
        #expect(decoded.steps[0].text == "구현")
        #expect(decoded.steps[0].requiresApproval == false)
        #expect(decoded.steps[1].text == "배포")
        #expect(decoded.steps[1].requiresApproval == true)
    }

    @Test("RoomPlan - 기존 String 배열 역호환 디코딩")
    func roomPlanLegacyStringArray() throws {
        // 기존에 저장된 [String] 형태의 steps JSON
        let json = """
        {"summary": "계획", "estimatedSeconds": 120, "steps": ["1단계", "2단계", "3단계"]}
        """
        let data = json.data(using: .utf8)!
        let plan = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(plan.steps.count == 3)
        #expect(plan.steps[0].text == "1단계")
        #expect(plan.steps[0].requiresApproval == false)
        #expect(plan.steps[2].text == "3단계")
    }

    // MARK: - Equatable

    @Test("Equatable - 동일")
    func equatable() {
        let a = RoomStep(text: "A", requiresApproval: true)
        let b = RoomStep(text: "A", requiresApproval: true)
        #expect(a == b)
    }

    @Test("Equatable - 다름")
    func notEquatable() {
        let a = RoomStep(text: "A", requiresApproval: false)
        let b = RoomStep(text: "A", requiresApproval: true)
        #expect(a != b)
    }

    // MARK: - StepStatus

    @Test("StepStatus - 기본값 pending")
    func stepStatusDefault() {
        let step = RoomStep(text: "작업")
        #expect(step.status == .pending)
    }

    @Test("StepStatus - 명시 설정")
    func stepStatusExplicit() {
        let step = RoomStep(text: "작업", status: .completed)
        #expect(step.status == .completed)
    }

    @Test("StepStatus - 상태 변경")
    func stepStatusMutation() {
        var step = RoomStep(text: "작업")
        step.status = .inProgress
        #expect(step.status == .inProgress)
        step.status = .completed
        #expect(step.status == .completed)
    }

    @Test("StepStatus - Codable 왕복")
    func stepStatusCodable() throws {
        let step = RoomStep(text: "작업", status: .completed)
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(decoded.status == .completed)
    }

    @Test("StepStatus - 레거시 JSON (status 없음) → pending")
    func stepStatusLegacyDecode() throws {
        let json = """
        {"text":"작업","requires_approval":false}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(decoded.status == .pending)
    }

    @Test("StepStatus - plain String 디코딩 → pending")
    func stepStatusPlainStringDecode() throws {
        let json = "\"작업\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RoomStep.self, from: data)
        #expect(decoded.status == .pending)
    }

    @Test("StepStatus - pending일 때 plain String 인코딩 유지")
    func stepStatusPendingPlainEncode() throws {
        let step = RoomStep(text: "작업")
        let data = try JSONEncoder().encode(step)
        let str = String(data: data, encoding: .utf8)!
        // pending + 기본값이면 plain String 인코딩
        #expect(str == "\"작업\"")
    }

    @Test("StepStatus - 모든 rawValue 왕복")
    func stepStatusAllRawValues() {
        for status in [StepStatus.pending, .inProgress, .completed, .skipped, .failed] {
            #expect(StepStatus(rawValue: status.rawValue) == status)
        }
    }
}
