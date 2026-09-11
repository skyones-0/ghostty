#!/usr/bin/env nu

# Build the macOS Ghostty app using xcodebuild with a clean environment
# to avoid Nix shell interference (NIX_LDFLAGS, NIX_CFLAGS_COMPILE, etc.).

def main [
    --scheme: string = "Ghostty"              # Xcode scheme (Ghostty, DockTilePlugin)
    --configuration: string = "ReleaseLocal" # Build configuration (Debug, ReleaseLocal, Release)
    --action: string = "build"                # xcodebuild action (build, test, clean, etc.)
    --arch: string = "arm64"                 # Architecture override (exclusive to macOS ARM Apple Silicon)
] {
    let project = ($env.FILE_PWD | path join "Ghostty.xcodeproj")
    let build_dir = ($env.FILE_PWD | path join "build")

    # Skip UI tests for CLI-based invocations because it requires
    # special permissions.
    let skip_testing = if $action == "test" {
        [-skip-testing GhosttyUITests]
    } else {
        []
    }

    let arch_arg = if ($arch | is-empty) {
        []
    } else {
        [-arch $arch]
    }

    # Strip any macOS Finder/quarantine extended attributes that break code signing
    try { ^xattr -cr $build_dir }

    (^env -i
        $"HOME=($env.HOME)"
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        xcodebuild
        -project $project
        -scheme $scheme
        -configuration $configuration
        $"SYMROOT=($build_dir)"
        ...$arch_arg
        ...$skip_testing
        $action)

    if ($action == "build") {
        let app_dir = ($build_dir | path join $configuration "Ghostty.app")
        let sparkle_framework = ($app_dir | path join "Contents" "Frameworks" "Sparkle.framework")
        let sign_id = try {
            ^security find-identity -v -p codesigning
            | lines
            | find "Apple Development:"
            | first
            | parse --regex "\"([^\"]+)\""
            | get capture0.0
        } catch { "-" }

        if ($sparkle_framework | path exists) {
            try { ^codesign --force --sign $sign_id $sparkle_framework }
            let target_entitlements = if ($entitlements | path exists) {
                $entitlements
            } else {
                ($env.FILE_PWD | path join "GhosttyReleaseLocal.entitlements")
            }
            if ($target_entitlements | path exists) {
                try { ^codesign --force --sign $sign_id --entitlements $target_entitlements $app_dir }
            } else {
                try { ^codesign --force --sign $sign_id $app_dir }
            }
            try {
                ^/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f $app_dir
            }
        }
    }
}
