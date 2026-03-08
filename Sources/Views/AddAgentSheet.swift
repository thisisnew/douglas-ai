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
    @State private var showValidation = false
    @State private var imageData: Data?
    @State private var referenceProjectPaths: [String] = []

    // 작업 규칙 (레코드 단위)
    @State private var workRules: [WorkRule] = []
    @State private var editingRule: WorkRule?
    @State private var showAddRule = false

    // Plan C: 에이전트 카드 메타데이터
    @State private var skillTagsText: String = ""
    @State private var selectedWorkModes: Set<WorkMode> = []
    @State private var selectedOutputStyles: Set<OutputStyle> = []
    @State private var showAdvancedCard = false
    @State private var selectedPreset: AgentPreset?
    @State private var showPresetPicker = false

    // 사전 입력 (AgentSuggestionCard에서 호출 시)
    var prefillName: String?
    var prefillPersona: String?
    var onCreated: ((Agent) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            SheetNavHeader(title: "새 에이전트") {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            } trailing: {
                Button {
                    if isFormValid {
                        addAgent()
                    } else {
                        withAnimation(.dgStandard) { showValidation = true }
                    }
                } label: {
                    Text("추가")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.userBubbleText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(palette.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
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
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(
                                showValidation && name.isEmpty ? Color.orange.opacity(0.6) : palette.cardBorder.opacity(0.15), lineWidth: 1))
                            .onChange(of: name) { _, _ in if showValidation { showValidation = false } }

                        if isDuplicateName {
                            inlineWarning("이미 같은 이름의 에이전트가 있습니다")
                        }
                        if showValidation && name.isEmpty {
                            validationHint("이름을 입력하세요")
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
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(
                                showValidation && persona.isEmpty ? Color.orange.opacity(0.6) : palette.cardBorder.opacity(0.15), lineWidth: 1))
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
                        if showValidation && persona.isEmpty {
                            validationHint("역할 설명을 입력하세요")
                        }
                    }

                    // 프리셋으로 빠른 설정
                    presetSection

                    // 에이전트 카드 메타데이터 (Plan C)
                    agentCardSection

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

                            Rectangle()
                                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 1)
                                .padding(.leading, 14)

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
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous).strokeBorder(
                            showValidation && selectedModel.isEmpty ? Color.orange.opacity(0.6) : .clear, lineWidth: 1))

                        if showValidation && selectedModel.isEmpty {
                            validationHint(selectedProvider.isEmpty ? "제공자와 모델을 선택하세요" : "모델을 선택하세요")
                        }
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

    // MARK: - 프리셋 섹션

    @ViewBuilder
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("프리셋", required: false)
            ForEach(AgentPreset.grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: 4) {
                    if group.category != .custom {
                        Text(group.category.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textSecondary.opacity(0.6))
                            .padding(.leading, 2)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(group.presets) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: preset.icon)
                                        .font(.caption)
                                    Text(preset.name)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedPreset?.id == preset.id ? palette.accent.opacity(0.15) : palette.inputBackground)
                                .foregroundColor(selectedPreset?.id == preset.id ? palette.accent : palette.textSecondary)
                                .continuousRadius(DesignTokens.Radius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                                        .strokeBorder(selectedPreset?.id == preset.id ? palette.accent.opacity(0.4) : .clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 에이전트 카드 섹션

    @ViewBuilder
    private var agentCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("전문 분야 태그", required: false)
            TextField("쉼표로 구분 (예: spring, java, api, 백엔드)", text: $skillTagsText)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(10)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                    .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))

            // 고급 설정: 작업 모드
            DisclosureGroup(isExpanded: $showAdvancedCard) {
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(spacing: 6) {
                        ForEach(WorkMode.allCases, id: \.self) { mode in
                            ToggleChip(label: mode.displayName, isSelected: selectedWorkModes.contains(mode)) {
                                if selectedWorkModes.contains(mode) {
                                    selectedWorkModes.remove(mode)
                                } else {
                                    selectedWorkModes.insert(mode)
                                }
                            }
                        }
                    }
                    Text("역할 배정과 도구 접근 권한에 영향을 줍니다. 프리셋 선택 시 자동 설정됩니다.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.top, 4)
            } label: {
                Label("작업 모드", systemImage: "gearshape.2")
                    .font(.system(size: DesignTokens.FontSize.sm, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            }
            .disclosureGroupStyle(PlainDisclosureStyle())
        }
    }

    // MARK: - 프리셋 적용

    private func applyPreset(_ preset: AgentPreset) {
        selectedPreset = preset
        skillTagsText = preset.tags.joined(separator: ", ")
        selectedWorkModes = preset.modes
        selectedOutputStyles = preset.outputs
        if !preset.modes.isEmpty { showAdvancedCard = true }
    }

    // MARK: - 작업 규칙 섹션

    @ViewBuilder
    private var workingRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("작업 규칙", required: true)

            if workRules.isEmpty && showValidation {
                Label("규칙을 최소 하나 추가해야 에이전트를 추가할 수 있습니다.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // 규칙 레코드 리스트
            if !workRules.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(workRules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(rule.name)
                                        .font(.system(size: DesignTokens.FontSize.sm, weight: .medium))
                                    if rule.isAlwaysActive {
                                        Text("항상")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(palette.accent)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(palette.accent.opacity(0.12))
                                            .continuousRadius(4)
                                    }
                                }
                                if !rule.summary.isEmpty {
                                    Text(rule.summary)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button {
                                editingRule = rule
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundColor(palette.textSecondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            Button {
                                workRules.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        if index < workRules.count - 1 {
                            Rectangle()
                                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 1)
                                .padding(.leading, 10)
                        }
                    }
                }
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }

            Button { showAddRule = true } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("규칙 추가")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(palette.inputBackground)
                .continuousRadius(DesignTokens.Radius.lg)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showAddRule) {
            WorkRuleEditSheet { rule in
                workRules.append(rule)
            }
        }
        .sheet(item: $editingRule) { rule in
            WorkRuleEditSheet(existingRule: rule) { updated in
                if let idx = workRules.firstIndex(where: { $0.id == updated.id }) {
                    workRules[idx] = updated
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
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(palette.avatarFallback)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(.secondary.opacity(0.6))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1.5))
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
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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

    private func validationHint(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundColor(.orange)
            .transition(.opacity.combined(with: .move(edge: .top)))
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

    // MARK: - Logic

    private var isFormValid: Bool {
        !name.isEmpty && !persona.isEmpty && !selectedModel.isEmpty && !isDuplicateName && !workRules.isEmpty
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

    private var parsedSkillTags: [String] {
        skillTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func addAgent() {
        let agent = Agent(
            name: name,
            persona: persona,
            providerName: selectedProvider,
            modelName: selectedModel,
            imageData: imageData,
            referenceProjectPaths: referenceProjectPaths,
            workRules: workRules,
            skillTags: parsedSkillTags,
            workModes: selectedWorkModes,
            outputStyles: selectedOutputStyles
        )
        agentStore.addAgent(agent)

        if let onCreated {
            onCreated(agent)
        }

        dismiss()
    }
}
