import Foundation

/// 각 페이즈 완료 시 구조화된 요약을 생성하고,
/// 다음 페이즈에서 전체 히스토리 대신 이전 페이즈 요약을 참조하도록 지원 (토큰 최적화)
struct PhaseContextSummarizer {

    /// 페이즈 완료 시 해당 페이즈의 핵심 산출물을 요약 문자열로 생성
    /// - Returns: 요약 문자열 (정보 없으면 빈 문자열)
    static func summarize(phase: WorkflowPhase, room: Room) -> String {
        switch phase {
        case .understand:
            return summarizeUnderstand(room)
        case .assemble:
            return summarizeAssemble(room)
        case .design:
            return summarizeDesign(room)
        case .build:
            return summarizeBuild(room)
        case .review:
            return summarizeReview(room)
        case .deliver:
            return summarizeDeliver(room)
        default:
            return ""
        }
    }

    /// 이전 완료 페이즈의 요약을 조합하여 다음 페이즈용 컨텍스트 생성
    /// 전체 메시지 히스토리 대신 이 요약을 참조하면 토큰 절감
    static func buildContextForPhase(_ phase: WorkflowPhase, room: Room) -> String {
        let summaries = room.workflowState.phaseSummaries
        guard !summaries.isEmpty else { return "" }

        // 현재 페이즈 이전에 완료된 페이즈의 요약만 포함
        let phaseOrder: [WorkflowPhase] = [.understand, .assemble, .design, .build, .review, .deliver]
        var parts: [String] = []

        for p in phaseOrder {
            if p == phase { break }  // 현재 페이즈 이전까지만
            if let summary = summaries[p], !summary.isEmpty {
                parts.append("[\(p.displayName)] \(summary)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - 페이즈별 요약 생성

    private static func summarizeUnderstand(_ room: Room) -> String {
        guard let brief = room.taskBrief else { return "" }
        var parts: [String] = ["목표: \(brief.goal)"]
        if !brief.constraints.isEmpty {
            parts.append("제약: \(brief.constraints.joined(separator: ", "))")
        }
        if !brief.successCriteria.isEmpty {
            parts.append("성공기준: \(brief.successCriteria.joined(separator: ", "))")
        }
        parts.append("산출물: \(brief.outputType.rawValue), 위험도: \(brief.overallRisk.rawValue)")
        return parts.joined(separator: " | ")
    }

    private static func summarizeAssemble(_ room: Room) -> String {
        let roles = room.agentRoles
        guard !roles.isEmpty else { return "" }
        let roleDesc = roles.map { "\($0.key): \($0.value.displayName)" }.joined(separator: ", ")
        return "에이전트 배정: \(roleDesc)"
    }

    private static func summarizeDesign(_ room: Room) -> String {
        // 토론 브리핑이 있으면 그것 사용, 없으면 계획 요약
        if let briefing = room.discussion.briefing {
            return briefing.asContextString()
        }
        if let plan = room.plan {
            return "계획: \(plan.summary) (\(plan.steps.count)단계)"
        }
        return ""
    }

    private static func summarizeBuild(_ room: Room) -> String {
        guard let plan = room.plan else { return "" }
        let completed = plan.steps.filter { $0.status == .completed }.count
        let total = plan.steps.count
        return "\(total)단계 중 \(completed)단계 완료"
    }

    private static func summarizeReview(_ room: Room) -> String {
        // Review 결과는 메시지에 있으므로 구조화된 요약이 없음
        return ""
    }

    private static func summarizeDeliver(_ room: Room) -> String {
        return ""
    }
}
