import Foundation

// MARK: - 워크플로우 단계

/// 워크플로우의 개별 단계
enum WorkflowPhase: String, Codable, CaseIterable {
    case intake       // ① 입력 파싱 (Jira fetch 등)
    case intent       // ② 작업 목적 확인
    case clarify      // ③ 요구사항 컨펌 (사용자 확인까지 루프)
    case assemble     // ④ 역할 매칭 + 에이전트 초대
    case plan         // ⑤ 토론 + 계획 수립 (동적 삽입: needsPlan 시에만)
    case execute      // ⑥ 실행 (즉답 / 토론+브리핑 / 단계별 실행)

    var displayName: String {
        switch self {
        case .intake:   return "입력 분석"
        case .intent:   return "목적 확인"
        case .clarify:  return "요건 확인"
        case .assemble: return "팀 구성"
        case .plan:     return "계획 수립"
        case .execute:  return "실행"
        }
    }
}

// MARK: - 워크플로우 의도

/// 사용자의 작업 목적: quickAnswer(즉답) 또는 task(모든 복합 작업)
/// plan 필요 여부는 clarify 이후 동적으로 판단 (Room.needsPlan)
enum WorkflowIntent: String, CaseIterable {
    case quickAnswer            // 단순 질문/번역 — 한 번의 응답으로 끝남
    case task                   // 분석·리서치·구현·문서 작성 등 모든 복합 작업

    var displayName: String {
        switch self {
        case .quickAnswer:  return "질의응답"
        case .task:         return "작업"
        }
    }

    /// SF Symbol 아이콘 이름
    var iconName: String {
        switch self {
        case .quickAnswer:  return "bolt"
        case .task:         return "hammer"
        }
    }

    /// 사용자에게 보여줄 한 줄 설명
    var subtitle: String {
        switch self {
        case .quickAnswer:  return "단순 질문에 바로 답변"
        case .task:         return "분석·리서치·구현·문서 작성"
        }
    }

    /// 토론 필요 여부 (전문가 2명+ 시)
    var requiresDiscussion: Bool {
        switch self {
        case .quickAnswer:  return false
        case .task:         return true
        }
    }

    /// 이 의도에 필요한 워크플로우 단계 목록
    /// task의 .plan은 여기에 포함하지 않음 — needsPlan 판단 후 동적 삽입
    var requiredPhases: [WorkflowPhase] {
        switch self {
        case .quickAnswer:
            // 질의응답: 복명복창 없이 최적 에이전트가 바로 답변
            return [.intake, .intent, .assemble, .execute]
        case .task:
            // 복합 작업: 요건 확인 → 팀 구성 → 실행 (.plan은 동적 삽입)
            return [.intake, .intent, .clarify, .assemble, .execute]
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
             "brainstorm", "requirementsAnalysis", "testPlanning",
             "taskDecomposition", "documentation":
            self = .task
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
