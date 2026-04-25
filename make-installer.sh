#!/usr/bin/env bash
set -euo pipefail

# Amara.app DMG Installer Builder
# Produces: Amara-<version>.dmg (drag-to-Applications)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/macos/build/Release"
APP_NAME="Amara"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="$SCRIPT_DIR/dist"

# ── 1. Release build ──────────────────────────────────────────────────────────
echo "▶ Building $APP_NAME (Release, arm64 + x86_64)…"
xcodebuild \
    -project "$SCRIPT_DIR/macos/Ghostty.xcodeproj" \
    -target "$APP_NAME" \
    -configuration Release \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -20

if [ ! -d "$APP_BUNDLE" ]; then
    echo "✗ Build failed: $APP_BUNDLE not found"
    exit 1
fi

# ── 2. Verify universal binary ────────────────────────────────────────────────
echo "▶ Verifying universal binary…"
MAIN_BIN=$(find "$APP_BUNDLE/Contents/MacOS" -maxdepth 1 -type f | head -1)
lipo -info "$MAIN_BIN" || true

# ── 3. Read version ───────────────────────────────────────────────────────────
VERSION=$(defaults read "$APP_BUNDLE/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/.dmg-staging-$$"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# ── 4. Stage contents ─────────────────────────────────────────────────────────
echo "▶ Staging DMG contents…"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# ── 5. Create DMG ─────────────────────────────────────────────────────────────
echo "▶ Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

# ── 6. Summary ────────────────────────────────────────────────────────────────
SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo ""
echo "✓ Done: $DMG_PATH ($SIZE)"
echo "  To install: open the DMG and drag $APP_NAME to Applications."
