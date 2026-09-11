# Developing Ghostty (macOS ARM Edition)

This document describes technical guidelines for developing and compiling this Ghostty fork, which is **engineered exclusively for macOS on Apple Silicon (ARM64)**.

---

## Toolchain & Requirements

Building the Ghostty macOS app requires:
- **macOS 14+** (Sonoma, Sequoia, or newer) running on Apple Silicon (arm64)
- **Xcode 26** with macOS 26 SDK and Metal Toolchain
- **Zig 0.16.0** (`brew install zig`)

Ensure the active Xcode developer directory is set properly:

```shell-session
sudo xcode-select --switch /Applications/Xcode.app
```

---

## Compiling Ghostty

### Fast Optimized Release (Recommended)

To compile the fully optimized app bundle using `ReleaseFast` and native ad-hoc code signing:

```bash
zig build -Doptimize=ReleaseFast -Demit-macos-app=true
```

The compiled application bundle will be located at:
```
macos/build/ReleaseLocal/Ghostty.app
```

### Debug Build

When diagnosing issues or adding new native Swift features:

```bash
zig build -Demit-macos-app=true
```

This compiles with debug optimizations and generates logs to `stderr`.

---

## Code Signing & Hardened Runtime (`ReleaseLocal`)

Ghostty uses dynamic frameworks (such as `Sparkle.framework`). Under macOS Hardened Runtime, dynamic libraries without matching Team IDs fail to load unless `com.apple.security.cs.disable-library-validation` is present.

For local non-notarized builds, the project uses the **`ReleaseLocal`** configuration:
- Entitlements: `macos/GhosttyReleaseLocal.entitlements`
- Codesign: Ad-hoc (`codesign -s -`)

When copying a build to `/Applications/Ghostty.app`, clear any quarantine attributes:

```bash
xattr -cr /Applications/Ghostty.app
```

---

## Logging

On macOS, logging to the macOS Unified Log is active by default. You can inspect Ghostty logs using the system `log` CLI:

```bash
sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'
```

You can also use the `GHOSTTY_LOG` environment variable:
- `GHOSTTY_LOG=stderr`: stream logs to standard error.
- `GHOSTTY_LOG=macos`: stream logs to the macOS Unified Log.
- `GHOSTTY_LOG=true`: enable all log sinks.

---

## Project Structure (macOS ARM Focus)

- `macos/Sources/App`: Application delegate, window management, menu bars, and lifecycle.
- `macos/Sources/Features`: Native SwiftUI feature implementations:
  - `Quick Commands`: Collapsible sidebar, floating toggle overlay, dynamic injection.
  - `Hardware`: USB Serial device detection (`IOKit`).
  - `Port Detector`: Local server port detector via `proc_pidinfo`.
  - `Command Notifications`: Long-running command notification handler.
- `src/`: Core terminal emulation, VT parser, and renderer in Zig.
- `include/`: C API headers for `libghostty`.
