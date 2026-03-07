import Foundation

/// 후속 입력 분류 기록
struct FollowUpAction: Codable, Identifiable {
    let id: UUID
    let roomID: UUID
    let input: String
    let followUpType: FollowUpType
    let targetStepIndex: Int?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        roomID: UUID,
        input: String,
        followUpType: FollowUpType,
        targetStepIndex: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.roomID = roomID
        self.input = input
        self.followUpType = followUpType
        self.targetStepIndex = targetStepIndex
        self.createdAt = createdAt
    }
}

/// 후속 처리 유형
enum FollowUpType: String, Codable {
    case immediateAdjustment    // 현재 단계에 즉시 반영
    case nextStepAdjustment     // 다음 단계에 반영
    case replan                 // 재계획
    case rollback               // 지정 단계로 롤백
    case modeSwitch             // 모드 전환 (토론→구현 등)
    case documentRequest        // 문서 생성 요청
}
