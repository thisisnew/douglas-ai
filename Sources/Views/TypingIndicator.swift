import SwiftUI

/// 채팅 하단에 표시되는 작업 진행 중 애니메이션
struct TypingIndicator: View {
    let room: Room
    let agentStore: AgentStore
    @EnvironmentObject var roomManager: RoomManager
    @State private var dotPhase = 0

    /// 현재 발언 중인 에이전트 (토론 턴)
    private var speakingAgent: Agent? {
        if let speakingID = roomManager.speakingAgentIDByRoom[room.id],
           let agent = agentStore.agents.first(where: { $0.id == speakingID }) {
            return agent
        }
        return nil
    }

    /// 초기 단계(intake~assemble)에서는 마스터 우선, 실행 단계부터는 서브 에이전트 우선
    private var isMasterPhase: Bool {
        guard let phase = room.currentPhase else { return true }
        switch phase {
        case .intake, .intent, .clarify, .assemble:
            return true
        default:
            return false
        }
    }

    /// 작업 중인 에이전트 (발언자가 아닌 경우)
    private var workingAgent: Agent? {
        if isMasterPhase {
            // 초기 단계: 마스터를 바로 반환 (status 체크 불필요 — syncAgentStatuses가 마스터를 건너뜀)
            if let master = room.assignedAgentIDs.lazy.compactMap({ id in
                agentStore.agents.first(where: { $0.id == id && $0.isMaster })
            }).first {
                return master
            }
        }
        // 실행 단계 또는 마스터 없음: 서브 에이전트 우선
        for id in room.assignedAgentIDs {
            if let agent = agentStore.agents.first(where: { $0.id == id }),
               !agent.isMaster,
               agent.status == .working || agent.status == .busy {
                return agent
            }
        }
        for id in room.assignedAgentIDs {
            if let agent = agentStore.agents.first(where: { $0.id == id }),
               agent.status == .working || agent.status == .busy {
                return agent
            }
        }
        return nil
    }

    private var statusText: String {
        // 1순위: 토론 발언 중
        if let agent = speakingAgent {
            return "\(agent.name) 발언 중"
        }
        // 2순위: 에이전트 작업 중
        if let agent = workingAgent {
            if agent.isMaster {
                return "DOUGLAS 분석 중"
            }
            // 토론 단계에서는 "발언 중"
            if room.currentPhase == .plan {
                return "\(agent.name) 발언 중"
            }
            return "\(agent.name) 작업 중"
        }
        // 기본
        return "DOUGLAS 분석 중"
    }

    var body: some View {
        HStack(spacing: 6) {
            // 점 3개 애니메이션
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .offset(y: dotPhase == i ? -3 : 0)
                }
            }
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dotPhase = (dotPhase + 1) % 3
                    }
                }
            }

            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignTokens.Colors.systemMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
