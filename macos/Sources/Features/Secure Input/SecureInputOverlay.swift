import SwiftUI

struct SecureInputOverlay: View {
    // Animations
    @State private var gradientAngle: Angle = .degrees(0)
    @State private var gradientOpacity: CGFloat = 0.5

    // Popover explainer text
    @State private var isPopover = false

    var body: some View {
        VStack {
            HStack {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        AngularGradient(
                                            gradient: Gradient(
                                                colors: [.cyan, .blue, .yellow, .blue, .cyan]
                                            ),
                                            center: .center,
                                            angle: gradientAngle
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .opacity(gradientOpacity)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                    .onTapGesture {
                        isPopover = true
                    }
                    .backport.pointerStyle(.link)
                    .popover(isPresented: $isPopover, arrowEdge: .bottom) {
                        Text("""
                        Secure Input is active. Secure Input is a macOS security feature that
                        prevents applications from reading keyboard events. This is enabled
                        automatically whenever Ghostty detects a password prompt in the terminal,
                        or at all times if `Ghostty > Secure Keyboard Entry` is active.
                        """)
                        .padding(.all)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }

            Spacer()
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
