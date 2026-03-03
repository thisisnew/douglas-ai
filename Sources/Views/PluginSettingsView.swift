import SwiftUI

/// 플러그인 관리 팝오버 — 플러그인 목록 + 활성화 토글 + 설정
struct PluginSettingsView: View {
    @EnvironmentObject var pluginManager: PluginManager
    @Environment(\.colorPalette) private var palette

    @State private var expandedPluginID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("플러그인")
                .font(.system(size: DesignTokens.FontSize.icon, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            if pluginManager.plugins.isEmpty {
                Text("설치된 플러그인이 없습니다.")
                    .font(.system(size: DesignTokens.FontSize.body, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            } else {
                ForEach(pluginManager.plugins, id: \.info.id) { plugin in
                    pluginRow(plugin)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
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
                    Text(plugin.info.name)
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
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

            // 설정 펼치기 버튼
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

                if expandedPluginID == plugin.info.id {
                    PluginConfigEditor(pluginID: plugin.info.id, fields: plugin.configFields)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
