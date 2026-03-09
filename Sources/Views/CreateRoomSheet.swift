import SwiftUI
import UniformTypeIdentifiers

/// 사용자가 수동으로 방을 만들어 에이전트를 초대하고 작업을 지시하는 시트
struct CreateRoomSheet: View {
    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var agentStore: AgentStore
    @Environment(\.dismiss) private var dismiss

    // 액션 전용 (body에서 읽지 않아 re-render 유발하지 않음)
    var onCreateRoom: ((String, [UUID], String, [FileAttachment]?) -> UUID)?

    @State private var title = ""
    @State private var task = ""
    @State private var selectedAgentIDs: Set<UUID> = []
    @State private var pendingAttachments: [FileAttachment] = []

    /// 서브에이전트 (마스터 제외)
    private var availableAgents: [Agent] {
        agentStore.subAgents
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavHeader(title: "새 방 만들기") {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            } trailing: {
                Button("만들기") { createRoom() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.userBubbleText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.accent, in: Capsule())
                    .contentShape(Capsule())
                    .opacity(canCreate ? 1 : 0.5)
                    .disabled(!canCreate)
            }

            ScrollView {
                VStack(spacing: 24) {
                    titleSection
                    agentSection
                    taskSection
                    attachmentSection
                }
                .padding(24)
                .animation(nil, value: title)
                .animation(nil, value: task)
            }
        }
        .frame(width: DesignTokens.WindowSize.createRoomSheet.width, height: DesignTokens.WindowSize.createRoomSheet.height)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
            return true
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("방 제목")
            TextField("예: 블로그 글 작성", text: $title)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(10)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("에이전트")
                Spacer()
                if !selectedAgentIDs.isEmpty {
                    Text("\(selectedAgentIDs.count)명")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            if availableAgents.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("에이전트를 먼저 추가하세요")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .background(palette.surfaceTertiary)
                .continuousRadius(DesignTokens.Radius.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(availableAgents.enumerated()), id: \.element.id) { index, agent in
                        if index > 0 {
                            Rectangle()
                                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 1)
                                .padding(.leading, 48)
                        }
                        agentRow(agent)
                    }
                }
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("작업 내용")
            TextEditor(text: $task)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(8)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))
            Text("에이전트들이 먼저 토론한 후, 계획을 세우고 작업을 진행합니다.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    @ViewBuilder
    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("첨부파일 (선택)")

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pendingAttachments) { att in
                            AttachmentThumbnail(attachment: att) {
                                att.delete()
                                pendingAttachments.removeAll { $0.id == att.id }
                            }
                        }
                    }
                }
            }

            Button(action: pickFile) {
                HStack {
                    Image(systemName: "paperclip")
                    Text(pendingAttachments.isEmpty ? "파일 첨부" : "파일 추가")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }
            .buttonStyle(.plain)

            Text("이미지, PDF, 텍스트 파일 등을 첨부할 수 있습니다. 드래그 앤 드롭도 지원합니다.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    // MARK: - Components

    // sectionLabel → SharedComponents 사용

    private func agentRow(_ agent: Agent) -> some View {
        let isSelected = selectedAgentIDs.contains(agent.id)

        return HStack(spacing: 10) {
            AgentAvatarView(agent: agent, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .medium : .regular)
                Text(agent.persona.prefix(50) + (agent.persona.count > 50 ? "..." : ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if agent.status == .working {
                statusBadge("작업중", color: .orange)
            } else if agent.status == .busy {
                statusBadge("바쁨", color: .red)
            }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : palette.stepInactive)
                .font(.title3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { toggleAgent(agent.id) }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .continuousRadius(DesignTokens.Radius.sm)
    }

    // MARK: - Logic

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedAgentIDs.isEmpty
    }

    private func toggleAgent(_ id: UUID) {
        if selectedAgentIDs.contains(id) {
            selectedAgentIDs.remove(id)
        } else {
            selectedAgentIDs.insert(id)
        }
    }

    private func createRoom() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedTask.isEmpty, !selectedAgentIDs.isEmpty else { return }

        let attachments = pendingAttachments.isEmpty ? nil : pendingAttachments
        // 새 방 채팅 윈도우가 열리기 전에 현재 윈도우를 먼저 닫아야 key window 혼동 방지
        UtilityWindowManager.shared.closeKeyWindow()
        _ = onCreateRoom?(trimmedTitle, Array(selectedAgentIDs), trimmedTask, attachments)
    }

    // MARK: - 파일 첨부

    private func pickFile() {
        let openPanel = NSOpenPanel()
        var types: [UTType] = [.jpeg, .png, .gif, .webP, .pdf, .plainText, .commaSeparatedText, .json, .html, .xml, .sourceCode, .shellScript]
        if let yaml = UTType(filenameExtension: "yaml") { types.append(yaml) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        openPanel.allowedContentTypes = types
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.message = "첨부할 파일을 선택하세요"
        guard openPanel.runModal() == .OK else { return }
        for url in openPanel.urls {
            addFileFromURL(url)
        }
    }

    private func addFileFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let mime = FileAttachment.detectMimeType(for: url, data: data) else { return }
        guard let attachment = try? FileAttachment.save(data: data, mimeType: mime, originalFilename: url.lastPathComponent) else { return }
        pendingAttachments.append(attachment)
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        addFileFromURL(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data,
                          let mime = FileAttachment.mimeType(for: data),
                          let attachment = try? FileAttachment.save(data: data, mimeType: mime) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append(attachment)
                    }
                }
            }
        }
    }
}
