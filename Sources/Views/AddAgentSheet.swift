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
    @State private var selectedTemplateID: String? = nil

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

                    // 역할 템플릿
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("역할 템플릿")
                        templatePicker
                    }

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

            // 템플릿 선택 시 프로바이더 변경에 맞춰 persona 재생성
            if let templateID = selectedTemplateID,
               let template = AgentRoleTemplateRegistry.template(for: templateID),
               let config = providerManager.configs.first(where: { $0.name == newValue }) {
                persona = template.resolvedPersona(for: config.type.rawValue)
            }
        }
    }

    // MARK: - Components

    private var templatePicker: some View {
        FlowLayout(spacing: 6) {
            templateChip(
                icon: "person.fill",
                label: "사용자 정의",
                isSelected: selectedTemplateID == nil
            ) {
                selectedTemplateID = nil
            }

            ForEach(AgentRoleTemplateRegistry.builtIn) { tmpl in
                templateChip(
                    icon: tmpl.icon,
                    label: tmpl.name,
                    isSelected: selectedTemplateID == tmpl.id
                ) {
                    applyTemplate(tmpl)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func templateChip(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func applyTemplate(_ template: AgentRoleTemplate) {
        selectedTemplateID = template.id
        if name.isEmpty { name = template.name }

        if let config = providerManager.configs.first(where: { $0.name == selectedProvider }) {
            persona = template.resolvedPersona(for: config.type.rawValue)
        } else {
            persona = template.basePersona
        }
    }

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
            roleTemplateID: selectedTemplateID
        )
        agentStore.addAgent(agent)
        dismiss()
    }
}
