import Foundation

// MARK: - 워크플로우 단계

/// 7단계 워크플로우의 개별 단계
enum WorkflowPhase: String, Codable, CaseIterable {
    case intake       // ① 입력 파싱 (Jira fetch 등)
    case intent       // ② 작업 목적 확인
    case clarify      // ③ 요구사항 컨펌 (사용자 확인까지 루프)
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

// MARK: - Plan 모드

/// Plan 단계의 동작 방식
enum PlanMode: String, Codable {
    case skip   // Plan 자체를 건너뜀 (quickAnswer)
    case lite   // 산출물형: 토론 결과 정리, RoomPlan 생성 안 함
    case exec   // 실행형: step 배열 생성 → execute로 전달
}

// MARK: - 워크플로우 의도

/// 사용자의 작업 목적에 따라 워크플로우 단계가 달라진다
enum WorkflowIntent: String, Codable, CaseIterable {
    case quickAnswer            // 단순 질문/번역
    case research               // 리서치/정보 조사
    case brainstorm             // 브레인스토밍
    case documentation          // 기획/문서 작성
    case implementation         // 구현: 전체 7단계
    case requirementsAnalysis   // 요건 분석
    case testPlanning           // 테스트 계획
    case taskDecomposition      // 작업 분해

    var displayName: String {
        switch self {
        case .quickAnswer:          return "즉답"
        case .research:             return "리서치"
        case .brainstorm:           return "브레인스토밍"
        case .documentation:        return "문서 작성"
        case .implementation:       return "구현"
        case .requirementsAnalysis: return "요건 분석"
        case .testPlanning:         return "테스트 계획"
        case .taskDecomposition:    return "작업 분해"
        }
    }

    /// 사용자에게 보여줄 한 줄 설명
    var subtitle: String {
        switch self {
        case .quickAnswer:          return "단순 질문에 바로 답변"
        case .research:             return "정보 조사·비교 분석"
        case .brainstorm:           return "아이디어 발산·토론"
        case .documentation:        return "기획서·문서 작성"
        case .implementation:       return "코드 구현·수정"
        case .requirementsAnalysis: return "요건 정리·분석"
        case .testPlanning:         return "테스트 전략·계획"
        case .taskDecomposition:    return "작업 분해·일감 정리"
        }
    }

    /// Plan 단계 동작 방식
    var planMode: PlanMode {
        switch self {
        case .quickAnswer:
            return .skip
        case .brainstorm, .research, .requirementsAnalysis, .testPlanning, .taskDecomposition:
            return .lite
        case .documentation, .implementation:
            return .exec
        }
    }

    /// 토론 필요 여부 (전문가 2명+ 시)
    var requiresDiscussion: Bool {
        switch self {
        case .quickAnswer:
            return false
        default:
            return true
        }
    }

    /// 사용자 승인 필요 여부 (Plan 실행 전)
    var requiresApproval: Bool {
        switch self {
        case .implementation:
            return true
        default:
            return false
        }
    }

    /// 이 의도에 필요한 워크플로우 단계 목록
    /// 공통: intake → intent → clarify → assemble
    /// 분기: planMode에 따라 plan/execute/review 조합
    var requiredPhases: [WorkflowPhase] {
        switch self {
        case .quickAnswer:
            // 즉답도 요건 확인 포함 — UX 일관성 + 사용자 조정 기회 보장
            return [.intake, .intent, .clarify, .assemble, .execute, .review]
        case .brainstorm, .requirementsAnalysis, .testPlanning, .taskDecomposition:
            // Plan-lite → 토론/정리만, 실행 없음
            return [.intake, .intent, .clarify, .assemble, .plan, .review]
        case .research:
            // 리서치: 토론 정리가 최종 산출물 (실행 없음)
            return [.intake, .intent, .clarify, .assemble, .plan, .review]
        case .documentation:
            // Plan-exec → 계획 수립 + 실행
            return [.intake, .intent, .clarify, .assemble, .plan, .execute, .review]
        case .implementation:
            // 풀 워크플로우: 토론 + 계획 + 승인 + 실행
            return [.intake, .intent, .clarify, .assemble, .plan, .execute, .review]
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
