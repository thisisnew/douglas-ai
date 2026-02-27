import SwiftUI

/// 에이전트 클릭 시 열리는 독립 채팅 윈도우
struct ChatWindowView: View {
    let agent: Agent
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                AgentAvatarView(agent: agent, size: 28)
                VStack(alignment: .leading) {
                    Text(agent.name).font(.headline)
                    Text("\(agent.providerName) / \(agent.modelName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if agent.status == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ChatContentView(agentID: agent.id, agent: agent)
        }
    }
}
