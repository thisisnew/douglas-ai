import SwiftUI
import MarkdownUI
import AppKit

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

    /// 메신저 스타일 비대칭 모서리 — 사용자는 우하단, 어시스턴트는 좌하단 뾰족
    private var bubbleShape: UnevenRoundedRectangle {
        let r: CGFloat = DesignTokens.CozyGame.cardRadius
        let small: CGFloat = 4
        if message.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: r, bottomLeadingRadius: r,
                bottomTrailingRadius: small, topTrailingRadius: r
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: r, bottomLeadingRadius: small,
                bottomTrailingRadius: r, topTrailingRadius: r
            )
        }
    }

    /// placeholder 메시지 (빈 content) → 아바타/이름 표시 안 함
    private var isEmptyPlaceholder: Bool {
        message.role == .assistant && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (message.attachments ?? []).isEmpty
    }

    var body: some View {
        // 시스템 메시지 — 별도 스타일
        if message.documentURL != nil {
            documentCompletionView
        } else if message.role == .system {
            systemMessageView
        } else if isEmptyPlaceholder {
            EmptyView()
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

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                    // 에이전트 이름 + 타입 아이콘 + 시간
                    if message.role == .assistant {
                        HStack(spacing: 4) {
                            if let name = message.agentName {
                                Text(name)
                                    .font(.system(size: DesignTokens.FontSize.sm, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary.opacity(0.65))
                                    .onTapGesture { if agent != nil { showAgentInfo = true } }
                            }
                            if let icon = typeIcon {
                                Image(systemName: icon)
                                    .font(.system(size: DesignTokens.FontSize.nano))
                                    .foregroundColor(typeColor.opacity(0.8))
                            }
                            Text(timeLabel)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                    } else if message.role == .user {
                        Text(timeLabel)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.35))
                    }

                    // 첨부 파일
                    if let attachments = message.attachments, !attachments.isEmpty {
                        let images = attachments.filter { $0.isImage }
                        let documents = attachments.filter { !$0.isImage }

                        // 이미지 첨부 (NSScrollView 기반 — 중첩 스크롤 환경에서 가로 스크롤 보장)
                        if !images.isEmpty {
                            NativeHScrollView {
                                HStack(spacing: 6) {
                                    ForEach(images) { att in
                                        if let data = try? att.loadData(), let nsImage = NSImage(data: data) {
                                            let maxW: CGFloat = 220
                                            let maxH: CGFloat = 160
                                            let ratio = nsImage.size.width / max(nsImage.size.height, 1)
                                            let w = min(maxW, maxH * ratio)
                                            let h = min(maxH, maxW / ratio)

                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .frame(width: w, height: h)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
                                                )
                                                .shadow(color: palette.sidebarShadow.opacity(0.3), radius: 3, y: 2)
                                                .onTapGesture { enlargedImage = nsImage }
                                                .onHover { hovering in
                                                    if hovering { NSCursor.pointingHand.push() }
                                                    else { NSCursor.pop() }
                                                }
                                        }
                                    }
                                }
                            }
                            .frame(height: 166)
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

                        // 문서 첨부
                        if !documents.isEmpty {
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                                ForEach(documents) { att in
                                    HStack(spacing: 6) {
                                        Image(systemName: att.fileIcon)
                                            .font(.system(size: 14))
                                            .foregroundColor(palette.accent)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(att.displayName)
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .lineLimit(1)
                                            Text(FileAttachment.formatFileSize(att.fileSizeBytes))
                                                .font(.system(size: 9, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(palette.inputBackground.opacity(0.5))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(palette.cardBorder.opacity(0.12), lineWidth: 0.5)
                                    )
                                    .onTapGesture {
                                        NSWorkspace.shared.open(att.diskPath)
                                    }
                                    .onHover { hovering in
                                        if hovering { NSCursor.pointingHand.push() }
                                        else { NSCursor.pop() }
                                    }
                                }
                            }
                        }
                    }

                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messageContent
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(bubbleBackground)
                            .foregroundColor(bubbleForeground)
                            .clipShape(bubbleShape)
                            .overlay(bubbleShape.strokeBorder(typeBorder, lineWidth: typeBorderWidth))
                            .shadow(color: palette.sidebarShadow.opacity(0.6), radius: 4, y: 2)
                            .textSelection(.enabled)
                    }
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
        HStack(spacing: 6) {
            Spacer()
            Rectangle()
                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)
                .frame(maxWidth: 40)
            Text(message.content)
                .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(palette.systemMessageBackground)
                .clipShape(Capsule())
            Rectangle()
                .fill(LinearGradient(colors: [palette.separator.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)
                .frame(maxWidth: 40)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - 문서 저장 완료 카드

    private var documentCompletionView: some View {
        let lines = message.content.components(separatedBy: "\n")
        let filename = lines.count > 1 ? lines[1] : "문서"
        let filepath = lines.count > 2 ? lines[2] : ""

        return HStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green.opacity(0.7))
                    Text("문서가 저장되었습니다")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                }

                Button {
                    if let urlStr = message.documentURL, let url = URL(string: urlStr) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text(filename)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                if !filepath.isEmpty {
                    Text(filepath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.messageSummary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                    .strokeBorder(palette.messageSummary.opacity(0.15), lineWidth: 1)
            )
            .continuousRadius(DesignTokens.CozyGame.cardRadius)
            Spacer()
        }
        .padding(.vertical, 4)
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
                    colors: [palette.userBubble.opacity(0.9), palette.userBubble],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        }
        let color: Color = {
            switch message.messageType {
            case .error:         return palette.messageError.opacity(0.12)
            case .summary:       return palette.messageSummary.opacity(0.12)
            case .chainProgress: return palette.messageChainProgress.opacity(0.12)
            case .delegation:    return palette.messageDelegation.opacity(0.12)
            case .suggestion:    return palette.messageSuggestion.opacity(0.12)
            case .toolActivity:  return palette.messageToolActivity.opacity(0.10)
            case .buildStatus:   return palette.messageBuildStatus.opacity(0.12)
            case .qaStatus:      return palette.messageQaStatus.opacity(0.12)
            case .approvalRequest: return palette.messageApprovalRequest.opacity(0.12)
            case .phaseTransition: return palette.messageSummary.opacity(0.10)
            case .progress:      return palette.messageProgress.opacity(0.08)
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
        case .phaseTransition: return "arrow.right.circle"
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
        case .phaseTransition: return palette.messageSummary
        case .progress:      return palette.messageProgress
        default:             return palette.textSecondary
        }
    }

    private var typeBorder: Color {
        switch message.messageType {
        case .summary: return palette.messageSummary.opacity(0.25)
        case .error:   return palette.messageError.opacity(0.2)
        default:
            return message.role == .assistant ? palette.cardBorder.opacity(0.15) : Color.clear
        }
    }

    private var typeBorderWidth: CGFloat {
        switch message.messageType {
        case .summary, .error: return 1
        default: return message.role == .assistant ? 0.5 : 0
        }
    }

    // MARK: - 마크다운 렌더링

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .user {
            Text(message.content)
                .font(.system(size: DesignTokens.FontSize.bodyMd))
                .lineSpacing(2)
        } else {
            Markdown(Self.normalizeMarkdown(message.content))
                .markdownTextStyle {
                    FontSize(DesignTokens.FontSize.bodyMd)
                }
                .markdownTextStyle(\.link) {
                    UnderlineStyle(.single)
                    ForegroundColor(palette.accent)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(10)
                        .background(palette.inputBackground.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(palette.cardBorder.opacity(0.1), lineWidth: 0.5)
                        )
                }
                .onHover { hovering in
                    if message.content.contains("](") {
                        if hovering { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
                }
        }
    }

    // MARK: - @멘션 하이라이트

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

// MARK: - macOS 전용 가로 스크롤 뷰 (NSScrollView 기반)

/// 중첩 ScrollView 환경에서도 가로 스크롤 제스처가 정상 동작하는 NSScrollView 래퍼
struct NativeHScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasHorizontalScroller = true
        sv.hasVerticalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.horizontalScrollElasticity = .automatic
        sv.verticalScrollElasticity = .none
        sv.scrollerStyle = .overlay

        let host = NSHostingView(rootView: content)
        sv.documentView = host
        host.frame.size = host.fittingSize
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let host = sv.documentView as? NSHostingView<Content> else { return }
        host.rootView = content
        host.invalidateIntrinsicContentSize()
        host.frame.size = host.fittingSize
    }
}
