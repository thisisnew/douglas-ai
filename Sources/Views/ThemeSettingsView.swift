import SwiftUI

/// 테마 선택 팝오버 — 프리셋 3종 + 커스텀 액센트 컬러
struct ThemeSettingsView: View {
    var isEmbedded = false

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !isEmbedded {
                    Text("테마")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                }

                // 프리셋 선택
                themeGrid

                Rectangle()
                    .fill(LinearGradient(colors: [.clear, palette.separator.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)

                // 커스텀 섹션
                HStack(spacing: 12) {
                    themeCard(.custom)

                    if themeManager.currentThemeID == .custom {
                        ColorPicker("", selection: $themeManager.customAccentColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(isEmbedded ? 24 : 16)
        }
        .frame(width: isEmbedded ? nil : 280)
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
    }

    private var themeGrid: some View {
        let columns = isEmbedded
            ? [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12)]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ThemeID.allCases.filter { $0 != .custom }, id: \.self) { themeID in
                themeCard(themeID)
            }
        }
    }

    private func themeCard(_ themeID: ThemeID) -> some View {
        let previewPalette = ThemePresets.palette(for: themeID, customAccent: themeManager.customAccentColor)
        let isSelected = themeManager.currentThemeID == themeID

        return Button {
            withAnimation(.dgStandard) {
                themeManager.currentThemeID = themeID
            }
        } label: {
            VStack(spacing: 6) {
                // 미니 프리뷰 스와치
                if themeID == .cozyGame {
                    // 코지 게임: 그라데이션 스와치
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(previewPalette.panelGradient)
                        .frame(width: 52, height: 24)
                        .overlay(
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(previewPalette.accent)
                                    .frame(width: 8, height: 8)
                                Circle()
                                    .fill(previewPalette.statusWorking)
                                    .frame(width: 8, height: 8)
                                Circle()
                                    .fill(previewPalette.roomCompleted)
                                    .frame(width: 8, height: 8)
                            }
                        )
                        .padding(6)
                        .background(previewPalette.surfaceSecondary)
                        .continuousRadius(DesignTokens.CozyGame.cardRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                                .strokeBorder(isSelected ? previewPalette.accent : palette.cardBorder.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        )
                        .shadow(color: isSelected ? previewPalette.buttonShadow.opacity(0.2) : .clear, radius: 3, y: 2)
                } else {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(previewPalette.background)
                            .frame(width: 16, height: 24)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(previewPalette.accent)
                            .frame(width: 16, height: 24)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(previewPalette.inputBackground)
                            .frame(width: 16, height: 24)
                    }
                    .padding(6)
                    .background(previewPalette.surfaceSecondary)
                    .continuousRadius(DesignTokens.CozyGame.cardRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CozyGame.cardRadius, style: .continuous)
                            .strokeBorder(isSelected ? previewPalette.accent : palette.cardBorder.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? previewPalette.buttonShadow.opacity(0.2) : .clear, radius: 3, y: 2)
                }

                Text(themeID.displayName)
                    .font(.system(.caption, design: .rounded).weight(isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? palette.accent : palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}
