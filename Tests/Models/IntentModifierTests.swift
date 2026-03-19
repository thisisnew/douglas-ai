import Testing
import Foundation
@testable import DOUGLAS

@Suite("IntentModifier Tests")
struct IntentModifierTests {

    @Test("IntentModifier 4가지 케이스")
    func allCases() {
        #expect(IntentModifier.allCases.count == 4)
    }

    @Test("ClassificationResult 기본 생성 — modifier 없음")
    func classificationResultDefault() {
        let result = ClassificationResult(intent: .discussion)
        #expect(result.intent == .discussion)
        #expect(result.modifiers.isEmpty)
    }

    @Test("ClassificationResult modifier 포함")
    func classificationResultWithModifiers() {
        let result = ClassificationResult(
            intent: .discussion,
            modifiers: [.adversarial, .breakdown]
        )
        #expect(result.has(.adversarial))
        #expect(result.has(.breakdown))
        #expect(!result.has(.outputOnly))
        #expect(!result.has(.withExecution))
    }

    @Test("ClassificationResult Equatable")
    func classificationResultEquatable() {
        let a = ClassificationResult(intent: .task, modifiers: [.withExecution])
        let b = ClassificationResult(intent: .task, modifiers: [.withExecution])
        let c = ClassificationResult(intent: .task, modifiers: [.outputOnly])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("discussion + adversarial → dialectic 강제를 위한 데이터")
    func adversarialModifier() {
        let result = ClassificationResult(intent: .discussion, modifiers: [.adversarial])
        #expect(result.intent == .discussion)
        #expect(result.has(.adversarial))
    }

    @Test("task + outputOnly → build 스킵을 위한 데이터")
    func outputOnlyModifier() {
        let result = ClassificationResult(intent: .task, modifiers: [.outputOnly])
        #expect(result.has(.outputOnly))
        #expect(!result.has(.withExecution))
    }

    @Test("IntentModifier Codable")
    func intentModifierCodable() throws {
        let modifier = IntentModifier.adversarial
        let data = try JSONEncoder().encode(modifier)
        let decoded = try JSONDecoder().decode(IntentModifier.self, from: data)
        #expect(decoded == modifier)
    }

    @Test("ClassificationResult — outputOnly + withExecution 모순 시 outputOnly 우선")
    func contradictoryModifiers_outputOnlyWins() {
        let result = ClassificationResult(intent: .discussion, modifiers: [.outputOnly, .withExecution])
        #expect(result.modifiers.contains(.outputOnly))
        #expect(!result.modifiers.contains(.withExecution))
    }

    @Test("ClassificationResult — 단일 modifier는 보존")
    func singleModifier_preserved() {
        let result = ClassificationResult(intent: .task, modifiers: [.withExecution])
        #expect(result.modifiers.contains(.withExecution))
    }
}
