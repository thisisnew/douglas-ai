import Foundation

/// 사용자 요청의 생명주기 기록
struct DouglasRequest: Codable, Identifiable {
    let id: UUID
    let roomID: UUID
    let originalInput: String
    let inputType: InputType
    var intentClassification: IntentClassification?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        roomID: UUID,
        originalInput: String,
        inputType: InputType = .text,
        intentClassification: IntentClassification? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.roomID = roomID
        self.originalInput = originalInput
        self.inputType = inputType
        self.intentClassification = intentClassification
        self.createdAt = createdAt
    }
}

/// Intent 분류 결과
struct IntentClassification: Codable, Equatable {
    let intentType: WorkflowIntent
    let confidence: ConfidenceLevel
    let isAmbiguous: Bool
    let reason: String?

    init(intentType: WorkflowIntent, confidence: ConfidenceLevel = .high, isAmbiguous: Bool = false, reason: String? = nil) {
        self.intentType = intentType
        self.confidence = confidence
        self.isAmbiguous = isAmbiguous
        self.reason = reason
    }
}

/// 분류 신뢰도
enum ConfidenceLevel: String, Codable {
    case high, medium, low
}

/// 입력 유형
enum InputType: String, Codable {
    case text, image, file, url, mixed
}
