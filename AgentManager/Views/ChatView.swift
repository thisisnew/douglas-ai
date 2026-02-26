import SwiftUI

struct ChatView: View {
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let agent = agentStore.selectedAgent {
                agentHeader(agent)
                Divider()
                ChatContentView(agentID: agent.id, agent: agent)
            }
        }
    }

    private func agentHeader(_ agent: Agent) -> some View {
        HStack {
            AgentAvatarView(agent: agent, size: 28)
            VStack(alignment: .leading) {
                Text(agent.name)
                    .font(.headline)
                Text("\(agent.providerName) / \(agent.modelName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if agent.status == .error {
                Label(agent.errorMessage ?? "오류", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - 메시지 버블 (타입별 시각 차별화)

struct MessageBubble: View {
    let message: ChatMessage
    @EnvironmentObject var agentStore: AgentStore

    private var agent: Agent? {
        guard let name = message.agentName else { return nil }
        return agentStore.agents.first { $0.name == name }
    }

    var body: some View {
        // 시스템 메시지 — 별도 스타일
        if message.role == .system {
            systemMessageView
        } else {
            HStack(alignment: .top, spacing: 8) {
                if message.role == .user { Spacer(minLength: 48) }

                // 에이전트 아바타
                if message.role == .assistant {
                    if let agent = agent {
                        AgentAvatarView(agent: agent, size: 26)
                            .padding(.top, 2)
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            )
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                    // 에이전트 이름 + 타입 아이콘
                    if let name = message.agentName, message.role == .assistant {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.7))
                            if let icon = typeIcon {
                                Image(systemName: icon)
                                    .font(.system(size: 8))
                                    .foregroundColor(typeColor)
                            }
                        }
                    }

                    Text(message.content)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground)
                        .foregroundColor(bubbleForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(typeBorder, lineWidth: typeBorderWidth)
                        )
                        .textSelection(.enabled)
                }

                if message.role == .assistant { Spacer(minLength: 48) }
            }
        }
    }

    // MARK: - 시스템 메시지

    private var systemMessageView: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.03))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var bubbleBackground: Color {
        if message.role == .user { return .accentColor }
        switch message.messageType {
        case .error:         return Color.red.opacity(0.1)
        case .summary:       return Color.purple.opacity(0.1)
        case .chainProgress: return Color.blue.opacity(0.1)
        case .delegation:    return Color.orange.opacity(0.1)
        case .suggestion:    return Color.orange.opacity(0.1)
        case .devAction:     return Color.green.opacity(0.1)
        case .buildResult:   return Color.teal.opacity(0.1)
        case .toolActivity:  return Color.gray.opacity(0.08)
        default:             return Color.black.opacity(0.05)
        }
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .primary
    }

    private var typeIcon: String? {
        switch message.messageType {
        case .delegation:    return "arrow.turn.up.right"
        case .summary:       return "text.document"
        case .chainProgress: return "link"
        case .suggestion:    return "sparkles"
        case .error:         return "exclamationmark.triangle"
        case .devAction:     return "hammer.fill"
        case .buildResult:   return "checkmark.circle"
        case .toolActivity:  return "wrench.and.screwdriver"
        default:             return nil
        }
    }

    private var typeColor: Color {
        switch message.messageType {
        case .delegation:    return .orange
        case .summary:       return .purple
        case .chainProgress: return .blue
        case .error:         return .red
        case .suggestion:    return .orange
        case .devAction:     return .green
        case .buildResult:   return .teal
        case .toolActivity:  return .gray
        default:             return .secondary
        }
    }

    private var typeBorder: Color {
        switch message.messageType {
        case .summary: return Color.purple.opacity(0.3)
        default:       return Color.clear
        }
    }

    private var typeBorderWidth: CGFloat {
        switch message.messageType {
        case .summary: return 1
        default:       return 0
        }
    }
}
