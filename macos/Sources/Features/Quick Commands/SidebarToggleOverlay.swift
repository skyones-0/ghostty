import SwiftUI

/// A minimalist, floating sidebar toggle button matching the Option A overlay design language.
struct SidebarToggleOverlay: View {
    let isShowing: Bool
    let onToggle: () -> Void

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
            .background(GhosttyOverlayBackground(cornerRadius: 12, isPermanent: false, isActive: isActive))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onToggle()
            }
            .backport.pointerStyle(.link)
            .help(isShowing ? "Hide Quick Commands (⌘⇧B)" : "Show Quick Commands (⌘⇧B)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isShowing ? "Hide Quick Commands" : "Show Quick Commands")
            .accessibilityAddTraits(.isButton)
    }
}
