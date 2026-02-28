import Testing
import Foundation
@testable import DOUGLAS

@Suite("WorkflowAssumption & UserAnswer Tests")
struct WorkflowAssumptionTests {

    // MARK: - WorkflowAssumption

    @Test("WorkflowAssumption 기본 초기화")
    func assumptionInit() {
        let a = WorkflowAssumption(text: "DB는 PostgreSQL 사용")
        #expect(a.text == "DB는 PostgreSQL 사용")
        #expect(a.risk == "")
        #expect(a.riskLevel == .medium)
        #expect(a.confirmByPhase == .execute)
    }

    @Test("WorkflowAssumption 전체 파라미터 초기화")
    func assumptionFullInit() {
        let id = UUID()
        let a = WorkflowAssumption(
            id: id,
            text: "API 인증은 JWT",
            risk: "잘못된 인증 방식 적용 시 전체 재작업",
            riskLevel: .high,
            confirmByPhase: .plan
        )
        #expect(a.id == id)
        #expect(a.text == "API 인증은 JWT")
        #expect(a.risk == "잘못된 인증 방식 적용 시 전체 재작업")
        #expect(a.riskLevel == .high)
        #expect(a.confirmByPhase == .plan)
    }

    @Test("WorkflowAssumption Codable 라운드트립")
    func assumptionCodable() throws {
        let a = WorkflowAssumption(
            text: "Swift 5.9 사용",
            risk: "하위 버전 호환 문제",
            riskLevel: .low,
            confirmByPhase: .assemble
        )
        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(WorkflowAssumption.self, from: data)
        #expect(decoded.id == a.id)
        #expect(decoded.text == "Swift 5.9 사용")
        #expect(decoded.risk == "하위 버전 호환 문제")
        #expect(decoded.riskLevel == .low)
        #expect(decoded.confirmByPhase == .assemble)
    }

    @Test("WorkflowAssumption Identifiable — 고유 ID")
    func assumptionIdentifiable() {
        let a = WorkflowAssumption(text: "A")
        let b = WorkflowAssumption(text: "A")
        #expect(a.id != b.id)
    }

    // MARK: - RiskLevel

    @Test("RiskLevel rawValue")
    func riskLevelRawValues() {
        #expect(WorkflowAssumption.RiskLevel.low.rawValue == "low")
        #expect(WorkflowAssumption.RiskLevel.medium.rawValue == "medium")
        #expect(WorkflowAssumption.RiskLevel.high.rawValue == "high")
    }

    @Test("RiskLevel Codable 라운드트립")
    func riskLevelCodable() throws {
        for level in [WorkflowAssumption.RiskLevel.low, .medium, .high] {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(WorkflowAssumption.RiskLevel.self, from: data)
            #expect(decoded == level)
        }
    }

    // MARK: - UserAnswer

    @Test("UserAnswer 기본 초기화")
    func userAnswerInit() {
        let answer = UserAnswer(question: "DB 종류?", answer: "PostgreSQL")
        #expect(answer.question == "DB 종류?")
        #expect(answer.answer == "PostgreSQL")
    }

    @Test("UserAnswer Codable 라운드트립")
    func userAnswerCodable() throws {
        let answer = UserAnswer(question: "배포 방식?", answer: "Docker + K8s")
        let data = try JSONEncoder().encode(answer)
        let decoded = try JSONDecoder().decode(UserAnswer.self, from: data)
        #expect(decoded.id == answer.id)
        #expect(decoded.question == "배포 방식?")
        #expect(decoded.answer == "Docker + K8s")
        #expect(decoded.answeredAt.timeIntervalSince1970 > 0)
    }

    @Test("UserAnswer Identifiable — 고유 ID")
    func userAnswerIdentifiable() {
        let a = UserAnswer(question: "Q", answer: "A")
        let b = UserAnswer(question: "Q", answer: "A")
        #expect(a.id != b.id)
    }
}
