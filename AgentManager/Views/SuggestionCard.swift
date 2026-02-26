import SwiftUI

struct SuggestionCard: View {
    let suggestion: AgentSuggestion
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("새 에이전트 제안")
                    .font(.callout.bold())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.name)
                    .font(.callout.weight(.medium))
                Text(suggestion.persona)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                if !suggestion.recommendedProvider.isEmpty {
                    Text("\(suggestion.recommendedProvider) / \(suggestion.recommendedModel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("추가") { createAgent() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("건너뛰기") { chatVM.pendingSuggestion = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private func createAgent() {
        let providerName = suggestion.recommendedProvider.isEmpty
            ? (agentStore.masterAgent?.providerName ?? "Claude Code")
            : suggestion.recommendedProvider
        let modelName = suggestion.recommendedModel.isEmpty
            ? (agentStore.masterAgent?.modelName ?? "claude-sonnet-4-6")
            : suggestion.recommendedModel

        let agent = Agent(
            name: suggestion.name,
            persona: suggestion.persona,
            providerName: providerName,
            modelName: modelName
        )
        agentStore.addAgent(agent)

        let msg = ChatMessage(
            role: .assistant,
            content: "'\(suggestion.name)' 에이전트가 생성되었습니다.",
            agentName: "마스터",
            messageType: .text
        )
        chatVM.appendMessagePublic(msg, for: suggestion.masterAgentID)
        chatVM.pendingSuggestion = nil
    }
}
