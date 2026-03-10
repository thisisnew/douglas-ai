import SwiftUI

// MARK: - Environment Key

private struct ColorPaletteKey: EnvironmentKey {
    static let defaultValue: ColorPalette = ThemePresets.pastel
}

extension EnvironmentValues {
    var colorPalette: ColorPalette {
        get { self[ColorPaletteKey.self] }
        set { self[ColorPaletteKey.self] = newValue }
    }
}

// MARK: - 테마 적용 래퍼

/// ThemeManager의 currentPalette 변경 시 자동으로 Environment를 갱신하는 래퍼 뷰
struct ThemedView<Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.colorPalette, themeManager.currentPalette)
            .tint(themeManager.currentPalette.accent)
            .fontDesign(.rounded)
            // DOUGLAS는 자체 테마를 사용하므로 시스템 다크모드와 독립적으로 라이트 모드 강제
            .preferredColorScheme(themeManager.currentThemeID == .dark ? .dark : .light)
    }
}
