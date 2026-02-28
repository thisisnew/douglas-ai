import SwiftUI

/// 채팅 하단에 표시되는 작업 진행 중 애니메이션
struct TypingIndicator: View {
    let room: Room
    let agentStore: AgentStore
    @State private var dotPhase = 0

    private var workingAgentName: String? {
        for id in room.assignedAgentIDs {
            if let agent = agentStore.agents.first(where: { $0.id == id }),
               agent.status == .working || agent.status == .busy {
                return agent.name
            }
        }
        return nil
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

            if let name = workingAgentName {
                Text("\(name) 작업 중")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            } else {
                Text("처리 중")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignTokens.Colors.systemMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
