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
    @State private var capabilityPreset: CapabilityPreset
    @State private var enabledToolIDs: Set<String>

    init(agent: Agent) {
        self.agent = agent
        _name = State(initialValue: agent.name)
        _persona = State(initialValue: agent.persona)
        _selectedProvider = State(initialValue: agent.providerName)
        _selectedModel = State(initialValue: agent.modelName)
        _imageData = State(initialValue: agent.imageData)
        _capabilityPreset = State(initialValue: agent.capabilityPreset ?? .none)
        _enabledToolIDs = State(initialValue: Set(agent.enabledToolIDs ?? []))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 네비게이션 바 스타일 헤더
            ZStack {
                Text("에이전트 수정")
                    .font(.headline)
                HStack {
                    Button("취소") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("저장") { save() }
                        .keyboardShortcut(.defaultAction)
                        .fontWeight(.semibold)
                        .disabled(name.isEmpty || persona.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

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
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(8)
                        } else {
                            TextField("에이전트 이름", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
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
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)

                        if let config = providerManager.configs.first(where: { $0.name == selectedProvider }),
                           !config.isConnected {
                            Label("이 프로바이더는 API 키가 설정되지 않았습니다. 설정에서 연동해주세요.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // 도구 설정
                    if !agent.isMaster {
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

                            if capabilityPreset != .none {
                                let activeTools = capabilityPreset == .custom
                                    ? Array(enabledToolIDs)
                                    : capabilityPreset.includedToolIDs
                                let names = ToolRegistry.tools(for: activeTools).map { $0.name }
                                if !names.isEmpty {
                                    Text("활성: \(names.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 440, height: min(600, (NSScreen.main?.frame.height ?? 800) * 0.75))
        .onAppear {
            loadModels(for: selectedProvider)
        }
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

    // MARK: - Logic

    private func loadModels(for providerName: String) {
        // 미연결 프로바이더는 모델 로딩 차단
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
        updated.capabilityPreset = capabilityPreset
        updated.enabledToolIDs = capabilityPreset == .custom ? Array(enabledToolIDs) : nil
        agentStore.updateAgent(updated)
        dismiss()
    }
}
