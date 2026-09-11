<!-- LOGO -->
<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Logo" width="128">
  <br>Ghostty (macOS ARM Edition)
</h1>
  <p align="center">
    Fast, feature-rich, GPU-accelerated terminal emulator optimized exclusively for <strong>macOS Apple Silicon (ARM64)</strong>.
    <br />
    Native SwiftUI & Metal frontend powered by a high-performance Zig core.
    <br />
    <a href="#about">About</a>
    ·
    <a href="#fork-enhancements">Fork Features</a>
    ·
    <a href="#building-on-macos-arm64">Building</a>
    ·
    <a href="CONTRIBUTING.md">Contributing</a>
    ·
    <a href="HACKING.md">Developing</a>
  </p>
</p>

---

## About

Ghostty is a modern terminal emulator engineered for speed, responsiveness, and native platform integration. This fork ([`skyones-0/ghostty`](https://github.com/skyones-0/ghostty)) is **strictly scoped and optimized exclusively for macOS Apple Silicon (ARM64)**, shedding non-macOS dependencies to deliver an uncompromising developer experience on modern Mac hardware.

### Architecture & Engine Highlights
- **Renderer**: Native Apple Metal GPU pipeline with zero-copy texture streaming.
- **Font Engine**: Native macOS CoreText for subpixel glyph discovery and rendering.
- **UI Architecture**: True AppKit & SwiftUI interface with full windowing, tabs, and splits support.
- **Core Engine**: Zig core with SIMD-accelerated VT parsing and kqueue event loop (`libxev`).

---

## Fork Enhancements

This distribution includes powerful native macOS productivity extensions designed for day-to-day developer workflows:

### ⚡ Quick Commands Sidebar (`⌘⇧B`)
- **1-Click Actions**: Execute (`▶`) or insert (`✎`) commands directly into the active terminal surface.
- **Floating Bottom-Right Toggle**: Minimalist floating toggle button matching macOS design language with animated hover gradient glow.
- **Interactive Parameter Placeholders**: Automatic modals for placeholders like `<host>`, `<branch>`, or `<commit>`.
- **Dynamic Auto-Injection**: Injects live runtime context (`{clipboard}`, `{selection}`).
- **SecureCRT-Style Broadcast Mode**: Send a command simultaneously across all split surfaces in a tab.
- **Keyboard Navigation**: Native arrow navigation (`↑`/`↓`), `Return` to execute, `⌥ Return` to insert, `Escape` to return focus to the terminal.
- **Synced Dotfiles Storage**: Atomic persistence to `~/.config/ghostty/quick-commands.json` with live Darwin filesystem watching.

### 🔌 USB Serial Device Watcher
- **IOKit Hardware Detection**: Automatically detects USB serial devices (microcontrollers, development boards, routers) upon connection.
- **Instant Connection Toast**: Ephemeral floating pill in the terminal with customizable baud rate and 1-click `screen` session launch.

### 🌐 Local Server Port Detector
- **Process Socket Monitoring**: Inspects child processes via Darwin `proc_pidinfo(PROC_PIDTASKINFO)` to detect when local dev servers begin listening on a TCP port.
- **Floating Port Toast**: Ephemeral banner displaying the active port (e.g. `3000`, `8080`, `8787`) with a 1-click button to open directly in the default browser.

### 🔔 Long-Running Command Notifications
- **Background & Desktop Alerts**: Delivers a native notification via `UNUserNotificationCenter` and a terminal floating toast whenever a long-running command (>15s) finishes while the terminal or tab is unfocused.

### ☕ Native Keep Awake (Caffeinate)
- **Menu Bar Sleep Inhibition**: Native macOS menu toggle to prevent the system or display from sleeping during lengthy scripts, builds, or data transfers.

### 📋 Quick Copy Last Command Output (`⌘⇧C`)
- **Instant Clipboard Extraction**: Captures the complete terminal output of the last executed command directly to the macOS clipboard with HUD feedback.

### ⚙️ Real-Time Process & Resource Monitor
- **Background Process Pill**: Live indicator in the top bar displaying running background child processes.
- **Process Popover**: Real-time Darwin CPU metrics and 1-click `SIGTERM` kill actions.

---

## Building on macOS ARM64

### Prerequisites
- macOS 14+ (Sonoma, Sequoia, or newer) on Apple Silicon (M1/M2/M3/M4)
- **Xcode 26** with macOS 26 SDK and Metal Toolchain (`xcode-select -p`)
- **Zig 0.16.0** (`brew install zig`)

### Fast Release Build & Installation

To build the fully-optimized macOS app bundle and install it to `/Applications/Ghostty.app`:

```bash
# Compile ReleaseLocal (ReleaseFast + ad-hoc Sparkle code signing)
zig build -Doptimize=ReleaseFast -Demit-macos-app=true

# Copy to Applications
rm -rf /Applications/Ghostty.app
cp -R macos/build/ReleaseLocal/Ghostty.app /Applications/Ghostty.app
xattr -cr /Applications/Ghostty.app
```

Or run the automated updater script:

```bash
./update-ghostty.sh --install
```

---

## Configuration

Ghostty configurations reside in `~/.config/ghostty/config`. To open the interactive configuration studio:

```bash
ghostty +config
```

For detailed Quick Commands documentation, see [QUICK_COMMANDS.md](macos/QUICK_COMMANDS.md).

---

## License

Ghostty is licensed under the Mozilla Public License 2.0. See [LICENSE](LICENSE) for details.
