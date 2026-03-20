import SwiftUI

/// 플러그인 관리 — 플러그인 목록 + 활성화 토글 + 설정 + 설치/제거
struct PluginSettingsView: View {
    var isEmbedded = false

    @EnvironmentObject var pluginManager: PluginManager
    @Environment(\.colorPalette) private var palette

    @State private var expandedPluginID: String?
    @State private var installMessage: String?
    @State private var showBuilder = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더 + 설치 버튼
            HStack {
                Text("플러그인")
                    .font(.system(size: DesignTokens.FontSize.icon, weight: .bold, design: .rounded))
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Button { showBuilder = true } label: {
                    Label("만들기", systemImage: "hammer")
                        .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(palette.textSecondary)

                Button {
                    installFromFolder()
                } label: {
                    Label("설치", systemImage: "plus.circle")
                        .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(palette.textSecondary)
            }

            // 설치 결과 메시지
            if let msg = installMessage {
                Text(msg)
                    .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                    .foregroundColor(msg.contains("실패") || msg.contains("찾을 수") ? .red.opacity(0.8) : .green.opacity(0.8))
                    .transition(.opacity)
            }

            // 추천 플러그인 프리셋
            presetSection

            // 설치된 플러그인
            if pluginManager.plugins.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 24))
                        .foregroundColor(palette.textSecondary.opacity(0.4))
                    Text("설치된 플러그인이 없습니다.")
                        .font(.system(size: DesignTokens.FontSize.body, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                    Text("plugin.json이 포함된 폴더를 선택해 설치하세요.")
                        .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                        .foregroundColor(palette.textSecondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(pluginManager.plugins, id: \.info.id) { plugin in
                    pluginRow(plugin)
                }
            }
        }
        .padding(isEmbedded ? 24 : 16)
        }
        .frame(width: isEmbedded ? nil : 320)
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
        .sheet(isPresented: $showBuilder) {
            PluginBuilderSheet()
                .environmentObject(pluginManager)
        }
    }

    // MARK: - 추천 플러그인 프리셋

    @ViewBuilder
    private var presetSection: some View {
        let uninstalled = PluginPreset.builtIn.filter { !pluginManager.isPresetInstalled($0.id) }
        if !uninstalled.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("추천 플러그인")
                    .font(.system(size: DesignTokens.FontSize.sm, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.textSecondary)

                ForEach(uninstalled) { preset in
                    HStack(spacing: 10) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 16))
                            .foregroundColor(palette.accent)
                            .frame(width: 28, height: 28)
                            .background(palette.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.system(size: DesignTokens.FontSize.body, weight: .medium, design: .rounded))
                                .foregroundColor(palette.textPrimary)
                            Text(preset.description)
                                .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            let result = pluginManager.installPreset(preset)
                            installMessage = result.success ? "✅ \(preset.name) 설치 완료" : result.message
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { installMessage = nil }
                        } label: {
                            Text("설치")
                                .font(.system(size: DesignTokens.FontSize.xs, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.userBubbleText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(palette.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 8)

            Rectangle()
                .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.bottom, 4)
        }
    }

    // MARK: - 플러그인 행

    private func pluginRow(_ plugin: any DougPlugin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: plugin.info.iconSystemName)
                    .font(.system(size: 14))
                    .foregroundColor(palette.accent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(plugin.info.name)
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                        // 빌트인 뱃지
                        if !(plugin is ScriptPlugin) {
                            Text("빌트인")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(palette.textSecondary.opacity(0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(palette.cardBorder.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    Text(plugin.info.description)
                        .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { plugin.isActive },
                    set: { newValue in
                        Task {
                            if newValue {
                                _ = await pluginManager.activatePlugin(plugin.info.id)
                            } else {
                                await pluginManager.deactivatePlugin(plugin.info.id)
                            }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // 설정 + 제거 버튼
            HStack(spacing: 12) {
                if !plugin.configFields.isEmpty {
                    Button {
                        withAnimation(.dgStandard) {
                            expandedPluginID = expandedPluginID == plugin.info.id ? nil : plugin.info.id
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expandedPluginID == plugin.info.id ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .medium))
                            Text("설정")
                                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                // 외부 플러그인만 제거 + 스크립트 열기 가능
                if let scriptPlugin = plugin as? ScriptPlugin {
                    Button {
                        NSWorkspace.shared.open(scriptPlugin.pluginDirectory)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
                            Text("스크립트 열기")
                                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(palette.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Button {
                        Task {
                            _ = await pluginManager.uninstallPlugin(plugin.info.id)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text("제거")
                                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 펼친 설정
            if expandedPluginID == plugin.info.id {
                PluginConfigEditor(pluginID: plugin.info.id, fields: plugin.configFields)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                .fill(palette.panelGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                        .strokeBorder(palette.cardBorder.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - 설치

    private func installFromFolder() {
        let panel = NSOpenPanel()
        panel.title = "플러그인 폴더 선택"
        panel.message = "plugin.json이 포함된 폴더를 선택하세요"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let result = pluginManager.installPlugin(from: url)
        withAnimation(.dgStandard) {
            installMessage = result.message
        }
        // 3초 후 메시지 제거
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.dgStandard) {
                installMessage = nil
            }
        }
    }
}

// MARK: - 설정 에디터

struct PluginConfigEditor: View {
    let pluginID: String
    let fields: [PluginConfigField]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields, id: \.key) { field in
                configFieldView(field)
            }
        }
        .padding(.leading, 8)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func configFieldView(_ field: PluginConfigField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.system(size: DesignTokens.FontSize.xs, weight: .medium, design: .rounded))
                .foregroundColor(palette.textSecondary)

            let binding = Binding<String>(
                get: {
                    PluginConfigStore.getValue(field.key, pluginID: pluginID, isSecret: field.isSecret) ?? ""
                },
                set: { newValue in
                    PluginConfigStore.setValue(
                        newValue.isEmpty ? nil : newValue,
                        key: field.key,
                        pluginID: pluginID,
                        isSecret: field.isSecret
                    )
                }
            )

            switch field.type {
            case .text:
                if field.isSecret {
                    SecureField(field.placeholder, text: binding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DesignTokens.FontSize.xs, design: .monospaced))
                } else {
                    TextField(field.placeholder, text: binding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
                }
            case .multilineText:
                TextField(field.placeholder, text: binding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
                    .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
            case .toggle:
                Toggle(field.label, isOn: Binding(
                    get: { binding.wrappedValue == "true" },
                    set: { binding.wrappedValue = $0 ? "true" : "false" }
                ))
                .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
            case .picker(let options):
                Picker("", selection: binding) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .font(.system(size: DesignTokens.FontSize.xs, design: .rounded))
            }
        }
    }
}
