# 👻 Ghostty (macOS Apple Silicon Edition)

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20(ARM64)-black?logo=apple&style=flat-square)](https://github.com/skyones-0/ghostty)
[![Version](https://img.shields.io/badge/version-3.0.0.1a-blue?style=flat-square)](https://github.com/skyones-0/ghostty/releases/tag/v3.0.0.1a)
[![Renderer](https://img.shields.io/badge/renderer-Metal%20GPU-red?style=flat-square)](https://github.com/skyones-0/ghostty)
[![License](https://img.shields.io/badge/license-MPL%202.0-green?style=flat-square)](LICENSE)

Fast, native, GPU-accelerated terminal emulator engineered **exclusively for macOS Apple Silicon (M1/M2/M3/M4)**.

This distribution ([`skyones-0/ghostty`](https://github.com/skyones-0/ghostty)) transforms Ghostty into an enterprise-grade workstation for system administrators, DevOps engineers, and network specialists—combining the raw speed of Metal GPU rendering with the depth and control of **SecureCRT** and **Core Shell**.

---

## 🚀 Download & Quickstart

Pre-built and optimized release binaries are available for direct download:

### [⬇️ **Download Ghostty v3.0.0.1a for macOS (Apple Silicon ARM64)**](https://github.com/skyones-0/ghostty/releases/download/v3.0.0.1a/Ghostty-macos-arm64-v3.0.0.1a.zip)

> **Installation (Quick 3-Step Setup):**
> 1. Download and extract `Ghostty-macos-arm64-v3.0.0.1a.zip`.
> 2. Move `Ghostty.app` into your `/Applications` directory.
> 3. Remove the macOS quarantine attribute to permit execution:
> ```bash
> xattr -cr /Applications/Ghostty.app
> ```

---

## ✨ Exclusive Features & Enhancements (v3.0.0.1a)

### 1. 🛡️ Enterprise SSH Session Engine (SecureCRT & Core Shell Grade)
* **Full OpenSSH Specifications**:
  * **Identity Keys**: Supports private keys (`id_ed25519`, `id_rsa`, `.pem`) with automatic discovery in `~/.ssh/` and native `Browse...` file picker.
  * **Bastions & Jump Hosts**: Direct `-J user@bastion:port` chaining.
  * **Session Stability**: KeepAlive intervals (`-o ServerAliveInterval=30`), compression (`-C`), and agent forwarding (`-A`).
  * **Post-Login Automation**: Automatic command execution upon login (`-t "tmux new -A -s main"`).
* **Port Forwarding Manager**: Interactive visual configuration of Local (`-L`), Remote (`-R`), and Dynamic SOCKS5 (`-D`) tunnels.
* **Environment Badges**: At-a-glance safety badges (`PROD` in red, `STAGING` in orange, `DEV` in green, `LAB` in blue).
* **Session Editor Modal (`⌘ E`)**: Professional 4-tab editor (`General`, `Authentication`, `Tunnels & Bastion`, `Advanced`).
* **`~/.ssh/config` Sincronización**: Imports host configs, keys, and bastion settings automatically.

---

### 2. ⚡ Smart SSH File Transfer (Zero-Latency Drag & Drop & Smart Paste)
* **OpenSSH Socket Multiplexing (`ControlMaster`)**: Reuses the already-authenticated SSH tunnel over UNIX domain sockets (`/tmp/ghostty-ssh-%C.sock`) for 0ms transfer startup without entering passwords or 2FA tokens again.
* **Smart Paste (`⌘ V`) in Full Screen**: Copy any file in Finder (`⌘ C`), switch to Ghostty in Full Screen, and press `⌘ V`—Ghostty uploads the file directly to the remote server and types its path in the prompt.
* **Drag & Drop Upload**: Drop files from Finder onto the terminal to trigger automatic background SCP upload.
* **Native Full Screen Picker (`⌘ ⇧ U`)**: Opens `NSOpenPanel` inside Ghostty to upload files without leaving full-screen mode.
* **1-Click Download (`⌘ ⇧ D` / Context Menu)**: Right-click any file path on screen to download it directly to `~/Downloads/`.
* **CLI Command `ghostty-get <file>`**: Type `ghostty-get backup.tar.gz` on the remote server to stream and download it to your Mac automatically.
* **Floating Transfer HUD**: Displays live progress `[████████░░]` with instant **"Show in Finder"** and **"Open"** actions upon completion.

---

### 3. 🔴 Forensic Session Recording (`SessionLogger`)
* **1-Click Audit Logging**: Records terminal input and output directly to `~/Documents/Ghostty Logs/`.
* **Millisecond Timestamps**: Injects `[YYYY-MM-DD HH:mm:ss.SSS]` on each line for post-incident analysis.
* **ANSI Code Stripping**: Generates clean, human-readable log files ready for ticketing systems.
* **Live Recording HUD**: Displays an animated `🔴 REC [00:03:12]` indicator with stop and reveal actions.

---

### 4. 🎯 Real-Time Keyword Highlighting (SecureCRT Style)
* **Live Buffer Scanner**: Intercepts screen text in real-time without latency:
  * **Critical & Errors**: `ERROR`, `FAIL`, `DOWN`, `CRITICAL`, `DENIED`, `PANIC` $\rightarrow$ Bold Red.
  * **Operational States**: `UP`, `OK`, `SUCCESS`, `ESTABLISHED`, `ONLINE` $\rightarrow$ Mint Green.
  * **Warnings & Alerts**: `WARNING`, `WARN`, `TIMEOUT`, `RETRY`, `DROPPED` $\rightarrow$ Amber.
  * **Network Addresses**: IPv4 (`\b(?:\d{1,3}\.){3}\d{1,3}\b`) in Cyan, MAC addresses in Purple.
* **Interactive HUD & Popover**: Live counter showing matching entities with 1-click clipboard copy.

---

### 5. 🤖 Expect / Send Logon Scripting
* **Prompt Automation**: Sequential triggers (`Expect: "Password:"` $\rightarrow$ `Send: "secret\n"`, `Expect: ">"` $\rightarrow$ `Send: "enable\n"`).
* **Hardware & Appliance Ready**: Perfect for Cisco routers, serial consoles, and legacy systems lacking SSH key authentication.

---

### 6. 🔌 Professional Serial Hardware Tools
* **Send Break Signal**: Dedicated button emitting both POSIX `tcsendbreak` to `/dev/cu.*` and GNU screen break `Ctrl-A + b` to enter Cisco ROMMON and U-Boot bootloaders.
* **Paste Throttling / Line Delay**: Throttles pasted configurations (20ms to 250ms per line) to prevent buffer overflows on 9600 baud UARTs.

---

### 7. ⚡ Quick Commands Sidebar & Floating Platter Hub
* **Global Shortcut**: `⌘ ⇧ B` or floating button.
* **Unified Animated Gradient**: Harmonized rotating neon palette (`[.cyan, .blue, .yellow, .blue, .cyan]`) across SecureInput Lock, Task Platter, and Sidebar buttons.
* **Task Overlay (`platter.2.filled.iphone.landscape`)**: Floating monitor showing active background jobs, transfers, and processes.

---

## 🛠️ Compiling from Source (macOS ARM64)

### Requirements
- macOS 14+ (Apple Silicon M1/M2/M3/M4)
- **Xcode 26** with macOS 26 SDK and Metal Toolchain
- **Zig 0.16.0** (`brew install zig`)

### Build & Installation Command

```bash
# Build optimized ReleaseLocal bundle with Sparkle library validation support
nu macos/build.nu --configuration ReleaseLocal --action build

# Install into /Applications
rm -rf /Applications/Ghostty.app
cp -R macos/build/ReleaseLocal/Ghostty.app /Applications/Ghostty.app
xattr -cr /Applications/Ghostty.app
```

---

## 📄 License

Ghostty is licensed under the Mozilla Public License 2.0. See [LICENSE](LICENSE) for details.
