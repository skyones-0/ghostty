import SwiftUI

struct BackgroundProcessOverlay: View {
    let jobs: [TerminalJob]
    let onKill: (TerminalJob) -> Void

    // Animations
    @State private var gradientAngle: Angle = .degrees(0)
    @State private var gradientOpacity: CGFloat = 0.5

    // Popover explainer text
    @State private var isPopover = false

    var body: some View {
        Image(systemName: "gearshape.2.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 19, height: 19)
            .foregroundColor(.black)
            .frame(width: 35, height: 35)
            .background(
                Rectangle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(
                                colors: [.purple, .blue, .cyan, .blue, .purple]
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
            .overlay(alignment: .topTrailing) {
                if jobs.count > 1 {
                    Text("\(jobs.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                isPopover = true
            }
            .backport.pointerStyle(.link)
            .popover(isPresented: $isPopover, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2.fill")
                            .foregroundColor(.purple)
                        Text("Procesos en Background (\(jobs.count))")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                    }

                    Divider()

                    if jobs.isEmpty {
                        Text("No hay procesos en segundo plano.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(jobs) { job in
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(job.name)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("PID \(job.pid)")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15))
                                            .cornerRadius(4)
                                        if job.isActive {
                                            Text("active")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.purple)
                                        }
                                    }
                                    if let cmd = job.commandLine, !cmd.isEmpty {
                                        Text(cmd)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: 8)

                                Button(role: .destructive) {
                                    onKill(job)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                        Text("Kill")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.85))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Terminar proceso (SIGTERM/SIGKILL)")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(14)
                .frame(minWidth: 280, maxWidth: 360)
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
