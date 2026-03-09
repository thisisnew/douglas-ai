import Testing
import SwiftUI
import AppKit

@testable import DOUGLAS

@Suite("ColorPalette Tests")
struct ColorPaletteTests {

    // MARK: - Color(hex:) 변환

    @Test("Color(hex: \"FF0000\") → red component ≈ 1.0")
    func hexRedColor() {
        let ns = NSColor(Color(hex: "FF0000")).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 1.0) < 0.02)
        #expect(abs(ns.greenComponent - 0.0) < 0.02)
        #expect(abs(ns.blueComponent - 0.0) < 0.02)
    }

    @Test("Color(hex: \"#00FF00\") → # prefix 처리, green ≈ 1.0")
    func hexGreenColorWithHash() {
        let ns = NSColor(Color(hex: "#00FF00")).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0.0) < 0.02)
        #expect(abs(ns.greenComponent - 1.0) < 0.02)
        #expect(abs(ns.blueComponent - 0.0) < 0.02)
    }

    @Test("Color(hex: \"0000FF\") → blue component ≈ 1.0")
    func hexBlueColor() {
        let ns = NSColor(Color(hex: "0000FF")).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0.0) < 0.02)
        #expect(abs(ns.greenComponent - 0.0) < 0.02)
        #expect(abs(ns.blueComponent - 1.0) < 0.02)
    }

    @Test("Color(hex: \"FFFFFF\") → 모든 컴포넌트 ≈ 1.0")
    func hexWhiteColor() {
        let ns = NSColor(Color(hex: "FFFFFF")).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 1.0) < 0.02)
        #expect(abs(ns.greenComponent - 1.0) < 0.02)
        #expect(abs(ns.blueComponent - 1.0) < 0.02)
    }

    @Test("Color(hex: \"\") → 빈 문자열은 black fallback")
    func hexEmptyStringFallback() {
        let ns = NSColor(Color(hex: "")).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0.0) < 0.02)
        #expect(abs(ns.greenComponent - 0.0) < 0.02)
        #expect(abs(ns.blueComponent - 0.0) < 0.02)
    }

    @Test("Color(hex: \"000000\") → 모든 컴포넌트 ≈ 0.0")
    func hexBlackColor() {
        let ns = NSColor(Color(hex: "000000")).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0.0) < 0.02)
        #expect(abs(ns.greenComponent - 0.0) < 0.02)
        #expect(abs(ns.blueComponent - 0.0) < 0.02)
    }

    // MARK: - toHex()

    @Test("toHex() — 알려진 색상의 hex 문자열 변환")
    func toHexKnownColor() {
        let color = Color(.sRGB, red: 1.0, green: 0.0, blue: 0.0, opacity: 1.0)
        #expect(color.toHex() == "#FF0000")
    }

    @Test("roundtrip — Color(hex:).toHex() 왕복 변환")
    func hexRoundtrip() {
        let hex = "FF8FAB"
        let result = Color(hex: hex).toHex()
        #expect(result == "#FF8FAB")
    }

    // MARK: - ThemeID

    @Test("ThemeID.allCases — 5개 케이스")
    func themeIDAllCasesCount() {
        #expect(ThemeID.allCases.count == 5)
    }

    @Test("ThemeID.displayName — 한국어 표시 이름")
    func themeIDDisplayNames() {
        #expect(ThemeID.cozyGame.displayName == "코지 게임")
        #expect(ThemeID.pastel.displayName == "파스텔")
        #expect(ThemeID.dark.displayName == "다크")
        #expect(ThemeID.warmCozy.displayName == "따뜻한")
        #expect(ThemeID.custom.displayName == "커스텀")
    }

    // MARK: - ThemePresets

    @Test("ThemePresets.palette(for: .pastel) — 유효한 accent 색상 팔레트 반환")
    func paletteForPastel() {
        let palette = ThemePresets.palette(for: .pastel)
        // pastel accent = Color(red: 0.70, green: 0.55, blue: 0.82)
        let ns = NSColor(palette.accent).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0.70) < 0.02)
        #expect(abs(ns.greenComponent - 0.55) < 0.02)
        #expect(abs(ns.blueComponent - 0.82) < 0.02)
    }

    @Test("ThemePresets.palette(for:) — 모든 non-custom ID가 크래시 없이 팔레트 반환")
    func paletteForAllNonCustomIDs() {
        let nonCustomIDs = ThemeID.allCases.filter { $0 != .custom }
        for id in nonCustomIDs {
            let palette = ThemePresets.palette(for: id)
            // 각 팔레트가 유효한 accent 색상을 가지는지 확인
            let ns = NSColor(palette.accent).usingColorSpace(.sRGB)!
            #expect(ns.redComponent >= 0.0 && ns.redComponent <= 1.0)
            #expect(ns.greenComponent >= 0.0 && ns.greenComponent <= 1.0)
            #expect(ns.blueComponent >= 0.0 && ns.blueComponent <= 1.0)
        }
    }
}
