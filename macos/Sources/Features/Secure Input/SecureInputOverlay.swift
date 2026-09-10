import SwiftUI

struct SecureInputOverlay: View {
    // Animations
    @State private var gradientAngle: Angle = .degrees(0)
    @State private var gradientOpacity: CGFloat = 0.5

    // Popover explainer text
    @State private var isPopover = false

    var body: some View {
        Image(systemName: "lock.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundColor(.black)
            .frame(width: 35, height: 35)
            .background(
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
                    .opacity(gradientOpacity)
            )
            .mask(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
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
            .onAppear {
                withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                    gradientAngle = .degrees(360)
                }

                withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: true)) {
                    gradientOpacity = 1
                }
            }
    }
}
