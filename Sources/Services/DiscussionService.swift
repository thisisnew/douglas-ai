import Foundation

/// 토론 관련 순수 로직 도메인 서비스 — RoomManager+Discussion에서 추출
/// 오케스트레이션(에이전트 호출, 메시지 관리)은 RoomManager에 유지
/// 파싱, 히스토리 빌드, 도메인 힌트 등 순수 함수만 포함
enum DiscussionService {

    // MARK: - 브리핑 파싱

    /// 토론 종합 응답에서 RoomBriefing JSON 파싱
    static func parseBriefing(from response: String) -> RoomBriefing? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? String else {
            return nil
        }
        let keyDecisions = json["key_decisions"] as? [String] ?? []
        let responsibilities = json["agent_responsibilities"] as? [String: String] ?? [:]
        let openIssues = json["open_issues"] as? [String] ?? []
        return RoomBriefing(
            summary: summary,
            keyDecisions: keyDecisions,
            agentResponsibilities: responsibilities,
            openIssues: openIssues
        )
    }

    /// 리서치 종합 응답에서 ResearchBriefing JSON 파싱
    static func parseResearchBriefing(from response: String) -> ResearchBriefing? {
        let jsonString = extractJSON(from: response)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["executive_summary"] as? String else {
            return nil
        }
        let findings: [ResearchFinding] = (json["findings"] as? [[String: Any]])?.compactMap { item in
            guard let topic = item["topic"] as? String,
                  let detail = item["detail"] as? String else { return nil }
            return ResearchFinding(topic: topic, detail: detail)
        } ?? []
        let actionablePoints = json["actionable_points"] as? [String] ?? []
        let limitations = json["limitations"] as? [String] ?? []
        return ResearchBriefing(
            executiveSummary: summary,
            findings: findings,
            actionablePoints: actionablePoints,
            limitations: limitations
        )
    }

    // MARK: - 히스토리 빌드

    /// Room으로부터 토론용 히스토리 빌드 (순수 함수)
    static func buildHistory(room: Room, currentAgentName: String?) -> [(role: String, content: String)] {
        let currentRound = room.discussion.currentRound
        let summaries = room.discussion.roundSummaries

        if !summaries.isEmpty, summaries.contains(where: { $0.round < currentRound }) {
            let filteredAll = DiscussionHistoryFilter.filterForHistory(room.messages)
            let agentCount = max(room.assignedAgentIDs.count, 1)
            let currentRoundMessages = Array(filteredAll.suffix(agentCount))
            return DiscussionHistoryBuilder.build(
                currentRound: currentRound,
                roundSummaries: summaries,
                currentRoundMessages: currentRoundMessages,
                currentAgentName: currentAgentName
            )
        }

        return DiscussionHistoryFilter.filterForHistory(room.messages)
            .map { msg in
                let role: String
                var content: String
                switch msg.role {
                case .user:
                    role = "user"
                    content = msg.content
                case .assistant:
                    if let agentName = msg.agentName, agentName == currentAgentName {
                        role = "assistant"
                        content = msg.content
                    } else {
                        role = "user"
                        content = "[\(msg.agentName ?? "에이전트")의 발언]: \(msg.content)"
                    }
                case .system:
                    role = "user"
                    content = "[시스템]: \(msg.content)"
                }
                if content.count > 800 {
                    content = String(content.prefix(800)) + "…"
                }
                return (role: role, content: content)
            }
    }

    // MARK: - 도메인 힌트

    /// 에이전트 이름에서 전문 영역 힌트 생성 (토론 시 역할 혼동 방지)
    static func domainHint(for agentName: String) -> String {
        let name = agentName.lowercased()
        if name.contains("프론트엔드") || name.contains("frontend") || name.contains("ui") {
            return """

            [전문 영역 — 반드시 준수] 당신은 프론트엔드 전문가입니다. 아래 영역만 다루세요:
            UI/UX, 클라이언트 상태관리, 컴포넌트 설계, 렌더링 성능, 브라우저 호환성, 반응형 디자인, 접근성, CSS/스타일링, 프론트엔드 프레임워크(React, Vue, Svelte 등)
            [금지] 백엔드, 서버, 데이터베이스, API 설계, 인프라에 대해 말하지 마세요.
            """
        } else if name.contains("백엔드") || name.contains("backend") || name.contains("서버") {
            return """

            [전문 영역 — 반드시 준수] 당신은 백엔드 전문가입니다. 아래 영역만 다루세요:
            API 설계, 데이터베이스, 서버 아키텍처, 인증/보안, 성능 최적화, 인프라, 마이크로서비스
            [금지] 프론트엔드, UI/UX, 컴포넌트, 렌더링, CSS에 대해 말하지 마세요.
            """
        } else if name.contains("qa") || name.contains("테스트") || name.contains("품질") {
            return "\n[전문 영역] 테스트 전략, 품질 보증, 자동화 테스트, 버그 트래킹"
        } else if name.contains("디자인") || name.contains("design") || name.contains("ux") {
            return "\n[전문 영역] 사용자 경험, 인터페이스 디자인, 디자인 시스템, 프로토타이핑"
        } else if name.contains("devops") || name.contains("인프라") || name.contains("sre") {
            return "\n[전문 영역] CI/CD, 컨테이너, 클라우드 인프라, 모니터링, 배포 전략"
        } else if name.contains("기획") || name.contains("pm") || name.contains("프로덕트") {
            return "\n[전문 영역] 제품 전략, 요구사항 분석, 로드맵, 사용자 리서치"
        } else if name.contains("리서치") || name.contains("분석") || name.contains("research") {
            return "\n[전문 영역] 시장 조사, 데이터 분석, 트렌드 파악, 경쟁사 분석"
        }
        return ""
    }

    // MARK: - JSON 추출 유틸

    /// LLM 응답에서 JSON 블록 추출 (코드블록 또는 { } 패턴)
    private static func extractJSON(from response: String) -> String {
        // 코드블록 안의 JSON
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            return String(response[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            return String(response[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // { ... } 패턴
        if let start = response.firstIndex(of: "{"),
           let end = response.lastIndex(of: "}") {
            return String(response[start...end])
        }
        return response
    }
}
