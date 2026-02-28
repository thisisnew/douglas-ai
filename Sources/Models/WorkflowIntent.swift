import Foundation

// MARK: - 워크플로우 단계

/// 7단계 워크플로우의 개별 단계
enum WorkflowPhase: String, Codable, CaseIterable {
    case intake       // ① 입력 파싱 (Jira fetch 등)
    case intent       // ② 작업 목적 확인
    case clarify      // ③ 결측치 질문 + 가정 선언
    case assemble     // ④ 역할 매칭 + 에이전트 초대
    case plan         // ⑤ 토론 + 계획 수립
    case execute      // ⑥ 단계별 병렬 실행
    case review       // ⑦ 검증 + 작업일지

    var displayName: String {
        switch self {
        case .intake:   return "입력 분석"
        case .intent:   return "목적 확인"
        case .clarify:  return "요건 확인"
        case .assemble: return "팀 구성"
        case .plan:     return "계획 수립"
        case .execute:  return "실행"
        case .review:   return "검토"
        }
    }
}

// MARK: - 워크플로우 의도

/// 사용자의 작업 목적에 따라 워크플로우 단계가 달라진다
enum WorkflowIntent: String, Codable, CaseIterable {
    case implementation         // 구현: 전체 7단계
    case requirementsAnalysis   // 요건 분석: 팀 구성/실행 스킵
    case testPlanning           // 테스트 계획: 팀 구성/실행 스킵
    case taskDecomposition      // 작업 분해: 팀 구성/실행 스킵

    var displayName: String {
        switch self {
        case .implementation:       return "구현"
        case .requirementsAnalysis: return "요건 분석"
        case .testPlanning:         return "테스트 계획"
        case .taskDecomposition:    return "작업 분해"
        }
    }

    /// 이 의도에 필요한 워크플로우 단계 목록
    var requiredPhases: [WorkflowPhase] {
        switch self {
        case .implementation:
            return [.intake, .intent, .clarify, .assemble, .plan, .execute, .review]
        case .requirementsAnalysis:
            return [.intake, .intent, .clarify, .plan, .review]
        case .testPlanning:
            return [.intake, .intent, .clarify, .plan, .review]
        case .taskDecomposition:
            return [.intake, .intent, .clarify, .plan, .review]
        }
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
