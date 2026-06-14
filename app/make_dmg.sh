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
VERSION="0.1.0"
NCPU="$(sysctl -n hw.ncpu)"

# ── 1. Build C engine ────────────────────────────────────────────────────────

echo "▸ [1/5] Building C engine (Release)…"
cmake -B "$BUILD_DIR" \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -S "$REPO_ROOT" \
    -Wno-dev 2>/dev/null
cmake --build "$BUILD_DIR" --target embershard_engine -j"$NCPU"

# Copy es_api.h into the bridge include (idempotent)
cp "$REPO_ROOT/include/es_api.h" "$SCRIPT_DIR/Sources/EmberShardBridge/include/es_api.h"
echo "  ✓ libembershard_engine.a"

# ── 2. Build Swift app ───────────────────────────────────────────────────────

echo "▸ [2/5] Building Swift app (release)…"
cd "$SCRIPT_DIR"
EMBERSHARD_BUILD="$BUILD_DIR" swift build -c release
BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: expected binary at $BINARY" >&2
    echo "Files in .build/release/:" >&2
    ls "$SCRIPT_DIR/.build/release/" >&2
    exit 1
fi
echo "  ✓ $BINARY ($(du -sh "$BINARY" | cut -f1))"

# ── 3. Assemble .app bundle ──────────────────────────────────────────────────

echo "▸ [3/5] Assembling .app bundle…"
rm -rf "$DIST_DIR"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Sources/EmberShardApp/Resources/Info.plist" "$APP/Contents/"

# ── 4. Bundle llama.cpp dylibs ───────────────────────────────────────────────

echo "▸ [4/5] Bundling dylibs…"
# Copy every real (non-symlink) .dylib from the build directory.
find "$BUILD_DIR" -maxdepth 3 -name "lib*.dylib" ! -type l | while IFS= read -r src; do
    libname="$(basename "$src")"
    dest="$APP/Contents/Frameworks/$libname"
    cp "$src" "$dest"
    # Rewrite install name so it resolves via @rpath at runtime
    install_name_tool -id "@rpath/$libname" "$dest"
    echo "  + $libname"
done

# Fix any absolute-path dylib references in the main binary
BIN="$APP/Contents/MacOS/$APP_NAME"
for dylib in "$APP/Contents/Frameworks/"*.dylib; do
    libname="$(basename "$dylib")"
    # Replace absolute build-dir reference → @rpath reference
    install_name_tool -change "$BUILD_DIR/$libname" "@rpath/$libname" "$BIN" 2>/dev/null || true
done
# Ensure the Frameworks rpath is present (Package.swift adds it, but just in case)
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

# ── 5. Sign and package ──────────────────────────────────────────────────────

echo "▸ [5/5] Signing and creating .dmg…"
codesign --force --deep --sign - "$APP"
echo "  ✓ Ad-hoc signed"

STAGE="$DIST_DIR/.dmg_stage"
mkdir -p "$STAGE"
cp -r "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

DMG="$DIST_DIR/$APP_NAME-$VERSION-mac.dmg"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"
rm -rf "$STAGE"

SIZE="$(du -sh "$DMG" | cut -f1)"
echo ""
echo "────────────────────────────────────────────────"
echo "  ✓  $DMG  ($SIZE)"
echo "────────────────────────────────────────────────"
echo ""
echo "  Test locally:       open \"$APP\""
echo ""
echo "  First launch on other Macs (Gatekeeper bypass):"
echo "    right-click → Open → Open"
echo "  Or from Terminal:"
echo "    xattr -dr com.apple.quarantine /path/to/Embershard.app"
echo ""
