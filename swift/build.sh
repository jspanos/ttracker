#!/usr/bin/env bash
# build.sh — Build TTracker.app from the Swift Package Manager project.
#
# Usage:
#   ./build.sh             # build native arch + assemble TTracker.app in ./build/
#   ./build.sh --universal # build universal binary (arm64 + x86_64) via lipo
#   ./build.sh --install   # also copy to /Applications/TTracker.app
#   ./build.sh --universal --install
#
# Requirements: Xcode Command Line Tools (swift, codesign, lipo)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/TTracker.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

UNIVERSAL=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=true ;;
        --install)   INSTALL=true ;;
    esac
done

# ── 1. Build the Swift Package ────────────────────────────────────────────────
cd "$SCRIPT_DIR"

if $UNIVERSAL; then
    echo "==> Building Swift package (release, arm64)…"
    swift build -c release --arch arm64
    echo "==> Building Swift package (release, x86_64)…"
    swift build -c release --arch x86_64

    ARM64_BIN="$SCRIPT_DIR/.build/arm64-apple-macosx/release/ttracker"
    X86_BIN="$SCRIPT_DIR/.build/x86_64-apple-macosx/release/ttracker"
    UNIVERSAL_DIR="$SCRIPT_DIR/.build/universal"
    mkdir -p "$UNIVERSAL_DIR"

    echo "==> Creating universal binary with lipo…"
    lipo -create "$ARM64_BIN" "$X86_BIN" -output "$UNIVERSAL_DIR/ttracker"
    BINARY="$UNIVERSAL_DIR/ttracker"
    lipo -info "$BINARY"
else
    echo "==> Building Swift package (release)…"
    swift build -c release
    BINARY="$SCRIPT_DIR/.build/release/ttracker"
fi

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Build succeeded but binary not found at $BINARY" >&2
    exit 1
fi

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
echo "==> Assembling TTracker.app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS/Resources"

cp "$BINARY"                    "$MACOS_DIR/ttracker"
cp "$SCRIPT_DIR/Info.plist"    "$CONTENTS/Info.plist"

# App icon
ICNS="$SCRIPT_DIR/AppIcon.icns"
if [[ -f "$ICNS" ]]; then
    cp "$ICNS" "$CONTENTS/Resources/AppIcon.icns"
else
    echo "WARNING: AppIcon.icns not found — run 'swift make_icon.swift' in swift/ to generate it"
fi

# Write a minimal PkgInfo (APPL + creator code)
printf "APPL????" > "$CONTENTS/PkgInfo"

# ── 3. Create entitlements ────────────────────────────────────────────────────
ENTITLEMENTS="$BUILD_DIR/ttracker.entitlements"
cat > "$ENTITLEMENTS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Allow sending Apple Events to other apps (browser URL/title via osascript) -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <!-- Accessibility for CGEvent tap (input monitoring) -->
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>com.apple.iohideventsystem</string>
    </array>
</dict>
</plist>
EOF

# ── 4. Ad-hoc code sign ───────────────────────────────────────────────────────
echo "==> Signing app bundle (ad-hoc)…"
codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP_DIR"

echo "==> Build complete: $APP_DIR"
codesign --verify --deep --strict "$APP_DIR" && echo "    Signature OK"

# ── 5. Optionally install to /Applications ────────────────────────────────────
if $INSTALL; then
    DEST="/Applications/TTracker.app"
    echo "==> Installing to $DEST…"
    rm -rf "$DEST"
    cp -R "$APP_DIR" "$DEST"
    echo "==> Installed: $DEST"
    echo
    echo "    To launch: open /Applications/TTracker.app"
    echo "    Or add a LaunchAgent for auto-start on login."
fi

echo
echo "Done. Run with:"
echo "  open \"$APP_DIR\""
