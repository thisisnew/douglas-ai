import Foundation

// MARK: - 워크플로우 단계

/// 워크플로우의 개별 단계 (Plan C: 6단계)
enum WorkflowPhase: String, Codable, CaseIterable {
    case intake       // ① 입력 파싱 (Jira fetch 등)
    case intent       // ② 작업 목적 확인
    case clarify      // ③ 요구사항 컨펌 (사용자 확인까지 루프) — 레거시 호환
    case understand   // ①② Understand (intake+intent+clarify 통합, Plan C)
    case assemble     // ③ 역할 매칭 + 에이전트 초대
    case design       // ④ 3턴 고정 프로토콜 (Propose→Critique→Revise) + 계획 승인
    case build        // ⑤ Creator가 단계별 실행 (riskLevel별 정책)
    case review       // ⑥ Reviewer가 Build 결과물 검토
    case deliver      // ⑦ 최종 산출물 전달 (high = Draft 프리뷰 + 명시 승인)
    case plan         // 레거시 호환: 기존 토론 + 계획 수립
    case execute      // 레거시 호환: 기존 실행

    var displayName: String {
        switch self {
        case .intake:     return "입력 분석"
        case .intent:     return "목적 확인"
        case .clarify:    return "요건 확인"
        case .understand: return "요청 분석"
        case .assemble:   return "전문가 배정"
        case .design:     return "설계"
        case .build:      return "구현"
        case .review:     return "검토"
        case .deliver:    return "전달"
        case .plan:       return "계획 수립"
        case .execute:    return "실행"
        }
    }
}

// MARK: - 워크플로우 의도

/// 사용자의 작업 목적: quickAnswer(즉답), task(복합 작업), discussion(의견 교환)
/// plan 필요 여부는 clarify 이후 동적으로 판단 (Room.needsPlan)
enum WorkflowIntent: String, CaseIterable {
    case quickAnswer            // 단순 질문/번역 — 한 번의 응답으로 끝남
    case task                   // 분석·리서치·구현·문서 작성 등 모든 복합 작업
    case discussion             // 의견 교환, 브레인스토밍, 관점 탐색

    var displayName: String {
        switch self {
        case .quickAnswer:  return "질의응답"
        case .task:         return "작업"
        case .discussion:   return "토론"
        }
    }

    /// SF Symbol 아이콘 이름
    var iconName: String {
        switch self {
        case .quickAnswer:  return "bolt"
        case .task:         return "hammer"
        case .discussion:   return "bubble.left.and.bubble.right"
        }
    }

    /// 사용자에게 보여줄 한 줄 설명
    var subtitle: String {
        switch self {
        case .quickAnswer:  return "단순 질문에 바로 답변"
        case .task:         return "분석·리서치·구현·문서 작성"
        case .discussion:   return "전문가 의견 교환 및 관점 탐색"
        }
    }

    /// 토론 필요 여부 (전문가 2명+ 시)
    var requiresDiscussion: Bool {
        switch self {
        case .quickAnswer:  return false
        case .task:         return true
        case .discussion:   return true
        }
    }

    /// 이 의도에 필요한 워크플로우 단계 목록 (Plan C: 새 6단계)
    var requiredPhases: [WorkflowPhase] {
        switch self {
        case .quickAnswer:
            // 질의응답: Understand → Assemble → 바로 답변
            return [.understand, .assemble, .deliver]
        case .task:
            // 복합 작업: Understand → Assemble → Design → Build → Review → Deliver
            return [.understand, .assemble, .design, .build, .review, .deliver]
        case .discussion:
            // 토론: Understand → Assemble → Design(토론+종합) → Deliver
            // Build/Review 불필요 — 토론 자체가 산출물
            return [.understand, .assemble, .design, .deliver]
        }
    }

    /// 사용자에게 보여줄 진행 단계 요약 (intake/intent 제외)
    var phaseSummary: String {
        requiredPhases
            .filter { $0 != .intake && $0 != .intent }
            .map { $0.displayName }
            .joined(separator: " → ")
    }

    /// 실행 단계를 포함하는지
    var includesExecution: Bool {
        requiredPhases.contains(.execute)
    }

    /// 팀 구성 단계를 포함하는지
    var includesAssembly: Bool {
        requiredPhases.contains(.assemble)
    }
}

// MARK: - Codable (하위 호환: 레거시 intent 마이그레이션)

extension WorkflowIntent: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        // 레거시 intent → .task로 통합
        case "research", "implementation",
             "requirementsAnalysis", "testPlanning",
             "taskDecomposition", "documentation":
            self = .task
        // 레거시 brainstorm → .discussion
        case "brainstorm":
            self = .discussion
        default:
            guard let value = WorkflowIntent(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown intent: \(raw)"
                )
            }
            self = value
        }
    }
}
