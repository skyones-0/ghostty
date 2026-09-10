import SwiftUI

/// A minimalist, floating sidebar toggle button matching the Option A overlay design language.
struct SidebarToggleOverlay: View {
    let isShowing: Bool
    let onToggle: () -> Void

    @State private var gradientAngle: Angle = .degrees(0)
    @State private var isHovered: Bool = false

    private var isActive: Bool {
        isHovered || isShowing
    }

    var body: some View {
        Image(systemName: "sidebar.right")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundColor(isActive ? .black : Color.primary.opacity(0.55))
            .frame(width: 35, height: 35)
            .background(
                ZStack {
                    // Subtle translucent base material for idle state
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .opacity(isActive ? 0.3 : 0.8)

                    // Option A animated glow, active only on hover or when open
                    Rectangle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(
                                    colors: [.cyan, .blue, .indigo, .blue, .cyan]
                                ),
                                center: .center,
                                angle: gradientAngle
                            )
                        )
                        .blur(radius: 4, opaque: true)
                        .opacity(isActive ? 0.85 : 0)
                }
            )
            .mask(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.white.opacity(0.3) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .animation(.easeInOut(duration: 0.2), value: isActive)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    withAnimation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        gradientAngle = .degrees(360)
                    }
                } else if !isShowing {
                    gradientAngle = .degrees(0)
                }
            }
            .onTapGesture {
                onToggle()
            }
            .backport.pointerStyle(.link)
            .help(isShowing ? "Hide Quick Commands (⌘⇧B)" : "Show Quick Commands (⌘⇧B)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isShowing ? "Hide Quick Commands" : "Show Quick Commands")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                if isShowing {
                    withAnimation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        gradientAngle = .degrees(360)
                    }
                }
            }
            .onChange(of: isShowing) { showing in
                if showing || isHovered {
                    withAnimation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        gradientAngle = .degrees(360)
                    }
                } else {
                    gradientAngle = .degrees(0)
                }
            }
    }
}
