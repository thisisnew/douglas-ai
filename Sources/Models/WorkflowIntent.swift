import Foundation

// MARK: - 워크플로우 단계

/// 워크플로우의 개별 단계 (Plan C: 6단계)
enum WorkflowPhase: String, Codable, CaseIterable {
    case intake       // ① 입력 파싱 (Jira fetch 등)
    case intent       // ② 작업 목적 확인
    case clarify      // ③ 요구사항 컨펌 (사용자 확인까지 루프) — 레거시 호환
    case understand   // ①② Understand (intake+intent+clarify 통합, Plan C)
    case assemble     // ③ 역할 매칭 + 에이전트 초대
    case design       // ④ 전문가 토론 (의견→상호피드백→종합) + task일 경우 계획 승인
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

/// 사용자의 작업 목적 — WORKFLOW_SPEC §4.1 6종
/// plan 필요 여부는 clarify 이후 동적으로 판단 (Room.needsPlan)
enum WorkflowIntent: String, CaseIterable {
    case quickAnswer            // 단순 질문/정보 확인 — 한 번의 응답으로 끝남
    case task                   // 코드 작성, 수정, 빌드, 배포 등 구현 작업
    case discussion             // 의견 교환, 브레인스토밍, 관점 탐색
    case research               // 자료 수집, 검색, 비교, 정리 등 조사 작업
    case documentation          // 문서 파일 작성 — 기획서, 보고서, 제안서 등
    case complex                // 둘 이상의 작업 모드가 혼합된 요청

    var displayName: String {
        switch self {
        case .quickAnswer:     return "질의응답"
        case .task:            return "구현"
        case .discussion:      return "토론"
        case .research:        return "조사"
        case .documentation:   return "문서화"
        case .complex:         return "복합 요청"
        }
    }

    /// SF Symbol 아이콘 이름
    var iconName: String {
        switch self {
        case .quickAnswer:     return "bolt"
        case .task:            return "hammer"
        case .discussion:      return "bubble.left.and.bubble.right"
        case .research:        return "magnifyingglass"
        case .documentation:   return "doc.text"
        case .complex:         return "square.stack.3d.up"
        }
    }

    /// modifier를 반영한 requiredPhases — withExecution은 build/review 추가, outputOnly는 build/review 제거
    func requiredPhases(with modifiers: Set<IntentModifier>) -> [WorkflowPhase] {
        var phases = requiredPhases

        // withExecution: discussion/research에 build+review 추가
        if modifiers.contains(.withExecution) {
            if !phases.contains(.build) {
                // deliver 바로 앞에 build 삽입
                if let deliverIdx = phases.firstIndex(of: .deliver) {
                    phases.insert(.review, at: deliverIdx)
                    phases.insert(.build, at: deliverIdx)
                }
            }
        }

        // outputOnly: build/review 제거
        if modifiers.contains(.outputOnly) {
            phases.removeAll(where: { $0 == .build || $0 == .review })
        }

        return phases
    }

    /// 사용자에게 보여줄 한 줄 설명
    var subtitle: String {
        switch self {
        case .quickAnswer:     return "단순 질문에 바로 답변"
        case .task:            return "코드 작성·수정·빌드·배포"
        case .discussion:      return "전문가 의견 교환 및 관점 탐색"
        case .research:        return "자료 수집·검색·비교·정리"
        case .documentation:   return "기획서·보고서·제안서 등 문서 작성"
        case .complex:         return "여러 작업 모드 혼합 처리"
        }
    }

    /// 토론 필요 여부 (전문가 2명+ 시)
    var requiresDiscussion: Bool {
        switch self {
        case .quickAnswer:  return false
        default:            return true
        }
    }

    /// 이 의도에 필요한 워크플로우 단계 목록 (Plan C: 새 6단계)
    var requiredPhases: [WorkflowPhase] {
        switch self {
        case .quickAnswer:
            // 질의응답: Understand → Assemble → 바로 답변
            return [.understand, .assemble, .deliver]
        case .task, .complex:
            // 구현/복합: Understand → Assemble → Design → Build → Review → Deliver
            return [.understand, .assemble, .design, .build, .review, .deliver]
        case .discussion, .research:
            // 토론/조사: Understand → Assemble → Design(토론·조사 수행) → Deliver
            return [.understand, .assemble, .design, .deliver]
        case .documentation:
            // 문서화: Understand → Assemble → Design(구조 설계) → Build(문서 작성) → Deliver
            return [.understand, .assemble, .design, .build, .deliver]
        }
    }

    /// intent 맥락에 맞는 단계 이름
    func phaseDisplayName(_ phase: WorkflowPhase) -> String {
        switch self {
        case .discussion:
            switch phase {
            case .design:  return "토론"
            case .deliver: return "결론 도출"
            default:       return phase.displayName
            }
        case .research:
            switch phase {
            case .design:  return "조사"
            case .deliver: return "결과 정리"
            default:       return phase.displayName
            }
        case .documentation:
            switch phase {
            case .design:  return "구조 설계"
            case .build:   return "문서 작성"
            case .deliver: return "최종 정리"
            default:       return phase.displayName
            }
        case .quickAnswer:
            switch phase {
            case .deliver: return "답변"
            default:       return phase.displayName
            }
        default:
            return phase.displayName
        }
    }

    /// 사용자에게 보여줄 진행 단계 요약 (intake/intent 제외)
    var phaseSummary: String {
        requiredPhases
            .filter { $0 != .intake && $0 != .intent }
            .map { phaseDisplayName($0) }
            .joined(separator: " → ")
    }

}

// MARK: - PhaseTransition (감사 기록)

/// 워크플로우 단계 전이 기록
struct PhaseTransition: Codable, Equatable {
    let from: WorkflowPhase?     // nil = 초기 전이
    let to: WorkflowPhase
    let timestamp: Date

    init(from: WorkflowPhase? = nil, to: WorkflowPhase, timestamp: Date = Date()) {
        self.from = from
        self.to = to
        self.timestamp = timestamp
    }

    /// Equatable: timestamp 무시 (from, to만 비교)
    static func == (lhs: PhaseTransition, rhs: PhaseTransition) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to
    }
}

// MARK: - 전이 검증

extension WorkflowIntent {
    /// 주어진 전이가 이 intent의 requiredPhases 순서에 맞는지 검증
    func canTransition(from: WorkflowPhase?, to: WorkflowPhase) -> Bool {
        let phases = requiredPhases
        guard let toIdx = phases.firstIndex(of: to) else { return false }

        if from == nil {
            return toIdx == 0  // 첫 단계만 허용
        }
        guard let fromIdx = phases.firstIndex(of: from!) else { return false }
        return toIdx == fromIdx + 1  // 순차 전이만 허용
    }
}

// MARK: - Codable (하위 호환: 레거시 intent 마이그레이션)

extension WorkflowIntent: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        // 레거시 intent → .task (구현 관련만)
        case "implementation",
             "requirementsAnalysis", "testPlanning",
             "taskDecomposition":
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
