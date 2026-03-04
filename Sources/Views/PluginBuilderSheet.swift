import SwiftUI

/// 노코드 플러그인 빌더 — 폼 기반으로 스크립트 플러그인 자동 생성
struct PluginBuilderSheet: View {
    @Environment(\.colorPalette) private var palette
    @EnvironmentObject var pluginManager: PluginManager
    @Environment(\.dismiss) private var dismiss

    // 기본 정보
    @State private var name = ""
    @State private var pluginDescription = ""
    // 이벤트 핸들러
    @State private var enabledEvents: Set<PluginEventType> = []
    @State private var handlers: [PluginEventType: HandlerConfig] = [:]

    // 설정 필드
    @State private var configFields: [BuilderConfigField] = []

    // 상태
    @State private var creationError: String?
    @State private var isCreating = false

    // 아이콘 (기본값 고정 — 추후 선택 기능 복원 가능)
    private let defaultIcon = "puzzlepiece.extension"

    var body: some View {
        VStack(spacing: 0) {
            SheetNavHeader(title: "플러그인 만들기") {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            } trailing: {
                Button("만들기") { createPlugin() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.userBubbleText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.accent, in: Capsule())
                    .contentShape(Capsule())
                    .opacity(isFormValid && !isCreating ? 1 : 0.5)
                    .disabled(!isFormValid || isCreating)
            }

            ScrollView {
                VStack(spacing: 28) {
                    basicInfoSection
                    gradientSeparator
                    eventHandlersSection
                    gradientSeparator
                    configFieldsSection

                    if let error = creationError {
                        inlineError(error)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 500, height: 600)
    }

    // MARK: - 기본 정보

    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 이름
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("이름", required: true)
                TextField("예) 작업 완료 알림, Slack 웹훅", text: $name)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(10)
                    .background(palette.inputBackground)
                    .continuousRadius(DesignTokens.CozyGame.cardRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                            .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
                    )
            }

            // 설명
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("설명", required: true)
                TextField("플러그인이 하는 일을 간단히 설명하세요", text: $pluginDescription)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(10)
                    .background(palette.inputBackground)
                    .continuousRadius(DesignTokens.CozyGame.cardRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                            .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - 이벤트 핸들러

    @ViewBuilder
    private var eventHandlersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("이벤트 핸들러", required: true)

            VStack(spacing: 0) {
                ForEach(Array(PluginEventType.allCases.enumerated()), id: \.element.id) { index, eventType in
                    if index > 0 {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, palette.separator.opacity(0.3), .clear],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(height: 1)
                            .padding(.leading, 14)
                    }

                    VStack(spacing: 0) {
                        // 이벤트 토글 행
                        HStack(spacing: 8) {
                            Image(systemName: eventType.icon)
                                .font(.system(size: 12))
                                .foregroundColor(enabledEvents.contains(eventType) ? palette.accent : palette.textSecondary.opacity(0.5))
                                .frame(width: 20)

                            Text(eventType.displayName)
                                .font(.system(size: DesignTokens.FontSize.body, weight: .medium, design: .rounded))
                                .foregroundColor(palette.textPrimary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { enabledEvents.contains(eventType) },
                                set: { enabled in
                                    withAnimation(.dgStandard) {
                                        if enabled {
                                            enabledEvents.insert(eventType)
                                            if handlers[eventType] == nil {
                                                handlers[eventType] = HandlerConfig(eventType: eventType)
                                            }
                                        } else {
                                            enabledEvents.remove(eventType)
                                            handlers.removeValue(forKey: eventType)
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        // 활성화된 이벤트의 액션 설정
                        if enabledEvents.contains(eventType), let binding = handlerBinding(for: eventType) {
                            actionConfigView(binding: binding, eventType: eventType)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .background(palette.inputBackground)
            .continuousRadius(DesignTokens.CozyGame.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                    .strokeBorder(palette.cardBorder.opacity(0.15), lineWidth: 1)
            )

            if enabledEvents.isEmpty {
                Label("최소 1개 이벤트를 활성화하세요", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary.opacity(0.7))
            }
        }
    }

    /// 이벤트별 액션 설정 카드
    @ViewBuilder
    private func actionConfigView(binding: Binding<HandlerConfig>, eventType: PluginEventType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 액션 타입 선택
            HStack(spacing: 6) {
                Text("액션")
                    .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)

                Picker("", selection: binding.actionType) {
                    ForEach(PluginActionType.allCases) { action in
                        Label(action.displayName, systemImage: action.icon)
                            .tag(action)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // 액션별 설정 필드
            switch binding.wrappedValue.actionType {
            case .webhook:
                actionTextField(
                    label: "URL",
                    text: binding.webhookURL,
                    placeholder: "https://hooks.slack.com/services/..."
                )

            case .shell:
                actionTextField(
                    label: "명령어",
                    text: binding.shellCommand,
                    placeholder: "echo \"$DOUGLAS_ROOM_TITLE 완료\" >> ~/log.txt",
                    isMonospaced: true
                )

            case .notification:
                actionTextField(
                    label: "제목",
                    text: binding.notifTitle,
                    placeholder: "DOUGLAS"
                )
                actionTextField(
                    label: "내용",
                    text: binding.notifBody,
                    placeholder: "$DOUGLAS_ROOM_TITLE 작업이 완료되었습니다"
                )
            }

            // 사용 가능 변수 캡슐
            variableCapsules(for: eventType)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.panelGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.cardBorder.opacity(0.1), lineWidth: 1)
        )
    }

    /// 설정 입력 필드
    private func actionTextField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        isMonospaced: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                .foregroundColor(palette.textSecondary)
                .frame(width: 40, alignment: .trailing)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.FontSize.xs, design: isMonospaced ? .monospaced : .rounded))
                .padding(6)
                .background(palette.inputBackground.opacity(0.6))
                .continuousRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.1), lineWidth: 1)
                )
        }
    }

    /// 사용 가능한 환경 변수 캡슐
    @ViewBuilder
    private func variableCapsules(for eventType: PluginEventType) -> some View {
        let vars = eventType.availableVariables
        VStack(alignment: .leading, spacing: 4) {
            Text("변수")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(palette.textSecondary.opacity(0.6))

            FlowLayout(spacing: 4) {
                ForEach(vars, id: \.self) { variable in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(variable, forType: .string)
                    } label: {
                        Text(variable)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(palette.accent.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.accent.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("클릭하여 복사")
                }
            }
        }
    }

    // MARK: - 설정 필드

    @ViewBuilder
    private var configFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("설정 필드", required: false)

            ForEach(Array(configFields.enumerated()), id: \.element.id) { index, _ in
                configFieldRow(index: index)
            }

            Button {
                withAnimation(.dgStandard) {
                    configFields.append(BuilderConfigField())
                }
            } label: {
                Label("필드 추가", systemImage: "plus.circle")
                    .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                    .foregroundColor(palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// 설정 필드 행
    @ViewBuilder
    private func configFieldRow(index: Int) -> some View {
        HStack(spacing: 6) {
            TextField("key", text: $configFields[index].key)
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.FontSize.xs, design: .monospaced))
                .padding(6)
                .background(palette.inputBackground)
                .continuousRadius(6)
                .frame(width: 100)

            TextField("라벨", text: $configFields[index].label)
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                .padding(6)
                .background(palette.inputBackground)
                .continuousRadius(6)

            Toggle("", isOn: $configFields[index].isSecret)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("비밀 값 (키체인 저장)")

            Image(systemName: configFields[index].isSecret ? "lock.fill" : "lock.open")
                .font(.system(size: 9))
                .foregroundColor(configFields[index].isSecret ? palette.accent : palette.textSecondary.opacity(0.4))

            Button {
                withAnimation(.dgStandard) {
                    _ = configFields.remove(at: index as Int)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSecondary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 1)
                .opacity(0.1)
                .padding(-4)
        )
    }

    // MARK: - 생성

    private func createPlugin() {
        isCreating = true
        creationError = nil

        // ID 생성 (충돌 시 재시도)
        var pluginID = PluginSlug.generate(from: name)
        var attempts = 0
        while pluginManager.isIDTaken(pluginID) && attempts < 5 {
            pluginID = PluginSlug.generate(from: name)
            attempts += 1
        }

        if pluginManager.isIDTaken(pluginID) {
            creationError = "플러그인 ID 생성 실패 — 다른 이름을 시도하세요"
            isCreating = false
            return
        }

        // 핸들러 목록
        let activeHandlers = enabledEvents.compactMap { handlers[$0] }

        // 매니페스트 생성
        let manifest = ScriptGenerator.generateManifest(
            id: pluginID,
            name: name.trimmingCharacters(in: .whitespaces),
            description: pluginDescription.trimmingCharacters(in: .whitespaces),
            icon: defaultIcon,
            handlers: activeHandlers,
            configFields: configFields
        )

        // 스크립트 생성
        let scripts = activeHandlers.map { handler in
            (filename: handler.eventType.scriptFileName, content: ScriptGenerator.generate(handler: handler))
        }

        // 설치
        let result = pluginManager.createPlugin(manifest: manifest, scripts: scripts)

        if result.success {
            dismiss()
        } else {
            creationError = result.message
            isCreating = false
        }
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        let nameOK = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let descOK = !pluginDescription.trimmingCharacters(in: .whitespaces).isEmpty
        let hasHandlers = !enabledEvents.isEmpty

        // 각 핸들러의 필수 필드 확인
        let handlersValid = enabledEvents.allSatisfy { event in
            guard let config = handlers[event] else { return false }
            switch config.actionType {
            case .webhook:      return !config.webhookURL.trimmingCharacters(in: .whitespaces).isEmpty
            case .shell:        return !config.shellCommand.trimmingCharacters(in: .whitespaces).isEmpty
            case .notification: return !config.notifTitle.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }

        return nameOK && descOK && hasHandlers && handlersValid
    }

    private func handlerBinding(for eventType: PluginEventType) -> Binding<HandlerConfig>? {
        guard handlers[eventType] != nil else { return nil }
        return Binding(
            get: { handlers[eventType] ?? HandlerConfig(eventType: eventType) },
            set: { handlers[eventType] = $0 }
        )
    }

    private var gradientSeparator: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, palette.separator.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
    }

    private func inlineError(_ text: String) -> some View {
        Label(text, systemImage: "xmark.circle")
            .font(.caption)
            .foregroundColor(.red)
    }
}

// FlowLayout은 DesignTokens.swift에 정의됨
