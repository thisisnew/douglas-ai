import Foundation

// MARK: - 워크플로우 가정

/// Clarify 단계에서 사용자가 미답한 항목에 대한 가정 선언
struct WorkflowAssumption: Codable, Identifiable {
    let id: UUID
    let text: String
    let risk: String                     // 이 가정이 틀리면 생길 문제
    let riskLevel: RiskLevel
    let confirmByPhase: WorkflowPhase    // 이 단계 전까지 확인 필요

    enum RiskLevel: String, Codable {
        case low
        case medium
        case high
    }

    init(
        id: UUID = UUID(),
        text: String,
        risk: String = "",
        riskLevel: RiskLevel = .medium,
        confirmByPhase: WorkflowPhase = .execute
    ) {
        self.id = id
        self.text = text
        self.risk = risk
        self.riskLevel = riskLevel
        self.confirmByPhase = confirmByPhase
    }
}

// MARK: - 사용자 답변

/// Clarify 단계에서 ask_user 도구로 받은 사용자 답변
struct UserAnswer: Codable, Identifiable {
    let id: UUID
    let question: String
    let answer: String
    let answeredAt: Date

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        answeredAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.answeredAt = answeredAt
    }
}
