import SwiftUI

/// 카테고리별 선호 모델 매핑 설정
struct ModelMappingSettingsView: View {
    var isEmbedded = false

    @EnvironmentObject private var providerManager: ProviderManager
    @Environment(\.colorPalette) private var palette
    @State private var mappings: [AgentCategory: ModelPreferences.Mapping] = [:]
    @State private var hasChanges = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !isEmbedded {
                    Text("모델 매핑")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                }

                Text("에이전트 카테고리별로 선호 모델을 지정합니다. 설정하지 않으면 에이전트의 기본 모델을 사용합니다.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(palette.textSecondary)

                ForEach(AgentCategory.allCases, id: \.self) { category in
                    categoryRow(category)
                }

                if hasChanges {
                    saveResetButtons
                }
            }
            .padding(24)
        }
        .onAppear { mappings = ModelPreferences.all() }
    }

    // MARK: - 저장/초기화 버튼

    private var saveResetButtons: some View {
        HStack {
            Spacer()
            Button("저장") {
                ModelPreferences.setAll(mappings)
                hasChanges = false
            }
            .buttonStyle(CozyButtonStyle(.accent))

            Button("초기화") {
                mappings = [:]
                ModelPreferences.setAll([:])
                hasChanges = false
            }
            .buttonStyle(CozyButtonStyle(.cream))
        }
    }

    // MARK: - 카테고리 행

    @ViewBuilder
    private func categoryRow(_ category: AgentCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryHeader(category)
            categoryControls(category)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.separator.opacity(0.2), lineWidth: 1)
        )
    }

    private func categoryHeader(_ category: AgentCategory) -> some View {
        HStack(spacing: 8) {
            categoryIcon(category)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.textPrimary)
                Text(category.description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()
        }
    }

    private func categoryControls(_ category: AgentCategory) -> some View {
        HStack(spacing: 10) {
            // 프로바이더 선택
            Picker("", selection: providerBinding(for: category)) {
                Text("기본값").tag("")
                ForEach(providerManager.configs, id: \.name) { config in
                    Text(config.name).tag(config.name)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            // 모델명 입력
            TextField("모델명 (예: claude-sonnet-4-6)", text: modelBinding(for: category))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            // 추천 모델 버튼
            suggestedModelMenu(category)
        }
    }

    private func suggestedModelMenu(_ category: AgentCategory) -> some View {
        Menu {
            ForEach(category.suggestedModels, id: \.model) { suggestion in
                Button("\(suggestion.provider) / \(suggestion.model)") {
                    mappings[category] = .init(provider: suggestion.provider, model: suggestion.model)
                    hasChanges = true
                }
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundColor(palette.accent)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
    }

    // MARK: - 바인딩 헬퍼

    private func providerBinding(for category: AgentCategory) -> Binding<String> {
        Binding(
            get: { mappings[category]?.provider ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    mappings.removeValue(forKey: category)
                } else {
                    let existing = mappings[category]
                    mappings[category] = .init(provider: newValue, model: existing?.model ?? "")
                }
                hasChanges = true
            }
        )
    }

    private func modelBinding(for category: AgentCategory) -> Binding<String> {
        Binding(
            get: { mappings[category]?.model ?? "" },
            set: { newValue in
                if let existing = mappings[category] {
                    mappings[category] = .init(provider: existing.provider, model: newValue)
                } else if !newValue.isEmpty {
                    mappings[category] = .init(provider: "", model: newValue)
                }
                hasChanges = true
            }
        )
    }

    // MARK: - 아이콘

    private func categoryIcon(_ category: AgentCategory) -> some View {
        let (icon, color): (String, Color) = {
            switch category {
            case .coding:    return ("chevron.left.forwardslash.chevron.right", .blue)
            case .reasoning: return ("brain.head.profile.fill", .purple)
            case .quick:     return ("bolt.fill", .orange)
            case .visual:    return ("paintbrush.fill", .pink)
            case .writing:   return ("doc.text.fill", .green)
            }
        }()

        return Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
    }
}
