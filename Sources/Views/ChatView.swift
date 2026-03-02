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
    @State private var enlargedImage: NSImage?

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
                            .fill(DesignTokens.Colors.avatarFallback)
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
                    // 에이전트 이름 + 타입 아이콘 + 시간
                    if message.role == .assistant {
                        HStack(spacing: 4) {
                            if let name = message.agentName {
                                Text(name)
                                    .font(.system(size: DesignTokens.FontSize.sm, weight: .semibold))
                                    .foregroundColor(.primary.opacity(0.7))
                            }
                            if let icon = typeIcon {
                                Image(systemName: icon)
                                    .font(.system(size: DesignTokens.FontSize.nano))
                                    .foregroundColor(typeColor)
                            }
                            Text(timeLabel)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    } else if message.role == .user {
                        Text(timeLabel)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    // 첨부 이미지
                    if let attachments = message.attachments, !attachments.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(attachments) { att in
                                if let data = try? att.loadData(), let nsImage = NSImage(data: data) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 180, maxHeight: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .onTapGesture { enlargedImage = nsImage }
                                        .onHover { hovering in
                                            if hovering { NSCursor.pointingHand.push() }
                                            else { NSCursor.pop() }
                                        }
                                }
                            }
                        }
                        .popover(isPresented: Binding(
                            get: { enlargedImage != nil },
                            set: { if !$0 { enlargedImage = nil } }
                        )) {
                            if let img = enlargedImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 500, maxHeight: 400)
                                    .padding(8)
                            }
                        }
                    }

                    markdownText(message.content, isUser: message.role == .user)
                        .font(.system(size: DesignTokens.FontSize.bodyMd))
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
                .font(.system(size: DesignTokens.FontSize.xs))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignTokens.Colors.systemMessageBackground)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }

    private var bubbleBackground: Color {
        if message.role == .user { return .accentColor }
        switch message.messageType {
        case .error:         return Color.red.opacity(0.1)
        case .summary:       return Color.purple.opacity(0.1)
        case .chainProgress: return Color.blue.opacity(0.1)
        case .delegation:    return Color.orange.opacity(0.1)
        case .suggestion:    return Color.orange.opacity(0.1)
        case .toolActivity:  return Color.gray.opacity(0.08)
        case .buildStatus:   return Color.orange.opacity(0.1)
        case .qaStatus:      return Color.teal.opacity(0.1)
        case .approvalRequest: return Color.yellow.opacity(0.1)
        case .progress:      return Color.blue.opacity(0.06)
        default:             return DesignTokens.Colors.messageBubbleBackground
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
        case .toolActivity:  return "wrench.and.screwdriver"
        case .buildStatus:   return "hammer"
        case .qaStatus:      return "checkmark.shield"
        case .approvalRequest: return "hand.raised"
        case .progress:      return "hourglass"
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
        case .toolActivity:  return .gray
        case .buildStatus:   return .orange
        case .qaStatus:      return .teal
        case .approvalRequest: return .yellow
        case .progress:      return .blue
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

    // MARK: - 마크다운 렌더링

    /// 마크다운을 AttributedString으로 렌더링 (실패 시 plain text 폴백)
    private func markdownText(_ raw: String, isUser: Bool) -> Text {
        // 사용자 메시지는 정규화 불필요
        if isUser {
            return Text(raw)
        }
        let normalized = Self.normalizeMarkdown(raw)
        if let attr = try? AttributedString(markdown: normalized, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(normalized)
    }

    /// 채팅용 마크다운 정규화 (후처리)
    static func normalizeMarkdown(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        lines = lines.map { line in
            var l = line
            // ### 헤더 → **볼드** (채팅에서 헤더 레벨은 과함)
            if let range = l.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                let content = String(l[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                l = "**\(content)**"
            }
            return l
        }

        var result: [String] = []
        var prevEmpty = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- 구분선 제거
            if trimmed.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
                continue
            }
            // === 구분선 제거
            if trimmed.range(of: #"^={3,}$"#, options: .regularExpression) != nil {
                continue
            }

            // 연속 빈 줄 1개로 축소
            if trimmed.isEmpty {
                if !prevEmpty { result.append("") }
                prevEmpty = true
                continue
            }
            prevEmpty = false

            // **[이름]** 패턴 제거 (단독 줄)
            if trimmed.range(of: #"^\*\*\[.+\]\*\*$"#, options: .regularExpression) != nil {
                continue
            }

            result.append(line)
        }

        // 앞뒤 빈 줄 제거
        while result.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeFirst() }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }

        return result.joined(separator: "\n")
    }
}
