import SwiftUI
import AppKit

struct AgentAvatarView: View {
    @Environment(\.colorPalette) private var palette
    let agent: Agent
    var size: CGFloat = 32

    private var avatarRadius: CGFloat {
        size * DesignTokens.CozyGame.avatarRadiusRatio
    }

    private var avatarShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: avatarRadius, style: .continuous)
    }

    var body: some View {
        if let data = agent.imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(avatarShape)
                .overlay(
                    avatarShape.strokeBorder(palette.avatarBorder.opacity(0.4), lineWidth: 1.5)
                )
        } else if agent.isMaster, let profileImage = masterProfileImage {
            Image(nsImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(avatarShape)
                .overlay(
                    avatarShape.strokeBorder(palette.avatarBorder.opacity(0.4), lineWidth: 1.5)
                )
        } else {
            avatarShape
                .fill(
                    LinearGradient(
                        colors: [defaultBackgroundColor.opacity(0.15), defaultBackgroundColor.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: defaultIconName)
                        .font(.system(size: size * 0.45, weight: .medium, design: .rounded))
                        .foregroundColor(defaultIconColor)
                )
                .overlay(
                    avatarShape.strokeBorder(palette.avatarBorder.opacity(0.3), lineWidth: 1.5)
                )
        }
    }

    /// 번들에서 douglas_profile.png 로드 (마스터 기본 아바타용)
    private var masterProfileImage: NSImage? {
        if let url = Bundle.appModule?.url(forResource: "douglas_profile", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "douglas_profile", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    private var defaultIconName: String {
        if agent.isMaster { return "brain.head.profile" }
        return "person.crop.circle"
    }

    private var defaultIconColor: Color {
        if agent.isMaster { return .purple }
        return .blue
    }

    private var defaultBackgroundColor: Color {
        if agent.isMaster { return .purple }
        return .blue
    }
}

/// NSOpenPanel 기반 이미지 선택 → 128x128 PNG Data
func pickAgentImage() -> Data? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = "에이전트 아바타 이미지를 선택하세요"
    guard panel.runModal() == .OK, let url = panel.url,
          let nsImage = NSImage(contentsOf: url) else {
        return nil
    }
    return resizedPNGData(from: nsImage, size: CGSize(width: 128, height: 128))
}

private func resizedPNGData(from image: NSImage, size: CGSize) -> Data? {
    let newImage = NSImage(size: size)
    newImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    newImage.unlockFocus()

    guard let tiffData = newImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}
