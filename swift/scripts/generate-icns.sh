#!/bin/bash
# Generates all required macOS icon sizes from a 1024x1024 PNG and creates assets/icon.icns
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path_to_1024x1024_png>"
    exit 1
fi

INPUT_PNG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ICONSET_DIR="$ROOT_DIR/assets/icon.iconset"

echo "Using input PNG: $INPUT_PNG"
echo "Iconset directory: $ICONSET_DIR"

mkdir -p "$ICONSET_DIR"

# Resize images using sips
echo "Resizing images..."
sips -s format png -z 16 16     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16.png"
sips -s format png -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -s format png -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32.png"
sips -s format png -z 64 64     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -s format png -z 128 128   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128.png"
sips -s format png -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -s format png -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256.png"
sips -s format png -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -s format png -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512.png"
sips -s format png -z 1024 1024 "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png"
sips -s format png -z 1024 1024 "$INPUT_PNG" --out "$ICONSET_DIR/icon_1024x1024.png"

# Compile to .icns
echo "Compiling to .icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/assets/icon.icns"

echo "Successfully generated $ROOT_DIR/assets/icon.icns!"
