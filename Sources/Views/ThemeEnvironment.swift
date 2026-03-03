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
    }
}
