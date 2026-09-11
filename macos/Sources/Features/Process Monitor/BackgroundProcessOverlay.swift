import SwiftUI

struct BackgroundProcessOverlay: View {
    var jobs: [TerminalJob] = []
    var tasks: [BackgroundTaskItem] = []
    var onKillJob: ((TerminalJob) -> Void)? = nil
    var onCancelTask: ((BackgroundTaskItem) -> Void)? = nil

    @State private var isHovered = false

    // Popover explainer text
    @State private var isPopover = false

    private var totalCount: Int {
        jobs.count + tasks.count
    }

    var body: some View {
        Image(systemName: "platter.2.filled.iphone.landscape")
            .resizable()
            .scaledToFit()
            .frame(width: 19, height: 19)
            .foregroundColor(.black)
            .frame(width: 35, height: 35)
            .background(GhosttyOverlayBackground(cornerRadius: 12, isPermanent: true))
            .overlay(alignment: .topTrailing) {
                if totalCount > 1 {
                    Text("\(totalCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                isPopover = true
            }
            .backport.pointerStyle(.link)
            .help("Background Tasks & Processes (\(totalCount))")
            .popover(isPresented: $isPopover, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "platter.2.filled.iphone.landscape")
                            .foregroundColor(.accentColor)
                        Text("Actividad en Background (\(totalCount))")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                    }

                    Divider()

                    if totalCount == 0 {
                        Text("No hay tareas ni procesos en segundo plano.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                // Background Tasks from BackgroundTaskManager
                                if !tasks.isEmpty {
                                    Text("BACKGROUND TASKS (\(tasks.count))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)

                                    ForEach(tasks) { task in
                                        HStack(alignment: .center, spacing: 8) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(task.title)
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .lineLimit(1)
                                                    Text(task.durationString)
                                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.secondary.opacity(0.15))
                                                        .cornerRadius(4)
                                                }
                                                Text(task.command)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }

                                            Spacer(minLength: 8)

                                            Button(role: .destructive) {
                                                onCancelTask?(task)
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "stop.circle.fill")
                                                        .font(.system(size: 10))
                                                    Text("Stop")
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.red.opacity(0.85))
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Detener tarea")
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }

                                if !tasks.isEmpty && !jobs.isEmpty {
                                    Divider()
                                }

                                // Shell jobs from TerminalProcessMonitor
                                if !jobs.isEmpty {
                                    Text("TERMINAL PROCESSES (\(jobs.count))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)

                                    ForEach(jobs) { job in
                                        HStack(alignment: .center, spacing: 8) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(job.name)
                                                        .font(.system(size: 12, weight: .semibold))
                                                    Text("PID \(job.pid)")
                                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.secondary.opacity(0.15))
                                                        .cornerRadius(4)
                                                }
                                                if let cmd = job.commandLine, !cmd.isEmpty {
                                                    Text(cmd)
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }

                                            Spacer(minLength: 8)

                                            Button(role: .destructive) {
                                                onKillJob?(job)
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
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(14)
                .frame(minWidth: 280, maxWidth: 360)
            }
    }
}
