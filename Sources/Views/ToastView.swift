import SwiftUI

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: DesignTokens.FontSize.icon, weight: .medium, design: .rounded))
            Text(message)
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CozyGame.buttonRadius, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(hex: "F06878"), Color(hex: "D4485A")],
                                   startPoint: .top, endPoint: .bottom)
                )
        )
        .shadow(color: Color(hex: "D4485A").opacity(0.3), radius: 8, y: 4)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if isShowing {
                ToastView(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.dgSlow, value: isShowing)
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message))
    }
}
