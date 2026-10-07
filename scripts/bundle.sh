#!/bin/bash
# Arma dist/CopyEzz.app: compila, copia recursos y Sparkle, y firma de adentro hacia afuera.
# Uso: scripts/bundle.sh [debug|release] [versión]      UNIVERSAL=1 compila arm64 + x86_64.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-debug}
VERSION=${2:-}
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-0.0.0}
IDENTITY=${SIGN_IDENTITY:-CopyEzz Self-Signed}
APP=dist/CopyEzz.app
SPARKLE=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework

if [ "${UNIVERSAL:-0}" = 1 ]; then
  BINARIES=()
  for arch in arm64 x86_64; do
    swift build -c "$CONFIG" --triple "$arch-apple-macosx14.0"
    BINARIES+=("$(swift build -c "$CONFIG" --triple "$arch-apple-macosx14.0" --show-bin-path)/CopyEzz")
  done
  BINARY=.build/CopyEzz-universal
  lipo -create "${BINARIES[@]}" -output "$BINARY"
else
  swift build -c "$CONFIG"
  BINARY="$(swift build -c "$CONFIG" --show-bin-path)/CopyEzz"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINARY" "$APP/Contents/MacOS/CopyEzz"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/index.html Resources/AppIcon.icns "$APP/Contents/Resources/"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# La app no usa App Sandbox: los servicios XPC de Sparkle no hacen falta.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# Mismo certificado en cada build => macOS conserva los permisos entre versiones y Sparkle acepta
# la actualización. Sin él (scripts/create-signing-cert.sh) se firma ad-hoc, solo para desarrollo.
SIGNING_DIR=${COPYEZZ_SIGNING_DIR:-$HOME/CopyEzz-signing}
KEYCHAIN="$HOME/Library/Keychains/copyezz-signing.keychain-db"
if [ -f "$KEYCHAIN" ] && [ -f "$SIGNING_DIR/keychain-password.txt" ]; then
  security unlock-keychain -p "$(cat "$SIGNING_DIR/keychain-password.txt")" "$KEYCHAIN"
  SIGN=(--sign "$IDENTITY" --keychain "$KEYCHAIN")
else
  echo "⚠︎ Falta el llavero de firma (scripts/create-signing-cert.sh): firma ad-hoc, los permisos se pierden en cada build." >&2
  SIGN=(--sign -)
fi
# Sin hardened runtime: no se notariza, y con un certificado propio impediría cargar Sparkle.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for item in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK" "$APP"; do
  codesign --force "${SIGN[@]}" "$item" 2>&1 | { grep -v "replacing existing signature" || true; }
done
codesign --verify --strict --deep "$APP"

echo "$APP ($VERSION, firmado con: ${SIGN[1]})"
