import Foundation

// MARK: - 워크플로우 단계

/// 6단계 워크플로우의 개별 단계
enum WorkflowPhase: String, Codable, CaseIterable {
    case intake       // ① 입력 파싱 (Jira fetch 등)
    case intent       // ② 작업 목적 확인
    case clarify      // ③ 요구사항 컨펌 (사용자 확인까지 루프)
    case assemble     // ④ 역할 매칭 + 에이전트 초대
    case plan         // ⑤ 토론 + 계획 수립
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

// MARK: - Plan 모드

/// Plan 단계의 동작 방식
enum PlanMode: String, Codable {
    case skip   // Plan 자체를 건너뜀 (quickAnswer)
    case lite   // 산출물형: 토론 결과 정리, RoomPlan 생성 안 함
    case exec   // 실행형: step 배열 생성 → execute로 전달
}

// MARK: - 워크플로우 의도

/// 사용자의 작업 목적에 따라 워크플로우 단계가 달라진다
enum WorkflowIntent: String, CaseIterable {
    case quickAnswer            // 단순 질문/번역
    case research               // 리서치/분석/토론/문서 정리 (brainstorm, 요건분석, 테스트계획, 작업분해, 문서작성 통합)
    case implementation         // 구현: 전체 6단계

    var displayName: String {
        switch self {
        case .quickAnswer:     return "질의응답"
        case .research:        return "리서치"
        case .implementation:  return "구현"
        }
    }

    /// SF Symbol 아이콘 이름
    var iconName: String {
        switch self {
        case .quickAnswer:     return "bolt"
        case .research:        return "magnifyingglass"
        case .implementation:  return "hammer"
        }
    }

    /// 사용자에게 보여줄 한 줄 설명
    var subtitle: String {
        switch self {
        case .quickAnswer:     return "단순 질문에 바로 답변"
        case .research:        return "조사·분석·토론·문서 정리"
        case .implementation:  return "코드 구현·수정"
        }
    }

    /// Plan 단계 동작 방식
    var planMode: PlanMode {
        switch self {
        case .quickAnswer:
            return .skip
        case .research:
            return .lite
        case .implementation:
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
    /// 분기: planMode에 따라 plan/execute 조합
    var requiredPhases: [WorkflowPhase] {
        switch self {
        case .quickAnswer:
            // 질의응답: 복명복창 없이 최적 에이전트가 바로 답변
            return [.intake, .intent, .assemble, .execute]
        case .research:
            // 리서치: 토론/분석 (execute에서 수행), 문서 요청 시 자동 문서화
            return [.intake, .intent, .clarify, .assemble, .execute]
        case .implementation:
            // 풀 워크플로우: 토론 + 계획 + 승인 + 실행
            return [.intake, .intent, .clarify, .assemble, .plan, .execute]
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
        case "brainstorm", "requirementsAnalysis", "testPlanning", "taskDecomposition", "documentation":
            self = .research
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
