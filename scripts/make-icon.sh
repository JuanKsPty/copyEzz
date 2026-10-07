#!/bin/bash
# Genera Resources/AppIcon.icns a partir de Resources/AppIcon.svg (Chrome headless + sips + iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK=$(mktemp -d)
PNG="$WORK/icon-1024.png"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$WORK/profile" \
  --default-background-color=00000000 --window-size=1024,1024 --screenshot="$PNG" \
  "file://$PWD/Resources/AppIcon.svg" 2>/dev/null &
CHROME_PID=$!
trap 'kill "$CHROME_PID" 2>/dev/null || true; wait "$CHROME_PID" 2>/dev/null || true; rm -rf "$WORK" || true' EXIT
for _ in $(seq 1 50); do
  [ -s "$PNG" ] && break
  sleep 0.2
done
[ -s "$PNG" ] || { echo "Chrome no generó el PNG del ícono" >&2; exit 1; }
sleep 0.5

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns"
