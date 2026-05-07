#!/usr/bin/env bash
# Generate Resources/WhisperHot.icns from a 1024x1024 source PNG.
# Usage: ./scripts/make-icns.sh path/to/icon-1024.png [OutputName]
#
# Requires sips (macOS built-in) and iconutil (macOS built-in).
set -euo pipefail

src="${1:?Usage: ./scripts/make-icns.sh icon-1024.png [OutputName]}"
name="${2:-WhisperHot}"
iconset="${name}.iconset"

if [ ! -f "$src" ]; then
    echo "Source PNG not found: $src" >&2
    exit 1
fi

rm -rf "$iconset" "${name}.icns"
mkdir -p "$iconset"

sips -z 16 16     "$src" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32     "$src" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$src" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64     "$src" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$src" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256   "$src" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$src" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512   "$src" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$src" --out "$iconset/icon_512x512.png" >/dev/null
cp "$src" "$iconset/icon_512x512@2x.png"

iconutil -c icns "$iconset" -o "${name}.icns"
rm -rf "$iconset"

echo "Generated ${name}.icns from $src"
echo "Move to Resources/ to replace the current icon:"
echo "  mv ${name}.icns Resources/WhisperHot.icns"
