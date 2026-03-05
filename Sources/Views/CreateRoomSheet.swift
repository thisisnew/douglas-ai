import SwiftUI

/// 사용자가 수동으로 방을 만들어 에이전트를 초대하고 작업을 지시하는 시트
struct CreateRoomSheet: View {
    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var roomManager: RoomManager
    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var task = ""
    @State private var selectedAgentIDs: Set<UUID> = []
    @State private var projectPaths: [String] = []
    @State private var buildCommand = ""
    @State private var testCommand = ""

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
                    projectSection
                }
                .padding(24)
            }
        }
        .frame(width: DesignTokens.WindowSize.createRoomSheet.width, height: DesignTokens.WindowSize.createRoomSheet.height)
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
    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("프로젝트 디렉토리 (선택)")

            if !projectPaths.isEmpty {
                projectPathList
            }

            Button {
                pickProjectDirectories()
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(projectPaths.isEmpty ? "디렉토리 선택" : "디렉토리 추가")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }
            .buttonStyle(.plain)

            if !projectPaths.isEmpty {
                buildTestFields
            }
        }
    }

    private var projectPathList: some View {
        VStack(spacing: 0) {
            ForEach(Array(projectPaths.enumerated()), id: \.offset) { index, path in
                projectPathRow(index: index, path: path)
                if index < projectPaths.count - 1 {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                        .padding(.leading, 30)
                }
            }
        }
        .background(palette.inputBackground)
        .continuousRadius(DesignTokens.Radius.lg)
    }

    private func projectPathRow(index: Int, path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: index == 0 ? "folder.fill" : "folder")
                .foregroundColor(index == 0 ? .accentColor : .secondary)
                .font(.caption)
            Text((path as NSString).lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            if index == 0 {
                Text("주")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.1))
                    .continuousRadius(DesignTokens.Radius.sm)
            }
            Spacer()
            Button {
                projectPaths.remove(at: index)
                if projectPaths.isEmpty {
                    buildCommand = ""
                    testCommand = ""
                } else if index == 0, let first = projectPaths.first {
                    if buildCommand.isEmpty { buildCommand = detectBuildCommand(at: first) }
                    if testCommand.isEmpty { testCommand = detectTestCommand(at: first) }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var buildTestFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hammer")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("빌드 명령 (예: swift build)", text: $buildCommand)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(6)
                    .background(palette.inputBackground)
                    .continuousRadius(DesignTokens.Radius.md)
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("테스트 명령 (예: swift test)", text: $testCommand)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(6)
                    .background(palette.inputBackground)
                    .continuousRadius(DesignTokens.Radius.md)
            }
            Text("빌드/테스트 명령은 첫 번째(주) 디렉토리에서 실행됩니다.")
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

        let trimmedBuild = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTest = testCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomID = roomManager.createManualRoom(
            title: trimmedTitle,
            agentIDs: Array(selectedAgentIDs),
            task: trimmedTask,
            projectPaths: projectPaths,
            buildCommand: trimmedBuild.isEmpty ? nil : trimmedBuild,
            testCommand: trimmedTest.isEmpty ? nil : trimmedTest
        )
        // 생성 시트 닫고 방 채팅 창 바로 열기
        UtilityWindowManager.shared.closeKeyWindow()
        UtilityWindowManager.shared.open(
            title: trimmedTitle, identifier: roomID.uuidString,
            width: DesignTokens.WindowSize.roomChat.width,
            height: DesignTokens.WindowSize.roomChat.height,
            agentStore: agentStore, providerManager: providerManager,
            chatVM: chatVM, roomManager: roomManager,
            themeManager: themeManager
        ) {
            RoomChatView(roomID: roomID)
        }
    }

    private func pickProjectDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "프로젝트 디렉토리를 선택하세요 (여러 개 가능)"
        guard panel.runModal() == .OK else { return }

        let newPaths = panel.urls.map(\.path).filter { !projectPaths.contains($0) }
        projectPaths.append(contentsOf: newPaths)

        // 첫 번째 경로 기준 빌드/테스트 명령 자동 감지
        if let first = projectPaths.first {
            if buildCommand.isEmpty {
                buildCommand = detectBuildCommand(at: first)
            }
            if testCommand.isEmpty {
                testCommand = detectTestCommand(at: first)
            }
        }
    }

    /// 프로젝트 디렉토리에서 테스트 명령 자동 감지
    private func detectTestCommand(at path: String) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("Package.swift")) {
            return "swift test"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("package.json")) {
            return "npm test"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("Cargo.toml")) {
            return "cargo test"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("build.gradle")) ||
           fm.fileExists(atPath: (path as NSString).appendingPathComponent("build.gradle.kts")) {
            return "./gradlew test"
        }
        return ""
    }

    /// 프로젝트 디렉토리에서 빌드 명령 자동 감지
    private func detectBuildCommand(at path: String) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("Package.swift")) {
            return "swift build"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("package.json")) {
            return "npm run build"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("Makefile")) {
            return "make"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("Cargo.toml")) {
            return "cargo build"
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent("build.gradle")) ||
           fm.fileExists(atPath: (path as NSString).appendingPathComponent("build.gradle.kts")) {
            return "./gradlew build"
        }
        return ""
    }
}
