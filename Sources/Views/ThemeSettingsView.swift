import SwiftUI

/// 테마 선택 팝오버 — 프리셋 3종 + 커스텀 액센트 컬러
struct ThemeSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("테마")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            // 프리셋 선택
            HStack(spacing: 12) {
                ForEach(ThemeID.allCases.filter { $0 != .custom }, id: \.self) { themeID in
                    themeCard(themeID)
                }
            }

            Divider()

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
        .padding(16)
        .frame(width: 280)
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
                .continuousRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? previewPalette.accent : Color.clear, lineWidth: 2)
                )

                Text(themeID.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? palette.accent : palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}
