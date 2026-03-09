import SwiftUI
import AppKit

struct EditAgentSheet: View {
    @Environment(\.colorPalette) private var palette
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

    // 작업 규칙 (레코드 단위)
    @State private var workRules: [WorkRule]
    @State private var editingRule: WorkRule?
    @State private var showAddRule = false

    // Plan C: 에이전트 카드 메타데이터
    @State private var skillTagsText: String
    @State private var selectedWorkModes: Set<WorkMode>
    @State private var selectedOutputStyles: Set<OutputStyle>
    @State private var showAdvancedCard: Bool

    init(agent: Agent) {
        self.agent = agent
        _name = State(initialValue: agent.name)
        _persona = State(initialValue: agent.persona)
        _selectedProvider = State(initialValue: agent.providerName)
        _selectedModel = State(initialValue: agent.modelName)
        _imageData = State(initialValue: agent.imageData)
        _referenceProjectPaths = State(initialValue: agent.referenceProjectPaths)

        // 작업 규칙 초기화 (레코드)
        _workRules = State(initialValue: agent.workRules)

        // Plan C: 에이전트 카드 초기화
        _skillTagsText = State(initialValue: agent.skillTags.joined(separator: ", "))
        _selectedWorkModes = State(initialValue: agent.workModes)
        _selectedOutputStyles = State(initialValue: agent.outputStyles)
        _showAdvancedCard = State(initialValue: !agent.workModes.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavHeader(title: "에이전트 수정") {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            } trailing: {
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.userBubbleText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.accent, in: Capsule())
                    .contentShape(Capsule())
                    .opacity(isFormValid ? 1 : 0.5)
                    .disabled(!isFormValid)
            }

            ScrollView {
                VStack(spacing: 28) {
                    // 아바타
                    avatarPicker
                        .padding(.top, 8)

                    // 이름
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("이름", required: true)
                        if agent.isMaster {
                            Text(name)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.surfaceTertiary)
                                .continuousRadius(DesignTokens.Radius.lg)
                        } else {
                            TextField("예) 백엔드 개발자, QA 담당, UI 디자이너", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .padding(10)
                                .background(palette.inputBackground)
                                .continuousRadius(DesignTokens.CozyGame.cardRadius)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))
                        }
                    }

                    // 역할 설명
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("역할 설명", required: true)
                        FormTextEditor(text: $persona, font: .systemFont(ofSize: 13))
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(palette.inputBackground)
                            .continuousRadius(DesignTokens.CozyGame.cardRadius)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous).strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1))
                    }

                    // 작업 규칙 (마스터가 아닌 경우만)
                    if !agent.isMaster {
                        workingRulesSection

                        // 에이전트 카드 메타데이터 (Plan C)
                        agentCardSection
                    }

                    // 모델 설정 (그룹 카드)
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("모델", required: true)

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
        .frame(width: DesignTokens.WindowSize.agentSheet.width)
        .frame(minHeight: DesignTokens.WindowSize.agentSheet.height, maxHeight: .infinity)
        .onAppear {
            loadModels(for: selectedProvider)
        }
        .onChange(of: selectedProvider) { newValue in
            selectedModel = ""
            availableModels = []
            if !newValue.isEmpty { loadModels(for: newValue) }
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
                                if selectedWorkModes.contains(mode) { selectedWorkModes.remove(mode) }
                                else { selectedWorkModes.insert(mode) }
                            }
                        }
                    }
                    Text("역할 배정과 도구 접근 권한에 영향을 줍니다.")
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

    // MARK: - 작업 규칙 섹션

    @ViewBuilder
    private var workingRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("작업 규칙", required: true)

            if workRules.isEmpty {
                Label("규칙을 추가하면 태스크에 맞는 규칙만 자동 적용됩니다.",
                      systemImage: "lightbulb")
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
                            Image(systemName: agent.isMaster ? "brain.head.profile" : "person.fill")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(agent.isMaster ? .purple.opacity(0.6) : .secondary.opacity(0.6))
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
        let baseValid = !name.isEmpty && !persona.isEmpty
        if agent.isMaster { return baseValid }
        // 규칙이 있거나, 기존에도 없었으면 저장 가능
        let hadNoRules = agent.workRules.isEmpty && (agent.workingRules == nil || agent.workingRules!.isEmpty)
        return baseValid && (!workRules.isEmpty || hadNoRules)
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

    private var parsedSkillTags: [String] {
        skillTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
            updated.workRules = workRules
            updated.workingRules = nil  // 레거시 클리어
            updated.skillTags = parsedSkillTags
            updated.workModes = selectedWorkModes
            updated.outputStyles = selectedOutputStyles
        }
        agentStore.updateAgent(updated)
        dismiss()
    }
}
