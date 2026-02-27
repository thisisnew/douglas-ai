import SwiftUI

struct AddAgentSheet: View {
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
    @State private var capabilityPreset: CapabilityPreset = .none
    @State private var enabledToolIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // 네비게이션 바 스타일 헤더
            ZStack {
                Text("새 에이전트")
                    .font(.headline)
                HStack {
                    Button("취소") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("추가") { addAgent() }
                        .keyboardShortcut(.defaultAction)
                        .fontWeight(.semibold)
                        .disabled(!isFormValid)
                }
                if !isFormValid && !name.isEmpty {
                    HStack {
                        Spacer()
                        Text(formValidationHint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 28) {
                    // 아바타 히어로
                    avatarPicker
                        .padding(.top, 8)

                    // 이름
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("이름")
                        TextField("에이전트 이름", text: $name)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .padding(10)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)

                        if isDuplicateName {
                            inlineWarning("이미 같은 이름의 에이전트가 있습니다")
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
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                    }

                    // 모델 설정 (그룹 카드)
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("모델")

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
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)

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

                    // 도구 설정
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("도구")

                        VStack(spacing: 0) {
                            settingsRow("프리셋") {
                                Picker("", selection: $capabilityPreset) {
                                    ForEach(CapabilityPreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }

                            if capabilityPreset == .custom {
                                Divider().padding(.leading, 14)
                                ForEach(ToolRegistry.allTools) { tool in
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { enabledToolIDs.contains(tool.id) },
                                            set: { on in
                                                if on { enabledToolIDs.insert(tool.id) }
                                                else { enabledToolIDs.remove(tool.id) }
                                            }
                                        )) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(tool.name).font(.body)
                                                Text(tool.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 440, height: min(600, (NSScreen.main?.frame.height ?? 800) * 0.75))
        .onChange(of: selectedProvider) { _, newValue in
            selectedModel = ""
            availableModels = []
            if !newValue.isEmpty { loadModels(for: newValue) }
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
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(.secondary.opacity(0.6))
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

    // MARK: - Logic

    private var isFormValid: Bool {
        !name.isEmpty && !persona.isEmpty && !selectedModel.isEmpty && !isDuplicateName
    }

    private var isDuplicateName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && agentStore.agents.contains { $0.name == trimmed }
    }

    private var formValidationHint: String {
        if isDuplicateName { return "이미 사용 중인 이름입니다" }
        if persona.isEmpty { return "역할을 입력하세요" }
        if selectedProvider.isEmpty { return "프로바이더를 선택하세요" }
        if selectedModel.isEmpty { return "모델을 선택하세요" }
        return ""
    }

    private func loadModels(for providerName: String) {
        // 미연결 프로바이더는 모델 로딩 차단
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
        let agent = Agent(
            name: name,
            persona: persona,
            providerName: selectedProvider,
            modelName: selectedModel,
            imageData: imageData,
            capabilityPreset: capabilityPreset == .none ? nil : capabilityPreset,
            enabledToolIDs: capabilityPreset == .custom ? Array(enabledToolIDs) : nil
        )
        agentStore.addAgent(agent)
        dismiss()
    }
}
