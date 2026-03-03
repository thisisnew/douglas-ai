import SwiftUI
import Combine

/// 테마 상태 관리 — 현재 테마 선택 및 커스텀 색상을 UserDefaults에 영속화
@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentThemeID: ThemeID {
        didSet { save() }
    }
    @Published var customAccentColor: Color {
        didSet { save() }
    }

    var currentPalette: ColorPalette {
        ThemePresets.palette(for: currentThemeID, customAccent: customAccentColor)
    }

    private let defaults: UserDefaults
    private static let themeIDKey = "selectedThemeID"
    private static let customAccentKey = "customAccentHex"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: Self.themeIDKey),
           let id = ThemeID(rawValue: raw) {
            self.currentThemeID = id
        } else {
            self.currentThemeID = .cozyGame
        }

        if let hex = defaults.string(forKey: Self.customAccentKey) {
            self.customAccentColor = Color(hex: hex)
        } else {
            self.customAccentColor = Color(red: 0.70, green: 0.55, blue: 0.82)
        }
    }

    private func save() {
        defaults.set(currentThemeID.rawValue, forKey: Self.themeIDKey)
        defaults.set(customAccentColor.toHex(), forKey: Self.customAccentKey)
    }
}
