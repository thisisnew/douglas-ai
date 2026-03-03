import SwiftUI

/// 통합 설정 윈도우 — API 설정 / 테마 / 플러그인 탭
struct SettingsTabView: View {
    @Environment(\.colorPalette) private var palette
    @State private var selectedTab: SettingsTab = .api

    enum SettingsTab: CaseIterable {
        case api, theme, plugins

        var title: String {
            switch self {
            case .api:     return "API 설정"
            case .theme:   return "테마"
            case .plugins: return "플러그인"
            }
        }

        var icon: String {
            switch self {
            case .api:     return "key.fill"
            case .theme:   return "paintpalette.fill"
            case .plugins: return "puzzlepiece.extension.fill"
            }
        }

        var tint: Color {
            switch self {
            case .api:     return Color(red: 0.55, green: 0.78, blue: 0.85)
            case .theme:   return Color(red: 0.82, green: 0.62, blue: 0.86)
            case .plugins: return Color(red: 0.93, green: 0.73, blue: 0.52)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 커스텀 탭 바
            tabBar

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, palette.separator.opacity(0.25), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // 탭 콘텐츠
            Group {
                switch selectedTab {
                case .api:
                    AddProviderSheet(isEmbedded: true)
                case .theme:
                    ThemeSettingsView(isEmbedded: true)
                case .plugins:
                    PluginSettingsView(isEmbedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            width: DesignTokens.WindowSize.settingsSheet.width,
            height: DesignTokens.WindowSize.settingsSheet.height
        )
    }

    // MARK: - 탭 바

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.dgSpring) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? tab.tint : palette.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tab.tint.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? tab.tint.opacity(0.25) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
