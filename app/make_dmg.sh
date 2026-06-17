#!/usr/bin/env bash
# make_dmg.sh — Build Embershard.app and package as a .dmg for distribution.
#
# No Apple Developer ID required. The app is signed with an ad-hoc signature.
# On first launch on another Mac: right-click → Open → Open (bypasses Gatekeeper).
#
# Usage:
#   cd app/
#   ./make_dmg.sh
#
# Output: app/dist/Embershard-0.1.0-mac.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="Embershard"
APP="$DIST_DIR/$APP_NAME.app"
VERSION="0.1.7"
VOL_NAME="$APP_NAME $VERSION"
NCPU="$(sysctl -n hw.ncpu)"

# ── 1. Build C engine ────────────────────────────────────────────────────────

echo "▸ [1/6] Building C engine (Release)…"
cmake -B "$BUILD_DIR" \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -S "$REPO_ROOT" \
    -Wno-dev 2>/dev/null
cmake --build "$BUILD_DIR" --target embershard_engine -j"$NCPU"

# Copy es_api.h into the bridge include (idempotent)
cp "$REPO_ROOT/include/es_api.h" "$SCRIPT_DIR/Sources/EmberShardBridge/include/es_api.h"
echo "  ✓ libembershard_engine.a"

# ── 2. Build Swift app ───────────────────────────────────────────────────────

echo "▸ [2/6] Building Swift app (release)…"
cd "$SCRIPT_DIR"
EMBERSHARD_BUILD="$BUILD_DIR" swift build -c release
BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: expected binary at $BINARY" >&2
    ls "$SCRIPT_DIR/.build/release/" >&2
    exit 1
fi
echo "  ✓ $BINARY ($(du -sh "$BINARY" | cut -f1))"

# ── 3. Assemble .app bundle ──────────────────────────────────────────────────

echo "▸ [3/6] Assembling .app bundle…"
rm -rf "$DIST_DIR"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Sources/EmberShardApp/Resources/Info.plist" "$APP/Contents/"

# SwiftPM resource bundle(s) — `Bundle.module` (logo.svg, ProviderIcons, …) looks
# for these under the app's Resources. Without them the app hits a fatalError at
# launch on any machine other than the build host. This is REQUIRED.
shopt -s nullglob
RES_BUNDLES=("$SCRIPT_DIR/.build/release/"*.bundle)
shopt -u nullglob
if [ ${#RES_BUNDLES[@]} -eq 0 ]; then
    echo "ERROR: no SwiftPM resource bundle found in .build/release (Bundle.module would crash)." >&2
    exit 1
fi
for b in "${RES_BUNDLES[@]}"; do
    cp -R "$b" "$APP/Contents/Resources/"
    echo "  ✓ $(basename "$b")"
done

# App icon
ICNS="$SCRIPT_DIR/Sources/EmberShardApp/Resources/AppIcon.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
    echo "  ✓ AppIcon.icns"
fi

# ── 4. Bundle llama.cpp dylibs ───────────────────────────────────────────────

echo "▸ [4/6] Bundling dylibs…"
find "$BUILD_DIR" -maxdepth 3 -name "lib*.dylib" ! -type l | while IFS= read -r src; do
    libname="$(basename "$src")"
    dest="$APP/Contents/Frameworks/$libname"
    cp "$src" "$dest"
    install_name_tool -id "@rpath/$libname" "$dest"
    echo "  + $libname"
done

# Create version symlinks (e.g. libllama.0.dylib -> libllama.0.0.1.dylib)
pushd "$APP/Contents/Frameworks" > /dev/null
for f in lib*.*.*.*.dylib; do
    [ -f "$f" ] || continue
    short="$(echo "$f" | sed -E 's/\.[0-9]+\.[0-9]+\.dylib/.dylib/')"
    [ ! -e "$short" ] && ln -sf "$f" "$short"
    bare="$(echo "$f" | sed -E 's/\.[0-9]+\.[0-9]+\.[0-9]+\.dylib/.dylib/')"
    [ ! -e "$bare" ] && ln -sf "$f" "$bare"
done
popd > /dev/null

# Fix load paths in binary
BIN="$APP/Contents/MacOS/$APP_NAME"
for dylib in "$APP/Contents/Frameworks/"*.dylib; do
    [ -L "$dylib" ] && continue
    libname="$(basename "$dylib")"
    install_name_tool -change "$BUILD_DIR/$libname" "@rpath/$libname" "$BIN" 2>/dev/null || true
    install_name_tool -change "$BUILD_DIR/bin/$libname" "@rpath/$libname" "$BIN" 2>/dev/null || true
done
# Also fix symlink names
for link in "$APP/Contents/Frameworks/"*.dylib; do
    libname="$(basename "$link")"
    install_name_tool -change "$BUILD_DIR/$libname" "@rpath/$libname" "$BIN" 2>/dev/null || true
    install_name_tool -change "$BUILD_DIR/bin/$libname" "@rpath/$libname" "$BIN" 2>/dev/null || true
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

# Fix inter-dylib references
for dylib in "$APP/Contents/Frameworks/"*.dylib; do
    [ -L "$dylib" ] && continue
    for other in "$APP/Contents/Frameworks/"*.dylib; do
        othername="$(basename "$other")"
        install_name_tool -change "$BUILD_DIR/$othername" "@rpath/$othername" "$dylib" 2>/dev/null || true
        install_name_tool -change "$BUILD_DIR/bin/$othername" "@rpath/$othername" "$dylib" 2>/dev/null || true
    done
    install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
done

# ── 5. Sign ──────────────────────────────────────────────────────────────────

echo "▸ [5/6] Signing…"
codesign --force --deep --sign - "$APP"
echo "  ✓ Ad-hoc signed"

# ── 6. Create DMG with drag-to-Applications window ───────────────────────────

echo "▸ [6/6] Creating DMG…"

DMG_FINAL="$DIST_DIR/$APP_NAME-$VERSION-mac.dmg"
DMG_WORK="$DIST_DIR/.work.dmg"

# Estimate size: app + a bit of headroom (MB)
APP_SIZE_KB=$(du -sk "$APP" | awk '{print $1}')
DMG_SIZE_MB=$(( (APP_SIZE_KB / 1024) + 32 ))

# Create a writable temporary DMG
rm -f "$DMG_WORK" "$DMG_FINAL"
hdiutil create \
    -size "${DMG_SIZE_MB}m" \
    -volname "$VOL_NAME" \
    -fs HFS+ \
    -type UDIF \
    -o "$DMG_WORK"

# Mount it (no auto-open)
MOUNT_POINT="$(hdiutil attach -noverify -noautoopen "$DMG_WORK" \
    | grep "Apple_HFS" | sed 's/.*Apple_HFS[[:space:]]*//')"
echo "  Mounted at: $MOUNT_POINT"

# Populate
cp -r "$APP" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"

# Wait for Finder to register the newly mounted volume
sleep 2

# Configure window layout via AppleScript (best-effort)
osascript -e "
    tell application \"Finder\"
        tell disk \"$VOL_NAME\"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 760, 440}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 128
            update without registering applications
            delay 1
            close
        end tell
    end tell
" 2>/dev/null || echo "  ⚠  Finder layout skipped (DMG will still work)"

# Give Finder time to flush .DS_Store
sync
sleep 2

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet

# Convert writable DMG → compressed read-only
hdiutil convert "$DMG_WORK" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL" 2>/dev/null

rm -f "$DMG_WORK"

SIZE="$(du -sh "$DMG_FINAL" | cut -f1)"
echo ""
echo "────────────────────────────────────────────────"
echo "  ✓  $DMG_FINAL  ($SIZE)"
echo "────────────────────────────────────────────────"
echo ""
echo "  Test locally:       open \"$APP\""
echo "  Test DMG:           open \"$DMG_FINAL\""
echo ""
echo "  First launch on other Macs (Gatekeeper bypass):"
echo "    right-click → Open → Open"
echo "  Or from Terminal:"
echo "    xattr -dr com.apple.quarantine /path/to/Embershard.app"
echo ""
