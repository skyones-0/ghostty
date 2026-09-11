import SwiftUI

/// Unified glowing animated gradient background used by Ghostty overlays
/// (SecureInput lock, Background Tasks platter, and Sidebar buttons).
public struct GhosttyOverlayBackground: View {
    public var cornerRadius: CGFloat = 12
    public var isPermanent: Bool = true
    public var isActive: Bool = true

    @State private var gradientAngle: Angle = .degrees(0)
    @State private var gradientOpacity: CGFloat = 0.55

    public init(cornerRadius: CGFloat = 12, isPermanent: Bool = true, isActive: Bool = true) {
        self.cornerRadius = cornerRadius
        self.isPermanent = isPermanent
        self.isActive = isActive
    }

    public var body: some View {
        ZStack {
            if !isPermanent {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(isActive ? 0.3 : 0.8)
            }

            Rectangle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(
                            colors: [.cyan, .blue, .yellow, .blue, .cyan]
                        ),
                        center: .center,
                        angle: gradientAngle
                    )
                )
                .blur(radius: 4, opaque: true)
                .opacity(isPermanent ? gradientOpacity : (isActive ? gradientOpacity : 0))
        }
        .mask(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isPermanent ? Color.white.opacity(0.35) : (isActive ? Color.white.opacity(0.35) : Color.primary.opacity(0.12)), lineWidth: 1)
        )
        .onAppear {
            withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                gradientAngle = .degrees(360)
            }
            withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: true)) {
                gradientOpacity = 1.0
            }
        }
    }
}

struct SecureInputOverlay: View {
    @State private var isPopover = false

    var body: some View {
        Image(systemName: "lock.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundColor(.black)
            .frame(width: 35, height: 35)
            .background(GhosttyOverlayBackground(cornerRadius: 12, isPermanent: true))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                isPopover = true
            }
            .backport.pointerStyle(.link)
            .popover(isPresented: $isPopover, arrowEdge: .leading) {
                Text("""
                Secure Input is active. Secure Input is a macOS security feature that
                prevents applications from reading keyboard events. This is enabled
                automatically whenever Ghostty detects a password prompt in the terminal,
                or at all times if `Ghostty > Secure Keyboard Entry` is active.
                """)
                .padding(.all)
            }
    }
}
