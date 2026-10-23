#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== Building Achievement Hunter macOS App ==="

APP_NAME="AchievementHunter"
DISPLAY_NAME="Achievement Hunter"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$DISPLAY_NAME.app"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_OUTPUT="$PROJECT_DIR/$APP_NAME.dmg"

# 1. Clean previous build artifacts
rm -rf "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE" "$DMG_STAGING" "$DMG_OUTPUT"
mkdir -p "$BUILD_DIR"

# 2. Compile Swift sources
echo "Compiling Swift sources..."
export CLANG_MODULE_CACHE_PATH="/tmp/clang-cache"
mkdir -p /tmp/clang-cache

swiftc -O -parse-as-library \
    -target arm64-apple-macos14.0 \
    -module-cache-path /tmp/clang-cache \
    Sources/Models/*.swift \
    Sources/Services/*.swift \
    Sources/Components/*.swift \
    Sources/Views/*.swift \
    Sources/App.swift \
    -o "$BUILD_DIR/$APP_NAME"

echo "Compilation successful: $BUILD_DIR/$APP_NAME"

# 3. Create macOS App Bundle
echo "Assembling macOS .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 4. Ad-hoc codesign
echo "Codesigning app bundle..."
codesign -s - --force --deep "$APP_BUNDLE"

# 5. Create DMG Staging folder
echo "Preparing DMG disk image..."
mkdir -p "$DMG_STAGING/.background"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Installer background (660x400 pt, with a Retina rendition) drawn by scripts/make_dmg_background.swift
STYLED=1
if swiftc -o "$BUILD_DIR/mkbg" -module-cache-path /tmp/clang-cache scripts/make_dmg_background.swift 2>/dev/null \
   && "$BUILD_DIR/mkbg" "$BUILD_DIR/bg1.png" 1 && "$BUILD_DIR/mkbg" "$BUILD_DIR/bg2.png" 2 \
   && sips -s format tiff "$BUILD_DIR/bg1.png" --out "$BUILD_DIR/bg1.tiff" >/dev/null \
   && sips -s format tiff "$BUILD_DIR/bg2.png" --out "$BUILD_DIR/bg2.tiff" >/dev/null \
   && tiffutil -cat "$BUILD_DIR/bg1.tiff" "$BUILD_DIR/bg2.tiff" -out "$DMG_STAGING/.background/background.tiff" 2>/dev/null; then
    :
else
    echo "warning: could not render the installer background; building a plain DMG"
    STYLED=0
fi
# 6. Build DMG using hdiutil
echo "Generating .dmg file..."
RW_DMG="$BUILD_DIR/rw.dmg"
rm -f "$RW_DMG"
# Make sure no stale volume with the same name is mounted (it would shift the mount point).
for stale in "/Volumes/$DISPLAY_NAME"*; do
    [ -d "$stale" ] && hdiutil detach "$stale" -force >/dev/null 2>&1 || true
done

if [ "$STYLED" = "1" ]; then
    hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
    VOLUME="/Volumes/$DISPLAY_NAME"
    MOUNT_OUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$VOLUME")"
    DEVICE="$(echo "$MOUNT_OUT" | grep -E '^/dev/' | head -1 | awk '{print $1}')"
    [ -d "$VOLUME/Applications" ] || { echo "error: installer volume did not mount at $VOLUME"; exit 1; }

    # Window layout via Finder. Needs a logged-in GUI session; falls back to the default layout if refused.
    if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DISPLAY_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 542}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$DISPLAY_NAME.app" of container window to {170, 205}
        set position of item "Applications" of container window to {490, 205}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
    then
        echo "warning: Finder styling was not applied (allow Terminal/your shell to control Finder in System Settings > Privacy > Automation)"
    fi

    # Custom volume icon. Added after the Finder step (Finder drops it if it exists beforehand).
    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "$VOLUME/.VolumeIcon.icns"
        SetFile -c icnC "$VOLUME/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$VOLUME" 2>/dev/null || true
    fi

    sync
    sleep 2
    hdiutil detach "$DEVICE" >/dev/null 2>&1 || hdiutil detach "$DEVICE" -force >/dev/null
    hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_OUTPUT" >/dev/null
    rm -f "$RW_DMG"
else
    hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_OUTPUT"
fi

# 7. Cleanup staging
rm -rf "$DMG_STAGING" "$BUILD_DIR/mkbg" "$BUILD_DIR"/bg*.png "$BUILD_DIR"/bg*.tiff

echo "=== Build Complete! ==="
echo "App bundle: $APP_BUNDLE"
echo "DMG installer: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
