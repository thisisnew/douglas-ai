import SwiftUI

struct AddAgentSheet: View {
    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var providerManager: ProviderManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var persona = ""
    @State private var selectedProvider = ""
    @State private var selectedModel = ""
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: String?
    @State private var imageData: Data?
    @State private var referenceProjectPaths: [String] = []

    // 작업 규칙 (인라인 + 파일 동시 사용 가능)
    @State private var inlineRules: String = ""
    @State private var rulesFilePaths: [String] = []

    // 사전 입력 (AgentSuggestionCard에서 호출 시)
    var prefillName: String?
    var prefillPersona: String?
    var onCreated: ((Agent) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            SheetNavHeader(title: "새 에이전트") {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("추가") { addAgent() }
                    .keyboardShortcut(.defaultAction)
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
            }

            ScrollView {
                VStack(spacing: 28) {
                    // 아바타 히어로
                    avatarPicker
                        .padding(.top, 8)

                    // 이름
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("이름", required: true)
                        TextField("예) 백엔드 개발자, QA 담당, UI 디자이너", text: $name)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .padding(10)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.Radius.lg)

                        if isDuplicateName {
                            inlineWarning("이미 같은 이름의 에이전트가 있습니다")
                        }
                    }

                    // 역할 설명
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("역할 설명", required: true)
                        TextEditor(text: $persona)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.Radius.lg)
                            .overlay(
                                Group {
                                    if persona.isEmpty {
                                        Text("예) Node.js 백엔드 API 전문 개발자. REST API 설계 및 구현을 담당합니다.")
                                            .font(.body)
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .padding(.leading, 12)
                                            .padding(.top, 16)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }

                    // 유사 에이전트 경고
                    if !similarAgents.isEmpty {
                        Label(
                            "비슷한 에이전트: \(similarAgents.map(\.name).joined(separator: ", "))",
                            systemImage: "person.2"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }

                    // 작업 규칙 (필수)
                    workingRulesSection

                    // 모델 설정 (그룹 카드)
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("모델", required: true)

                        VStack(spacing: 0) {
                            settingsRow("제공자") {
                                Picker("", selection: $selectedProvider) {
                                    Text("선택").tag("")
                                    ForEach(providerManager.configs) { config in
                                        HStack(spacing: 4) {
                                            Text(config.name)
                                            if !config.isConnected {
                                                Text("(연동 필요)")
                                                    .font(.caption2)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .tag(config.name)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }

                            Divider().padding(.leading, 14)

                            settingsRow("모델") {
                                if isLoadingModels {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(height: 16)
                                } else {
                                    Picker("", selection: $selectedModel) {
                                        Text("선택").tag("")
                                        ForEach(availableModels, id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .fixedSize()
                                    .disabled(availableModels.isEmpty)
                                }
                            }
                        }
                        .background(palette.inputBackground)
                        .continuousRadius(DesignTokens.Radius.lg)

                        if let errorMessage {
                            inlineError(errorMessage)
                        }

                        if let config = providerManager.configs.first(where: { $0.name == selectedProvider }),
                           !config.isConnected {
                            Label("이 프로바이더는 API 키가 설정되지 않았습니다. 설정에서 연동해주세요.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // 참조 프로젝트
                    referenceProjectSection

                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: DesignTokens.WindowSize.agentSheet.width, height: min(DesignTokens.WindowSize.agentSheet.height, (NSScreen.main?.frame.height ?? 800) * 0.75))
        .onAppear {
            if let n = prefillName { name = n }
            if let p = prefillPersona { persona = p }
        }
        .onChange(of: selectedProvider) { _, newValue in
            selectedModel = ""
            availableModels = []
            if !newValue.isEmpty { loadModels(for: newValue) }
        }
    }

    // MARK: - 작업 규칙 섹션

    @ViewBuilder
    private var workingRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("작업 규칙", required: true)

            // 직접 입력
            TextEditor(text: $inlineRules)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
                .overlay(
                    Group {
                        if inlineRules.isEmpty {
                            Text("""
                            예) \
                            - 산출물: 마크다운 체크리스트, 초안 수준
                            - 코드 작성 시 feature/ 브랜치 사용
                            - 한국어로 작성, 존댓말 금지
                            - 변경 사항마다 테스트 포함 필수
                            """)
                                .font(.body)
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.leading, 12)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            // 파일 참조
            rulesFileList

            if !hasValidRules {
                Label("작업 규칙을 입력하거나 파일을 추가해야 에이전트를 추가할 수 있습니다.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var rulesFileList: some View {
        if !rulesFilePaths.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rulesFilePaths.enumerated()), id: \.offset) { index, path in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text((path as NSString).lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            rulesFilePaths.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    if index < rulesFilePaths.count - 1 {
                        Divider().padding(.leading, 30)
                    }
                }
            }
            .background(palette.inputBackground)
            .continuousRadius(DesignTokens.Radius.lg)
        }

        Button {
            pickRulesFiles()
        } label: {
            HStack {
                Image(systemName: "doc.badge.plus")
                Text(rulesFilePaths.isEmpty ? "규칙 파일 추가" : "파일 추가")
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(palette.inputBackground)
            .continuousRadius(DesignTokens.Radius.lg)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Components

    private var avatarPicker: some View {
        Button {
            if let data = pickAgentImage() { imageData = data }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let data = imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(palette.avatarFallback)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(.secondary.opacity(0.6))
                        )
                }

                Circle()
                    .fill(palette.accent)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    )
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsRow(label: label, content: content)
    }

    private func inlineWarning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundColor(.orange)
    }

    private func inlineError(_ text: String) -> some View {
        Label(text, systemImage: "xmark.circle")
            .font(.caption)
            .foregroundColor(.red)
    }

    // MARK: - 참조 프로젝트

    @ViewBuilder
    private var referenceProjectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("참조 프로젝트", required: false)

            if !referenceProjectPaths.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(referenceProjectPaths.enumerated()), id: \.offset) { index, path in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text((path as NSString).lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                referenceProjectPaths.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        if index < referenceProjectPaths.count - 1 {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }

            Button {
                pickReferenceProjects()
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(referenceProjectPaths.isEmpty ? "디렉토리 선택" : "디렉토리 추가")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }
            .buttonStyle(.plain)
        }
    }

    private func pickReferenceProjects() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "참조 프로젝트 디렉토리를 선택하세요 (여러 개 가능)"
        guard panel.runModal() == .OK else { return }
        let newPaths = panel.urls.map(\.path).filter { !referenceProjectPaths.contains($0) }
        referenceProjectPaths.append(contentsOf: newPaths)
    }

    private func pickRulesFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "작업 규칙 파일을 선택하세요 (여러 개 가능)"
        guard panel.runModal() == .OK else { return }
        let newPaths = panel.urls.map(\.path).filter { !rulesFilePaths.contains($0) }
        rulesFilePaths.append(contentsOf: newPaths)
    }

    // MARK: - Logic

    private var isFormValid: Bool {
        !name.isEmpty && !persona.isEmpty && !selectedModel.isEmpty && !isDuplicateName && hasValidRules
    }

    private var hasValidRules: Bool {
        !inlineRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !rulesFilePaths.isEmpty
    }

    private var similarAgents: [Agent] {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPersona = persona.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty || !trimmedPersona.isEmpty else { return [] }
        return AgentMatcher.findSimilarAgents(
            name: trimmedName,
            persona: trimmedPersona,
            among: agentStore.agents
        )
    }

    private var isDuplicateName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && agentStore.agents.contains { $0.name == trimmed }
    }

    private func loadModels(for providerName: String) {
        if let config = providerManager.configs.first(where: { $0.name == providerName }),
           !config.isConnected {
            availableModels = []
            selectedModel = ""
            errorMessage = nil
            return
        }

        isLoadingModels = true
        errorMessage = nil
        Task {
            do {
                availableModels = try await providerManager.fetchModels(for: providerName)
                if let first = availableModels.first {
                    selectedModel = first
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingModels = false
        }
    }

    private func addAgent() {
        let rules = WorkingRulesSource(inlineText: inlineRules, filePaths: rulesFilePaths)

        let agent = Agent(
            name: name,
            persona: persona,
            providerName: selectedProvider,
            modelName: selectedModel,
            imageData: imageData,
            referenceProjectPaths: referenceProjectPaths,
            workingRules: rules
        )
        agentStore.addAgent(agent)

        if let onCreated {
            onCreated(agent)
        }

        dismiss()
    }
}
