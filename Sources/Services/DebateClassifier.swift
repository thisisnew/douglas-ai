import Foundation

/// 토론 주제 + 에이전트 구성 → DebateMode 결정
/// IntentModifier.adversarial이 있으면 무조건 dialectic
struct DebateClassifier {

    /// 토론 모드 분류 (동기 — 키워드 기반)
    /// - Parameters:
    ///   - topic: 토론 주제 텍스트
    ///   - agentRoles: 참여 에이전트들의 역할 이름
    ///   - modifiers: IntentClassifier에서 추출한 modifier 집합
    /// - Returns: 적합한 DebateMode
    static func classify(
        topic: String,
        agentRoles: [String],
        modifiers: Set<IntentModifier> = []
    ) -> DebateMode {
        // 1. adversarial modifier → 무조건 dialectic
        if modifiers.contains(.adversarial) {
            return .dialectic
        }

        // 2. 에이전트 역할 겹침도 분석
        let overlapScore = roleOverlapScore(agentRoles)

        // 3. 주제 키워드 분석
        let topicSignal = analyzeTopicKeywords(topic)

        // 4. 종합 판단
        switch (overlapScore, topicSignal) {
        case (.high, _):
            return .dialectic       // 역할 겹침 높음 → 대립
        case (_, .dialectic):
            return .dialectic       // 주제가 대안 탐색 → 대립
        case (.low, .coordination):
            return .coordination    // 역할 보완적 + 조율 주제
        case (.low, _):
            return .collaborative   // 역할 보완적 → 종합
        case (.medium, .coordination):
            return .coordination
        case (.medium, _):
            return .collaborative   // 중간 겹침 → 기본 종합
        }
    }

    // MARK: - 역할 겹침도

    enum OverlapLevel {
        case high    // 같은 도메인 (백엔드 3명)
        case medium  // 일부 겹침 (백엔드 2명 + QA)
        case low     // 완전 보완 (백엔드 + 프론트 + 디자이너)
    }

    /// 에이전트 역할명의 겹침 정도 분석
    static func roleOverlapScore(_ roles: [String]) -> OverlapLevel {
        guard roles.count >= 2 else { return .low }

        let normalized = roles.map { normalizeRole($0) }
        let uniqueDomains = Set(normalized)

        let overlapRatio = 1.0 - (Double(uniqueDomains.count) / Double(normalized.count))

        if overlapRatio >= 0.5 {
            return .high    // 절반 이상 같은 도메인
        } else if overlapRatio > 0 {
            return .medium
        }
        return .low
    }

    /// 역할명 → 도메인 정규화 (동의어 해소)
    private static func normalizeRole(_ role: String) -> String {
        let lower = role.lowercased()

        let domainMap: [(keywords: [String], domain: String)] = [
            (["백엔드", "backend", "서버", "server", "api", "spring", "django", "express"], "backend"),
            (["프론트", "frontend", "프론트엔드", "ui", "react", "vue", "angular", "swiftui"], "frontend"),
            (["디자이너", "디자인", "design", "ux", "ui/ux"], "design"),
            (["qa", "테스트", "test", "품질"], "qa"),
            (["인프라", "devops", "클라우드", "cloud", "sre", "배포"], "infra"),
            (["기획", "pm", "product", "기획자", "프로덕트"], "planning"),
            (["데이터", "data", "ml", "ai", "분석"], "data"),
            (["보안", "security", "인증", "auth"], "security"),
        ]

        for entry in domainMap {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return entry.domain
            }
        }
        return lower  // 매칭 실패 시 원본 반환
    }

    // MARK: - 주제 키워드

    enum TopicSignal {
        case dialectic     // 대안 탐색, 비교, 트레이드오프
        case coordination  // 조율, 분담, 확정
        case neutral       // 명확한 신호 없음
    }

    /// 주제에서 토론 유형 신호 추출
    static func analyzeTopicKeywords(_ topic: String) -> TopicSignal {
        let lower = topic.lowercased()

        let dialecticKeywords = [
            "vs", "선택", "비교", "어떤 게 나을", "뭐가 좋을", "트레이드오프", "tradeoff",
            "장단점", "아키텍처", "설계 방향", "전략", "어떤 방식", "어떤 접근",
        ]
        let coordinationKeywords = [
            "맡아서", "나눠서", "분담", "일정", "스케줄", "순서", "확정",
            "스펙 확인", "인터페이스 확인", "API 확정",
        ]

        let hasDialectic = dialecticKeywords.contains(where: { lower.contains($0) })
        let hasCoordination = coordinationKeywords.contains(where: { lower.contains($0) })

        if hasDialectic && !hasCoordination { return .dialectic }
        if hasCoordination && !hasDialectic { return .coordination }
        if hasDialectic && hasCoordination { return .dialectic }  // 둘 다 있으면 대립 우선
        return .neutral
    }
}
