#!/usr/bin/env bash
set -euo pipefail

# Amara.app DMG Installer Builder
# Produces: Amara-<version>.dmg (notarized, drag-to-Applications)
#
# Required env var before running:
#   export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password from appleid.apple.com

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/macos/build/Release"
APP_NAME="Amara"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="$SCRIPT_DIR/dist"
ENTITLEMENTS="$SCRIPT_DIR/macos/Ghostty.entitlements"

APPLE_ID="amaramusic@gmail.com"
TEAM_ID="Q35CCLCGFN"
APP_PASSWORD="${APP_PASSWORD:?Set APP_PASSWORD to your app-specific password (appleid.apple.com → Security → App Passwords)}"

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

# ── 4. Find signing identity ──────────────────────────────────────────────────
SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application.*$TEAM_ID" \
    | head -1 \
    | sed 's/.*"\(.*\)"/\1/')

if [ -z "$SIGN_IDENTITY" ]; then
    echo "✗ Developer ID Application certificate for team $TEAM_ID not found in keychain."
    echo "  Download it from https://developer.apple.com/account/resources/certificates/list"
    exit 1
fi
echo "▶ Signing identity: $SIGN_IDENTITY"

# ── 5. Sign app bundle (inside-out) ──────────────────────────────────────────
echo "▶ Signing app bundle…"

# Sign standalone Mach-O executables first (e.g. Sparkle's Autoupdate binary)
find "$APP_BUNDLE" -type f -perm +111 | while read -r f; do
    if file "$f" | grep -q "Mach-O"; then
        codesign --force --options runtime \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            "$f"
    fi
done

# Sign all bundle types inside-out (deepest path first)
find "$APP_BUNDLE" \
    \( -name "*.framework" \
    -o -name "*.app" \
    -o -name "*.xpc" \
    -o -name "*.plugin" \
    -o -name "*.dylib" \
    -o -name "*.bundle" \) \
    | awk '{ print length, $0 }' \
    | sort -rn \
    | awk '{print $2}' \
    | while read -r item; do
        codesign --force --options runtime \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            "$item"
    done

# Sign the app bundle itself with entitlements
codesign --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP_BUNDLE"

# Verify
codesign --verify --deep --strict "$APP_BUNDLE"
echo "  Signature OK"

# ── 6. Stage contents ─────────────────────────────────────────────────────────
echo "▶ Staging DMG contents…"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# ── 7. Create DMG ─────────────────────────────────────────────────────────────
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

# ── 8. Notarize DMG ──────────────────────────────────────────────────────────
echo "▶ Submitting to Apple for notarization (this may take a few minutes)…"
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

# ── 9. Staple notarization ticket ────────────────────────────────────────────
echo "▶ Stapling notarization ticket…"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# ── 10. Summary ───────────────────────────────────────────────────────────────
SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo ""
echo "✓ Done: $DMG_PATH ($SIZE)"
echo "  Notarized and ready for distribution."
echo "  To install: open the DMG and drag $APP_NAME to Applications."
