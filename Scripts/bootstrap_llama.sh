#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LLAMA_DIR="$ROOT/.build/llama.cpp"
COMMIT="b10507"
if [ ! -d "$LLAMA_DIR/.git" ]; then
  mkdir -p "$ROOT/.build"
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
fi
cd "$LLAMA_DIR"
git fetch --depth 1 origin "$COMMIT"
git checkout --detach "$COMMIT"
./build-xcframework.sh
mkdir -p "$ROOT/Vendor"
rm -rf "$ROOT/Vendor/llama.xcframework"
cp -R "$LLAMA_DIR/build-apple/llama.xcframework" "$ROOT/Vendor/llama.xcframework"
echo "XCFramework copied to $ROOT/Vendor/llama.xcframework"
