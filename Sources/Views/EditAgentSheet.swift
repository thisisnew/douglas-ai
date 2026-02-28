import SwiftUI
import AppKit

struct EditAgentSheet: View {
    @EnvironmentObject var agentStore: AgentStore
    @EnvironmentObject var providerManager: ProviderManager
    @Environment(\.dismiss) private var dismiss

    let agent: Agent

    @State private var name: String
    @State private var persona: String
    @State private var selectedProvider: String
    @State private var selectedModel: String
    @State private var imageData: Data?
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var referenceProjectPaths: [String]

    // 작업 규칙
    @State private var rulesMode: RulesInputMode
    @State private var inlineRules: String
    @State private var rulesFilePath: String

    init(agent: Agent) {
        self.agent = agent
        _name = State(initialValue: agent.name)
        _persona = State(initialValue: agent.persona)
        _selectedProvider = State(initialValue: agent.providerName)
        _selectedModel = State(initialValue: agent.modelName)
        _imageData = State(initialValue: agent.imageData)
        _referenceProjectPaths = State(initialValue: agent.referenceProjectPaths)

        // 작업 규칙 초기화
        switch agent.workingRules {
        case .inline(let text):
            _rulesMode = State(initialValue: .inline)
            _inlineRules = State(initialValue: text)
            _rulesFilePath = State(initialValue: "")
        case .filePath(let path):
            _rulesMode = State(initialValue: .filePath)
            _inlineRules = State(initialValue: "")
            _rulesFilePath = State(initialValue: path)
        case nil:
            _rulesMode = State(initialValue: .inline)
            _inlineRules = State(initialValue: "")
            _rulesFilePath = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavHeader(title: "에이전트 수정") {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
            }

            ScrollView {
                VStack(spacing: 28) {
                    // 아바타
                    avatarPicker
                        .padding(.top, 8)

                    // 이름
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("이름")
                        if agent.isMaster {
                            Text(name)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignTokens.Colors.surfaceTertiary)
                                .continuousRadius(DesignTokens.Radius.lg)
                        } else {
                            TextField("에이전트 이름", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(DesignTokens.Colors.inputBackground)
                                .continuousRadius(DesignTokens.Radius.lg)
                        }
                    }

                    // 역할 설명
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("역할 설명")
                        TextEditor(text: $persona)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(DesignTokens.Colors.inputBackground)
                            .continuousRadius(DesignTokens.Radius.lg)
                    }

                    // 작업 규칙 (마스터가 아닌 경우만)
                    if !agent.isMaster {
                        workingRulesSection
                    }

                    // 모델 설정 (그룹 카드)
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("모델")

                        VStack(spacing: 0) {
                            settingsRow("제공자") {
                                Picker("", selection: $selectedProvider) {
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
                        .background(DesignTokens.Colors.inputBackground)
                        .continuousRadius(DesignTokens.Radius.lg)

                        if let config = providerManager.configs.first(where: { $0.name == selectedProvider }),
                           !config.isConnected {
                            Label("이 프로바이더는 API 키가 설정되지 않았습니다. 설정에서 연동해주세요.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // 참조 프로젝트
                    if !agent.isMaster {
                        referenceProjectSection
                    }

                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: DesignTokens.WindowSize.agentSheet.width, height: min(DesignTokens.WindowSize.agentSheet.height, (NSScreen.main?.frame.height ?? 800) * 0.75))
        .onAppear {
            loadModels(for: selectedProvider)
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
            sectionLabel("작업 규칙 (필수)")

            // 기존 에이전트에 규칙이 없는 경우 안내
            if agent.workingRules == nil {
                Label("작업 규칙을 설정하면 더 정확한 결과를 얻을 수 있습니다.",
                      systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Picker("입력 방식", selection: $rulesMode) {
                Text("직접 입력").tag(RulesInputMode.inline)
                Text("파일 참조").tag(RulesInputMode.filePath)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch rulesMode {
            case .inline:
                TextEditor(text: $inlineRules)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(DesignTokens.Colors.inputBackground)
                    .continuousRadius(DesignTokens.Radius.lg)
                    .overlay(
                        Group {
                            if inlineRules.isEmpty {
                                Text("코딩 컨벤션, 작업 원칙, 금지 사항 등...")
                                    .font(.body)
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.leading, 12)
                                    .padding(.top, 16)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )

            case .filePath:
                VStack(spacing: 8) {
                    if !rulesFilePath.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text((rulesFilePath as NSString).lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Text(rulesFilePath)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                rulesFilePath = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Colors.inputBackground)
                        .continuousRadius(DesignTokens.Radius.lg)
                    }

                    Button {
                        pickRulesFile()
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text(rulesFilePath.isEmpty ? "파일 선택" : "파일 변경")
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(DesignTokens.Colors.inputBackground)
                        .continuousRadius(DesignTokens.Radius.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                        .fill(DesignTokens.Colors.avatarFallback)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: agent.isMaster ? "brain.head.profile" : "person.fill")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(agent.isMaster ? .purple.opacity(0.6) : .secondary.opacity(0.6))
                        )
                }

                Circle()
                    .fill(Color.accentColor)
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

    // MARK: - 참조 프로젝트

    @ViewBuilder
    private var referenceProjectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("참조 프로젝트 (선택)")

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
                .background(DesignTokens.Colors.inputBackground)
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
                .background(DesignTokens.Colors.inputBackground)
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

    private func pickRulesFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "작업 규칙 파일을 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rulesFilePath = url.path
    }

    // MARK: - Logic

    private var isFormValid: Bool {
        let baseValid = !name.isEmpty && !persona.isEmpty
        if agent.isMaster { return baseValid }
        return baseValid && hasValidRules
    }

    private var hasValidRules: Bool {
        switch rulesMode {
        case .inline: return !inlineRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .filePath: return !rulesFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func loadModels(for providerName: String) {
        if let config = providerManager.configs.first(where: { $0.name == providerName }),
           !config.isConnected {
            availableModels = []
            return
        }

        isLoadingModels = true
        Task {
            do {
                availableModels = try await providerManager.fetchModels(for: providerName)
                if !availableModels.contains(selectedModel), let first = availableModels.first {
                    selectedModel = first
                }
            } catch {
                availableModels = []
            }
            isLoadingModels = false
        }
    }

    private func save() {
        var updated = agent
        updated.name = name
        updated.persona = persona
        updated.providerName = selectedProvider
        updated.modelName = selectedModel
        updated.imageData = imageData
        updated.referenceProjectPaths = referenceProjectPaths
        if !agent.isMaster {
            updated.workingRules = rulesMode == .inline
                ? .inline(inlineRules)
                : .filePath(rulesFilePath)
        }
        agentStore.updateAgent(updated)
        dismiss()
    }
}
