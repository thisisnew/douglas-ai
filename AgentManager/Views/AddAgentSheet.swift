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
                                        Text(config.name).tag(config.name)
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
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 440, height: 520)
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

    private func loadModels(for providerName: String) {
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
            imageData: imageData
        )
        agentStore.addAgent(agent)
        dismiss()
    }
}
