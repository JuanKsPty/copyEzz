#!/bin/bash
# Publica una versión: tests, app universal firmada, .dmg, appcast de Sparkle, tag y GitHub Release.
# Uso: make release VERSION=X.Y.Z   (antes agrega la sección "## X.Y.Z" a CHANGELOG.md)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Uso: scripts/release.sh X.Y.Z}
TAG="v$VERSION"
REPO=JuanKsPty/copyEzz
SIGNING_DIR=${COPYEZZ_SIGNING_DIR:-$HOME/CopyEzz-signing}
SPARKLE_KEY="$SIGNING_DIR/sparkle-private-key"
SIGN_UPDATE=.build/artifacts/sparkle/Sparkle/bin/sign_update
DMG="dist/CopyEzz-$VERSION.dmg"
APPCAST=dist/appcast.xml

fail() { echo "✗ $*" >&2; exit 1; }

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "versión inválida: $VERSION (usa X.Y.Z)"
[ "$(git branch --show-current)" = main ] || fail "publica desde main"
git diff --quiet && git diff --cached --quiet || fail "hay cambios sin commit"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "el tag $TAG ya existe"
[ -f "$SPARKLE_KEY" ] || fail "falta la llave de Sparkle en $SPARKLE_KEY"
[ -f "$HOME/Library/Keychains/copyezz-signing.keychain-db" ] || fail "falta el llavero de firma (scripts/create-signing-cert.sh)"
NOTES=$(awk -v v="## $VERSION" '$0 == v {found=1; next} /^## / {found=0} found' CHANGELOG.md | sed '/./,$!d')
[ -n "$NOTES" ] || fail "agrega la sección '## $VERSION' a CHANGELOG.md"

make test
UNIVERSAL=1 scripts/bundle.sh release "$VERSION"

# .dmg con acceso directo a /Applications para arrastrar e instalar.
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto dist/CopyEzz.app "$STAGING/CopyEzz.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "CopyEzz $VERSION" -srcfolder "$STAGING" -format UDZO "$DMG"

# Firma EdDSA de Sparkle (sparkle:edSignature="…" length="…") y appcast de una sola entrada:
# Sparkle solo necesita la versión más reciente.
SIGNATURE=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY" "$DMG")
NOTES_HTML=$(printf '%s\n' "$NOTES" | sed -E 's/&/\&amp;/g; s/</\&lt;/g; s/^- (.*)/<li>\1<\/li>/')
cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CopyEzz</title>
    <item>
      <title>CopyEzz $VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$NOTES_HTML
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/CopyEzz-$VERSION.dmg"
                 type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF

git tag -a "$TAG" -m "CopyEzz $VERSION"
git push origin main "$TAG"
gh release create "$TAG" "$DMG" "$APPCAST" --repo "$REPO" --title "CopyEzz $VERSION" --notes "$NOTES"
echo "Publicado: https://github.com/$REPO/releases/tag/$TAG"
