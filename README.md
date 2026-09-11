# 👻 Ghostty (macOS Apple Silicon Edition)

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20(ARM64)-black?logo=apple&style=flat-square)](https://github.com/skyones-0/ghostty)
[![Version](https://img.shields.io/badge/version-1.3.2-blue?style=flat-square)](https://github.com/skyones-0/ghostty/releases/tag/v1.3.2)
[![Renderer](https://img.shields.io/badge/renderer-Metal%20GPU-red?style=flat-square)](https://github.com/skyones-0/ghostty)
[![License](https://img.shields.io/badge/license-MPL%202.0-green?style=flat-square)](LICENSE)

Fast, native, GPU-accelerated terminal emulator engineered **exclusively for macOS Apple Silicon (M1/M2/M3/M4)**.

This distribution ([`skyones-0/ghostty`](https://github.com/skyones-0/ghostty)) brings specialized productivity enhancements tailored for modern developers, hardware hackers, and DevOps engineers on macOS.

---

## 🚀 Download & Quickstart

Pre-built and optimized release binaries are available for direct download:

### [⬇️ **Download Ghostty v1.3.2 for macOS (Apple Silicon ARM64)**](https://github.com/skyones-0/ghostty/releases/download/v1.3.2/Ghostty-macos-arm64-v1.3.2.zip)

> **Installation (Quick 3-Step Setup):**
> 1. Download and extract `Ghostty-macos-arm64-v1.3.2.zip`.
> 2. Move `Ghostty.app` into your `/Applications` directory.
> 3. Remove the macOS quarantine attribute to permit execution:
> ```bash
> xattr -cr /Applications/Ghostty.app
> ```

---

## ✨ Exclusive Features & Enhancements

### 1. ⚡ Quick Commands Sidebar
* **Global Shortcut**: `⌘ ⇧ B` or click the **floating action button** in the bottom-right corner of the terminal window.
* **Minimalist Floating Toggle Button**: Embedded directly in the terminal viewport (`SidebarToggleOverlay`), featuring a translucent glass design and animated neon gradient glow on hover.
* **1-Click Command Execution**:
  * Run directly in the active terminal surface (`▶`).
  * Insert command into the prompt for inspection without executing (`✎`).
  * **Split & Send**: Automatically creates a new horizontal split to the right and executes the command immediately.
* **Interactive Parameter Modals**: Commands containing placeholders (such as `<host>`, `<branch>`, or `<target>`) trigger an interactive modal prompt before execution.
* **Dynamic Context Injection**: Supports dynamic variables like `{clipboard}` (active clipboard content) and `{selection}` (current terminal text selection).
* **Broadcast Mode**: Replicates command execution across **all open terminal splits simultaneously** within the active tab.
* **Full Keyboard Navigation**:
  * `↑` / `↓` arrow keys for circular list navigation.
  * `Return` to execute, `⌥ Return` to insert, and `Escape` to return focus to the terminal.
* **Real-Time Atomic Dotfiles Sync**: Commands are stored in `~/.config/ghostty/quick-commands.json` and synchronized instantaneously across all windows and tabs via Darwin `FSEvents`.

---

### 2. 🔌 USB Serial Device Watcher (Hardware Detection)
* **Real-Time IOKit Monitoring**: Automatically recognizes microcontrollers and serial devices upon connection (ESP32, Arduino, Raspberry Pi Pico, USB UART bridges, FTDI, CH340, CP2102).
* **Ephemeral Floating Toast**: Displays an unobtrusive toast banner at the top of the terminal showing the device name, BSD path (`/dev/cu.usbserial...`), and a baud rate selector (115200, 9600, etc.).
* **1-Click Connect**: Click **Connect** to automatically launch an interactive serial terminal session (`screen <device> <baud>`).

---

### 3. 🌐 Local Development Server & TCP Port Detector
* **Darwin Socket Inspection**: Continuously monitors child processes via kernel-level `proc_pidinfo(PROC_PIDTASKINFO)`.
* **Automatic Port Discovery**: Detects when development servers bind to local TCP ports (e.g. Vite, Next.js, Django, FastAPI, Flask, Express, Docker, Go on ports `3000`, `5173`, `8000`, `8080`, `8787`).
* **Ephemeral Floating Banner**: Displays the detected local address with a 1-click button to open directly in your default browser.

---

### 4. 🔔 Long-Running Command Notifications
* **Native Desktop Alerts**: Automatically sends a native macOS banner notification via `UNUserNotificationCenter` when any command exceeding 15 seconds completes while Ghostty or the tab is in the background.
* **In-Terminal Completion Toast**: An ephemeral floating pill displays the exit code and total execution duration upon returning to the terminal.

---

### 5. ☕ Keep Awake Mode (Caffeinate)
* **Native Menu Bar Controls**: Easily toggle display and system sleep prevention directly from the application menu, keeping long builds, data transfers, or tasks uninterrupted.

---

### 6. 📋 Copy Last Command Output (`⌘ ⇧ C`)
* **Instant Extraction**: Copies the entire output of the last executed command to the macOS clipboard with visual HUD feedback, eliminating manual mouse scrolling and text selection.

---

### 7. ⚙️ Real-Time Process & Resource Monitor
* **Background Process Pill**: Displays an active background jobs badge (`[⠋ N bg]`) in the top bar.
* **Process Popover**: Live CPU metrics with a 1-click `SIGTERM` kill action to quickly terminate runaway processes.

---

### 8. 🛠️ Interactive Configuration Studio (`ghostty +config`)
* Terminal-based interactive configuration editor covering 60+ settings with live theme previews.

---

## 🛠️ Compiling from Source (macOS ARM64)

### Requirements
- macOS 14+ (Apple Silicon M1/M2/M3/M4)
- **Xcode 26** with macOS 26 SDK and Metal Toolchain
- **Zig 0.16.0** (`brew install zig`)

### Build & Installation Command

```bash
# Build optimized ReleaseLocal bundle with Sparkle library validation support
zig build -Doptimize=ReleaseFast -Demit-macos-app=true

# Install into /Applications
rm -rf /Applications/Ghostty.app
cp -R macos/build/ReleaseLocal/Ghostty.app /Applications/Ghostty.app
xattr -cr /Applications/Ghostty.app
```

Or using the automated updater script:
```bash
./update-ghostty.sh --install
```

---

## 📄 License

Ghostty is licensed under the Mozilla Public License 2.0. See [LICENSE](LICENSE) for details.
