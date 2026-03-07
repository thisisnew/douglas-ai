import Testing
import Foundation
@testable import DOUGLAS

@Suite("DouglasRequest & FollowUpAction Tests")
struct RequestActionTests {

    // MARK: - DouglasRequest

    @Test("DouglasRequest - 기본 생성")
    func requestCreation() {
        let roomID = UUID()
        let req = DouglasRequest(roomID: roomID, originalInput: "API 서버 만들어줘")
        #expect(req.roomID == roomID)
        #expect(req.originalInput == "API 서버 만들어줘")
        #expect(req.inputType == .text)
        #expect(req.intentClassification == nil)
    }

    @Test("DouglasRequest - Codable 왕복")
    func requestCodable() throws {
        let req = DouglasRequest(
            roomID: UUID(),
            originalInput: "테스트",
            inputType: .mixed,
            intentClassification: IntentClassification(intentType: .task, confidence: .high)
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(DouglasRequest.self, from: data)
        #expect(decoded.originalInput == "테스트")
        #expect(decoded.inputType == .mixed)
        #expect(decoded.intentClassification?.intentType == .task)
        #expect(decoded.intentClassification?.confidence == .high)
    }

    // MARK: - IntentClassification

    @Test("IntentClassification - 기본 생성")
    func classificationCreation() {
        let cls = IntentClassification(intentType: .discussion, confidence: .medium, isAmbiguous: true, reason: "토론과 구현이 모호")
        #expect(cls.intentType == .discussion)
        #expect(cls.confidence == .medium)
        #expect(cls.isAmbiguous == true)
        #expect(cls.reason == "토론과 구현이 모호")
    }

    @Test("IntentClassification - Equatable")
    func classificationEquatable() {
        let a = IntentClassification(intentType: .task, confidence: .high)
        let b = IntentClassification(intentType: .task, confidence: .high)
        #expect(a == b)
    }

    @Test("IntentClassification - Codable 왕복")
    func classificationCodable() throws {
        let cls = IntentClassification(intentType: .quickAnswer, confidence: .low, isAmbiguous: true, reason: "테스트")
        let data = try JSONEncoder().encode(cls)
        let decoded = try JSONDecoder().decode(IntentClassification.self, from: data)
        #expect(decoded == cls)
    }

    // MARK: - InputType / ConfidenceLevel

    @Test("InputType - 모든 rawValue 왕복")
    func inputTypeRawValues() {
        for type in [InputType.text, .image, .file, .url, .mixed] {
            #expect(InputType(rawValue: type.rawValue) == type)
        }
    }

    @Test("ConfidenceLevel - 모든 rawValue 왕복")
    func confidenceLevelRawValues() {
        for level in [ConfidenceLevel.high, .medium, .low] {
            #expect(ConfidenceLevel(rawValue: level.rawValue) == level)
        }
    }

    // MARK: - FollowUpAction

    @Test("FollowUpAction - 기본 생성")
    func actionCreation() {
        let roomID = UUID()
        let action = FollowUpAction(roomID: roomID, input: "3단계를 수정해줘", followUpType: .rollback, targetStepIndex: 2)
        #expect(action.roomID == roomID)
        #expect(action.input == "3단계를 수정해줘")
        #expect(action.followUpType == .rollback)
        #expect(action.targetStepIndex == 2)
    }

    @Test("FollowUpAction - Codable 왕복")
    func actionCodable() throws {
        let action = FollowUpAction(
            roomID: UUID(),
            input: "문서로 정리해줘",
            followUpType: .documentRequest
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(FollowUpAction.self, from: data)
        #expect(decoded.input == "문서로 정리해줘")
        #expect(decoded.followUpType == .documentRequest)
        #expect(decoded.targetStepIndex == nil)
    }

    // MARK: - FollowUpType

    @Test("FollowUpType - 모든 rawValue 왕복")
    func followUpTypeRawValues() {
        for type in [FollowUpType.immediateAdjustment, .nextStepAdjustment, .replan, .rollback, .modeSwitch, .documentRequest] {
            #expect(FollowUpType(rawValue: type.rawValue) == type)
        }
    }
}
