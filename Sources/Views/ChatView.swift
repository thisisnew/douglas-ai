import SwiftUI
import MarkdownUI

struct ChatView: View {
    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let agent = agentStore.selectedAgent {
                agentHeader(agent)
                // 코지 게임 스타일: 그라데이션 구분선
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [palette.cardBorder.opacity(0), palette.cardBorder.opacity(0.4), palette.cardBorder.opacity(0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)
                ChatContentView(agentID: agent.id, agent: agent)
            }
        }
    }

    private func agentHeader(_ agent: Agent) -> some View {
        HStack {
            AgentAvatarView(agent: agent, size: 28)
            VStack(alignment: .leading) {
                Text(agent.name)
                    .font(.system(.headline, design: .rounded))
                Text("\(agent.providerName) / \(agent.modelName)")
                    .font(.system(.caption, design: .rounded))
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
    @Environment(\.colorPalette) private var palette
    let message: ChatMessage
    @EnvironmentObject var agentStore: AgentStore
    @State private var enlargedImage: NSImage?
    @State private var showAgentInfo = false

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
                            .onTapGesture { showAgentInfo = true }
                            .help(agent.name)
                    } else {
                        Circle()
                            .fill(palette.avatarFallback)
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
                                    .font(.system(size: DesignTokens.FontSize.sm, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary.opacity(0.7))
                                    .onTapGesture { if agent != nil { showAgentInfo = true } }
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

                    messageContent
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground)
                        .foregroundColor(bubbleForeground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                .strokeBorder(typeBorder, lineWidth: typeBorderWidth)
                        )
                        .shadow(color: palette.sidebarShadow, radius: 3, y: 2)
                        .textSelection(.enabled)
                }

                if message.role == .assistant { Spacer(minLength: 48) }
            }
            .sheet(isPresented: $showAgentInfo) {
                if let agent = agent {
                    AgentInfoSheet(agent: agent)
                        .frame(
                            width: DesignTokens.WindowSize.agentInfoSheet.width,
                            height: DesignTokens.WindowSize.agentInfoSheet.height
                        )
                }
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
                .background(palette.systemMessageBackground)
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

    private var bubbleBackground: AnyShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [palette.userBubble.opacity(0.85), palette.userBubble],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        let color: Color = {
            switch message.messageType {
            case .error:         return palette.messageError.opacity(0.15)
            case .summary:       return palette.messageSummary.opacity(0.15)
            case .chainProgress: return palette.messageChainProgress.opacity(0.15)
            case .delegation:    return palette.messageDelegation.opacity(0.15)
            case .suggestion:    return palette.messageSuggestion.opacity(0.15)
            case .toolActivity:  return palette.messageToolActivity.opacity(0.12)
            case .buildStatus:   return palette.messageBuildStatus.opacity(0.15)
            case .qaStatus:      return palette.messageQaStatus.opacity(0.15)
            case .approvalRequest: return palette.messageApprovalRequest.opacity(0.15)
            case .progress:      return palette.messageProgress.opacity(0.10)
            default:             return palette.messageBubbleBackground
            }
        }()
        return AnyShapeStyle(color)
    }

    private var bubbleForeground: Color {
        message.role == .user ? palette.userBubbleText : palette.textPrimary
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
        case .delegation:    return palette.messageDelegation
        case .summary:       return palette.messageSummary
        case .chainProgress: return palette.messageChainProgress
        case .error:         return palette.messageError
        case .suggestion:    return palette.messageSuggestion
        case .toolActivity:  return palette.messageToolActivity
        case .buildStatus:   return palette.messageBuildStatus
        case .qaStatus:      return palette.messageQaStatus
        case .approvalRequest: return palette.messageApprovalRequest
        case .progress:      return palette.messageProgress
        default:             return palette.textSecondary
        }
    }

    private var typeBorder: Color {
        switch message.messageType {
        case .summary: return palette.messageSummary.opacity(0.3)
        default:
            // 코지 게임 스타일: 어시스턴트 버블에 카드 테두리
            return message.role == .assistant ? palette.cardBorder.opacity(0.25) : Color.clear
        }
    }

    private var typeBorderWidth: CGFloat {
        switch message.messageType {
        case .summary: return 1
        default:       return message.role == .assistant ? DesignTokens.CozyGame.borderWidth * 0.5 : 0
        }
    }

    // MARK: - 마크다운 렌더링

    /// 마크다운을 AttributedString으로 렌더링 (실패 시 plain text 폴백)
    /// 메시지 내용 렌더링: 사용자=플레인 텍스트, 에이전트=MarkdownUI
    @ViewBuilder
    private var messageContent: some View {
        if message.role == .user {
            Text(message.content)
                .font(.system(size: DesignTokens.FontSize.bodyMd))
        } else {
            Markdown(Self.normalizeMarkdown(message.content))
                .markdownTextStyle {
                    FontSize(DesignTokens.FontSize.bodyMd)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(8)
                        .background(palette.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
        }
    }

    /// 채팅용 마크다운 정규화 (후처리)
    static func normalizeMarkdown(_ text: String) -> String {
        var result: [String] = []
        var prevEmpty = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- 구분선 제거
            if trimmed.range(of: #"^-{3,}$"#, options: .regularExpression) != nil { continue }
            // === 구분선 제거
            if trimmed.range(of: #"^={3,}$"#, options: .regularExpression) != nil { continue }

            // 연속 빈 줄 1개로 축소
            if trimmed.isEmpty {
                if !prevEmpty { result.append("") }
                prevEmpty = true
                continue
            }
            prevEmpty = false

            // **[이름]** 패턴 제거 (단독 줄)
            if trimmed.range(of: #"^\*\*\[.+\]\*\*$"#, options: .regularExpression) != nil { continue }

            result.append(line)
        }

        // 앞뒤 빈 줄 제거
        while result.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeFirst() }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }

        return result.joined(separator: "\n")
    }
}
