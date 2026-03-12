import Foundation

/// Intent 수식자 — intent를 변경하지 않고 행동을 세밀하게 조절
/// 6개 intent 체계를 유지하면서 modifier 조합으로 확장
enum IntentModifier: String, Codable, CaseIterable {
    /// "날카롭게", "반박", "devil's advocate" → 토론 시 DebateMode.dialectic 강제
    case adversarial

    /// "~만 해줘", "결과만", "정리만" → Build phase 스킵
    case outputOnly

    /// "~하고 구현해줘", "실행까지" → 전체 6페이즈 실행
    case withExecution

    /// "분해", "쪼개", "나눠" → actionItems 생성 보장
    case breakdown
}

/// Intent 분류 결과 — intent + modifier 조합
struct ClassificationResult: Equatable {
    let intent: WorkflowIntent
    let modifiers: Set<IntentModifier>

    init(intent: WorkflowIntent, modifiers: Set<IntentModifier> = []) {
        self.intent = intent
        self.modifiers = modifiers
    }

    /// modifier 존재 여부 확인
    func has(_ modifier: IntentModifier) -> Bool {
        modifiers.contains(modifier)
    }
}
