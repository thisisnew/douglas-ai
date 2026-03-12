import Foundation

// MARK: - Strategy Protocol

/// 토론 모드별 행동을 캡슐화하는 전략
/// 각 구현체가 Turn 2 프롬프트, 합의 감지, 쟁점 추출의 책임을 가짐
protocol DebateStrategy {
    var mode: DebateMode { get }

    /// Turn 2에서 사용할 피드백 프롬프트 생성
    func turn2Prompt(agentRole: String, otherOpinions: String) -> String

    /// 응답이 합의를 나타내는지 판단
    func isConsensus(response: String) -> Bool

    /// 응답에서 우려/쟁점 추출
    func extractConcerns(from response: String) -> [String]

    /// 이 전략의 최소 턴 수
    var minimumTurns: Int { get }
}

// MARK: - Dialectic (대립/논쟁)

/// 같은 도메인에서 다른 해법 → 빈틈·대안 지적 요구
struct DialecticStrategy: DebateStrategy {
    let mode: DebateMode = .dialectic
    let minimumTurns: Int = 2

    func turn2Prompt(agentRole: String, otherOpinions: String) -> String {
        """
        다른 전문가의 의견을 읽고, **빈틈, 리스크, 대안**을 짚어주세요.
        - 동의만 하지 마세요. 반드시 "이 부분은 다르게 생각합니다" 또는 "이 리스크가 있습니다"를 포함하세요.
        - 완전히 동의할 경우에만 "[전면 동의]" 태그를 붙이세요.

        당신의 역할: \(agentRole)

        다른 전문가들의 의견:
        \(otherOpinions)
        """
    }

    func isConsensus(response: String) -> Bool {
        // 명시적 태그 우선
        if response.contains("[합의]") || response.contains("[전면 동의]") { return true }
        if response.contains("[계속]") || response.contains("[이의]") { return false }

        // 설계 모드: 약한 동의 = 비합의
        let weakAgreePhrases = ["좋은 계획", "좋은 방향", "좋은 접근", "좋은 의견",
                                "동의합니다", "좋은 제안", "잘 정리"]
        if weakAgreePhrases.contains(where: { response.contains($0) }) {
            return false
        }

        return false  // dialectic은 명시적 합의 태그 없으면 비합의
    }

    func extractConcerns(from response: String) -> [String] {
        extractTaggedContent(from: response, tags: ["리스크", "우려", "문제점", "빈틈", "대안"])
    }
}

// MARK: - Collaborative (종합/통합)

/// 다른 도메인 간 연결점·갭·영향도 발견
struct CollaborativeStrategy: DebateStrategy {
    let mode: DebateMode = .collaborative
    let minimumTurns: Int = 1

    func turn2Prompt(agentRole: String, otherOpinions: String) -> String {
        """
        다른 전문가의 의견을 읽고:
        1. 내 영역과 맞닿는 **연결 지점**(인터페이스, 데이터 흐름)을 명확히 하세요.
        2. 빠진 영역이나 **회색 지대**(누구 책임인지 불명확한 부분)를 짚어주세요.
        3. 상대 영역의 제약이 내 구현에 미치는 **영향**을 언급하세요.

        당신의 역할: \(agentRole)

        다른 전문가들의 의견:
        \(otherOpinions)
        """
    }

    func isConsensus(response: String) -> Bool {
        // 명시적 태그 우선
        if response.contains("[합의]") || response.contains("[전면 동의]") { return true }
        if response.contains("[계속]") || response.contains("[이의]") { return false }

        // collaborative: 약한 동의 허용하되 근거 필요
        let weakAgreePhrases = ["좋은 계획", "좋은 방향", "좋은 접근"]
        let hasWeakAgree = weakAgreePhrases.contains(where: { response.contains($0) })
        if hasWeakAgree {
            // "왜냐하면", "이유는", "때문" 등 근거가 있으면 합의
            let reasonIndicators = ["왜냐", "이유는", "때문", "근거", "고려하면"]
            return reasonIndicators.contains(where: { response.contains($0) })
        }

        return false
    }

    func extractConcerns(from response: String) -> [String] {
        extractTaggedContent(from: response, tags: ["회색 지대", "갭", "연결 지점", "영향", "미결"])
    }
}

// MARK: - Coordination (조율/확인)

/// 구현 세부사항 정렬 — 합의 기준 느슨
struct CoordinationStrategy: DebateStrategy {
    let mode: DebateMode = .coordination
    let minimumTurns: Int = 1

    func turn2Prompt(agentRole: String, otherOpinions: String) -> String {
        """
        다른 전문가의 의견을 읽고, 보완점이나 조율이 필요한 부분을 짚어주세요.
        - 동의하면 동의해도 됩니다. 단, 구체적 이유를 1문장으로 덧붙이세요.

        당신의 역할: \(agentRole)

        다른 전문가들의 의견:
        \(otherOpinions)
        """
    }

    func isConsensus(response: String) -> Bool {
        // 명시적 태그 우선
        if response.contains("[합의]") || response.contains("[전면 동의]") { return true }
        if response.contains("[계속]") || response.contains("[이의]") { return false }

        // coordination: 약한 동의도 합의로 인정
        let agreePhrases = ["좋은 계획", "좋은 방향", "좋은 접근", "좋은 의견",
                            "동의합니다", "좋은 제안", "잘 정리", "좋습니다",
                            "그렇게 하죠", "네 맞습니다", "그대로 진행"]
        return agreePhrases.contains(where: { response.contains($0) })
    }

    func extractConcerns(from response: String) -> [String] {
        []  // coordination 모드에서는 쟁점 추적 불필요
    }
}

// MARK: - Factory

extension DebateMode {
    /// 모드에 해당하는 Strategy 인스턴스 생성
    var strategy: DebateStrategy {
        switch self {
        case .dialectic:    return DialecticStrategy()
        case .collaborative: return CollaborativeStrategy()
        case .coordination:  return CoordinationStrategy()
        }
    }
}

// MARK: - 내부 헬퍼

/// 응답에서 특정 태그/키워드 근처의 문장 추출
private func extractTaggedContent(from response: String, tags: [String]) -> [String] {
    let sentences = response.components(separatedBy: CharacterSet(charactersIn: ".。\n"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    return sentences.filter { sentence in
        tags.contains(where: { sentence.contains($0) })
    }
}
