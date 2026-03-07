import Testing
import Foundation
@testable import DOUGLAS

@Suite("ApprovalRecord Tests")
struct ApprovalRecordTests {

    // MARK: - ApprovalType

    @Test("ApprovalType - 모든 케이스 rawValue 왕복")
    func approvalTypeRawValues() {
        for type in [ApprovalType.clarifyApproval, .teamConfirmation, .planApproval,
                     .stepApproval, .lastStepConfirmation, .deliverApproval, .designApproval] {
            let encoded = type.rawValue
            #expect(ApprovalType(rawValue: encoded) == type)
        }
    }

    @Test("ApprovalType - Codable 왕복")
    func approvalTypeCodable() throws {
        let type = ApprovalType.planApproval
        let data = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(ApprovalType.self, from: data)
        #expect(decoded == type)
    }

    // MARK: - AwaitingType

    @Test("AwaitingType - 모든 케이스 rawValue 왕복")
    func awaitingTypeRawValues() {
        for type in [AwaitingType.clarification, .agentConfirmation, .planApproval,
                     .stepApproval, .finalApproval, .irreversibleStep, .deliverApproval,
                     .designApproval, .userFeedback, .discussionCheckpoint] {
            let encoded = type.rawValue
            #expect(AwaitingType(rawValue: encoded) == type)
        }
    }

    @Test("AwaitingType - Codable 왕복")
    func awaitingTypeCodable() throws {
        let type = AwaitingType.finalApproval
        let data = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(AwaitingType.self, from: data)
        #expect(decoded == type)
    }

    // MARK: - AwaitingType → ApprovalType 변환

    @Test("AwaitingType.toApprovalType - 매핑 검증")
    func awaitingTypeToApprovalType() {
        #expect(AwaitingType.clarification.toApprovalType == .clarifyApproval)
        #expect(AwaitingType.agentConfirmation.toApprovalType == .teamConfirmation)
        #expect(AwaitingType.planApproval.toApprovalType == .planApproval)
        #expect(AwaitingType.stepApproval.toApprovalType == .stepApproval)
        #expect(AwaitingType.finalApproval.toApprovalType == .lastStepConfirmation)
        #expect(AwaitingType.deliverApproval.toApprovalType == .deliverApproval)
        #expect(AwaitingType.designApproval.toApprovalType == .designApproval)
    }

    // MARK: - ApprovalRecord

    @Test("ApprovalRecord - 기본 생성")
    func approvalRecordCreation() {
        let record = ApprovalRecord(type: .planApproval, approved: true)
        #expect(record.type == .planApproval)
        #expect(record.approved == true)
        #expect(record.feedback == nil)
        #expect(record.stepIndex == nil)
        #expect(record.planVersion == nil)
    }

    @Test("ApprovalRecord - 모든 필드 설정")
    func approvalRecordFullFields() {
        let record = ApprovalRecord(
            type: .stepApproval,
            approved: false,
            feedback: "3단계를 수정해주세요",
            stepIndex: 2,
            planVersion: 3
        )
        #expect(record.type == .stepApproval)
        #expect(record.approved == false)
        #expect(record.feedback == "3단계를 수정해주세요")
        #expect(record.stepIndex == 2)
        #expect(record.planVersion == 3)
    }

    @Test("ApprovalRecord - Codable 왕복")
    func approvalRecordCodable() throws {
        let record = ApprovalRecord(
            type: .lastStepConfirmation,
            approved: true,
            feedback: "좋습니다",
            stepIndex: 5,
            planVersion: 2
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ApprovalRecord.self, from: data)
        #expect(decoded == record)
    }

    @Test("ApprovalRecord - Equatable")
    func approvalRecordEquatable() {
        let id = UUID()
        let date = Date()
        let a = ApprovalRecord(id: id, type: .planApproval, timestamp: date, approved: true)
        let b = ApprovalRecord(id: id, type: .planApproval, timestamp: date, approved: true)
        #expect(a == b)
    }

    @Test("ApprovalRecord - 다른 ID는 다름")
    func approvalRecordNotEqual() {
        let date = Date()
        let a = ApprovalRecord(type: .planApproval, timestamp: date, approved: true)
        let b = ApprovalRecord(type: .planApproval, timestamp: date, approved: true)
        #expect(a != b) // 다른 UUID
    }

    // MARK: - RoomPlan version

    @Test("RoomPlan - version 기본값 1")
    func roomPlanDefaultVersion() {
        let plan = RoomPlan(summary: "테스트", estimatedSeconds: 60, steps: [])
        #expect(plan.version == 1)
    }

    @Test("RoomPlan - version 명시 설정")
    func roomPlanExplicitVersion() {
        let plan = RoomPlan(summary: "테스트", estimatedSeconds: 60, steps: [], version: 3)
        #expect(plan.version == 3)
    }

    @Test("RoomPlan - 레거시 JSON(version 없음) 디코딩 시 기본값 1")
    func roomPlanLegacyDecode() throws {
        let json = """
        {"summary":"테스트","estimatedSeconds":60,"steps":[]}
        """
        let data = json.data(using: .utf8)!
        let plan = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(plan.version == 1)
    }

    @Test("RoomPlan - version 포함 Codable 왕복")
    func roomPlanVersionCodable() throws {
        let plan = RoomPlan(summary: "v2 계획", estimatedSeconds: 120, steps: [], version: 2)
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RoomPlan.self, from: data)
        #expect(decoded.version == 2)
    }

    // MARK: - Room 통합

    @Test("Room - approvalHistory 초기값 빈 배열")
    func roomApprovalHistoryDefault() {
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.approvalHistory.isEmpty)
    }

    @Test("Room - awaitingType 초기값 nil")
    func roomAwaitingTypeDefault() {
        let room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        #expect(room.awaitingType == nil)
    }

    @Test("Room - approvalHistory append 동작")
    func roomApprovalHistoryAppend() {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        let record = ApprovalRecord(type: .clarifyApproval, approved: true)
        room.approvalHistory.append(record)
        #expect(room.approvalHistory.count == 1)
        #expect(room.approvalHistory[0].type == .clarifyApproval)
    }

    @Test("Room - Codable 왕복 (approvalHistory + awaitingType)")
    func roomCodableWithApproval() throws {
        var room = Room(title: "테스트", assignedAgentIDs: [], createdBy: .user)
        room.approvalHistory.append(ApprovalRecord(type: .planApproval, approved: true, planVersion: 1))
        room.awaitingType = .stepApproval

        let data = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        #expect(decoded.approvalHistory.count == 1)
        #expect(decoded.approvalHistory[0].type == .planApproval)
        #expect(decoded.awaitingType == .stepApproval)
    }

    @Test("Room - 레거시 JSON(approvalHistory/awaitingType 없음) 디코딩")
    func roomLegacyDecodeWithoutApproval() throws {
        // 최소 Room JSON (필수 키만)
        var room = Room(title: "레거시", assignedAgentIDs: [], createdBy: .user)
        let data = try JSONEncoder().encode(room)

        // approvalHistory/awaitingType 키를 제거한 JSON 시뮬레이션
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "approvalHistory")
        dict.removeValue(forKey: "awaitingType")
        let modifiedData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(Room.self, from: modifiedData)
        #expect(decoded.approvalHistory.isEmpty)
        #expect(decoded.awaitingType == nil)
    }
}
