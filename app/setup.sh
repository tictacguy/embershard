#!/usr/bin/env bash
# setup.sh — build the embershard engine library before opening in Xcode
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

echo "▸ Building embershard engine..."
cmake -B "$BUILD_DIR" \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -S "$REPO_ROOT" 2>/dev/null
cmake --build "$BUILD_DIR" --target embershard_engine -j"$(sysctl -n hw.ncpu)"

echo "▸ Updating es_api.h in bridge..."
cp "$REPO_ROOT/include/es_api.h" "$(dirname "$0")/Sources/EmberShardBridge/include/es_api.h"

echo "✓ Done. Open app/Package.swift in Xcode to build the app."
